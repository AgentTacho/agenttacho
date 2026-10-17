# Tasks: Monthly Budget Period

**Input**: Design documents from `/specs/003-monthly-budget-period/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/config-file.md, quickstart.md

**Tests**: Included. The project covers every `UsageCore` type with Swift Testing suites (`import Testing`, `@Suite`, `@Test`), and quickstart.md names the suites that prove this feature. Write each test task before its implementation task and confirm it fails first.

**Organization**: Tasks are grouped by user story. US1, US2, and US4 are P1; US3 is P2. US4 (legacy configs keep working) shares the model change with everything else, so its core lands in the Foundational phase and its phase only adds the remaining contract tests.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: User story from spec.md (US1 to US4)

## Path Conventions

Swift package at the repository root: `Sources/UsageCore/`, `Sources/AgentTacho/`, `Tests/UsageCoreTests/`. Run tests with `make test` (or `swift test`).

---

## Phase 1: Setup

**Purpose**: Confirm a green baseline before changing shared types.

- [X] T001 Run `make test` from the repository root and confirm all existing suites pass before any change (baseline for regressions)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The `BudgetPeriod` model and the `budgetUSD` rename touch every consumer of `BudgetGroup`. Nothing else compiles until this is done.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T002 Write failing tests in `Tests/UsageCoreTests/ConfigurationTests.swift` for `BudgetPeriod`: raw values `"weekly"`/`"monthly"`; `adjective` ("weekly"/"monthly"), `perUnit` ("per week"/"per month"), `budgetLabel` ("Weekly budget"/"Monthly budget"); `windowKind` (`.weekly`/`.monthly`) (research R4, R7; data-model BudgetPeriod)
- [X] T003 Add `WindowKind.monthly` with `displayName` "monthly" in `Sources/UsageCore/Notifications/ThresholdTracker.swift` (keep the group key on `.weekly` for now; T031 switches it)
- [X] T004 Add `public enum BudgetPeriod: String, Codable, CaseIterable, Sendable { case weekly, monthly }` with `adjective`, `perUnit`, `budgetLabel`, and `windowKind` in `Sources/UsageCore/Config/Configuration.swift` (data-model BudgetPeriod, research R7)
- [X] T005 Write failing tests in `Tests/UsageCoreTests/ConfigurationTests.swift` for the `BudgetGroup` decoding and encoding rules: legacy `weeklyBudgetUSD` only → weekly with that amount; `period` + `budgetUSD` round-trips; encoding writes `period` and `budgetUSD` and never `weeklyBudgetUSD` (FR-002, FR-003, FR-004; contracts/config-file.md rows 1 to 3)
- [X] T006 In `Sources/UsageCore/Config/Configuration.swift`, replace `BudgetGroup.weeklyBudgetUSD` with `budgetUSD: Decimal`, add `period: BudgetPeriod = .weekly`, update the memberwise `init`, rewrite `init(from:)` per the decoding table in `specs/003-monthly-budget-period/contracts/config-file.md` (keep `weeklyBudgetUSD` as a decode-only coding key), and add an explicit `encode(to:)` that writes `id, name, label, icon, period, budgetUSD, shownInBar, thresholds` (research R5)
- [X] T007 In `Configuration.validate()` in `Sources/UsageCore/Config/Configuration.swift`, check `group.budgetUSD <= 0` and throw `"\(group.period.budgetLabel) of group \"\(group.name)\" must be greater than 0."` (FR-001, FR-019)
- [X] T008 Update every remaining `weeklyBudgetUSD` reference to `budgetUSD` so the package builds: `Sources/UsageCore/Snapshot/Aggregator.swift`, `Sources/AgentTacho/AccountSettingsView.swift`, and the tests in `Tests/UsageCoreTests/AggregatorTests.swift`, `AttributionTests.swift`, `LogIndexTests.swift`, `ThresholdTrackerTests.swift`, `ConfigurationTests.swift` (and any JSON fixtures under `Tests/UsageCoreTests/Fixtures/` that construct groups only if they fail to decode; legacy fixtures must keep `weeklyBudgetUSD` to keep exercising the legacy path)
- [X] T009 Run `make test`; all suites from T001 plus T002 and T005 pass

**Checkpoint**: Groups carry a period and a neutral amount; behaviour is still weekly everywhere.

---

## Phase 3: User Story 1 - Track a group against a monthly budget (Priority: P1) 🎯 MVP

**Goal**: A monthly group's spend, percent, reset date, bar entry, and breakdowns refer to the current calendar month.

**Independent Test**: Configure one monthly group with a budget and records on several days of the month (some before the current week, some on the last day of the previous month); the snapshot shows month-to-date spend against the budget, `resetAt` on the 1st of next month, member breakdowns over the month, and Unassigned still on the weekly window.

### Tests for User Story 1

- [X] T010 [P] [US1] Write failing tests in `Tests/UsageCoreTests/WindowResolverTests.swift` for `WindowResolver.monthWindow(now:calendar:)` with a fixed-time-zone calendar (for example `Europe/Berlin`): mid-month, exactly 00:00 on the 1st, 23:59:59 on the last day; February in a leap and a non-leap year, a 30-day and a 31-day month; a month containing a DST change (window length is not `days * 86400`); the same instant near midnight on the 1st resolved with two calendars in different time zones (for example `Pacific/Auckland` and `America/Los_Angeles`) yields different months, so a time zone change moves the window (FR-005, FR-016, research R1)
- [X] T011 [US1] Write failing tests in `Tests/UsageCoreTests/WindowResolverTests.swift` for the collection-window helper: only weekly groups → equals the weekly window; at least one monthly group → starts at `min(weekly.start, month.start)` and ends at `max(weekly.end, month.end)` (research R2)
- [X] T012 [P] [US1] Write failing tests in `Tests/UsageCoreTests/AggregatorTests.swift`: a monthly group counts records in `[1st, next 1st)` only and excludes the last day of the previous month; `GroupEntry.period`, `.window`, `.resetAt == window.end`, `budgetUSD`, and percent use existing rounding and over-100% rules; a member token-based account's breakdown covers the group's monthly window; Unassigned and subscription breakdowns stay on the weekly window; a weekly and a monthly group side by side each use their own window; a monthly group with no usage this month shows $0 and 0% (FR-008, FR-009, FR-011, FR-013, spec US1 scenarios 1, 2, 5, edge cases)
- [X] T013 [US1] Write failing tests in `Tests/UsageCoreTests/AggregatorTests.swift` for the per-day trend: a monthly window yields one entry per day from the 1st through today (zero-filled, nothing after today); a weekly window keeps one entry per day of the whole window (FR-013, research R6)
- [X] T014 [P] [US1] Write failing tests in `Tests/UsageCoreTests/RefreshCoordinatorTests.swift`: with only weekly groups the record source's `RefreshContext.window` equals the weekly window (unchanged behaviour); with a monthly group it is the collection window spanning the month; the snapshot's `window` stays the weekly window; a monthly group's window ignores a new 7-day reset fetched in the same refresh; starting weekly-only and then adding a monthly group, the next refresh includes records from the 1st of the month (LogIndex reset path) (FR-006, spec US1 scenario 4, research R2)

### Implementation for User Story 1

- [X] T015 [US1] Add `monthWindow(now:calendar:) -> DateInterval` (via `calendar.dateInterval(of: .month, for:)`) and a `collectionWindow(weekly:now:configuration:calendar:) -> DateInterval` helper to `Sources/UsageCore/Windows/WindowResolver.swift`, with doc comments citing FR-005, FR-006 and research R1, R2
- [X] T016 [US1] Add `period: BudgetPeriod` and `window: DateInterval` to `GroupEntry` in `Sources/UsageCore/Snapshot/UsageSnapshot.swift` (update its `init`; `resetAt` stays and equals `window.end`) (data-model GroupEntry)
- [X] T017 [US1] In `Sources/UsageCore/Snapshot/Aggregator.swift`: remove the up-front `inWindow` filter to the weekly window and bucket all passed records by account and Unassigned first; resolve each group's window (weekly window for weekly groups, `monthWindow` for monthly) and filter its members' records to that window; fill the new `GroupEntry` fields; compute each token-based account's breakdown over its group's window; filter the Unassigned bucket and each subscription account's records to the weekly window. Change the signatures to `breakdown(of:priced:window:lastDay:calendar:)` and `perDay(of:priced:window:lastDay:calendar:)`, where `lastDay` is the window's last day for weekly windows and the start of today for monthly windows (FR-008, FR-009, FR-011, FR-013, research R3, R6)
- [X] T018 [US1] In `Sources/UsageCore/Snapshot/RefreshCoordinator.swift`, build `RefreshContext` with the collection window for both the initial and the final resolution, compare collection starts for the T040 re-run of window-sensitive sources, pass the weekly window to the aggregator, update the `RefreshContext.window` doc comment, log the collection window start in the record source's "record(s) since" line, and add the group's period to the per-group refresh log line. Read the calendar per refresh so a time zone change moves the monthly window: replace the stored `calendar: Calendar = .current` default with `Calendar.autoupdatingCurrent` (tests keep injecting a fixed calendar). When the record source fails and previous group entries are carried over as stale, they keep their old `period` and `window`; document this in a comment (stale values are shown as such and skipped by the threshold tracker) (FR-016, research R1, R2)
- [X] T019 [US1] Run `make test`; T010 to T014 pass and no earlier suite regresses

**Checkpoint**: Monthly groups work end to end when configured in the file (US1 deliverable).

---

## Phase 4: User Story 2 - Choose the period in settings (Priority: P1)

**Goal**: The user picks Weekly or Monthly next to the amount when editing or creating a group; labels follow the period.

**Independent Test**: In the running app, switch a weekly group to monthly and save; the summary reads "per month", the amount label reads "Monthly budget", and the next refresh shows month-to-date values. Create a new monthly group while adding a token-based account.

### Tests for User Story 2

- [X] T020 [P] [US2] Add a regression test in `Tests/UsageCoreTests/ConfigurationTests.swift` that changing only a group's `period` (or `budgetUSD`) requires a local refresh (`needsRefresh(comparedTo:)` is true) but no network refresh (`needsNetworkRefresh(comparedTo:)` is false), so a period switch reprices at the next refresh (FR-010). It may already pass after Phase 2; it guards the behaviour.

### Implementation for User Story 2

- [X] T021 [US2] In the group editor of `Sources/AgentTacho/AccountSettingsView.swift` (the `Section("Budget group")` view with `@Binding var group: BudgetGroup`), add a segmented `Picker("Period", selection: $group.period)` next to the amount, label the amount with `group.period.budgetLabel`, show `"The \(group.period.adjective) budget must be greater than 0."` as the inline error, and pass `"the \(group.period.adjective) budget"` to `ThresholdsEditor` (FR-014, FR-018, FR-019)
- [X] T022 [US2] In the add-account sheet of `Sources/AgentTacho/AccountSettingsView.swift`, add `@State private var newGroupPeriod: BudgetPeriod = .weekly` with a segmented period picker next to the new-group amount, label the amount with `newGroupPeriod.budgetLabel`, and create the group with `period: newGroupPeriod, budgetUSD: newGroupBudget` (FR-002, FR-018)
- [X] T023 [US2] In the group list summary of `Sources/AgentTacho/AccountSettingsView.swift`, show `"\(UsageFormat.usd(group.budgetUSD)) \(group.period.perUnit), N member(s)"`, and change the "Vertex weekly" name prompts to "Vertex" (FR-014)
- [X] T024 [US2] In `Sources/AgentTacho/SettingsView.swift`, add a caption under the "Weekly window" section: "Applies to weekly budget groups and the Unassigned entry. Monthly groups always run from the 1st to the end of the month." (FR-020, research R8)
- [X] T025 [US2] In `Sources/AgentTacho/BreakdownView.swift`, add a `period: BudgetPeriod` property; lay the day row out as a `Grid` that wraps after 7 columns; label weekly columns with the weekday initial and monthly columns with the day of the month; make the legend say "one column per day of the \(period.adjective) window" and, for monthly, "from the 1st to today". Update every `BreakdownView(...)` call in `Sources/AgentTacho/DropdownView.swift` to pass the group's period (from `GroupEntry.period` or the member's group) and `.weekly` for subscription accounts and Unassigned (FR-013, FR-014, SC-006, research R6)
- [X] T026 [US2] Run `make build` and `make test`; both succeed

**Checkpoint**: The feature is usable without hand-editing the configuration file.

---

## Phase 5: User Story 4 - Existing configurations keep working (Priority: P1)

**Goal**: Files written by the previous version load unchanged; invalid hand edits are rejected per FR-004a.

**Independent Test**: Load a previous-version configuration file; every group is weekly with its old amount, window, and thresholds. Hand-edited files matching the error rows of the contract table are rejected.

### Tests for User Story 4

- [X] T027 [P] [US4] Add tests in `Tests/UsageCoreTests/ConfigurationTests.swift` for the remaining rows of `specs/003-monthly-budget-period/contracts/config-file.md`: both `budgetUSD` and `weeklyBudgetUSD` present → `budgetUSD` wins; `"period": "monthly"` with only `weeklyBudgetUSD` → decode error; no amount → decode error; `"period": "yearly"` → decode error; `"period": 1` → decode error (FR-004a)
- [X] T028 [P] [US4] Add a test in `Tests/UsageCoreTests/ConfigStoreTests.swift` that loading a legacy file (with `weeklyBudgetUSD`) leaves the file bytes unchanged, and that saving it writes `period` and `budgetUSD` and reloads to equal groups (FR-003, FR-004, spec US4 scenario 2)
- [X] T029 [US4] Fix any failure from T027 or T028 in `Sources/UsageCore/Config/Configuration.swift` or `Sources/UsageCore/Config/ConfigStore.swift`, then run `make test`

**Checkpoint**: Upgrade safety proven by tests.

---

## Phase 6: User Story 3 - Threshold notifications for a monthly group (Priority: P2)

**Goal**: Monthly groups notify once per threshold per calendar month, naming the monthly window.

**Independent Test**: With a monthly group and a 50% threshold, drive the percent from 45% to 55% (one crossing named "monthly"), stay above 50% (no repeat), roll the month (re-armed, baseline first), and switch the period (baseline, no notification for thresholds already exceeded).

### Tests for User Story 3

- [X] T030 [P] [US3] Write failing tests in `Tests/UsageCoreTests/ThresholdTrackerTests.swift`: a monthly group crossing 50% yields one `ThresholdCrossing` with `windowKind == .monthly`; later refreshes in the same month above 50% yield none; a new `resetAt` (month rollover, or a time zone change moving the month) resets state and the first observation is a baseline; switching the group's period from weekly to monthly while above a threshold yields no crossing on the first refresh after the switch (FR-015, FR-016, FR-017, SC-005)

### Implementation for User Story 3

- [X] T031 [US3] In `Sources/UsageCore/Notifications/ThresholdTracker.swift`, key group state by `Key(entityId: group.id, windowKind: group.period.windowKind)` and update the doc comment to cite FR-015 to FR-017 (research R4)
- [X] T032 [US3] Check `Sources/AgentTacho/NotificationPresenter.swift` and `Sources/AgentTacho/App.swift` handle `.monthly` (body "monthly window at N%", identifier and log line use `windowKind`); change code only if an exhaustive `switch` over `WindowKind` needs the new case (FR-015)
- [X] T033 [US3] Run `make test`; T030 passes

**Checkpoint**: All user stories complete.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T034 [P] Update `specs/001-agenttacho/contracts/config-file.md` example and rules to the new `period`/`budgetUSD` form with a pointer to `specs/003-monthly-budget-period/contracts/config-file.md` for legacy decoding
- [X] T035 [P] Update README.md wherever it describes weekly budgets so it mentions the weekly or monthly period choice
- [X] T036 Run `rg -n "weeklyBudgetUSD|weekly budget|per week" Sources` and confirm the only remaining hits are the decode-only legacy key and period-driven wording
- [X] T037 Run the manual steps in `specs/003-monthly-budget-period/quickstart.md` that do not need a real month rollover (`make run`), and record any deviation; with a monthly group configured, read the "done in N s" refresh line from the diagnostic log and confirm it meets spec 001 SC-004 (SC-006)
  - Automated part only (ship pipeline, no GUI access): `make app` builds. Headless timing with a monthly group over the real session logs on 2026-10-14 (release build): full refresh 3.76 s (914 files, 1.3 GB re-read, 36.5k records), incremental 0.26 s, both within SC-004. A debug build takes 13.6 s for the same cold refresh (weekly-only: 3.3 s), so the cold refresh grows with the month's log volume. Quickstart GUI steps 2 to 6 were NOT run and still need a manual pass.
- [X] T038 Run `make test` and `make build` a final time

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none.
- **Foundational (Phase 2)**: after Setup; blocks all stories (shared type change).
- **US1 (Phase 3)**: after Foundational. MVP.
- **US2 (Phase 4)**: after Foundational. T025 needs `GroupEntry.period` from T016, so run it after US1's T016.
- **US4 (Phase 5)**: after Foundational; independent of US1 and US2.
- **US3 (Phase 6)**: after Foundational (needs `WindowKind.monthly` from T003); its tests use `GroupEntry` values, so run after T016.
- **Polish (Phase 7)**: after all stories.

### Within Each Story

Tests first and failing, then implementation, then the story's `make test` checkpoint.

### Parallel Opportunities

- T010 (WindowResolverTests), T012 (AggregatorTests), and T014 (RefreshCoordinatorTests) touch different files and can be written in parallel; T011 and T013 follow in the same files.
- US4 (T027, T028) can run in parallel with US1 once Phase 2 is done.
- T034 and T035 are independent documentation edits.
- Implementation tasks within a story mostly touch shared files (`Aggregator.swift`, `AccountSettingsView.swift`) and run sequentially.

## Parallel Example: User Story 1

```text
Task: "T010 monthWindow tests in Tests/UsageCoreTests/WindowResolverTests.swift"
Task: "T012 monthly group aggregation tests in Tests/UsageCoreTests/AggregatorTests.swift"
Task: "T014 collection window tests in Tests/UsageCoreTests/RefreshCoordinatorTests.swift"
```

## Implementation Strategy

### MVP First

1. Phase 1 and Phase 2 (model change, still weekly behaviour).
2. Phase 3 (US1): monthly groups work from the configuration file. Validate with T019.

### Incremental Delivery

1. US1: monthly windows and display.
2. US2: settings controls and labels (feature usable without file edits).
3. US4: upgrade safety tests for every contract row.
4. US3: monthly notifications.
5. Polish: docs and final checks.
