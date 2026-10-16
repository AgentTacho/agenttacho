# Tasks: Keep Last Good Values

**Input**: Design documents from `specs/010-keep-last-good-values/` (spec.md, plan.md, research.md, data-model.md, contracts/last-good-file.md, quickstart.md)

**Tests**: Required. AGENTS.md asks for tests first; every implementation task follows its test task.

**Organization**: Tasks are grouped by user story so each story can be implemented and tested on its own after the foundational phase.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: US1 (blip), US2 (rejected sign-in), US3 (relaunch)

## Global Constraints

- Build and test only through the Makefile (`make test`, `make app`).
- Logic in `Sources/UsageCore` with tests; `Sources/AgentMeter` only renders and wires.
- Doc comments cite `spec 010 FR-0xx`. No em or en dash characters anywhere.
- Quick-retry delay 30 s (`RetryEpisodes.delay`), timer at `retryAt + 1 s`.
- Saved file `~/Library/Application Support/agentmeter/last-good.json`: file 0600 after every write, directory 0700, atomic replace, never a token (contracts/last-good-file.md).
- AgentMeter never writes to the agents' files.

---

## Phase 1: Setup

- [X] T001 Run `make test` and confirm all existing suites pass (baseline before changes).

---

## Phase 2: Foundational (blocking prerequisites)

**Purpose**: The shared classifier, episode type, trigger and new states that all three stories use.

- [X] T002 [P] Create `Tests/UsageCoreTests/FailureCategoryTests.swift` covering every row of the classification table in data-model.md: `UsageEndpointError.network` → transport, `.httpStatus(500)`/`(503)`/`(599)` → transport, `.httpStatus(401)`/`(403)` → signInRejected, `.rateLimited` → rateLimited, `.decoding`, `.httpStatus(302)`, `.httpStatus(404)`, `CodexUsageError.noLimits` → serviceChanged, an arbitrary other error type → transport (spec 010 FR-001).
- [X] T003 Create `Sources/UsageCore/Snapshot/FailureCategory.swift` with `public enum FailureCategory { transport, signInRejected, rateLimited, serviceChanged }` and `static func classify(_ error: Error) -> FailureCategory`, so T002 passes.
- [X] T004 [P] Create `Tests/UsageCoreTests/RetryEpisodesTests.swift` covering every transition in the RetryEpisodes table of data-model.md: first transport failure → `.grace(retryAt: now + 30, unmarked:)` with `unmarked` taken from `hasLiveValuesThisRun`; first non-transport failure → `.exhausted`; failure in grace → `.exhausted`; `expire` in grace → `.exhausted`; success from any phase clears the account; `retryAt(id)`; `forget(except:)` drops unknown ids; accounts are independent (spec 010 FR-004, FR-006, FR-009).
- [X] T005 Create `Sources/UsageCore/Snapshot/RetryEpisodes.swift` per data-model.md (`delay = 30`), so T004 passes.
- [X] T006 [P] Add tests to `Tests/UsageCoreTests/EndpointPolicyTests.swift`: `decide(.quickRetry)` returns `.fetch` right after a failed fetch (no 60 s spacing, no "already fresh" reuse), returns `.reuse(reason:retryAt: nil)` while a rate-limit block is active, and does not change `retryUsed`; `RefreshTrigger.quickRetry.rank == 2` (spec 010 FR-007, FR-008).
- [X] T007 Add `case quickRetry` to `RefreshTrigger` (rank 2) and its rule in `EndpointPolicy.decide` in `Sources/UsageCore/Snapshot/EndpointPolicy.swift`; add `.quickRetry` to the switch in `CodexLimitsSource.decide` (temporarily as `.notDue`) and wherever else `RefreshTrigger` is switched over, so T006 passes and the package builds.
- [X] T008 Extend the state types per data-model.md, with compile-only updates to every exhaustive switch (`RefreshCoordinator.describe`, the `subscriptionSourceFailure` carry-over switch in `RefreshCoordinator.performRefresh` (`.retrying` and `.signInRejected` become `.stale` with the source failure, keeping `lastGoodAt`), `DropdownView.stateLine`, `BarLayout.subscriptionItem`, `CodexLimitsSource.describe`, `CodexLimitsEntry.markedStale` (`.retrying` becomes `.stale`)): in `Sources/UsageCore/Snapshot/UsageSnapshot.swift` add `SubscriptionState.retrying(lastGoodAt:error:retryAt:)` and `.signInRejected(lastGoodAt:)`, `SubscriptionState.isStale` (true for `.stale`, `.signInRejected`, `.credentialsExpired`), `SubscriptionEntry.failureCategory`, `SubscriptionEntry.quickRetryAt`, `SubscriptionEntry.endingGrace(now:)`, `UsageSnapshot.isPreliminary` (default false); in `Sources/UsageCore/Subscription/CodexLimits.swift` add `CodexLimitsState.retrying(reason:retryAt:)` (`isStale` false, `impliedLiveLimits` true), `CodexLimitsEntry.quickRetryAt`, `CodexLimitsEntry.signInRejected`. Add unit tests for `endingGrace(now:)` (retrying with past `retryAt` → stale with the same error and `lastGoodAt`; future `retryAt` and other states unchanged) to `Tests/UsageCoreTests/SubscriptionSourceTests.swift` and for the new Codex state's flags and `markedStale` to `Tests/UsageCoreTests/CodexLimitsTests.swift`.

