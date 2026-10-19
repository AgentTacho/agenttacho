# Tasks: Dropdown Layout Polish

**Input**: Design documents from `specs/026-dropdown-layout-polish/`

**Prerequisites**: plan.md, spec.md (FR-001 to FR-018, FR-009a), research.md (R1 to R9), data-model.md, contracts/dropdown-ui.md, quickstart.md

**Tests**: Required. Constitution II: every new `UsageCore` or `DemoMode` behavior gets its tests first (Swift Testing, `@Test`, `#expect`), and they must fail before the implementation. Run tests only with `make test` / `make test-release`, build only with `make app` / `make app-demo`.

## Conventions for every task

- Doc comments cite the spec requirements they implement (for example `spec 026 FR-009`).
- No em dash or en dash anywhere (code, comments, JSON, docs, commit messages).
- `Sources/AgentTacho` only renders values from `UsageCore`.
- Fixed test inputs: `Locale(identifier: "en_US")`, UTC calendar.
- Commit at each checkpoint with a Conventional Commit message ending in `Assisted-By: 🤖 Claude Code`.
- Do NOT run `scripts/screenshots/capture.sh`, do NOT push, do NOT touch the site repository.

## Interfaces

```swift
// T003, Sources/UsageCore/Dropdown/CompactFormat.swift
// All members below are public (the app is a separate module), including memberwise inits where the app builds values.
public enum CompactFormat { public static func millions(_ tokens: Int, locale: Locale) -> String; public static func usd(_ value: Decimal, locale: Locale) -> String }
// T005, Sources/UsageCore/Dropdown/DayRowTotal.swift
public struct DayRowTotal: Equatable, Sendable { let text: String; let tooltip: String
    public static func make(days: [DayUsage], showsCost: Bool, incomplete: Bool, locale: Locale) -> DayRowTotal }
public enum DayRowLayout { public static func rows(dayCount: Int, monthly: Bool) -> [Range<Int>]   // weekly: one row; monthly: chunks of 7
                           public static func sumRowIndex(dayCount: Int, monthly: Bool) -> Int }   // Σ goes on the last row
// T007, Sources/UsageCore/Dropdown/MemberDisplay.swift
public struct MemberDisplay: Equatable, Sendable { let lines: [String]; let tables: [String]; var showsAccountsButton: Bool
    static func make(memberIds: [String], usage: [String: TokenAccountEntry]) -> MemberDisplay }
// T009, Sources/UsageCore/Dropdown/FooterText.swift
public struct FooterErrorLine: Equatable, Sendable { let text: String; let tooltip: String }
public enum FooterErrors { public static func visible(_ errors: [SourceError], limit: Int = 3) -> [FooterErrorLine] }
extension FooterText { static func statusTooltip(statusText: String, isTruncated: Bool, paceText: String?) -> String? }
// T016, Sources/DemoMode/ScenarioCoverage.swift: CoverageReport gains memberDisplays: [String: MemberDisplay] (by group name)
```

---

## Phase 1: Setup

- [X] T001 Run `make test` and `make test-release` once to record the baseline; both must pass (stop and report if not).

## Phase 2: Foundational (core values)

