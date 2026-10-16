# Tasks: Pace Forecast

**Input**: Design documents from `/specs/011-pace-forecast/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/pace-display.md, quickstart.md

**Tests**: Included (AGENTS.md: write the test first). Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`). Write each test task before its implementation and confirm it fails once the package compiles.

**Global constraints** (from plan.md):
- Pace uses observation times and the snapshot time, never `Date()` (research R2).
- Existing configurations load unchanged; `BarItem`'s initializer stays source compatible (default `runOutMarker: false`).
- No network requests, credential reads or files (FR-016). No em dash or en dash characters. Doc comments cite spec 011 FR ids.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on incomplete tasks)
- **[Story]**: US1 (budgets), US2 (subscription windows), US3 (bar marker)

---

## Phase 1: Setup

- [X] T001 Run `make test` and confirm all existing suites pass (baseline).

---

## Phase 2: Foundational (blocking): the pace computation

- [X] T002 Create `Tests/UsageCoreTests/PaceTests.swift` with tests for `Pace.compute(usedPercent:windowStart:resetsAt:observedAt:now:)` (research R5, data-model.md): expected percent is the elapsed share (0 at start, 50 halfway, clamped to 0...100 when `observedAt` is before the start or after the end); delta uses the unrounded used percent and rounds to the nearest whole number (for example 47.6 used at 42.857 expected gives 5, 47.4 gives 5, 48.0 gives 5, 48.4 gives 6); status is `.onPace` for -5 and +5 (inclusive), `.ahead(6)` at +6, `.behind(6)` at -6; run-out is nil when on pace or behind, nil before 10% of the window has elapsed (also when far ahead; at 9.9% elapsed it is nil, at exactly 10.0% it is set), nil when used is 0, a negative used percent (possible from outside Codex values) gives `.behind` (for example -3 at 20% expected gives `.behind(23)`) and no run-out, and otherwise equals `observedAt + (100 - used) * elapsed / used` and is before `resetsAt`; nil pace when used >= 100, used not finite, `resetsAt <= windowStart`, or `resetsAt <= now`. Include the spec examples as tests: monthly budget 145 of 300 on 10 Oct 2026 00:00 local in a window from 1 Oct to 1 Nov gives delta 19 and run-out 19 Oct 14:53 (compare to the minute in a fixed `Europe/Berlin` calendar); 7-day window at 62% three days in gives delta 19 and run-out 44 h 07 min after the observation; Story 1 scenarios (48% at 33% gives 15 ahead with run-out; 50% at 50% on pace; 20% at 60% gives 40 behind, no run-out); Story 3 scenario 3 (5% elapsed, far ahead, no run-out). Add tests for `Pace.summary(runOutText:)`: "on pace", "12% ahead", "8% behind", and "12% ahead · runs out X" with the closure's text when `runOut` is set.
- [X] T003 Create `Sources/UsageCore/Pace/Pace.swift` with `PaceStatus`, `Pace` (`expectedPercent`, `delta`, `status`, `runOut`), `Pace.tolerancePoints = 5`, `Pace.holdBackShare = 0.10`, `Pace.compute(...)` and `summary(runOutText:)` (spec 011 FR-001 to FR-008, FR-017). Use `PercentFormatter.rounded` for the delta. T002 passes.
  Interfaces: `public enum PaceStatus: Equatable, Sendable { case onPace, ahead(Int), behind(Int) }`; `public struct Pace: Equatable, Sendable { public let expectedPercent: Double; public let delta: Int; public let status: PaceStatus; public let runOut: Date? }`; `public static func compute(usedPercent: Double, windowStart: Date, resetsAt: Date, observedAt: Date, now: Date) -> Pace?`; `public func summary(runOutText: (Date) -> String) -> String`.

**Checkpoint**: the pace rules are complete and tested; no UI yet.

---

## Phase 3: User Story 1 - Will the budget last until the reset? (P1) MVP