**Checkpoint**: `make test` passes; no behavior changes yet.

---

## Phase 3: User Story 1 - A network blip does not mark values stale (Priority: P1) MVP

**Goal**: One quick retry 30 s after a transport failure, values unmarked meanwhile, stale only if the retry fails too; for Claude and Codex.

**Independent Test**: With an account showing live values, make the next request fail with a transport error and the following one succeed: the bar never shows `~` (quickstart step 1).

- [X] T009 [US1] Add tests to `Tests/UsageCoreTests/SubscriptionSourceTests.swift` with a stub client and clock: after a success, a `.network` failure yields `.retrying(lastGoodAt:error:retryAt: now + 30)` with the previous status, `failureCategory == .transport` and `quickRetryAt` set; an HTTP 503 does the same; a second failure (any category) yields `.stale` and `quickRetryAt == nil`; a later success clears the episode so the next transport failure gets a new grace period; a first-launch transport failure without any values yields the stale "no data yet" entry with `quickRetryAt` set; a `.quickRetry` collect at or after `retryAt` requests only accounts in grace whose retry is due, and returns the other accounts' last entries with `fetchOutcome == nil`; a `.quickRetry` before `retryAt` requests nothing for that account; an account without a last entry or with a changed credential directory is requested on `.quickRetry`; a grace account counts as due on `.quickRetry` only while `retryAt <= now < retryAt + RetryEpisodes.delay`; once that window has passed without a request (for example the retry was suppressed by a rate limit and ended by `endingGrace`), the source expires the episode, so a later `.quickRetry` (fired by the Codex timer) does not request the account and its next failure is stale with no second retry; rate limited and service changed failures never set `quickRetryAt`; credentials expired, unreadable and not signed in give `failureCategory == nil`, no `quickRetryAt` and their existing wording (spec 010 FR-002, FR-004 to FR-007, FR-009).
- [X] T010 [US1] Implement T009 in `Sources/UsageCore/Subscription/SubscriptionSource.swift`: classify thrown errors with `FailureCategory.classify`, own a `RetryEpisodes`, track accounts with a successful request this run, keep `lastEntries` per account for the `.quickRetry` subset, log the category and "quick retry scheduled at" (spec 010 FR-003). Doc comments cite spec 010.
- [X] T011 [US1] Add tests to `Tests/UsageCoreTests/CodexLimitsSourceTests.swift`: after a live success, a transport failure shows `.retrying(reason:retryAt:)` with the shown observation and `quickRetryAt`; a `.quickRetry` refresh at or after `retryAt` and within 60 s of the failed attempt fetches for that account (spacing bypassed) and only for accounts in grace whose retry is due; a `.quickRetry` before `retryAt` does not fetch; a `.local` or `.wake` refresh within the spacing before the retry time keeps `.retrying`; a `.quickRetry` while the home is rate limited shows stale with the transport reason and exhausts the episode; a second failure is stale; a 5xx answer is transport with reason "usage service unavailable (HTTP 503)"; a Codex answer without main-bucket windows and an answer from an unexpected location are service changed (no retry); expired, missing and remembered-rejected sign-ins give no `quickRetryAt` and their existing wording (spec 010 FR-001, FR-002, FR-004 to FR-008).
- [X] T012 [US1] Implement T011 in `Sources/UsageCore/Subscription/CodexLimitsSource.swift`: `failure(for:)` keyed by `FailureCategory` (5xx wording), a `RetryEpisodes` value plus a separate set of accounts with a live success this run, `.quickRetry` handling in `decide` (grace with due retry → `.fetch`, otherwise `.notDue`), `.retrying` entries in the `.notDue` and `.blocked` paths before the retry time, `expire` when blocked at or after the retry time, log lines per plan Design Note 8. In `Sources/UsageCore/Subscription/CodexUsageClient.swift`, throw `UsageEndpointError.decoding("answer from an unexpected location")` instead of `.network` for that case, with a test in `Tests/UsageCoreTests/CodexUsageClientTests.swift` that an answer from another host throws `.decoding`; confirm the existing transport test (`.network`) still passes. Apply the same due window as T009 for Codex grace accounts.
- [X] T013 [US1] Add tests to `Tests/UsageCoreTests/RefreshCoordinatorTests.swift` (injected clock, `retrySleep` and a separate `quickRetrySleep`): a `.retrying` entry schedules one `.quickRetry` refresh at `retryAt + 1 s`; the earliest of several `quickRetryAt` values wins; a reprice with the same earliest time does not reschedule; a scheduled refresh that fetches before the retry cancels the pending quick retry and its outcome ends grace; a `.wake` refresh that fetches (after the spacing) does the same; a `.wake` refresh reused by spacing leaves the quick retry pending; a quick retry while the policy is blocked is reused and the reused `.retrying` entry becomes `.stale` through `endingGrace`; a reprice after the retry time also shows `.stale`; `.retrying` entries add no source error but keep `lastSuccessfulRefreshAt` at the previous value; `.signInRejected` entries add a source error like `.stale`; a quick retry sets the policy's last attempt (a manual refresh 10 s later is spaced) and a 429 on it sets the shared block; a successful quick retry keeps a pending `.settings` follow-up (spec 010 FR-005, FR-007 to FR-010).
- [X] T014 [US1] Implement T013 in `Sources/UsageCore/Snapshot/RefreshCoordinator.swift`: `quickRetryTask` and an injectable `quickRetrySleep` next to `retryTask`, scheduling from `quickRetryAt` of subscription and Codex entries after each refresh (only when the earliest time changes), `.quickRetry` in the pending-trigger rule (a scheduled tick replaces it, as for `.retry`), `endingGrace(now:)` applied to gathered subscription entries, `.retrying` excluded from source errors but holding back `lastSuccessfulRefreshAt`, `.signInRejected` counted as a source error, a successful quick retry cancelling only a rate-limit `.retry`, log lines "quick retry sent/dropped/suppressed".
- [X] T015 [P] [US1] Add tests to `Tests/UsageCoreTests/BarLayoutTests.swift`: a Claude `.retrying` entry and a Codex `.retrying` entry show their percent without the stale marker; then update `Sources/UsageCore/Bar/BarLayout.swift` so they pass (spec 010 FR-005).
- [X] T016 [US1] In `Sources/AgentMeter/DropdownView.swift`, render `.retrying` for Claude and Codex as a caption in `.secondary`: "Couldn't reach the usage service, retrying at HH:MM" (the failure text for 5xx), without the stale wording; keep the stale and rate-limit notes unchanged (spec 010 FR-005).

