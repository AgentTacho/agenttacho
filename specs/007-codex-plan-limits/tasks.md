# Tasks: Codex Plan Limits

**Input**: Design documents from `/specs/007-codex-plan-limits/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/codex-usage-endpoint.md, contracts/config-file.md, quickstart.md

**Tests**: Included. The project covers every `UsageCore` type with Swift Testing suites (`import Testing`, `@Suite`, `@Test`, `#expect`). Write each test task right before its implementation and confirm that it fails once the package compiles.

**Organization**:
- Phase 2 holds the shared model, configuration, coordinator plumbing and the `WindowKind` refactor. Every story depends on it.
- Stories run in priority order: US1 (live utilization, P1), US2 (fallback, P1), US3 (thresholds, P2), US4 (snapshot-only mode, P3).

**Global constraints** (from plan.md):
- Never write to a Codex home, never call `auth.openai.com`, never decode or hold the refresh token or id token.
- Only `https://chatgpt.com/backend-api/wham/usage` is requested, through an ephemeral `URLSession`.
- With `liveLimits == false`, neither `auth.json` is read nor a request made.
- No credential text in logs, errors, notifications, entry descriptions, or files.
- Claude subscription fetch and `EndpointPolicy` stay unchanged; existing tests pass unchanged unless a task says otherwise.
- No em-dash or en-dash characters. Doc comments cite FR ids.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on incomplete tasks)
- **[Story]**: US1 to US4

---

## Phase 1: Setup

- [X] T001 Run `make test` and confirm all existing suites pass (baseline).
- [X] T002 [P] Add synthetic rollout fixtures under `Tests/UsageCoreTests/Fixtures/codex/` (contracts/codex-usage-endpoint.md section 3), each with `session_meta` plus `token_count` events, timestamps in October 2026:
  - `limits-plus.jsonl`: two snapshots (older and newer) with `limit_id "codex"`, `plan_type "plus"`, primary 300 min and secondary 10080 min; the newer one has `info: null`.
  - `limits-free.jsonl`: one snapshot, `plan_type "free"`, primary 43200 min, `secondary: null`.
  - `limits-noise.jsonl`: a `limit_id "premium"` snapshot with null windows, an all-null `rate_limits`, an API-key snapshot (`plan_type: null`) with windows, and one valid plus snapshot in between (the valid one must win).
  - `limits-reached.jsonl`: one plus snapshot with primary `used_percent 100.0` and `rate_limit_reached_type {"type":"rate_limit_reached"}`.
  - `limits-forked.jsonl`: a forked file whose copied parent history (repeated `session_meta`, events stamped within 1 s of the fork) carries a plus snapshot, while the child's own events carry no `rate_limits`, following the spec 006 subagent fixture layout (expected result: nil).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Settings fields, limit value types, coordinator plumbing, the snapshot rename, and the `WindowKind` refactor. The package must compile and pass at the end of this phase.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T003 Add tests in `Tests/UsageCoreTests/ConfigurationTests.swift` (FR-016, FR-017, contracts/config-file.md):
  - A spec 006 `codexSubscription` account (only `codexHome`) decodes with `shownInBar == true`, `thresholds == []`, `liveLimits == true`.
  - All four keys round-trip.
  - A threshold of 0 or below on a Codex account fails `validate()`.
  - `needsRefresh(comparedTo:)` (which uses the private `dataRelevant()`) is false for two configs that differ only in a Codex account's `shownInBar` or `thresholds`, and true when they differ in `liveLimits`.
  - A configuration whose `alignmentAccountId` names a Codex account fails validation, and `effectiveAlignmentAccountId` with a Codex account listed first returns the first Claude subscription account.
