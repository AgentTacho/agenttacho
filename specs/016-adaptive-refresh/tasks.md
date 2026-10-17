# Tasks: Adaptive Refresh

**Input**: Design documents from `specs/016-adaptive-refresh/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/refresh-pace.md, contracts/settings-and-dropdown.md, quickstart.md

**Tests**: Required. AGENTS.md asks for test-first development of all `UsageCore` logic; test tasks come before their implementation and must fail first. Run tests only with `make test`, build only with `make app`.

**Organization**: The configuration key, the new triggers, `reachedService` and the pure `AdaptivePace` are foundational; each user story then wires one part into the coordinator or the app.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: User story from spec.md (US1 to US4)

## Conventions for every task

- Doc comments cite the spec requirements they implement (for example `spec 016 FR-005`).
- No em dash or en dash characters anywhere (code, comments, docs, commit messages).
- Every phase ends with a checkpoint: `make test` passes (and `make app` builds from Phase 3 on). Fix failures before the next phase.
- Commit after each phase with a Conventional Commit message ending in `Assisted-By: 🤖 Claude Code`.
- With `adaptiveRefresh` off, behavior must stay identical to the code before this feature (FR-002, SC-004); existing tests must keep passing unchanged.

---

## Phase 1: Foundational (Blocking Prerequisites)

**Purpose**: Configuration key, triggers, the "reached the service" fact, and the pure pace value every story builds on. Start by running `make test` once to confirm the baseline passes.

### Tests first

- [X] T001 [P] Add tests to `Tests/UsageCoreTests/ConfigurationTests.swift` (FR-001, research R10): a JSON without `adaptiveRefresh` decodes to `true`; `true` and `false` decode as given; a non-boolean (`"yes"`, `3`) decodes to `true`, does not throw, and records exactly one note (`adaptiveRefresh is not a boolean, using true`) in a `ConfigurationLoadNotes` collector passed through `JSONDecoder.userInfo`; encoding writes the key; changing only `adaptiveRefresh` makes `needsRefresh(comparedTo:)` and `needsNetworkRefresh(comparedTo:)` false.
- [X] T002 [P] Add tests to `Tests/UsageCoreTests/EndpointPolicyTests.swift` (FR-011, FR-012, research R6): `.dropdownOpen` and `.idleReturn` have rank 1; within 60 s of the last attempt they return `.reuse` with no follow-up time; after 60 s they return `.fetch`; during a rate-limit block they return `.reuse` and leave `retryUsed` false (a later `.scheduled` decision during the same block still gets its single `retryAt`).
- [X] T003 [P] Create `Tests/UsageCoreTests/AdaptivePaceTests.swift` covering the pure rows of `contracts/refresh-pace.md` with explicit `now` values:
  - P1 (call sequence 0, 5, 15, 35, 65, 95 with `recordCall` and `shouldCall` at 5-minute ticks), P2, P3, P4 (OpenCode counts for both), P5 (activity older than the last call is none), P6 and P7 (no `recordCall` leaves interval and last call unchanged, so older activity counts later), P8, P9, P10 (5 s tolerance), P11 (base 2400 s never stretches), P12 (base 60 s: 60, 120, 240, 480, 960, 1800);
  - T1 to T6 and T8 for `timerInterval`, its reason, `dueAt` and `nextScheduledRefresh(now:)` (never earlier than `now`);
  - D1, D2, D3, D5, D6 for `shouldRefreshOnOpen(now:)`;
  - P13: disabled means `shouldCall` is always true, `timerInterval == base`, `status` is nil, `shouldRefreshOnOpen` is false;
  - T9, T10, T11: an endpoint whose last call cannot move (transport failure, block, no request) or that was never called does not pull the timer forward (`nextScheduledRefresh` = last refresh plus timer interval, never a time at or before the last refresh); T12: `lastRefreshAt == nil` gives `now + timerInterval`; with `lastScheduledAt` nil a past due time gives `now` once and, after that scheduled refresh, is ignored; T13: a reprice just before a due time does not hide it, only a scheduled refresh within the tolerance does; T11: after `normalize(now:)` with the clock moved back 1 hour, `shouldCall(.claude, ...)` becomes true within `max(interval, timerInterval)`; L6: `status(now)` never returns a time before `now`;
  - `update(configuration:)` with a changed base or toggle resets every interval to the base; `update(conditions:)` reports whether the timer interval or reason changed; `timerReason` is nil while disabled;
  - `isInUse`: Claude in use with a Claude subscription account, Codex in use only with a Codex subscription account whose `liveLimits` is on.
- [X] T004 [P] Create `Tests/UsageCoreTests/RefreshPaceStatusTests.swift` for rows L1 to L5 of `contracts/refresh-pace.md` (FR-016): reason ranking (idle, Low Power Mode, high temperature, no agent activity), time choice per reason, `Plan limits next checked at HH:MM (reason)` versus `Next refresh at HH:MM (reason)`, time only for today and abbreviated weekday plus time otherwise, with a fixed `Calendar` and time zone.
- [X] T005 [P] Add tests to `Tests/UsageCoreTests/SubscriptionSourceTests.swift` (research R5): `reachedService` is true for a success, a 401, a 429 and an unreadable answer; false for a transport failure, an HTTP 5xx, a missing or expired sign-in, a credential read failure, and an entry kept without a request during a quick retry.
- [X] T006 [P] Add tests to `Tests/UsageCoreTests/CodexLimitsSourceTests.swift` (research R4, R5, R6): with `RefreshContext(codexPaceDue: false)` a `.scheduled` refresh makes no request for a home already attempted and shows the entry as for `.notDue` (no stale marking); a new account or changed home still fetches once; `codexPaceDue` is ignored for every other trigger; `.dropdownOpen` and `.idleReturn` are spaced 60 s per home like `.wake` and never fetch during a block; `reachedService` follows the same rules as T005.

### Implementation

- [X] T007 Update `Sources/UsageCore/Config/Configuration.swift` to make T001 pass: add `public var adaptiveRefresh: Bool` (init parameter default `true`, coding key `adaptiveRefresh`); decode it leniently: when the key is present but `(try? c.decodeIfPresent(Bool.self, forKey: .adaptiveRefresh)) ?? nil` is nil, use `true` and append the note to `decoder.userInfo[ConfigurationLoadNotes.userInfoKey] as? ConfigurationLoadNotes`; encode it; reset it in the data-relevance copy next to `levelColor`.
- [X] T008 Update `Sources/UsageCore/Snapshot/EndpointPolicy.swift` to make T002 pass: add `case dropdownOpen, idleReturn` to `RefreshTrigger` with rank 1, and add both to the spaced list in `decide` (`[.manual, .wake, .settings, .dropdownOpen, .idleReturn]`), with no follow-up time (only `.settings` gets one).
- [X] T009 Add `public var reachedService: Bool = false` to `SubscriptionEntry` in `Sources/UsageCore/Snapshot/UsageSnapshot.swift` and to `CodexLimitsEntry` in `Sources/UsageCore/Subscription/CodexLimits.swift` (init parameter with default, not part of equality-relevant saved data; make sure `LastGoodStore` neither writes nor reads it). `reused(now:)` and `markedStale` copies set it to false.
- [X] T010 Update `Sources/UsageCore/Subscription/SubscriptionSource.swift` to make T005 pass: in `apply`, set `reachedService = true` for `.success` and for `.failed` whose `FailureCategory.classify(error)` is not `.transport`; set `kept.reachedService = false` on the entry kept without a request during a quick retry (next to `kept.fetchOutcome = nil`).
- [X] T011 Update `Sources/UsageCore/Snapshot/RefreshCoordinator.swift`: add `public let codexPaceDue: Bool` to `RefreshContext` with init parameter default `true` (spec 016 FR-006), and the marker protocol `public protocol EndpointGatedSource: UsageSource {}` with a doc comment (a plain source that gates its own endpoint requests; collected after the record sources, research R3).
- [X] T012 Update `Sources/UsageCore/Subscription/CodexLimitsSource.swift` to make T006 pass: declare conformance to `EndpointGatedSource` (it stays not `NetworkBoundSource`); in `decide`, `.scheduled` returns `context.codexPaceDue ? .fetch : .notDue` (pass the flag into `decide`); add `.dropdownOpen, .idleReturn` to the spaced case; the `.notDue` log note says `no request due (adaptive pace)` when the pace held a scheduled request back; set `entry.reachedService = true` for `.success` and for `.failed` whose category is not `.transport`.
- [X] T013 Create `Sources/UsageCore/Snapshot/AdaptivePace.swift` per `data-model.md` to make T003 pass. Interfaces:
  - `public enum PacedEndpoint: String, CaseIterable, Sendable { case claude, codex; public var harnesses: Set<Harness>; public func isInUse(_ configuration: Configuration) -> Bool }`
  - `public struct SystemConditions: Equatable, Sendable { public var idle, lowPowerMode, thermalPressure: Bool; public init(idle: Bool = false, lowPowerMode: Bool = false, thermalPressure: Bool = false) }`
  - `public enum PaceReason: Int, Comparable, Sendable { case idle, lowPowerMode, highTemperature, noAgentActivity }` (ranked by raw value, explicit `<`); `public struct IntervalChange: Equatable, Sendable { public let endpoint: PacedEndpoint; public let from, to: TimeInterval; public let reason: PaceReason? }`
  - `public struct AdaptivePace: Equatable, Sendable` with `public static let cap: TimeInterval = 1800`, `tickTolerance = 5`, `openSpacing = 60`; `public init(enabled: Bool = true, base: TimeInterval)`; `public mutating func update(configuration: Configuration)`; `public mutating func update(conditions: SystemConditions) -> Bool`; `public var timerInterval: TimeInterval`; `public var timerReason: PaceReason?` (nil while disabled); `public func newestActivity(_ endpoint: PacedEndpoint, in records: [UsageRecord]) -> Date?`; `public func shouldCall(_ endpoint: PacedEndpoint, newestActivity: Date?, now: Date) -> Bool`; `public mutating func recordCall(_ endpoint: PacedEndpoint, at: Date, scheduled: Bool, newestActivity: Date?) -> IntervalChange?` (returns old and new interval and reason when it changed); `public func dueAt(_ endpoint: PacedEndpoint) -> Date?`; `public mutating func refreshCompleted(at: Date, scheduled: Bool)`; `public mutating func normalize(now: Date)`; `public func nextScheduledRefresh(now: Date) -> Date`; `public func shouldRefreshOnOpen(now: Date) -> Bool`; `public func status(now: Date) -> RefreshPaceStatus?`; read access to `enabled`, `inUse`, `lastRefreshAt`, `lastScheduledAt` and each endpoint's `lastCallAt` and `interval`.
- [X] T014 Create `Sources/UsageCore/Snapshot/RefreshPaceStatus.swift` to make T004 pass: `public struct RefreshPaceStatus: Equatable, Sendable { public enum Kind { case planLimits, refresh }; public let reason: PaceReason; public let nextAt: Date; public let kind: Kind; public func text(now: Date, calendar: Calendar) -> String }` with reason names `away`, `Low Power Mode`, `high temperature`, `no agent activity`.

**Checkpoint**: `make test` passes; no behavior change yet (nothing calls the pace).

---

## Phase 2: User Story 2 - Fewer endpoint calls while no agent works (Priority: P1)

**Goal**: Scheduled refreshes scan locally at the base pace and call each usage endpoint only when its pace says so.

**Independent Test**: `RefreshCoordinatorTests` with stub sources and a fake clock reproduce P1, P2, P6 and U2/U3 of `contracts/refresh-pace.md`; by hand, quickstart steps 2 and 3.

### Tests first

- [X] T015 [US2] Add tests to `Tests/UsageCoreTests/RefreshCoordinatorTests.swift` (FR-004 to FR-007, FR-013, FR-014, SC-001, SC-002, SC-004). First add test support in that file: a `reachedService:` parameter (default `true` for new tests) on the `subscriptionOutput` helper, a recording Codex stub conforming to `EndpointGatedSource` that records each `RefreshContext` it receives (trigger and `codexPaceDue`) and returns entries with a settable `reachedService`, and an ordering probe (a shared actor log the record stub and network stubs append to). Then:
  - record sources finish before the Claude stub and the Codex stub start (ordering probe);
  - P1: with `adaptiveRefresh` on and no records after each call, after a launch call at 0, 24 `.scheduled` refreshes at 5-minute steps (t=5 to t=120) call the Claude stub only at 5, 15, 35, 65, 95, the record stub every time, and the log shows `pace: claude interval 600 s (no agent activity)` once;
  - P2: a record with `harness .claudeCode` and a timestamp after the last call makes the next scheduled refresh call Claude and logs the return to base;
  - the paced refresh shows the reused Claude entries unmarked (not stale, `lastSuccessfulRefreshAt` unchanged), its summary line says `endpoint reused (adaptive pace, next call <time>)`, and `EndpointPolicy` state is untouched;
  - Codex: with only Codex records the Codex stub receives `codexPaceDue == true` and Claude is paced; with no records at all, `codexPaceDue` is false on the ticks where the Codex pace is not due;
  - P6: a stub Claude entry with `reachedService == false` (transport failure) leaves the pace unchanged;
  - P8/P9: a `.dropdownOpen` refresh call counts as last call without doubling, and resets to base when it saw activity;
  - U2: during a rate-limit block the pace never causes a call and the scheduled retry time is unchanged;
  - U4: a scheduled tick during a Claude rate-limit block passes `codexPaceDue == false` to the Codex stub when the Codex pace is not due;
  - U5: a pace or reprice reuse of a stored Claude result whose entries carry `reachedService == true` leaves Claude's last call and interval unchanged;
  - U6: after a configuration edit that adds a Claude account (or changes a credential directory) while Claude is paced, the next scheduled refresh calls the Claude stub;
  - U3/SC-004: with `adaptiveRefresh` false the same 24 ticks call the Claude stub every time, with stub entries whose `reachedService` is true, as before; existing tests stay unchanged and green (check the gated-source tests near lines 1422 and 1568 after T016).

### Implementation

- [X] T016 [US2] Update `Sources/UsageCore/Snapshot/RefreshCoordinator.swift` refresh order (research R3, plan Design Note 1): in every mode collect the record sources first (neither `NetworkBoundSource` nor `EndpointGatedSource`), then, in one concurrent batch, the Claude source (full mode only) and every `EndpointGatedSource`; keep the window-sensitive re-run as is.
- [X] T017 [US2] Update `Sources/UsageCore/Snapshot/RefreshCoordinator.swift` to make T015 pass (plan Design Notes 2 to 4, 9):
  - own `private var pace = AdaptivePace(base: ...)` and call `pace.update(configuration:)` at the start of each refresh;
  - compute `newestActivity` per endpoint from the records of the scan;
  - pace reuse: when the policy says `.fetch` for `.scheduled`, the toggle is on, `pace.shouldCall(.claude, ...)` is false, a stored Claude result exists and `lastNetworkDirectories == directories`, switch to the existing `.reprice` mode with reuse reason `adaptive pace, next call <iso time>` (shown by the summary line as `endpoint reused (adaptive pace, next call ...)`);
  - for every `.scheduled` refresh, in every mode, build the second-batch context with `codexPaceDue: pace.shouldCall(.codex, ...)`; other triggers keep `true`;
  - after collecting, for each endpoint with any fresh (not reused) entry whose `reachedService` is true, call `pace.recordCall(...)` with `scheduled: trigger == .scheduled` and log changes as `pace: <endpoint> interval <n> s (no agent activity)` or `pace: <endpoint> interval back to base (activity)`; reused results never record a call;
  - call `pace.normalize(now: started)` at the start and `pace.refreshCompleted(at: started, scheduled: trigger == .scheduled)` at the end of every refresh; the public API in T017a calls `normalize(now: clock())` before answering.
- [X] T017a [US2] Add the public pace API to `Sources/UsageCore/Snapshot/RefreshCoordinator.swift`, all using `clock()`, with tests in `Tests/UsageCoreTests/RefreshCoordinatorTests.swift`: `nextScheduledRefresh() -> Date?` (nil when the toggle is off); `shouldRefreshOnOpen() -> Bool` (false while a refresh runs); `setConditions(_:) -> Bool` (logs `pace: timer <n> s (<reason>)` or `pace: timer back to base <n> s` on change; with the toggle off it stores the conditions, returns false and logs nothing); `configurationChanged(_:)` (calls `pace.update(configuration:)` at once, logging a toggle change as `pace: adaptive refresh on` or `off`); `paceStatus() -> RefreshPaceStatus?` (nil when off).
- [X] T018 [US2] Update `Sources/AgentTacho/App.swift` (research R7, plan Design Note 5): `restartTimer` keeps the existing fixed loop when `configuration.adaptiveRefresh` is false; when true, run a loop that awaits `coordinator.nextScheduledRefresh()`, sleeps until that date (at least 1 s), then requests `.scheduled`; re-arm the loop after each snapshot in `startConsumingSnapshots`, on wake, and when a saved or reloaded configuration changes `refreshIntervalSeconds` or `adaptiveRefresh` (today only the interval is compared); on such a change first `await coordinator.configurationChanged(config)`. When `nextScheduledRefresh()` returns nil the adaptive loop ends and `restartTimer` starts the fixed loop. At launch the loop's first wait is one timer interval (T12), so no scheduled request is queued behind the launch refresh.

**Checkpoint**: `make test` passes, `make app` builds; quickstart steps 2 and 3 behave as described.

---

## Phase 3: User Story 1 - Current numbers when I look (Priority: P1)

**Goal**: Opening the dropdown refreshes when an endpoint's last call is at least a minute old.

**Independent Test**: D1 to D7 of `contracts/refresh-pace.md` in tests; quickstart step 1 by hand.

### Tests first

- [X] T019 [US1] Add tests to `Tests/UsageCoreTests/RefreshCoordinatorTests.swift` (FR-012, SC-003): `shouldRefreshOnOpen()` is true 4 minutes after the last Claude call and false 30 s after it; with Claude at 30 s and Codex at 5 minutes a `.dropdownOpen` refresh calls only the Codex stub; during a rate-limit block the `.dropdownOpen` refresh calls no endpoint; with the toggle off `shouldRefreshOnOpen()` is false; `shouldRefreshOnOpen()` is false while a refresh runs, so opening during a refresh raises `refreshCount` by one only (no queued second refresh).

### Implementation

- [X] T020 [US1] Add `func dropdownOpened()` to `AppModel` in `Sources/AgentTacho/App.swift`: when `configuration.adaptiveRefresh` is true, ask `await coordinator.shouldRefreshOnOpen()` and, if true, `requestRefresh(trigger: .dropdownOpen)` (spec 016 FR-012); call it from `.onAppear` of the root view in `Sources/AgentTacho/DropdownView.swift`. If the walkthrough shows `.onAppear` fires only on the first opening, switch to `NSWindow.didBecomeKeyNotification` for the extra's window behind the same model method (research R9).

**Checkpoint**: `make test` passes, `make app` builds; quickstart step 1 behaves as described.

---

## Phase 4: User Story 3 - A slower timer while I am away or saving power (Priority: P2)

**Goal**: Idle, Low Power Mode and thermal pressure stretch the timer; returning from idle refreshes.

**Independent Test**: T1 to T8 in `AdaptivePaceTests` (Phase 1); coordinator test below; quickstart steps 4 and 5 by hand.

### Tests first

- [X] T021 [US3] Add tests to `Tests/UsageCoreTests/RefreshCoordinatorTests.swift` (FR-008 to FR-011): `setConditions(SystemConditions(idle: true))` returns true and logs `pace: timer 1800 s (idle)`; `nextScheduledRefresh()` then is the last refresh plus 1800 s unless an endpoint is due earlier; setting the same conditions again returns false and logs nothing; ending the condition logs the return to base; an `.idleReturn` refresh is spaced and calls the endpoints regardless of the endpoint pace; with `adaptiveRefresh` off, `setConditions` returns false and logs nothing (P13).

### Implementation

- [X] T022 [P] [US3] Create `Sources/AgentTacho/SystemConditionsMonitor.swift` (research R8): a `@MainActor` class that publishes `SystemConditions` changes through a closure. It reads `ProcessInfo.processInfo.isLowPowerModeEnabled` (observing `.NSProcessInfoPowerStateDidChange`), `thermalState` `.serious` or `.critical` (observing `ProcessInfo.thermalStateDidChangeNotification`), idle from `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)` of at least 600 s polled every 60 s, the `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` distributed notifications, and `NSWorkspace.screensDidSleepNotification` / `screensDidWakeNotification`. No permissions; doc comments cite spec 016 FR-008, FR-009, FR-011, FR-020.
- [X] T023 [US3] Wire the monitor in `Sources/AgentTacho/App.swift` (plan Design Note 6): on each change, log `conditions: idle=..., lowPower=..., thermal=...` with source `app`, call `coordinator.setConditions(_:)`, re-arm the adaptive timer when it returns true, and, only when `configuration.adaptiveRefresh` is true (FR-002), on a transition from idle to not idle request `.idleReturn` unless a wake refresh started less than 60 s ago (record the wake time in `observeWake`).

**Checkpoint**: `make test` passes, `make app` builds; quickstart steps 4 and 5 behave as described.

---

## Phase 5: User Story 4 - Know what the refresh is doing, and turn it off (Priority: P3)

**Goal**: The toggle in Settings and the pace line in the dropdown.

**Independent Test**: L1 to L5 in `RefreshPaceStatusTests` (Phase 1); quickstart step 6 by hand.

- [X] T024 [P] [US4] Add the "Adapt refresh" toggle to the General tab in `Sources/AgentTacho/SettingsView.swift`, directly below the refresh interval field, bound to `draft.adaptiveRefresh`, with the help text from `contracts/settings-and-dropdown.md` (spec 016 FR-001).
- [X] T025 [US4] Add `private(set) var paceStatus: RefreshPaceStatus?` to `AppModel` in `Sources/AgentTacho/App.swift`, updated from `await coordinator.paceStatus()` after each snapshot and after each condition change; show `paceStatus?.text(now: Date(), calendar: .autoupdatingCurrent)` as one caption line in secondary color directly under the "Last refreshed" row in the footer of `Sources/AgentTacho/DropdownView.swift` (spec 016 FR-016); no line when nil.

**Checkpoint**: `make test` passes, `make app` builds; quickstart step 6 behaves as described.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T026 [P] Update `README.md` per `contracts/settings-and-dropdown.md` (FR-018): add `"adaptiveRefresh": true` to the example configuration, describe the toggle and the adaptive behavior (30-minute bound, refresh when the menu opens) in the General bullet, and rewrite the request frequency sentence in "Security and privacy" (the bullet starting "The tokens are powerful").
- [X] T027 [P] Scan all changed files for em dash and en dash characters (`rg -n "\x{2014}|\x{2013}" Sources Tests README.md specs/016-adaptive-refresh`) and fix any.
- [X] T028 Run `make test` and `make app`; confirm every FR of spec.md is cited by at least one doc comment or test (`rg -n "spec 016 FR-0" Sources Tests`); check the diff adds no new host, credential read, file write or permission (FR-020, SC-006: `git diff main -- Sources | rg -n "URL\(string|FileManager|write\(to|SecItem|authorizationStatus"` shows nothing new beyond existing code) and no refresh triggered by notifications (FR-015); update the quickstart if any log text differs from the implementation.

---

## Dependencies & Execution Order

- Phase 1 blocks everything. Within it, tests T001 to T006 can be written in parallel; T007 to T014 follow their tests; T012 needs T011 (`codexPaceDue`), T013 needs T014 for `status(now:)` (write T014 first or together).
- T017a needs T017; T018 needs T017a.
- Phase 2 (US2) needs Phase 1. Phase 3 (US1) needs T017a (`shouldRefreshOnOpen`). Phase 4 (US3) needs T017a and T018. Phase 5 needs T017a (`paceStatus`) and T007 (toggle).
- Phase 6 last.

## Parallel Examples

- Phase 1 tests: T001, T002, T003, T004, T005, T006 together (different files).
- Phase 4: T022 (new app file) in parallel with T021 (tests).
- Phase 5: T024 (only `SettingsView.swift`) in parallel with T025.
- Phase 6: T026 and T027 together.

## Implementation Strategy

MVP is Phase 1 plus Phase 2 (US2): the main protection of the rate-limited endpoints. Phase 3 (US1) restores freshness when looking and makes the slower background pace pleasant. Phases 4 and 5 add battery savings and transparency. Each phase is a complete, testable increment with its own commit.
