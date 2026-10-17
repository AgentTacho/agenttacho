# Implementation Plan: Keep Last Good Values

**Branch**: `010-keep-last-good-values` | **Date**: 2026-10-15 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/010-keep-last-good-values/spec.md`

## Summary

Make transient failures of the two plan-limit services (Claude usage service, Codex live limits) invisible, make rejected sign-ins actionable, and keep the last good values across launches. One shared failure classifier and one shared per-account episode type drive both sources; a new `quickRetry` trigger runs one retry 30 s after a transport failure while the values stay unmarked; a small JSON file in AgentTacho's application support directory holds the last good numbers, loaded at launch into an early result before the first refresh finishes.

## Technical Context

**Language/Version**: Swift 5.10 tools, macOS 14+

**Primary Dependencies**: Foundation, SwiftUI (app layer only); no new dependencies

**Storage**: New file `~/Library/Application Support/agenttacho/last-good.json` (JSON, 0600, atomic writes); existing config and log unchanged

**Testing**: Swift Testing via `make test`; stub clients and `StubURLProtocol` for failures; injected clocks and `retrySleep` for timing

**Target Platform**: macOS menu bar app

**Project Type**: desktop app (UsageCore library + thin SwiftUI layer)

**Performance Goals**: no measurable change; one extra request per account per failure episode at most (SC-005); file writes only when saved values change

**Constraints**: AgentTacho never writes to the agents' files; no tokens in any file (FR-014); README security section updated in the same change (FR-021, AGENTS.md)

**Scale/Scope**: 5 to 10 accounts; file of a few KB at most

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The constitution file is the unfilled template, so the project conventions from AGENTS.md serve as the gates:

| Gate | Status |
|---|---|
| Logic in `UsageCore`, covered by tests; `Sources/AgentTacho` stays thin | Pass: classifier, episodes, store, policy, source and coordinator changes are in UsageCore; the app layer only renders new states and calls `publishSavedValues()` |
| Tests first | Pass: tasks order tests before implementation per unit |
| Doc comments cite spec requirements | Pass: planned (`spec 010 FR-0xx`) |
| No em or en dashes | Pass: checked in review |
| Agents' files read only; credential or network changes keep README "Security and privacy" true | Pass: new file is AgentTacho's own; README update is FR-021 |
| Build and test only through the Makefile | Pass |

Post-design re-check: unchanged, all pass.

## Project Structure

### Documentation (this feature)

```text
specs/010-keep-last-good-values/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── last-good-file.md
├── checklists/requirements.md
└── tasks.md            # /speckit-tasks
```

### Source Code (repository root)

```text
Sources/UsageCore/
├── Config/Paths.swift                       # + lastGoodFileURL
├── Snapshot/
│   ├── FailureCategory.swift                # new: classifier (FR-001)
│   ├── RetryEpisodes.swift                  # new: per-account episodes (FR-004 to FR-009)
│   ├── LastGoodStore.swift                  # new: saved values file (FR-013, FR-014, FR-018)
│   ├── EndpointPolicy.swift                 # + .quickRetry trigger and decision
│   ├── RefreshCoordinator.swift             # quick-retry timer, grace expiry, publishSavedValues, SavedValuesSource
│   └── UsageSnapshot.swift                  # new states, effective(now:), isPreliminary
├── Subscription/
│   ├── SubscriptionSource.swift             # classification, episodes, quickRetry subset, store, saved output
│   ├── CodexLimits.swift                    # .retrying state, signInRejected flag
│   └── CodexLimitsSource.swift              # classification, episodes, quickRetry gate, store, saved output
└── Bar/BarLayout.swift                      # stale rules for new states, effective(now:)

Sources/AgentTacho/
├── App.swift                                # build LastGoodStore, publishSavedValues, skip preliminary for thresholds
└── DropdownView.swift                       # grace / rejected notes and colors, effective(now:), "Refreshing…" for preliminary

Tests/UsageCoreTests/
├── FailureCategoryTests.swift               # new
├── RetryEpisodesTests.swift                 # new
├── LastGoodStoreTests.swift                 # new
├── EndpointPolicyTests.swift                # + quickRetry
├── SubscriptionSourceTests.swift            # + grace, rejected, quick retry subset, saved values
├── CodexLimitsSourceTests.swift             # + grace, quick retry gate, saved live result
├── RefreshCoordinatorTests.swift            # + timer, collisions, grace expiry, early result, alignment seed
└── BarLayoutTests.swift                     # + new states, reset zeroing

