# Endpoint Call Policy: Fewer Usage API Calls, Fresh Scheduled Refreshes

Date: 2026-10-13
Status: approved in brainstorming, awaiting spec review

## Intent

**What the user asked for:** make calls to Anthropic's usage endpoint less frequent, while the data must be current when the next scheduled refresh happens.

**Why:** On 2026-10-13 the app called the endpoint 158 times and received HTTP 429 50 times. The 5-minute timer accounts for 12 calls per hour; the rest came from 64 settings saves (every pause while typing a price override triggers a full refresh), 24 launches (development rebuilds) and one wake from sleep. Once rate limited, the scheduled refresh fails too and the menu bar shows stale values.

**Success criteria:**
- Every scheduled timer refresh fetches fresh values unless a rate-limit block is active; after a block, fresh values arrive as soon as the block ends.
- Settings edits, price overrides and price imports never call the endpoint, except edits that change subscription accounts.
- "Refresh now" and wake from sleep call the endpoint at most once per 60 seconds.
- In normal use the endpoint sees about one call per refresh interval (12 per hour at 300 s).

## Decisions

| Topic | Decision |
|---|---|
| Triggers that may call the endpoint | Timer, launch, wake from sleep, "Refresh now", settings edits that change subscription accounts |
| Spacing | "Refresh now", wake and subscription-relevant settings edits skip the call when the last attempt is under 60 s old |
| After HTTP 429 | Block every call until `Retry-After` (60 s if absent, doubling on consecutive 429s, capped at the refresh interval), then retry once |
| Scope of a block | One block for all subscription accounts (they are fetched together) |
| Persistence | None. Every launch fetches; nothing about fetches or blocks is stored on disk (spec 010 now saves fetch results, see below) |
| Approach | A pure `EndpointPolicy` value type decides per trigger; the coordinator applies the decision and owns the retry task |

## EndpointPolicy

A value type in `Sources/UsageCore/Snapshot/EndpointPolicy.swift` with no actors, clocks or I/O. The coordinator owns one instance.

**State:** `lastAttemptAt: Date?`, `lastOutcome: FetchOutcome?`, `blockedUntil: Date?`, `consecutiveRateLimits: Int`, `retryUsed: Bool`, `refreshInterval: TimeInterval`.

**Triggers:** `scheduled`, `launch`, `wake`, `manual`, `settings`, `retry`, `local`.

**`decide(trigger:now:) -> Decision`** (`.fetch`, or `.reuse(reason, retryAt: Date?)`), first matching rule wins:

