# Tasks: Threshold Levels and Budget Direction

**Input**: Design documents from `specs/030-threshold-levels-direction/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Required. Constitution II: logic in UsageCore, tests written first and failing before the implementation. Every new or changed UsageCore type cites its FRs in doc comments (`spec 030 FR-00x`).

**Rules for every task**: build and test only with `make test` (and `make test-release` at the end), never `swift build` or `xcodebuild`. No em dash or en dash characters anywhere. Conventional Commits with the "Assisted-By: 🤖 Claude Code" trailer.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: US1 to US4 from spec.md

---

## Phase 1: Setup

- [X] T001 Run `make test` on the branch before any change and note the baseline (all tests pass) in the commit message of T004; no file change.

---

## Phase 2: Foundational (blocks all stories)

**Purpose**: the direction setting and the level rule are used by every story.

- [X] T002 [P] Write failing tests in `Tests/UsageCoreTests/LevelThresholdsTests.swift` for `LevelThresholds` with every row of the table in `contracts/level-rule.md` (warning, critical, and the level at 79, 85, 91, 100), plus `atRealLimit: true` below the thresholds giving critical, and `usedPercent: nil` giving normal.
- [X] T003 [P] Write failing tests in `Tests/UsageCoreTests/ConfigurationTests.swift` for `Configuration.displayDirection`: missing key decodes `.used`; `"remaining"` decodes `.remaining`; `"Remaining"`, `"sideways"`, `42` and `null` decode `.used` without failing the file; encode then decode round-trips both values; an older configuration file fixture loads unchanged (FR-008).
- [X] T004 Implement `Sources/UsageCore/Bar/LevelThresholds.swift` (`LevelThresholds`, `init(_ thresholds: [Int])` keeping duplicates, `level(usedPercent:atRealLimit:)`) and `PercentTone` (`primary`, `warning`, `critical`, `init(_ level: BarLevel)`) in the same file, so T002 passes. Doc comments cite spec 030 FR-001 to FR-003, FR-005.
- [X] T005 Implement `Sources/UsageCore/Config/DisplayDirection.swift` (`enum DisplayDirection: String, Codable, Sendable { case used, remaining }`) and the `displayDirection` property, init parameter (default `.used`), lenient decode and encode in `Sources/UsageCore/Config/Configuration.swift`, following the pattern of `levelColor`, so T003 passes (FR-008).
- [X] T006 Make `BarLayout.level(percent:thresholds:)` in `Sources/UsageCore/Bar/BarLayout.swift` delegate to `LevelThresholds`; keep `warningThreshold` and `defaultWarningThreshold`. Update the `BarLevel.critical` doc comment ("at or above the critical threshold, or at a real limit"). Run `make test`; fix tests in `Tests/UsageCoreTests/BarLayoutTests.swift` only where they assert the old fixed-100 rule with a second threshold below 100, and add a test: thresholds `[80, 90]`, budget at 91% is critical.

**Checkpoint**: `make test` passes; no visible change yet except the menu bar critical level following the second threshold.

---

## Phase 3: User Story 1, Red at my own limit (P1) 🎯 MVP

**Goal**: thresholds drive warning and critical in the menu bar, the dropdown row percents, the section header percents and the red bar.

**Independent test**: thresholds 80 and 90 with values 79, 85, 91: menu bar level, dropdown percent tone and bar tone match `contracts/level-rule.md`.

### Tests (write first, must fail)

- [X] T007 [P] [US1] Extend `Tests/UsageCoreTests/BarLayoutTests.swift`: subscription with thresholds `[80, 90]` and headline 91% is critical with `overLimit == false`; Claude 7-day at 100% while 5-hour is the headline is critical with `overLimit == true`; Codex with `anyLimitReached` is critical with `overLimit == true`; thresholds `[80, 120]` at 100% is critical with `overLimit == true`; a group member item keeps the group's thresholds (`[50, 75]`, member share 80% is critical) (FR-003, FR-004).
- [X] T008 [P] [US1] Extend `Tests/UsageCoreTests/BarPresentationTests.swift`: accessibility text reads "critical" for a critical item without `overLimit` and "over limit" with it; warning stays "warning" (FR-004).
- [X] T009 [P] [US1] Extend `Tests/UsageCoreTests/RowBarTests.swift`: `RowBar.make` with thresholds `[80, 90]` at 85% has level warning and tone neutral (or attention with an attention reading), at 91% level critical and tone `.overLimit`; `limitReached: true` at 40% is critical; `RowBar.budget` with thresholds `[50, 75]` at 60% is warning with a neutral bar, at 80% critical and red; with `[]` the old behavior holds (red exactly at a rounded 100) (FR-005, FR-006).
- [X] T010 [P] [US1] Extend `Tests/UsageCoreTests/HeadlineWindowTests.swift`: the subscription header carries the same level as the bar item, including the Claude 7-day cross-window rule and the Codex `anyLimitReached` rule (I-4 decision).

### Implementation

- [X] T011 [US1] In `Sources/UsageCore/Bar/BarLayout.swift`: add `overLimit: Bool` to `BarItem` (default false); extract the level decisions of `subscriptionItem` and `codexItem` into internal statics (for example `subscriptionLevel(...)` and `codexLevel(...)` returning level and overLimit) used by both the items and the header; `budgetItem` sets `overLimit` when the rounded percent is at least 100. Doc comments cite spec 030 FR-003, FR-004.
- [X] T012 [US1] In `Sources/UsageCore/Bar/BarPresentation.swift`: accessibility word "critical" vs "over limit" from `item.overLimit` (FR-004). T008 passes.
- [X] T013 [US1] In `Sources/UsageCore/Dropdown/RowBar.swift`: `make(usedPercent:limitReached:thresholds:reading:)` and `budget(_:thresholds:reading:)` decide `level` through `LevelThresholds` (row's own rounded percent and own `limitReached`); expose `public let level: BarLevel` and `percentTone: PercentTone`; tone `.overLimit` exactly when level is critical; warning never colors the bar. Update doc comments (spec 030 FR-005, FR-006, amends spec 025 FR-003, FR-007). T009 passes.
- [X] T014 [US1] In `Sources/UsageCore/Bar/HeadlineWindow.swift` add public header factories that the app can call (T011's level statics are internal, so these wrap them):
  - `public static func claudeHeader(_ headline: ResolvedHeadline, entry: SubscriptionEntry?, thresholds: [Int], now: Date) -> HeadlineHeader?`
  - `public static func codexHeader(_ headline: ResolvedHeadline?, entry: CodexLimitsEntry, thresholds: [Int], now: Date) -> HeadlineHeader?`
  - both call `BarLayout.subscriptionLevel` / `BarLayout.codexLevel`, so the header and the bar item cannot disagree (cross-window rules included);
  - `HeadlineHeader` gains `level: BarLevel`, `overLimit: Bool` and `accessibilityValue: String` (equal to `value` until T027).
  T010 passes against these functions.
- [X] T015 [US1] In `Sources/AgentTacho/DropdownView.swift`: pass the account's or budget's thresholds into `RowBar.make` and `RowBar.budget`; `LimitRowLayout` colors the percent from `bar.percentTone` (primary, orange, red); switch the Claude header call (`HeadlineWindow.header(_:state:)`, near line 557) and the Codex header (`headline?.header`, near line 1070) to `claudeHeader`/`codexHeader`, and `HeadlineHeaderText` colors the bold value from `header.level`; add a `thresholds: [Int]` property to `BudgetSection`, pass `group.thresholds` or the own budget's `thresholds` where it is built, and color its header percent from the budget level. Member lines stay `.secondary`. Map `PercentTone` to colors in one extension next to `NoteStyle.color`.
- [X] T016 [US1] In `Sources/AgentTacho/SettingsView.swift` `ThresholdsEditor`: update the level sentence literal to "The first value marks the entry as a warning, the second as critical (80% and 100% when empty). A real limit at 100% is always critical. The Menu Bar tab sets how levels look." (keeps the empty-field sentence). T034 later replaces it with `ThresholdDisplay.explanation`.

**Checkpoint**: `make test` passes; US1 scenarios 1 to 6 hold in unit tests.

---

## Phase 4: User Story 2, Watch the budget empty (P1)

**Goal**: one global switch shows every level value as remaining, with flipped bars and markers.

**Independent test**: switch the direction in the demo build; every level value is 100 minus its used value, markers flip, colors stay.

### Tests (write first, must fail)

- [X] T017 [P] [US2] Create `Tests/UsageCoreTests/DirectedPercentTests.swift` with the `DirectedPercent` table of `contracts/direction-presentation.md` (value, text with U+2212, accessibility text for `.budget` and `.window`, fill and tick in both directions, clamping, non-finite input gives 0).
- [X] T018 [P] [US2] Create `Tests/UsageCoreTests/RunOutGlyphTests.swift`: ↗, ↑ in used; ↘, ↓ in remaining (FR-011).
- [X] T019 [P] [US2] Create `Tests/UsageCoreTests/BudgetAmountLineTests.swift` with the dollar table of the contract, including 100.4 of 100 reading "$0 left" and 115 of 100 reading "$15 over", and a budget of 0 or less returning `.of(spent)` in both directions ("$5 of $0/week") (FR-012, M-7, review-plan decision).
- [X] T020 [P] [US2] Extend `Tests/UsageCoreTests/BarLayoutTests.swift`: with `displayDirection = .remaining`, subscription at 70% has value "30%", Codex and budget values flip, a member share stays the used share, "…" and "--" unchanged, stale keeps "~" before the value in the presentation; levels are identical in both directions for the same snapshot; the subscription header from `claudeHeader` reads value "30%" and accessibility value "30% left" in remaining (FR-009, FR-013, FR-014).
- [X] T021 [P] [US2] Extend `Tests/UsageCoreTests/BarPresentationTests.swift`: remaining-mode entry uses ↘/↓ and its accessibility text reads "30% left" (FR-009, FR-011).
- [X] T022 [P] [US2] Extend `Tests/UsageCoreTests/RowBarTests.swift`: in remaining, fill is the remaining share and the tick the expected remaining share; tone and level unchanged from used; a row at 99.6% used in remaining shows "0%", is critical, and has a fill of about 0.004 (spec Edge Cases, FR-010, FR-014).
- [X] T023 [P] [US2] Extend `Tests/UsageCoreTests/RowTextTests.swift`: in remaining the window accessibility label names "30% left", and a window at 104% names "4% over the limit"; in used it is unchanged (FR-009, FR-012).

### Implementation

- [X] T024 [P] [US2] Create `Sources/UsageCore/Bar/DirectedPercent.swift` per the contract (FR-009, FR-010, FR-012). T017 passes.
- [X] T025 [P] [US2] Create `Sources/UsageCore/Bar/RunOutGlyph.swift` (FR-011). T018 passes.
- [X] T026 [P] [US2] Create `Sources/UsageCore/Dropdown/BudgetAmountLine.swift` (FR-012). T019 passes.
- [X] T027 [US2] Wire the direction through UsageCore: `BarLayout.segments` reads `configuration.displayDirection` and builds values via `DirectedPercent` (members excluded), a new `BarItem.accessibilityValue`, and a new `BarItem.runOutGlyph: String?` set from `RunOutGlyph.text(burnsFast:direction:)` when the item carries a marker (review-plan decision: the item carries its glyph, so `BarPresentation.entries` keeps its signature and every caller, including the Settings preview with its draft configuration, follows the direction automatically); `BarPresentation` takes the marker from `item.runOutGlyph` and the words from `accessibilityValue`; `RowBar.make`/`budget` take `direction` for fill and tick; `RowText.window` takes `direction`; `claudeHeader`/`codexHeader` take `direction: DisplayDirection` and build `value` and `accessibilityValue` via `DirectedPercent`. `direction` has no default value on `RowBar.make`, `RowBar.budget`, `RowText.window` and the header factories, so the compiler finds every call site; tests pass `.used` explicitly. Files: `Sources/UsageCore/Bar/BarLayout.swift`, `BarPresentation.swift`, `HeadlineWindow.swift`, `Sources/UsageCore/Dropdown/RowBar.swift`, `RowText.swift`. T020 to T023 pass; fix call sites in `Sources/DemoMode` and existing tests for the new parameters (default `.used` where a default keeps old call sites valid).
- [X] T028 [US2] App layer: `Sources/AgentTacho/SettingsView.swift` `GeneralSettingsTab` gets `Section("Display")` right after `Section("Refresh")` with `Picker("Show usage as", selection: $configuration.displayDirection)` (`.pickerStyle(.segmented)`, "Used"/"Remaining") and the caption from FR-008; `Sources/AgentTacho/MenuBarSettingsTab.swift` checkbox label built from `RunOutGlyph` and the preview passing the direction; `Sources/AgentTacho/DropdownView.swift` passes the direction to rows, headers, budget percent (`DirectedPercent.text`), adds `.accessibilityLabel` to `HeadlineHeaderText` from `header.accessibilityValue` and to the budget header percent from `DirectedPercent.accessibilityText(.budget)`, and the amount line (`BudgetAmountLine.text` with `UsageFormat.amount`/`UsageFormat.budget`); `Sources/AgentTacho/BarLabel.swift` and wherever `BarPresentation.entries` is called pass the direction. Follow the save path the other General settings use.

**Checkpoint**: `make test` passes; `make app-demo` shows US2 scenarios 1 to 6.

---

## Phase 5: User Story 3, Over budget in remaining mode (P2)

**Goal**: values above 100% used read negative, red, with an empty bar and "$N over".

**Independent test**: unit tests for a budget at 115% in both directions.

- [X] T029 [US3] Add tests to `Tests/UsageCoreTests/BarLayoutTests.swift` and `Tests/UsageCoreTests/RowBarTests.swift`: budget at 115% in remaining has value "−15%", level critical with `overLimit`, fill 0, and the full presentation accessibility text "Side project over limit 15% over budget" (doubled wording accepted, review-plan decision); a subscription window reported at 104% reads "−4%" with "4% over the limit"; in used the same values read "115%" and "$115 of $100/week" (US3 scenarios 1 to 3, FR-012). Fix any gap in T024 to T027 until they pass.

---

## Phase 6: User Story 4, Thresholds in the chosen direction (P2)

**Goal**: the editor and the notifications speak the chosen direction while stored values stay used percent.

**Independent test**: conversion and notification text unit tests in both directions.

### Tests (write first, must fail)

- [X] T030 [P] [US4] Create `Tests/UsageCoreTests/ThresholdDisplayTests.swift`: shown/stored conversion both ways (80 ↔ 20, 100 ↔ 0, 120 ↔ −20), validity (used: > 0; remaining: < 100, negatives allowed), caption "(20% over)" for stored 120 in remaining and nil otherwise, placeholders, field suffix "%" vs "% left", the explanation text in both directions names both levels and the empty-field rule (FR-007), the further-thresholds line in the direction, and `validationMessage(direction:)` ("Use whole numbers greater than 0." in used, "Use whole numbers below 100." in remaining) (FR-015).
- [X] T031 [P] [US4] Create `Tests/UsageCoreTests/ThresholdNotificationTextTests.swift` with every row of the notification table in `data-model.md` and the contract examples, including the jump from 70% to 115% ("weekly window at 15% over") and used mode staying "<name> reached T%" / "<window> window at P%" (FR-016); `logDescription(_:)` names the threshold and percent in used percent whatever the direction (FR-017).

### Implementation

- [X] T032 [P] [US4] Create `Sources/UsageCore/Notifications/ThresholdDisplay.swift` (FR-007, FR-015). T030 passes.
- [X] T033 [P] [US4] Create `Sources/UsageCore/Notifications/ThresholdNotificationText.swift` (FR-016). T031 passes.
- [X] T034 [US4] `Sources/AgentTacho/SettingsView.swift` `ThresholdsEditor`: take `direction`; fields show `ThresholdDisplay.shown`, write `ThresholdDisplay.stored`, suffix and placeholders from `ThresholdDisplay`, caption for stored values above 100, validation message from `ThresholdDisplay.validationMessage(direction:)`, explanation and further-thresholds line from `ThresholdDisplay`. Pass the direction from every call site (`AccountSettingsView.swift` and others found with `rg ThresholdsEditor`).
- [X] T035 [US4] `Sources/AgentTacho/NotificationPresenter.swift`: change to `init(log: DiagnosticLog, direction: @escaping @MainActor () -> DisplayDirection)`; `Sources/AgentTacho/App.swift` (near line 133) passes a closure returning the current configuration's `displayDirection`; `post(_:)` calls it when it posts (FR-016 posting-time rule) and takes title and body from `ThresholdNotificationText.make(crossing, direction:)`; the log line uses `ThresholdNotificationText.logDescription(_:)` (moved from the private `describe(_:)`, FR-017). For SC-004 add tests in `Tests/UsageCoreTests/ThresholdDisplayTests.swift` that `stored(shown(T))` equals T for every T in -50...250 in both directions, and in `Tests/UsageCoreTests/ConfigurationTests.swift` that a configuration with `displayDirection = .remaining` encodes and decodes with the same stored thresholds as in `.used`.

**Checkpoint**: `make test` passes; US4 scenarios 1 to 4 hold.

---

## Phase 7: Polish, demo, docs, spec amendments

- [X] T036 Demo scenario: first run the coverage report of the current `default` scenario and record which bar entry carries ↗ and which ↑ (a critical entry loses its marker, `BarLayout.markers` requires a normal level); choose the owner so both markers stay. Then in `Resources/demo/default.json` lower ChatGPT Plus thresholds so its weekly window (60%) is critical below 100 (for example `[50, 55]`); keep Claude Max at 80/100. Add `thresholdCriticalRows` (rows whose level is critical while their rounded used percent is below 100) to `Sources/DemoMode/ScenarioCoverage.swift` and an `#expect` that it is not empty in `Tests/DemoModeTests/DefaultScenarioTests.swift`. All existing expectations (levels, markers ↗ and ↑, pace states, attention row Claude 7-day, bar tags, headline rows) must still pass; if a marker check breaks because the Codex entry turned critical, pick another owner or values and record the choice in plan.md's Screenshots table. Also add a check in `Tests/DemoModeTests` that some budget owner in the `default` or `variants` scenario is above 100% after the last frame, adjusting a scenario if none is (FR-020).
- [X] T037 [P] `docs/usage.md`: rewrite the levels paragraph (thresholds set orange and red, a real limit is always red, dropdown percents and the red bar) and add a paragraph on "Show usage as" (what flips, what does not, negative values over budget, thresholds and notifications in the direction). `docs/configuration.md`: document `displayDirection` (`"used"` default, `"remaining"`) and that thresholds stay in used percent (FR-019).
- [X] T038 [P] Spec amendments (FR-019): add a dated "Amended by spec 030 (2026-10-20)" note at the affected requirement in `specs/001-agenttacho/spec.md` (FR-003, FR-027, FR-028), `specs/012-colored-bar-levels/spec.md` (critical from the second threshold, "critical" vs "over limit"), `specs/025-minimal-dropdown/spec.md` (FR-002 fill and tick follow the direction, FR-003 and FR-007 red at the critical threshold, percents take level colors), `specs/011-pace-forecast/spec.md` FR-012 and `specs/017-burn-rate-escalation/spec.md` FR-008 (↘ and ↓ in remaining).
- [X] T039 Update `specs/030-threshold-levels-direction/plan.md` "Screenshots and website" if T036 chose a different owner; leave capture (AGENTS.md step 4) and the site pull request for after the walkthrough, since capture needs the maintainer's go.
- [X] T040 Run `make test` and `make test-release`; both must pass. Run `rg -n '\x{2013}|\x{2014}'` over changed files; none may match.
- [X] T041 Walk through `quickstart.md` steps 1 to 6 in `make app-demo` as far as possible without the capture; note anything that differs.

---

## Dependencies & Execution Order

- Phase 1 → Phase 2 (T002/T003 before T004/T005; T006 after T004).
- US1 (Phase 3) depends on Phase 2.
- US2 (Phase 4) depends on Phase 2; it touches the same files as US1 (`BarLayout`, `RowBar`, `HeadlineWindow`, `DropdownView`), so run it after US1 to avoid conflicts.
- US3 (Phase 5) depends on US2.
- US4 (Phase 6) depends on Phase 2 (direction) only; T032/T033 can run in parallel with US2, T034/T035 after T016.
- Phase 7 after all stories.

## Parallel Examples

- Phase 2: T002 and T003 together; then T004 and T005 together.
- US1 tests: T007, T008, T009, T010 together.
- US2 tests: T017 to T023 together; then T024, T025, T026 together.
- US4: T030 and T031 together; then T032 and T033 together.
- Polish: T037 and T038 together.

## Implementation Strategy

- **MVP**: Phases 1 to 3 (US1): thresholds drive the levels everywhere, no setting yet. Shippable on its own.
- **Increment 2**: US2 and US3, the direction switch with negative values.
- **Increment 3**: US4, the editor and notifications in the direction.
- Commit after each phase with a Conventional Commit message; `make test` green at every commit.