**Checkpoint**: US1 complete; `make test` passes; quickstart step 1 can be tried.

---

## Phase 4: User Story 2 - A rejected sign-in asks the user to act (Priority: P2)

**Goal**: A 401/403 from the Claude usage service is its own state with a red action note; Codex rejected reasons use the same style.

**Independent Test**: A stubbed HTTP 401 for an account with values shows `~` and the red sign-in note (quickstart step 2).

- [X] T017 [US2] Add tests to `Tests/UsageCoreTests/SubscriptionSourceTests.swift`: HTTP 401 and 403 yield `.signInRejected(lastGoodAt:)` with the previous status, `failureCategory == .signInRejected` and no `quickRetryAt`; a rejection without previous values yields `.signInRejected(lastGoodAt: nil)` with no status; a later success returns `.ok`; a transport failure in grace followed by a rejected quick retry yields `.signInRejected` (spec 010 FR-006, FR-010, FR-011).
- [X] T018 [US2] Implement T017 in `Sources/UsageCore/Subscription/SubscriptionSource.swift`.
- [X] T019 [P] [US2] Add tests to `Tests/UsageCoreTests/BarLayoutTests.swift`: `.signInRejected` with a percent shows the stale marker, without values shows the placeholder; `.credentialsExpired` with a status shows its percent with the stale marker (changed from `--`), without a status `--`; then update `Sources/UsageCore/Bar/BarLayout.swift`, including the `subscriptionItem` doc comment that says `--` for expired credentials (spec 010 FR-010, FR-015).
- [X] T020 [P] [US2] Add tests to `Tests/UsageCoreTests/CodexLimitsSourceTests.swift`: a 401 answer, a 403 answer and the remembered-token case set `CodexLimitsEntry.signInRejected`, with and without an observation; an offline failure does not; then set the flag from `Failure.signInRejected` in `Sources/UsageCore/Subscription/CodexLimitsSource.swift` with wording unchanged (spec 010 FR-012).
- [X] T021 [US2] In `Sources/AgentMeter/DropdownView.swift`, render `.signInRejected` in `.red`: "Sign-in rejected, run claude to sign in again", or "run CLAUDE_CONFIG_DIR=<configured directory> claude to sign in again" when the account's credential directory, expanded with `Paths.expand`, differs from the expanded `Paths.defaultClaudeDirectory`, plus "Last good value <time>" when `lastGoodAt` is set; render a Codex entry with `signInRejected` in `.red` instead of `.orange` or `.secondary`, in both its stale and its unavailable branch (spec 010 FR-010, FR-012).