1. `local` → reuse ("local change").
2. `lastAttemptAt == nil` → fetch.
3. `blockedUntil` in the future → reuse ("rate limited until HH:MM"). For `scheduled`, the decision also carries `retryAt = blockedUntil` and sets `retryUsed`, so the coordinator fetches as soon as the block ends. If `now < lastAttemptAt` (the clock moved backwards), the block counts as expired.
4. `retry` when `lastOutcome` is not rate limited → reuse ("already fresh") (amended by spec 021: with a merged manual refresh while an account's last request got no answer, `.fetchNoAnswer` instead).
5. `manual`, `wake` or `settings` with `now - lastAttemptAt < 60 s` → reuse ("last fetch N s ago") (amended by spec 021 for no-answer failures: a manual refresh, also one merged into another trigger, asks again the accounts whose last request got no answer). For `settings`, the decision carries `retryAt = lastAttemptAt + 60 s`, and the coordinator runs one `settings` follow-up then, so a subscription edit gets fresh data within a minute. Reused entries whose account credential directory changed since the fetch are dropped instead of shown.
6. Otherwise → fetch.

`decide(.scheduled, ...)` also resets `retryUsed` to false.

**`record(outcome:now:) -> Date?`** after each fetch; returns a retry time or nil:

- `success`: `lastAttemptAt = now`, clear `blockedUntil`, `consecutiveRateLimits = 0`.
- `rateLimited(retryAfter)`: `lastAttemptAt = now`, `blockedUntil = now + (retryAfter ?? min(60 * 2^consecutiveRateLimits, refreshInterval))`, increment `consecutiveRateLimits`. If `retryUsed` is false, set it and return `blockedUntil`.
- `otherError`: `lastAttemptAt = now`, no block.

Constants: `minimumSpacing = 60 s`, `defaultBackoff = 60 s`.

## Wiring

**`UsageEndpointClient`:** HTTP 429 throws `UsageEndpointError.rateLimited(retryAfter: TimeInterval?)`. `Retry-After` is parsed as delta-seconds or HTTP-date; an unparsable value counts as absent. Other non-200 statuses still throw `.httpStatus(code)`. The description stays "usage endpoint returned HTTP 429", plus the wait when known.

**`SubscriptionSource`:** no policy. `SubscriptionEntry` gains `fetchOutcome: FetchOutcome?`, nil when no request was made (not signed in, credentials expired, credential read failed).

**`RefreshCoordinator`:**
- `requestRefresh(trigger:)`. `requestRefresh()` stays as `.scheduled`, `requestReprice()` as `.local`.
- The policy decides when a run starts, not when it is requested. While a run is in progress, one pending trigger is kept, the strongest by rank: `scheduled`, `retry` > `launch`, `wake`, `manual`, `settings` > `local`.
- `.fetch` runs the existing full refresh; `.reuse` runs the existing reprice path, which reuses the stored network result. The reused subscription result is filtered to currently configured accounts.
- A reuse decision with a `retryAt` schedules the retry task the same way as a retry returned by `record`.
- After a full refresh, the coordinator combines the account outcomes (any rate limited → rate limited with the longest wait; all success → success; no outcomes → nothing recorded; otherwise other error) and calls `policy.record`. A returned retry time replaces any pending retry task, which calls `requestRefresh(trigger: .retry)` at that time.
- `UsageSnapshot` gains `endpointBlockedUntil: Date?` and `nextRetryAt: Date?`.
- The refresh "done" log line gains ", trigger <name>, endpoint fetched" or ", endpoint reused (<reason>)".

**`Configuration`:** `needsNetworkRefresh(comparedTo:)` is true when the set of subscription account ids, any subscription `credentialDirectory`, or `effectiveAlignmentAccountId` changes.

**`AppModel`:** timer → `.scheduled`; first refresh → `.launch`; wake → `.wake`; "Refresh now" → `.manual`; price import apply and removal → `.local`. `saveConfiguration`: if `needsRefresh` and `needsNetworkRefresh` → `.settings`; if only `needsRefresh` → `.local`.

**Dropdown:** while `endpointBlockedUntil` is set, the stale note adds "retrying at HH:MM". No other UI change. A "Refresh now" within 60 s of a fetch has no visible effect beyond the log line.

## Edge cases

- **Wake after a long sleep:** the block has expired, so `wake` fetches.
- **Retry and timer at the same time:** the first one runs; the second is reused (rule 4 or 5).
- **Retry also gets 429:** a new block is set and no further retry is scheduled. The next `scheduled` trigger resets `retryUsed`; if the block is still active, that tick is reused and schedules one retry at the block end (rule 3).
- **No subscription accounts:** no outcomes are recorded; the policy never blocks.
- **Account removed between fetch and reuse:** filtered out before aggregation.

## Testing

Swift Testing via `make test`.

- `EndpointPolicyTests`: each rule of `decide` in order; a `scheduled` trigger inside a block returns `retryAt` once per period; backoff 60, 120, 240 capped at the interval; `Retry-After` over backoff; one retry per scheduled period; `retry` after success is reused; backwards-clock guard; `scheduled` resets `retryUsed`.
- `UsageEndpointClientTests` (`StubURLProtocol`): 429 with delta-seconds, with HTTP-date, without header, with an unparsable header.
- `SubscriptionSourceTests`: `fetchOutcome` for success, 429, network error, not signed in (nil), two accounts with mixed outcomes.
- `RefreshCoordinatorTests` (fake network source with call counter, injectable clock): `.manual` twice within 60 s makes one call; `.local` makes none; a 429 schedules exactly one retry at the block end; a `scheduled` trigger inside a block reuses and the entry is stale; the pending-trigger merge keeps the strongest; reused results drop removed accounts.
- `ConfigurationTests`: `needsNetworkRefresh` false for price override, budget, log directory, marker, label and threshold edits; true for adding or removing a subscription account, changing its credential directory, or changing the alignment account.

**Manual check:** edit a price override and type several digits: the log shows reprice lines only. Click "Refresh now" twice within a minute: one fetch line, then "endpoint reused (last fetch N s ago)". Over an hour of normal use, count fetch lines: about 12.

## Out of scope

- Persisting fetch results or blocks across launches.

Note: spec 010 (`specs/010-keep-last-good-values/`) changed this. It saves the last good fetch results across launches; the policy state (blocks, spacing, retry state) stays in memory only. It also adds the `quickRetry` trigger: one retry 30 s after a transport failure, which skips the spacing but not a rate-limit block.
- Changing the refresh interval or the timer's schedule.
- The "1 more new models" wording in the price import preview (separate fix).