- [X] T004 In `Sources/UsageCore/Config/Configuration.swift` (research R9): extend `CodexSubscriptionSettings` with `shownInBar = true`, `thresholds: [Int] = []`, `liveLimits = true` and an initializer with defaults. In `Account` decoding of `"codexSubscription"`, read `shownInBar` and `thresholds` (existing coding keys) and a new `liveLimits` key with `decodeIfPresent ?? default`; encode all of them. In `validate()`, apply `checkThresholds` to Codex accounts. In `dataRelevant()`, blank `shownInBar` and `thresholds` for `.codexSubscription` (keep `liveLimits`). Update any call site that constructs `CodexSubscriptionSettings(codexHome:)` only if it no longer compiles.
- [X] T005 [P] Add tests in `Tests/UsageCoreTests/CodexLimitsTests.swift` (new) (FR-009, FR-010, research R2, R7):
  - `CodexLimitWindow.name`: 300 min "5-hour", 60 min "1-hour", 10080 min "weekly", 10000 min "weekly" (rounds to 7 days), 43200 min "30-day", 2160 min "2-day" (36 h rounds to 2 days).
  - `effectiveWindows(now:)`: a window with `resetsAt <= now` becomes 0%, `resetsAt nil`, not reached; others unchanged; result sorted shortest first.
  - `CodexLimitObservation` keeps only the first of two windows with the same name.
  - `CodexLimitsEntry.planDisplayName("plus")` is "Plus", nil stays nil.
  - `CodexLimitsEntry.barPercent(now:)` is the rounded percent of the longest effective window (20.4 gives 20, 130.0 gives 130), nil without observation; `anyLimitReached(now:)` true when any effective window is reached and false after that window's reset passed.
- [X] T006 [P] Create `Sources/UsageCore/Subscription/CodexLimits.swift` (data-model.md): `CodexLimitWindow`, `CodexLimitObservation` (with `Origin { live, snapshot }` and `effectiveWindows(now:)`), `CodexLimitsState { live, localOnly, stale(reason:), unavailable(reason:) }`, `CodexLimitsEntry { observation, state, sourceError }` with `windows(now:)`, `barPercent(now:)` (use `PercentFormatter.rounded`), `anyLimitReached(now:)`, and a static `planDisplayName(_:)` that capitalizes the plan type ("plus" gives "Plus"). Include a static helper that applies the research R2 limit-reached rule to a list of windows plus a source-level reached flag.
- [X] T007 (after T006) In `Sources/UsageCore/Snapshot/UsageSnapshot.swift`, `Sources/UsageCore/Snapshot/Aggregator.swift`, `Sources/UsageCore/Snapshot/RefreshCoordinator.swift`, `Sources/AgentTacho/DropdownView.swift` and every test using `planAccounts` (including `AggregatorTests`, `BarLayoutTests`, `ThresholdTrackerTests`, `RefreshCoordinatorTests`): rename `planAccounts` to `codexPlanTokens` (research R11), update its doc comment, and add `codexLimits: [String: CodexLimitsEntry] = [:]` to `UsageSnapshot` (initializer default so existing tests compile).
- [X] T008 In `Sources/UsageCore/Snapshot/RefreshCoordinator.swift` (plan Design Note 6):
  - Add `trigger: RefreshTrigger` to `RefreshContext`, with an initializer default of `.scheduled`; the coordinator passes the trigger of the current refresh.
  - Add `SourceOutput.codexLimits([String: CodexLimitsEntry])`. Merge every such output by key into `snapshot.codexLimits`. For each entry with a `sourceError`, append a `SourceError` naming the source and account. Treat the case like `.records` in the network outcome switch (no `FetchOutcome`).
  - If the codex limits source (identified by `CodexLimitsSourceName`, a `public let CodexLimitsSourceName = "codexLimits"` declared once in `CodexLimits.swift` (T006) and used as `CodexLimitsSource.sourceName` in T015) fails as a whole, exclude it from `subscriptionSourceFailure` (the Claude carry-over at the `.failure` branch) and carry over the previous snapshot's `codexLimits`, turning `.live` into `.stale(reason: "refresh failed")`.
  - Add tests in `Tests/UsageCoreTests/RefreshCoordinatorTests.swift`: a static source returning `.codexLimits` lands in `snapshot.codexLimits`; an entry with `sourceError` yields a `SourceError`; a failing source named `codexLimits` carries previous codex entries over as stale and leaves `snapshot.subscriptions` untouched; the context's trigger equals the requested trigger (`.local` for a reprice request).