- [X] T004 [US1] Add tests to `Tests/UsageCoreTests/PaceTests.swift` for `GroupEntry.pace(now:)`: uses `spentUSD / budgetUSD * 100` unrounded (not `percent`), the entry's `window` start and end, and `now` as observation time; nil for an empty group (`members == []`), for `budgetUSD <= 0`, at or above 100%, and when `window.end <= now`; works for a weekly and a monthly (31-day) window (FR-001, FR-002, FR-007).
- [X] T005 [US1] Implement `GroupEntry.pace(now:)` in `Sources/UsageCore/Pace/Pace.swift` (data-model.md). T004 passes.
  Interface: `extension GroupEntry { public func pace(now: Date) -> Pace? }`.
- [X] T006 [US1] In `Sources/AgentMeter/DropdownView.swift` add `UsageFormat.runOutText(_:)` (time only when today, otherwise weekday, day, month, hour and minute, also at local midnight; FR-009) and a `PaceLine` view taking an optional `Pace`: renders nothing for nil, otherwise `pace.summary(runOutText: UsageFormat.runOutText)` in `.caption`, orange when `runOut != nil`, secondary otherwise (FR-008, FR-010). Interface: `struct PaceLine: View { let pace: Pace?; var indent: CGFloat = 0 }` and `static func runOutText(_ date: Date) -> String` in `UsageFormat`. Under window rows (T009) the indent aligns the line with the percent column (the 60 pt title width plus the HStack spacing); under the budget amount line there is no indent. In `BudgetSection`, show `PaceLine(pace: entry.pace(now: snapshot.generatedAt))` directly below the amount and reset line, not for member lines (FR-011). `make app` builds.

**Checkpoint**: budgets show their pace in the dropdown.

---

## Phase 4: User Story 2 - Will the subscription limit hold until the reset? (P1)

- [X] T007 [US2] Add tests to `Tests/UsageCoreTests/PaceTests.swift` for the window adapters: `LimitWindow.pace(length:observedAt:now:)` is nil without `resetsAt` and uses `resetsAt - length` as start (5 h and 7 d); `ModelLimit.pace(observedAt:now:)` uses a 7-day length; `CodexLimitWindow.pace(observedAt:now:)` uses `lengthMinutes * 60`, is nil without `resetsAt` and when `limitReached`; a Codex entry whose window has passed its reset gives nil through `CodexLimitsEntry.windows(now:)` (research R3); a stale Claude status whose 7-day reset is before `now` gives nil (FR-001, FR-002, FR-007).
- [X] T008 [US2] Implement the three adapters in `Sources/UsageCore/Pace/Pace.swift`, using 5 h for the 5-hour window and `WindowResolver.weekSeconds` for 7-day windows (research R4). T007 passes.
  Interfaces: `extension LimitWindow { public func pace(length: TimeInterval, observedAt: Date, now: Date) -> Pace? }`, `extension ModelLimit { public func pace(observedAt: Date, now: Date) -> Pace? }`, `extension CodexLimitWindow { public func pace(observedAt: Date, now: Date) -> Pace? }`, plus `Pace.fiveHourSeconds: TimeInterval = 5 * 60 * 60`.