- [X] T002 [P] Write failing tests in `Tests/UsageCoreTests/CompactFormatTests.swift` with `Locale(identifier: "en_US")` pinning today's outputs of the app's `UsageFormat.millions` ("0", "<1" below half a million, "188", "1,000") and `UsageFormat.compactUSD` ("<1" for 0.4, "409", "1.6K" for 1,596); assert `usd(0) == "0"`.
- [X] T003 Implement `CompactFormat` in `Sources/UsageCore/Dropdown/CompactFormat.swift` until T002 passes; make `UsageFormat.millions` and `UsageFormat.compactUSD` in `Sources/AgentTacho/DropdownView.swift` call it with `.autoupdatingCurrent`.
- [X] T004 [P] Write failing tests in `Tests/UsageCoreTests/DayRowTotalTests.swift` (spec FR-009): token row sum text and "Total: 188,712,345 tokens" tooltip; cost row "1.6K" text and "Total: $1,596.40" tooltip (nil cost counts 0); empty or all-zero row "0"; incomplete adds "\nincomplete: some usage is unpriced"; all with the en_US locale. Also test `DayRowLayout` for weekly 7 and 8 days (one row, Σ on it) and monthly 28, 30 and 31 days (rows of 7; Σ on the last row, also when it is full).
- [X] T005 Implement `DayRowTotal` and `DayRowLayout` in `Sources/UsageCore/Dropdown/DayRowTotal.swift` until T004 passes.
- [X] T006 [P] Write failing tests in `Tests/UsageCoreTests/MemberDisplayTests.swift` (spec FR-002, FR-003, FR-007, Edge Cases): 0 and 1 member (no lines, no tables); 2 members with usage (2 lines, 2 tables, button); 2 members, 1 with a non-empty breakdown (2 lines, no tables, no button); 3 members, 2 with usage (lines for members with an entry, 2 tables, member order kept); a member without a usage entry has no line.
- [X] T007 Implement `MemberDisplay` in `Sources/UsageCore/Dropdown/MemberDisplay.swift` until T006 passes.
- [X] T008 [P] Write failing tests in `Tests/UsageCoreTests/FooterTextTests.swift` (spec FR-011, FR-013): `FooterErrors.visible` with 0, 3, 4 and 5 errors (4 gives 2 lines plus "+2 more", 5 gives 2 lines plus "+3 more" whose tooltip lists all 5); `statusTooltip` returns nil, the status text, the pace text, or both joined by a newline; remove the `DetailsTotal` tests.
- [X] T009 Implement `FooterErrors`, `FooterErrorLine` and `FooterText.statusTooltip` in `Sources/UsageCore/Dropdown/FooterText.swift`, and remove `DetailsTotal`, until T008 passes.

**Checkpoint**: `make test` passes; commit `feat(core): member display, day row total and footer texts for spec 026`.

## Phase 3: User Story 1 - One Details per budget (P1)

**Independent Test**: quickstart step 1 and 4.

- [X] T010 [US1] In `Sources/AgentTacho/BreakdownView.swift` add `memberTables: [MemberTable] = []` (`struct MemberTable: Identifiable { id, icon, name, breakdown, incomplete }`) and `@AppStorage("showsMemberTables") private var showsMemberTables = false`; when `memberTables` is not empty, render after the group's day row a borderless caption button "Show accounts" / "Hide accounts" toggling it, and when shown each member's header (icon and name, secondary), the table for the current `mode` and its day row, with no extra leading indent (FR-003 to FR-005, FR-009a). Factor the table and day row rendering so group and members share it.
- [X] T011 [US1] In `BudgetSection` (`Sources/AgentTacho/DropdownView.swift`) build `MemberDisplay.make(memberIds: members.map(\.id), usage: snapshot?.tokenAccounts ?? [:])`; render member lines from `display.lines` without their `BreakdownView`; map `display.tables` to `MemberTable`s (each id to its `Account` in `members` for icon and name, and to `snapshot.tokenAccounts[id]` for `breakdown` and `incomplete`) and pass them as `memberTables` to the group's `BreakdownView` (FR-001, FR-002).

**Checkpoint**: `make test` and `make app` pass; commit `feat(dropdown): one Details per budget with Show accounts`.

## Phase 4: User Story 2 - The sum where the days are (P1)

**Independent Test**: quickstart step 2.

- [X] T012 [US2] In `Sources/AgentTacho/BreakdownView.swift` remove `totalLine` and its rendering (FR-008); in `dayTrend` use `minWidth: 30`, use `DayRowLayout` for the rows and append a Σ column (label "Σ" secondary, value semibold, `.help(total.tooltip)`) from `DayRowTotal.make(days:showsCost:incomplete:locale: .autoupdatingCurrent)` on the row `DayRowLayout.sumRowIndex` names (FR-009, FR-009a). Add an `incomplete: Bool` parameter (budgets pass `entry.incomplete`, others false).
- [X] T013 [US2] Remove the `totalLine:` arguments and `DetailsTotal` uses from `SubscriptionSection` and `CodexPlanSection` in `Sources/AgentTacho/DropdownView.swift`; update the Details legend text in `BreakdownView.explanation` to mention the Σ column.

**Checkpoint**: `make test` and `make app` pass; commit `feat(dropdown): sum column at the end of the day row`.