- [X] T009 In `Sources/UsageCore/Notifications/ThresholdTracker.swift` and `Sources/AgentTacho/NotificationPresenter.swift` (research R8): convert `WindowKind` from an enum to `public struct WindowKind: Hashable, Sendable { public let rawValue: String; public let displayName: String }` with static members `fiveHour`, `sevenDay`, `weekly`, `monthly` carrying today's raw values and display names, and `static func codex(_ window: CodexLimitWindow, live: Bool) -> WindowKind` (raw value `codex-live-<name>` or `codex-local-<name>`, display name `window.name`). Replace `CaseIterable` uses and `switch` statements over `WindowKind` in `Sources/` and `Tests/`. All existing `ThresholdTrackerTests` must pass unchanged in behavior.

**Checkpoint**: `make test` passes. No behavior change visible yet.

---

## Phase 3: User Story 1 - See live Codex plan utilization (Priority: P1) 🎯 MVP

**Goal**: With a valid ChatGPT sign-in, the account shows every plan window live, in the dropdown and in the bar.

**Independent Test**: With a stubbed usage service and a temp Codex home holding a chatgpt `auth.json`, a refresh yields `snapshot.codexLimits[id]` in state `.live` with the stubbed windows; the bar shows the longest window's percent.

- [X] T010 [P] [US1] Add tests in `Tests/UsageCoreTests/CodexCredentialReaderTests.swift` (new) (FR-002, FR-003, research R3), using temp Codex homes and synthetic JWTs built in the test (header.payload.signature, base64url, payload with `exp`):
  - chatgpt mode with token and account id gives `.found` with `expiresAt` from `exp`; a non-JWT token gives `expiresAt == nil`.
  - `auth_mode "apikey"` gives `.missing("no Codex plan sign-in found in this Codex home")`.
  - chatgpt mode without `tokens.access_token` gives the no-sign-in reason.
  - No `auth.json` and `config.toml` with `cli_auth_credentials_store = "keyring"` (and `"auto"`) gives `.missing("Codex keeps its sign-in in the keychain")`; without that key, the no-sign-in reason.
  - Malformed JSON throws an error whose description does not contain the file content.
  - `String(describing:)` and `String(reflecting:)` of a credential do not contain the token or the account id; the reader never modifies the file (modification date unchanged).