- [X] T009 [US2] In `Sources/AgentMeter/DropdownView.swift` show a `PaceLine` below each of `WindowRow` (5-hour, 7-day; pass length, `status.fetchedAt` and the snapshot's `generatedAt` from `SubscriptionSection`), `ModelLimitRow` and `CodexWindowRow` (pass `limits.observation?.observedAt` and `now` from `CodexPlanSection`) (FR-008, contracts/pace-display.md). Use `Pace.fiveHourSeconds` and `WindowResolver.weekSeconds` as lengths, and pass `indent:` (the 60 pt title width plus the HStack spacing) to each of these `PaceLine`s so they align with the percent column. Rows without a pace look exactly as before. `make app` builds.

**Checkpoint**: every subscription and plan window shows its pace.

---

## Phase 5: User Story 3 - See a coming run-out without opening the menu (P2)

- [X] T010 [P] [US3] Add tests to `Tests/UsageCoreTests/ConfigurationTests.swift`: a configuration without `showsRunOutMarker` decodes with `true`; `false` decodes as false; encoding and decoding round-trips the value; the default `Configuration()` has `true` (FR-014).
- [X] T011 [US3] Add `showsRunOutMarker: Bool` to `Configuration` in `Sources/UsageCore/Config/Configuration.swift`: stored property with doc comment, init parameter (default `true`), coding key, `decodeIfPresent ?? true` (research R7). T010 passes.
- [X] T012 [US3] Add tests to `Tests/UsageCoreTests/BarLayoutTests.swift` for `BarItem.runOutMarker` (FR-012, FR-013, research R6): spec Story 3 scenario 1 (an entry at 40% with 25% of its window elapsed and thresholds [80] gets `runOutMarker == true`) and scenario 2 (the same pace at the warning level, for example 85% with thresholds [80], gives `false`); a subscription whose 7-day window is ahead with a counting run-out gets the marker, also when its 5-hour window is not ahead; a subscription ahead only on the 5-hour window does not; a Codex plan gets it from its longest effective window only; a group and an own budget get it from their budget pace; a group member's share entry never gets it; no marker when the level is warning or critical, when the item is stale, during the hold back, when on pace, for an empty group, or when `showsRunOutMarker` is false; placeholder items ("…", "--") never get it. Also test `BarItem.accessibilitySuffix`: ", projected to run out before reset" with the marker, empty without (FR-015).
- [X] T013 [US3] In `Sources/UsageCore/Bar/BarLayout.swift` add `runOutMarker: Bool` to `BarItem` (initializer parameter defaulting to `false`) and set it in `subscriptionItem`, `codexItem` and `budgetItem` from the paces of T005 and T008 with `now = snapshot.generatedAt`, gated by `configuration.showsRunOutMarker`, level `.normal` and not stale; `memberItem` leaves it false. Interfaces: `subscriptionItem`, `codexItem` and `budgetItem` each gain a `showsMarker: Bool` parameter (passed `configuration.showsRunOutMarker` from `segments`), and `budgetItem` also gains `now: Date?` (the snapshot's `generatedAt`, nil without a snapshot); add `public var accessibilitySuffix: String` on `BarItem`. T012 passes; all existing `BarLayoutTests` stay green.
- [X] T014 [US3] In `Sources/AgentMeter/BarLabel.swift` append `"↗"` to `valueText` when `runOutMarker` is set, and make `text` (accessibility label and logs) read `"<name> <value>"` plus `accessibilitySuffix` instead of the glyph (FR-012, FR-015). In `Sources/AgentMeter/MenuBarSettingsTab.swift` add `Toggle("Mark entries projected to run out before reset", isOn: $draft.showsRunOutMarker)` below the preview; the preview follows it through `BarLayout.segments` (FR-014). `make app` builds.

**Checkpoint**: the bar marks entries that will run out before their reset, and the toggle removes the marker.

---

## Phase 6: Polish

- [X] T015 [P] Check changed files for em dash and en dash characters and remove any (`rg -n '\x{2014}|\x{2013}' Sources Tests specs/011-pace-forecast README.md`).
- [X] T016 [P] Confirm the README's "Security and privacy" section needs no change (no requests, credentials or files added, FR-016) and update the README: add `↗` to the "What it does" bullet that explains the bar glyphs (`⚠`, `‼`, `~`), mention the dropdown pace line there, and add the new toggle to the Menu Bar tab bullet of the settings list.
- [X] T017 Run `make test` and `make app`; walk through the quickstart.md steps that need no GUI and list the GUI steps for the user.

---

## Dependencies

- Phase 2 (T002, T003) blocks everything.
- US1: T004 then T005 then T006.
- US2: T007 then T008 then T009; T009 reuses `PaceLine` from T006.
- US3: T010 then T011; T012 then T013 (needs T005, T008, T011); T014 needs T011 and T013.
- Polish last.

## Parallel opportunities

T010 (different file) alongside US1 or US2; T015 and T016. T007 and T008 edit the same files as T004 and T005 and follow them.

## Implementation strategy

MVP is Phase 2 plus US1: budgets show whether they will last. US2 extends the same line to subscription and plan windows; US3 adds the bar marker and its toggle.