README.md                                    # Security and privacy: last-good.json (FR-021)
```

**Structure Decision**: Existing single-package layout; new logic in three new UsageCore files plus targeted changes in the two sources, the policy and the coordinator.

## Design Notes

### 1. Classification (FR-001 to FR-003)

`FailureCategory.classify` (research R4) is called in both sources where a request threw. Claude: `SubscriptionSource.fetch` stores the category on the entry and logs it. Codex: `CodexLimitsSource.failure(for:)` becomes a function of the category (plus status for wording); 5xx moves from "usage service returned HTTP N" to transport with reason "usage service unavailable (HTTP N)". Credential-stage failures keep their paths and are not classified.

### 2. Episodes and grace in the sources (FR-004 to FR-006, FR-009)

Both sources own a `RetryEpisodes` value. On success: `succeeded(id)`. On a classified failure: `failed(id, category, now, hasLiveValuesThisRun:)`, where "live values this run" is true when the account had a successful request since launch (Claude: an `ok` entry this run; Codex: a live result this run, or an unmarked snapshot shown under 007 FR-005 and FR-006). The returned phase picks the entry:

- `grace(retryAt, unmarked: true)`: Claude `.retrying(lastGoodAt:error:retryAt:)` with the previous status; Codex `.retrying(reason:retryAt:)` with the shown observation.
- `grace(retryAt, unmarked: false)`: the stale entry as today (or "no data yet"), but the episode still has a pending retry, signalled through a `quickRetryAt` value the coordinator reads (Claude: `SubscriptionEntry.quickRetryAt`; Codex: `CodexLimitsEntry.quickRetryAt`).
- `exhausted`: stale as today, with the rejected styling for `signInRejected`.

To keep the coordinator simple, every entry exposes `quickRetryAt: Date?` (set for both grace variants); `.retrying` additionally drives the display.

### 3. Quick-retry trigger (FR-004, FR-007 to FR-009)

- `EndpointPolicy.decide(.quickRetry)` → `.fetch` unless blocked (research R2).
- `RefreshCoordinator`: after assembling each snapshot, `nextQuickRetry = min(quickRetryAt of all subscription and Codex entries where > now)`; schedule `quickRetryTask` for it (`retrySleep`, injectable), or cancel. `requestRefresh` treats `.quickRetry` like `.retry` for the pending-trigger rule (a scheduled tick replaces it).
- `SubscriptionSource.collect` on `.quickRetry`: request accounts whose episode is in grace; return `lastEntries[id]` with `fetchOutcome = nil` for the rest, so `FetchOutcome.combined` only sees requested accounts.
- `CodexLimitsSource.decide` on `.quickRetry`: grace phase → `.fetch` (or `.blocked`, which with a grace phase whose retry time has passed calls `expire(id)` and shows stale); no grace → `.notDue`. A `.notDue` or `.blocked` for an account in grace before its retry time keeps the `.retrying` entry.
- A scheduled or wake refresh that actually requests the account ends grace through the normal success/failure path (FR-008). A reused refresh leaves the pending retry.

### 4. Grace expiry for reused Claude results (FR-007, research R3)

In `performRefresh`, after the subscription entries are gathered (fresh or reused), apply `entry.endingGrace(now: started)` to each. A reused `.retrying` entry whose retry time has passed (the quick retry was reused because of a rate-limit block, or a reprice ran after the retry time) becomes `.stale` with its transport reason. `SubscriptionSource` learns of it on its next request: its episode is still in grace, so that request's failure exhausts it (no second retry) and a success clears it.

`.retrying` entries are not source errors (no "stale" footer), but they hold back `lastSuccessfulRefreshAt` (FR-005): the refresh counts as successful for the footer time only when no entry is `.retrying`.

### 5. Rejected sign-in (FR-010 to FR-012)

`SubscriptionSource`: a `signInRejected` category yields `.signInRejected(lastGoodAt:)` with the previous status. BarLayout marks it stale when a percent exists. DropdownView renders the red note; for a non-default credential directory it names `CLAUDE_CONFIG_DIR=<directory as configured>`. Codex: `Failure.signInRejected` sets `CodexLimitsEntry.signInRejected`, which DropdownView renders in red; wording unchanged.

### 6. Saved values (FR-013 to FR-019)

- `App` loads `LastGoodStore.load(from: paths.lastGoodFileURL)` once, logs a problem string if any, and passes one `LastGoodStore` to both sources. Sources seed their in-memory last good values from it on first `collect` (and in `savedOutput`), keyed by account id and accepted only when the canonical directory matches. Seeded Claude values do not count as "live values this run" (no grace for saved values, FR-005).
- After each `collect`, a source builds its saved map from its current in-memory last good values (only accounts in this configuration) and calls `store.replace(...)` when it differs from the last written map.
- Codex: `lastLive` is seeded from the saved entry (as an observation with `origin = .live`); turning live limits off discards it (existing code path) and the next write drops it.
- `RefreshCoordinator.publishSavedValues()` (research R6) yields the preliminary snapshot and seeds `lastAlignmentReset` (FR-020, research R9).
- `App.apply` skips threshold evaluation and first-snapshot work for a preliminary snapshot (FR-019).

### 7. Reset at display time (FR-016)

`SubscriptionStatus.effective(now:)` (research R7) is used by BarLayout (`barPercent`) and DropdownView (section header percent, window rows, model rows). The alignment step is unchanged: the window resolver already rolls a past reset forward, and saved resets seed alignment only when in the future (FR-020). `ModelLimit.resetsAt` becomes optional; the model row hides the reset text when nil.

### 10. Review-driven details (plan review)

- Quick retry requests only accounts whose retry is due, `retryAt <= now < retryAt + RetryEpisodes.delay` (a timer fired for one provider never sends another provider's retry early); after that window a grace account that got no request (for Claude, one ended by `endingGrace`) is expired by its source. The timer fires at `retryAt + 1 s`, like `scheduleRetry`, and is rescheduled only when the earliest time changes. It uses its own injectable sleep (`quickRetrySleep`) so existing retry tests stay isolated.
- On `.quickRetry`, `SubscriptionSource` also requests accounts without a last entry or with a changed credential directory.
- A successful quick retry cancels only a pending rate-limit `.retry`, never a `.settings` follow-up.
- Codex: seeding `lastLive` from the file also seeds `accountHomes`, so the first collect's home check does not wipe it; "live values this run" is a separate set, not `lastLive != nil`. `CodexUsageClient` throws `.decoding("answer from an unexpected location")` instead of `.network` for that case, so it classifies as service changed.
- `publishSavedValues()` re-checks `latestSnapshot == nil` after its awaits, and sets `previousSnapshot` (not `latestSnapshot`) to the preliminary snapshot so the carry-over paths keep saved values on a failed first refresh.
- `App.apply`: "first snapshot" means the first non-preliminary one. The preliminary snapshot goes to the threshold tracker with `subscriptions` emptied, so saved Codex values set the Codex baseline (FR-019, spec 007 FR-015) and Claude values never do.
- BarLayout shows a `.credentialsExpired` account's percent with `~` when a status exists (FR-015).
- The rejected-sign-in note compares the configured credential directory with the default after expanding both.

### 8. Diagnostic log (FR-003, FR-018)

Lines per account: category and detail of a failed request; "quick retry scheduled at", "quick retry sent", "quick retry dropped (scheduled refresh took its place)", "quick retry suppressed (rate limited), marked stale". One line per launch for an unreadable saved file; one line when saved values were loaded (count only, no values).

### 9. README (FR-021)

Add a "What it writes" note (or a row in the table) to "Security and privacy": `~/Library/Application Support/agenttacho/last-good.json`, holds per account the last plan-limit percentages, reset times, fetch time and the credential directory path, readable only by you, no token; deleting it is safe. Adjust the sentence "Tokens are never written to the configuration, the log, notifications or any other file" only if needed (it stays true).

## Complexity Tracking

No gate violations. The one structural addition, a second timer task in the coordinator, is justified by keeping the rate-limit retry design unchanged (research R2).