**Checkpoint**: US2 complete; `make test` passes.

---

## Phase 5: User Story 3 - Values survive a relaunch (Priority: P3)

**Goal**: Last good values saved on every success, shown right after launch, marked stale once the first refresh fails; reset windows show 0%.

**Independent Test**: Fetch, quit, start offline: every subscription account shows its values right away and stale with the original time after the first refresh (quickstart step 3).

- [X] T022 [US3] Add tests for `SubscriptionStatus.effective(now:)` to `Tests/UsageCoreTests/BarLayoutTests.swift` (5-hour, 7-day and model windows with a passed reset show 0% and nil reset; future resets unchanged; the bar percent of a stale entry whose 7-day window reset shows 0) and implement: make `ModelLimit.resetsAt` optional in `Sources/UsageCore/Snapshot/UsageSnapshot.swift` (update `Sources/UsageCore/Subscription/UsageEndpointClient.swift` and its tests), add `effective(now:)`, use it in `Sources/UsageCore/Bar/BarLayout.swift` with `snapshot.generatedAt` (spec 010 FR-016).
- [X] T023 [US3] Add `Paths.lastGoodFileURL` (`~/Library/Application Support/agentmeter/last-good.json`) in `Sources/UsageCore/Config/Paths.swift` and create `Tests/UsageCoreTests/LastGoodStoreTests.swift` against a temporary home: round trip of the contract example (contracts/last-good-file.md, model limit with and without `resetsAt`); `values()` returns the loaded values plus later replaces; `replace(claude:)` and `replace(codex:)` keep the other section; the file has mode 0600 after the first and after a second write; a new directory has 0700 and an existing 0755 directory is tightened to 0700; an existing file is replaced atomically (no partial file after a write); a failed write (read-only directory) is logged once and does not throw; a missing file, invalid JSON and `"version": 2` load as nil with a problem string; a written file contains none of the token strings used by the test credentials (SC-004) (spec 010 FR-013, FR-014, FR-018).
- [X] T024 [US3] Create `Sources/UsageCore/Snapshot/LastGoodStore.swift` with `SavedClaudeValues`, `SavedCodexValues`, `SavedWindow`, `SavedModelLimit` (optional `resetsAt`), `LastGoodValues` and the `LastGoodStore` actor (`load(from:)`, `values()`, `replace(claude:)`, `replace(codex:)`) per data-model.md and the contract (ISO 8601 dates with fractional seconds), so T023 passes.
- [X] T025 [US3] Add tests to `Tests/UsageCoreTests/SubscriptionSourceTests.swift` with a `LastGoodStore` on a temporary file and a temporary `Paths` home: a success writes the account's values with the canonical credential directory and no plan type; an unchanged second success does not rewrite the file; removing an account drops it at the next write; saved values with a matching canonical directory (`~/.claude` vs the expanded path) are used as last good values and appear in `savedOutput(configuration:now:)` as `.ok` entries; a mismatching directory is ignored; a saved `fetchedAt` in the future is clamped to `now`; a failure after launch with saved values yields `.stale(lastGoodAt: savedFetchedAt, ...)` and never `.retrying` (no grace for saved values), while `quickRetryAt` is still set for a transport failure; credentials expired or unreadable show the saved values stale; not signed in shows none (spec 010 FR-005, FR-013, FR-015).
- [X] T026 [US3] Implement T025 in `Sources/UsageCore/Subscription/SubscriptionSource.swift`: `init` gains `store: LastGoodStore? = nil` and `paths: Paths = Paths()`; seeding once from `store.values()`; saved map after each collect; `SavedValuesSource` conformance (protocol added to `Sources/UsageCore/Snapshot/RefreshCoordinator.swift`).
- [X] T027 [US3] Add tests to `Tests/UsageCoreTests/CodexLimitsSourceTests.swift` and implement them in `Sources/UsageCore/Subscription/CodexLimitsSource.swift` (`init` gains `store: LastGoodStore? = nil`): a live success writes windows with length, limit-reached flag and plan type; a saved live result with a matching canonical Codex home seeds `lastLive` together with `accountHomes`, survives the first collect, and competes with snapshots by observation time (spec 007 FR-005); after a failed first fetch it is shown stale; a transport failure on the first fetch after launch with a saved live result yields stale (not `.retrying`) with `quickRetryAt` set; a saved `observedAt` in the future is clamped to `now`; turning live limits off discards it and the next write drops it; `savedOutput` returns the newer of the saved live result and the newest snapshot; a Codex home mismatch ignores the saved entry (spec 010 FR-005, FR-013, FR-015, FR-017).
- [X] T028 [US3] In `Sources/AgentMeter/DropdownView.swift`, use `effective(now:)` for the Claude section header percent, window rows and model limit rows (hide the reset text when nil); while `snapshot.isPreliminary`, show "Refreshing…" instead of "No data" in the subscription state line, instead of the empty-group text in group and budget sections, and in the footer instead of "No successful refresh yet" (spec 010 FR-015, FR-016).
- [X] T029 [US3] Add tests to `Tests/UsageCoreTests/RefreshCoordinatorTests.swift` and implement `publishSavedValues()` in `Sources/UsageCore/Snapshot/RefreshCoordinator.swift`: it yields a snapshot with `isPreliminary == true` containing only the saved subscription and Codex entries (groups, budgets, token accounts empty, `lastSuccessfulRefreshAt` nil) and stores it as `previousSnapshot`, not `latestSnapshot`; it yields nothing when no source has saved values, and nothing when a refresh result exists, checked again after its awaits; it seeds `lastAlignmentReset` from the alignment account's saved 7-day reset only when that reset is in the future, so the first refresh's initial window is aligned; a failed first refresh after it shows the saved Claude values stale through the carry-over path (spec 010 FR-015, FR-020).
- [X] T030 [US3] Wire it up in `Sources/AgentMeter/App.swift`: load `LastGoodStore.load(from: paths.lastGoodFileURL)` once at launch and log a problem string or the number of loaded entries (no values); pass one `LastGoodStore` to `SubscriptionSource` and `CodexLimitsSource`; call `coordinator.publishSavedValues()` after registering sources and before `requestRefresh(trigger: .launch)`; in `apply(_:)` compute "first snapshot" as the first non-preliminary one, and pass a preliminary snapshot to the threshold tracker only with `subscriptions` emptied (spec 010 FR-018, FR-019).