## Phase 5: User Story 3 - A footer that never scrolls away (P1)

**Independent Test**: quickstart step 3.

- [X] T014 [US3] Restructure `body` in `Sources/AgentTacho/DropdownView.swift` per research R5: a `VStack(spacing: 0)` with the sections in `ScrollView(.vertical, showsIndicators: false)` (sections height measured) and the pinned footer (divider plus footer content, height measured) below it; scroll view height `min(sections, max(160, cap - footer))`, panel height `scrollHeight + footer`; move the `.padding(12)` from `content()` into a horizontal padding of 12 pt on both the sections and the footer (plus top padding on the sections and bottom padding on the footer), and move the divider before the footer into the footer; keep `resizePanel`, the dark background and every existing modifier (FR-010, FR-011, FR-015).
- [X] T015 [US3] Rewrite the footer per contracts/dropdown-ui.md: error lines from `FooterErrors.visible` (one line each, `.lineLimit(1)`, tail truncation, `.help(tooltip)`), the update line, then one status row: refresh button, status text (`.lineLimit(1)`, tail truncation, tooltip from `FooterText.statusTooltip`, truncation detected with `ViewThatFits`: first a fixed-size variant whose tooltip has `isTruncated: false`, then a truncated variant with `isTruncated: true`), the "stale" marker, `Spacer`, Settings and Quit buttons with their identifiers and shortcuts; accessibility value of the status is the pace text (FR-012 to FR-014).

**Checkpoint**: `make test` and `make app` pass; commit `feat(dropdown): pinned footer with the status beside refresh`.

## Phase 6: Demo, capture and docs

- [X] T016 Write failing tests in `Tests/DemoModeTests/DefaultScenarioTests.swift`: the `default` report's `memberDisplays["Company budget"]` has 2 lines and the accounts button; the `variants` report's one-member group has no lines and no button; then extend `CoverageReport` and `ScenarioCoverage.evaluate` in `Sources/DemoMode/ScenarioCoverage.swift` with `memberDisplays` built from `MemberDisplay.make` until they pass (FR-007).
- [X] T017 In `scripts/screenshots/capture.sh` add `-showsMemberTables NO` to the demo launch arguments (next to `-demoScenario default`), so the `details` crop never shows member tables left over from a walkthrough; assert it in `scripts/release/tests/test_screenshots.sh`; `make test-release` passes (FR-018).
- [X] T018 [P] Update `docs/usage.md` (Σ column, pinned status row with "Last refreshed" beside the refresh icon) and `docs/accounts-and-budgets.md` (one budget Details, "Show accounts", the week's total as Σ instead of a line) (FR-017).
- [X] T019 [P] Amend in place, citing spec 026 (FR-016): `specs/025-minimal-dropdown/spec.md` (scroll-mode edge case and height-cap assumption, FR-010, FR-014, FR-023, FR-024, FR-025, FR-027) and `specs/025-minimal-dropdown/contracts/dropdown-ui.md`; `specs/016-adaptive-refresh/spec.md` FR-016; `specs/003-monthly-budget-period/spec.md` FR-013; `specs/004-icon-labels-standalone-budgets/spec.md` FR-018a.

## Phase 7: Polish

- [X] T020 Search for leftovers: `rg -n "totalLine|DetailsTotal|This week" Sources Tests docs` returns nothing relevant; `rg -n "[\x{2013}\x{2014}]"` over changed files returns nothing.
- [X] T021 Run `make test`, `make test-release`, `make app`, `make app-demo`; all pass; everything committed.

## Dependencies & Execution Order

- Phase 1, then Phase 2 (T002 to T009) before any story.
- US1 (T010, T011) and US2 (T012, T013) both edit `BreakdownView.swift`: do US1 first, then US2.
- US3 (T014, T015) after Phase 2; independent of US1 and US2 apart from `DropdownView.swift` merges.
- Phase 6 after US1 to US3; Phase 7 last.

## Parallel Opportunities

- T002, T004, T006, T008 (test files) in parallel; T018 and T019 in parallel.

## Implementation Strategy

MVP is Phase 2 plus US1 (the budget Details); US2 and US3 complete the polish; Phase 6 keeps the demo, capture and docs in line.
