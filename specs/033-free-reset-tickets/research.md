# Research: Free Reset Tickets

All findings were read from CodexBar (https://github.com/steipete/CodexBar, commit `ad0c567`, 2026-10-21) and from this repository. Nothing was checked against a live account; the quickstart's manual steps cover that.

## R1: Claude free-reset block

- **Decision**: Add `cedar_ember=1` as a query item to the existing `GET https://api.anthropic.com/api/oauth/usage` request (same headers, same session rules). Decode the optional top-level `cedar_ember` object leniently next to the existing `Body` fields: `eligible: Bool`, `grants: [{ resets_left: Int, resets_total: Int?, starts_at: ISO 8601?, ends_at: ISO 8601?, paused: Bool }]`. Ignore `id` and `usable_now` (never decoded).
- **Rationale**: No extra request (SC-005); CodexBar reads the same block from the same response (`ClaudeOAuthUsageFetcher.swift:61-98`, `ClaudeRateLimitResetCredits.swift:57-150`).
- **Usable rule** (spec FR-002): `eligible == true`; per grant `paused == false`, `starts_at` absent or `<= now`, `ends_at` absent or `> now`; the grant contributes `resets_left` tickets with expiry `ends_at`.
- **Missing vs malformed** (FR-003): no `cedar_ember` key, `eligible == false`, or an empty `grants` list is a successful read with zero tickets. A present block whose `eligible` or `grants` has the wrong type, a grant with a negative `resets_left`, an unparsable time, more than 200 grant records or more than 50 usable tickets is a clearing failure. The usage windows decode independently, so a bad block never fails the usage request.
- **Alternatives**: claude.ai web endpoint with cookies (rejected: AgentTacho reads no browser cookies, constitution III).

## R2: Claude flag refusal (FR-004)

- **Decision**: The client takes `includeTickets: Bool`. `SubscriptionSource` keeps a per-account `TicketFlag` state (`on`, `suspended`, `offForRun`) in the actor. Because `attempt` is static and runs in a task group, the actor passes the account's current flag into `attempt`, which returns the ticket read and the flag transition with the attempt; `apply` commits both. With `on`, a `UsageEndpointError.httpStatus(code)` where `400 <= code < 500`, `code != 401`, `code != 429` triggers one plain repeat in the same `attempt`. Plain success moves the state to `offForRun` and clears tickets; plain failure moves it to `suspended`, and the next plain success moves it back to `on` (the flag is sent on the following refresh).
- **Interaction with failure categories**: `FailureCategory.classify` maps 403 to `signInRejected`. The repeat's result alone feeds `apply`, so a 403 that is a real sign-in rejection is classified from the plain repeat, exactly as today; it costs one extra request per refusal (spec FR-004, SC-005). 401 and 429 are never repeated.
- **Alternatives**: retry only on 400 (CodexBar's rule; rejected by spec review because other client errors would hide usage until relaunch).

## R3: Codex reset credits

- **Decision**: `GET https://chatgpt.com/backend-api/wham/rate-limit-reset-credits` with the headers of the `wham/usage` request (`Authorization`, `ChatGPT-Account-ID` when known, `Accept`, `User-Agent`), the same ephemeral session (no cache, no cookies, redirects refused, unexpected host or path rejected) and `timeoutInterval = 10`. Sent only after `client.fetch` succeeded, inside `CodexLimitsSource.live`, with the credential already read (no second credential read). The URL is a `resetCreditsURL` init parameter of `CodexUsageClient` (default above) so tests can stub it. The 10 s bound is total: the request uses its own ephemeral session configuration with `timeoutIntervalForRequest` and `timeoutIntervalForResource` of 10 s.
- **Shape**: `{ available_count: Int, credits: [ { id, reset_type, status, granted_at, expires_at?, redeem_started_at?, redeemed_at?, title?, description? } ] }`. Only `status` and `expires_at` are decoded (`CodexOAuthUsageFetcher.swift:686-711`, `CreditsModels.swift:190-357`).
- **Usable rule**: `status == "available"` and `expires_at` absent or `> now`. A missing `credits` key is zero tickets; a wrong type, an unparsable time or more than 50 usable credits is a clearing failure. Any thrown request error (transport, timeout, HTTP status) is a temporary failure.
- **CodexBar headers not copied**: `OpenAI-Beta: codex-1` and `originator: Codex Desktop`. AgentTacho's `wham/usage` call works without them; if the credit endpoint refuses, that is a temporary failure and shows no glyphs. The walkthrough checks a real account.

## R4: Where tickets live

- **Decision**: `SubscriptionEntry.resetTickets: [ResetTicket]` and `CodexLimitsEntry.resetTickets: [ResetTicket]`, filled by the sources from an in-memory `lastTickets` dictionary (Claude per account id; Codex per canonical Codex home, mapped to accounts through `plan.home` for accounts with live limits on). Codex entries built without a request (`notDue`, `blocked`, `noRequest`, `fallback`, `graceEntry`) attach `lastTickets` minus expired. Claude attempts without a request: `notSignedIn` clears, `credentialsExpired` and `credentialReadFailed` keep. Copied by `reused(now:)`, `endingGrace` and `markedStale`; never passed to `SavedClaudeValues` or `SavedCodexValues`, so `last-good.json` is unchanged (FR-006). Pruned with the other per-account state.
- **Rationale**: entries are what the dropdown and trackers read; `lastGood` stores only statuses.

## R5: Notification record

- **Decision**: A protocol `ResetTicketNoticeStore` in UsageCore (`load() -> Set<ResetTicketNoticeKey>`, `save(_:)`) with a `UserDefaults` implementation storing an array of strings `"<accountId>|<expiry epoch seconds>|<step>"` under the key `freeResetNotices`, and an in-memory implementation for tests. The tracker loads once at init, prunes keys whose expiry has passed or whose account is gone, and saves after each change.
- **Rationale**: FR-016 requires no repeat across relaunches; UsageCore has no defaults abstraction today; the macOS defaults already hold UI preferences (README "What it writes").
- **Alternatives**: a JSON file in Application Support (rejected: new file); checking delivered notifications (rejected: the user can clear them).

## R6: Usage page links (FR-010a)

- **Decision**: Claude `https://claude.ai/settings/usage`, Codex `https://chatgpt.com/settings/usage?tab=overview`, as `AppLinks.claudeUsagePage` and `AppLinks.codexUsagePage`.
- **Rationale**: CodexBar uses and tests both for subscription accounts (`ClaudeProviderDescriptor.swift:152`, `StatusMenuTests.swift:174-177`, `CodexProviderDescriptorTests.swift:11`). A third-party page names `chatgpt.com/codex/settings/usage`, which no official source confirms.
- **Opening**: `NSWorkspace.shared.open(url)` (as `Updater.swift`), then the dropdown's `panel?.close()` through a closure passed to the sections.

## R7: Demo build

- **Decision**: Expiry notifications are wired in `AppModel.apply` inside the existing `#if !AGENTTACHO_DEMO` branch, next to the credential tracker. The demo still delivers its one threshold alert (`defaultScenarioFiresOneAlert` stays green).
- **Scenario**: `ClaudeWindows` gains an optional `tickets: [ScenarioTicket]` with `expiresIn: ScenarioDuration?` (absent means no expiry). `acc-max` gets two: `expiresIn: "2d4h"` and one without. New coverage fields `resetTicketsWithExpiry` and `resetTicketsWithoutExpiry`.

## R8: Times in tooltips

- **Decision**: Add `TimeText.expiry(_ date: Date) -> String` returning "in 2d 3h (Thu 14:00)" from the existing relative form and the private absolute form, so tooltips and notification bodies reuse the reset formats (FR-010, FR-015). Notification bodies use the absolute form via a second public method `TimeText.absolute(_:)`.

## R9: Diagnostics once per run

- **Decision**: Each source keeps a `Set<String>` of `"<accountId>|<failure kind>"` already logged; a failure kind is logged the first time per run (FR-019). The flag drop logs once per account. Log source names: `subscription` and `codex` as today, `notifications` for expiry events.

## R10: README and website

- README `Security and privacy`: line 65 (Codex sign-in also asks for reset credits), line 72 (query flag on the Claude request, the credit request and its 10 s timeout), line 79 (notification record in defaults; tickets in memory only, not in `last-good.json`), line 84 (requests per refresh: the Codex credit request and the single Claude repeat; tickets never redeemed), line 87 (expiry notification bullet and switch).
- Site: `src/components/agenttacho/Privacy.astro` mirrors these; `docs/card-candidates.md` entry updated (spec, pull request, status).