**Checkpoint**: US3 complete; `make test` passes; quickstart steps 3 and 4 can be tried.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T031 [P] Update `README.md`: in "Security and privacy" add `~/Library/Application Support/agentmeter/last-good.json` (per account the last plan-limit percentages, reset times, fetch time and the credential directory path; readable only by you; no token; safe to delete), add it to the "Usage data is stored in plain text" bullet, and change "a single read-only request per refresh" to say there is at most one extra retry 30 s after a network failure; in "Accounts and budgets" update the Codex bullet (saved live result, brief retry before marking stale) and describe the quick retry and the rejected-sign-in note for Claude where stale values are described; check every remaining statement stays true (spec 010 FR-021).
- [X] T032 [P] Check every changed file for em dash and en dash characters and for doc comments citing spec 010 where new behavior is implemented; fix any gaps.
- [X] T033 Run `make test` and `make app`; follow `specs/010-keep-last-good-values/quickstart.md` steps that need no network manipulation (file contents and permissions after a refresh) and note the result.

---

## Dependencies & Execution Order

- **Phase 1** → **Phase 2** (T002 to T008) → user stories.
- **US1** (T009 to T016): depends on Phase 2 only. MVP.
- **US2** (T017 to T021): depends on Phase 2; T017/T018 edit the same file as T009/T010, so run after US1 when done sequentially.
- **US3** (T022 to T030): depends on Phase 2; T022 (optional `ModelLimit.resetsAt`) comes before T023/T024; T025 to T027 edit the same source files as US1 and US2.
- **Polish** after all stories.

Within each story: test task before its implementation task.

## Parallel Opportunities

- Phase 2: T002, T004, T006 in parallel (separate test files); T003, T005 in parallel after their tests.
- US1: T015 (BarLayout) in parallel with T009 to T014.
- US2: T019 and T020 in parallel with T017/T018.
- Polish: T031 and T032 in parallel.

## Implementation Strategy

1. Phase 1 and 2, then US1: the most visible gap (wake blips) is fixed and shippable on its own.
2. US2: rejected sign-ins get their state.
3. US3: persistence and the early result, plus the README statement (T031 must ship with US3 because it adds the file).