- [X] T011 [P] [US1] Create `Sources/UsageCore/Subscription/CodexCredentialReader.swift`: `CodexCredential` (redacted `description` and `debugDescription`), `CodexCredentialLookup { found, missing(reason:) }`, `protocol CodexCredentialReader: Sendable { func read(codexHome: String) throws -> CodexCredentialLookup }`, and `struct FileCodexCredentialReader` (expands `~`, decodes only `auth_mode`, `tokens.access_token`, `tokens.account_id`; reads `config.toml` line by line for `cli_auth_credentials_store` only when `auth.json` is missing; decodes the JWT payload's `exp`).
- [X] T012 [P] [US1] Add tests in `Tests/UsageCoreTests/CodexUsageClientTests.swift` (new) using `StubURLProtocol` (contracts/codex-usage-endpoint.md section 1):
  - The request is `GET https://chatgpt.com/backend-api/wham/usage` with `Authorization: Bearer <token>`, `ChatGPT-Account-ID`, `Accept: application/json`, a `User-Agent` starting with `AgentTacho/`, and no `ChatGPT-Account-ID` when the credential has none.
  - The sample payload decodes to plan "plus", windows 300 and 10080 minutes (from `limit_window_seconds` with ceiling), percents, `resetsAt` from `reset_at`, `origin .live`, `observedAt` from the injected clock.
  - `limit_reached: true` marks the highest window reached; `additional_rate_limits` and `credits` are ignored; a window with `limit_window_seconds` 0 is dropped.
  - 200 without windows throws `CodexUsageError.noLimits`; garbage JSON throws `.decoding`; 401 and 403 throw `.httpStatus`; 429 with `Retry-After: 120` throws `.rateLimited(120)`; 500 throws `.httpStatus(500)`; a transport failure throws `.network`.
  - No thrown error's description contains the token.
- [X] T013 [US1] Create `Sources/UsageCore/Subscription/CodexUsageClient.swift`: `struct CodexUsageClient: Sendable { init(session: URLSession = UsageEndpointClient.defaultSession, url: URL = default, clock: @escaping @Sendable () -> Date = { Date() }, userAgent: String = "AgentTacho/<bundle version or dev>"); func fetch(_ credential: CodexCredential) async throws -> CodexLimitObservation }`, lenient `Decodable` bodies, reuse of `UsageEndpointError` and the existing internal `UsageEndpointClient.parseRetryAfter(_:now:)`, and `CodexUsageError.noLimits`.
- [X] T014 [US1] Add tests in `Tests/UsageCoreTests/CodexLimitsSourceTests.swift` (new) for the live path, with a fake credential reader, a stubbed client session, and an injected clock (FR-001, FR-002, FR-005, FR-021):
  - Live on, credential found, fetch ok: entry `.live` with the fetched observation.
  - Two accounts with different homes are fetched with their own credentials and never share results.
  - A credential with `expiresAt <= now` makes no request (no recorded request on the stub) and gives `.unavailable` when no snapshot exists, with reason "Codex sign-in expired, run Codex to renew it".
  - A throwing credential reader for one account gives that account `.unavailable` (reason without file content) and leaves the other account `.live`.
  - A missing credential (`.missing(reason)`) makes no request and shows that reason.
- [X] T015 [US1] Create `Sources/UsageCore/Subscription/CodexLimitsSource.swift`: `actor CodexLimitsSource: UsageSource` with `public static let sourceName = "codexLimits"` and `public nonisolated let name`, init `(credentialReader:client:log: DiagnosticLog? = nil, paths: Paths = Paths(), clock: @escaping @Sendable () -> Date = { Date() })`. `collect` runs per `configuration.codexSubscriptionAccounts` in a task group: if `liveLimits`, read the credential; on `.missing`, a throw, or `expiresAt <= now` (FR-003) make no request and produce `.unavailable(reason:)` (US2 adds the snapshot fallback); otherwise fetch (gating, snapshots and fallback come in US2), build a `CodexLimitsEntry`, store `lastLive[accountId]`, and log one line per account (`"<id>: live, observed <time>"` or the reason). Drop `lastLive` for removed accounts. Returns `.codexLimits(entries)`.
- [X] T016 [US1] Register `CodexLimitsSource(credentialReader: FileCodexCredentialReader(), client: CodexUsageClient(), log: log, paths: paths)` (use the app's existing `Paths` instance) in `AppModel.init` in `Sources/AgentTacho/App.swift`, next to the other sources.
- [X] T017 [P] [US1] In `Tests/UsageCoreTests/BarLayoutTests.swift`, replace `codexSubscriptionNeverYieldsABarItem` with tests (FR-012): a Codex account with `shownInBar` shows the longest window's percent in configuration order; `shownInBar == false` yields no item; `.live` is not stale; `.stale` is stale; `.unavailable` shows "--"; no entry shows "…"; level follows thresholds; any reached window gives `.critical` even at 40%.
- [X] T018 [US1] In `Sources/UsageCore/Bar/BarLayout.swift`, replace `case .codexSubscription: continue` with a `codexItem(account:settings:snapshot:)` per research R8, using `snapshot.generatedAt` as `now` for `effectiveWindows`.
- [X] T019 [US1] In `Sources/AgentTacho/DropdownView.swift`, extend `CodexPlanSection` (plan Design Note 9, FR-011): header with the bar percent, one row per effective window titled by `window.name` (add a small `CodexWindowRow` that shows no reset text for a nil reset time, instead of `WindowRow`'s "not started"), a "Limit reached" caption on reached windows, the capitalized plan type, the state line (live: nothing extra; stale: "Stale, as of <time>: <reason>"; local only: "Local data, as of <time>"; unavailable: "<reason>"), then the existing token breakdown. Remove the "plan limits are not shown yet" caption. Update the call site `CodexPlanSection(account:entry:)` to pass `snapshot.codexLimits[account.id]` and `snapshot.generatedAt`.
- [X] T020 [US1] In `Sources/UsageCore/Logs/CodexSessionSource.swift` (research R10): add every Codex subscription account's `codexHome` to `homes(for:)`, deduplicated by canonical path. Test in `Tests/UsageCoreTests/CodexSessionSourceTests.swift`: a session in an account home not listed in `codexHomes` is read and attributed to that account.

**Checkpoint**: With the usage service reachable, the account shows live windows in the dropdown and the bar.

---

## Phase 4: User Story 2 - Keep a plausible value when the service is unavailable (Priority: P1)

**Goal**: Offline, expired sign-in, rate limit or a changed answer: show the newest observation, marked stale with time and reason.

**Independent Test**: With rollout fixtures in a temp Codex home and a stub that fails, the account shows the fixture's newest snapshot as `.stale` with its event timestamp and reason.

- [X] T021 [P] [US2] Add tests in `Tests/UsageCoreTests/CodexSessionParserTests.swift` for `latestLimitSnapshot(in:)` (FR-004, FR-008, contracts section 3) using the T002 fixtures: plus gives the newer snapshot (from the `info: null` event) with both windows and `origin .snapshot`; free gives one 30-day window; noise gives the valid plus snapshot only; reached marks the 300-minute window reached; forked ignores the copied parent snapshot; a file without snapshots gives nil; a truncated last line is ignored.
- [X] T022 [US2] Implement `static func latestLimitSnapshot(in data: Data) -> CodexLimitObservation?` in `Sources/UsageCore/Logs/CodexSessionParser.swift`. Extract the copied-history state machine of `parse(data:)` into a private helper used by both functions (existing parser tests stay unchanged), reuse the line splitting, and evaluate `rate_limits` before the `info` guard.
- [X] T023 [US2] Reuse the existing internal `CodexSessionSource.rolloutFiles(under:errors:)` from `CodexLimitsSource` for the account home (no new helper); adjust its visibility only if needed. Existing `CodexSessionSourceTests` must pass unchanged.
- [X] T024 [US2] Add tests in `Tests/UsageCoreTests/CodexLimitsSourceTests.swift` for snapshots and selection (FR-004, FR-005, FR-006, FR-010, research R4, R6):
  - Newest snapshot of the account home is found even when its file is older than the token window (modification date 20 days back).
  - Newest-first scan: with three files, an unchanged second refresh parses no file (assert through a `public private(set) var lastFilesParsed` counter on the source, as `CodexSessionSource` has); a newer file with a snapshot replaces the result.
  - Service unreachable: `.stale(reason: "offline")` with the snapshot.
  - Earlier live result newer than the snapshot wins after a later failure; a snapshot newer than the earlier live result wins.
  - A snapshot timestamp in the future is clamped to `now` for the comparison, so a later live result still wins once it is newer than `now` at that refresh.
  - `noLimits` answer gives stale with reason "usage service reported no limits"; `.decoding` gives stale with `sourceError` "usage service changed"; 401 gives `sourceError` "Codex sign-in rejected"; offline, 429 and expired sign-in give no `sourceError`.
  - No snapshot and no live result gives `.unavailable(reason)`.
  - After launch (fresh source), only snapshots apply until the first successful fetch.
  - The per-account log line names the shown source (live or snapshot), the observation time and the reason (FR-020).
- [X] T025 [US2] Extend `CodexLimitsSource` (research R4, R6): per-home file cache `{size, modificationDate, snapshot}`, newest-first scan stopping per research R4, selection rules with clamping, reasons and `sourceError` mapping per contracts section 1, and the log line naming the shown source, observation time and reason (FR-020).
- [X] T026 [US2] Add tests in `Tests/UsageCoreTests/CodexLimitsSourceTests.swift` for the fetch gate (FR-007, research R5): trigger `.local` makes no request; 429 with `Retry-After: 300` blocks requests for that home until 300 s pass on the injected clock (manual triggers included) while another home still fetches; 429 without `Retry-After` blocks for one `refreshIntervalSeconds`; two `.manual` refreshes 30 s apart make one request, 61 s apart make two; `.scheduled` refreshes are not spaced; a skip because none was due (`.local`, spacing) keeps a kept live result in state `.live`, while a rate-limit wait shows it as stale; an account with no fetch attempt yet for its current (Codex home, live limits) is fetched once even on `.local` (new account, live limits turned back on, changed Codex home), but after a failed attempt a `.local` refresh makes no request; `.retry` and `.launch` are spaced like `.manual`; a 429 without Retry-After blocks for one refresh interval measured from `context.now` of that refresh.
- [X] T027 [US2] Implement `CodexFetchGate` (per canonical Codex home) in `Sources/UsageCore/Subscription/CodexLimitsSource.swift` and use it in `collect`. Drop gates and file caches for homes no account references any more. Track the Codex home per account and clear `lastLive` when it changes; keep the per-account attempt record from research R5. Use `context.now` for expiry, the gate and live observation times.

**Checkpoint**: Offline or with an expired sign-in, the account shows the newest snapshot marked stale.

---

## Phase 5: User Story 3 - Threshold notifications for Codex windows (Priority: P2)

**Goal**: Thresholds on a Codex account notify once per threshold per window.

**Independent Test**: Feed two snapshots to `ThresholdTracker.observe` with a Codex account entry at 70% then 85% on the weekly window and threshold 80: exactly one crossing for "weekly".

- [X] T028 [P] [US3] In `Tests/UsageCoreTests/ThresholdTrackerTests.swift`, replace `codexSubscriptionYieldsNoCrossings` with tests (FR-014, FR-015): 70 to 85 with thresholds [80, 95] gives one crossing named "weekly"; both windows crossing in one refresh give two crossings; the first observation after launch gives none; a new `resetsAt` resets state and the next crossing notifies again; values from a `.stale` entry and a `.localOnly` entry count; a `.unavailable` entry yields none; a window that disappears (Free to Plus) drops its state and a new window starts with a baseline; toggling `liveLimits` between two refreshes yields no crossing at the toggle refresh; an `.unavailable` or missing entry between two observations keeps the state, so a later crossing still notifies; live and snapshot reset times 30 s apart for the same window do not re-baseline.
- [X] T029 [US3] In `Sources/UsageCore/Notifications/ThresholdTracker.swift`, add scope `.codexPlan` and a loop over `configuration.codexSubscriptionAccounts`: for each effective window (at `snapshot` time) with a `resetsAt`, key `.codex(window, live: settings.liveLimits)`, `windowEnd = resetsAt`, evaluate with the account's thresholds; skip `.unavailable` entries. Add a key to `liveKeys` for every window of the observation (evaluated or not); for a missing or `.unavailable` entry, keep the account's existing `.codexPlan` keys. Compare `windowEnd` for `.codexPlan` keys with a 120 s tolerance; on a match within tolerance keep the stored `windowEnd`.
- [X] T030 [US3] In `Sources/AgentTacho/AccountSettingsView.swift`, extend `CodexSubscriptionEditor` with a "Show in menu bar" toggle and `ThresholdsEditor` (limit description "Applies to every plan window"); remove the "limits are not available yet" captions; in `NewAccountSheet`, the ChatGPT platform caption mentions plan limits instead of "tokens only".

**Checkpoint**: Thresholds notify per window; the bar uses the warning style at the lowest threshold.

---

## Phase 6: User Story 4 - Use local snapshots only (Priority: P3)

**Goal**: With live limits off, no credential read and no request; values are local data, not a failure.

**Independent Test**: With `liveLimits == false`, a refresh records no request on the stub, the fake credential reader is never called, and the entry is `.localOnly` with the newest snapshot.

- [X] T031 [P] [US4] Add tests in `Tests/UsageCoreTests/CodexLimitsSourceTests.swift` (FR-005, FR-006, FR-019): live off gives `.localOnly` with the snapshot, zero credential reads, zero requests; turning live off discards a kept live result even if it is newer than the snapshot; live off without snapshots gives `.unavailable`; `BarLayout` shows a `.localOnly` entry without stale styling (add to `Tests/UsageCoreTests/BarLayoutTests.swift`).
- [X] T032 [US4] Implement the live-off path in `Sources/UsageCore/Subscription/CodexLimitsSource.swift` (skip credential read and gate, clear `lastLive[accountId]`, state `.localOnly`).
- [X] T033 [US4] In `Sources/AgentTacho/AccountSettingsView.swift`, add the toggle "Live limits from the usage service" to `CodexSubscriptionEditor`, with a caption: on reads the Codex sign-in in this Codex home (never changes it) and asks the ChatGPT usage service; off uses only the last limits Codex recorded on this Mac.

**Checkpoint**: All four stories work independently.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T034 Add a token sentinel test in `Tests/UsageCoreTests/CodexLimitsSourceTests.swift` (FR-018, SC-005): with a credential whose token and account id are `SECRET-CODEX-TOKEN-123` and `SECRET-ACCOUNT-456`, run refreshes covering success, 401, decoding error, 429 and offline; assert that neither string appears in the diagnostic log file, in `String(describing:)` of the entries, in any `SourceError` text, or in `String(describing:)` of the `ThresholdCrossing` values (whose `entityName` and `windowKind.displayName` build the notification text in the app target).
- [X] T035 [P] Add a Codex-home immutability test (SC-004): snapshot the paths, sizes and modification dates of every file in a temp Codex home, run several refreshes of `CodexLimitsSource` with live limits on, and assert nothing changed.
- [X] T036 [P] Update `README.md` (including the statements near lines 17, 26, 115, 143 and 144: limits are not read, AgentTacho never opens Codex credential files, and the only regular request goes to `api.anthropic.com`; now also `chatgpt.com/backend-api/wham/usage` with the Codex token, only when live limits are on): Codex subscription accounts now show plan limits (live from the ChatGPT usage service, with local fallback), the live-limits setting, and that AgentTacho reads but never refreshes the Codex sign-in.
- [X] T037 Run `make test`, then `rg -n '\x{2014}|\x{2013}' Sources Tests specs/007-codex-plan-limits -g '!**/LICENSE.txt' -g '!tasks.md'` (expect no hits), then build the app with `make build`.
- [ ] T038 Walk through `specs/007-codex-plan-limits/quickstart.md` manual scenarios 1 to 3 where a ChatGPT sign-in is available, and record the results. (Deferred to the user: needs the GUI app and a real ChatGPT sign-in.)

---

## Dependencies & Execution Order

- **Setup (T001-T002)** → **Foundational (T003-T009)** → stories.
- **US1 (T010-T020)** first (MVP). **US2 (T021-T027)** extends `CodexLimitsSource` from US1. **US3 (T028-T030)** needs T006, T009 and an entry source (US1 or US2). **US4 (T031-T033)** needs US2's snapshot path.
- **Polish** after all stories.

Within phases: T003 before T004; T005 before T006; T010 before T011; T012 before T013; T014 before T015; T017 before T018; T021 before T022; T024 before T025; T026 before T027; T028 before T029; T031 before T032.

## Parallel Opportunities

- Setup: T002 in parallel with T001.
- Foundational: T005/T006 (new file) in parallel with T003/T004 (configuration); T009 after T006.
- US1: T010/T011 (credentials), T012/T013 (client) and T017 (bar tests) in parallel; T015 after T011 and T013.
- US2: T021 in parallel with T023.
- Polish: T035 and T036 in parallel.

## Implementation Strategy

- **MVP**: Phases 1 to 3 (live limits in the dropdown and bar). Validate with quickstart scenario 1.
- **Increment 2**: US2 fallback; validate with scenario 2.
- **Increment 3**: US3 thresholds; scenario 4.
- **Increment 4**: US4 snapshot-only; scenario 3.
- Run `make test` at each checkpoint.
