# Code Review: Dropdown layout polish

**Spec:** specs/026-dropdown-layout-polish/spec.md
**Date:** 2026-10-19
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 100% (20 of 20 functional requirements, 9 of 9 edge cases)**

- Functional requirements: 20 of 20 compliant (FR-001 to FR-018, FR-009a and FR-010a)
- Edge cases: 9 of 9
- Success criteria: SC-005 and SC-006 covered by tests; SC-001 to SC-004 by the code below and the walkthrough

No `## Constants` section in the spec, so the constants check was skipped. The screenshot recapture of FR-018 is deferred to one round after spec 027 by the maintainer's recorded decision; the capture script change it requires is done.

## Functional requirements

| FR | Implementation | Status |
|---|---|---|
| FR-001 | `BudgetSection` member lines are plain `HStack`s without `BreakdownView`; one `BreakdownView` per group | Compliant |
| FR-002 | `MemberDisplay.make`: no lines below 2 members, otherwise every member with a usage entry, in member order | Compliant |
| FR-003 | `MemberDisplay.tables` (2+ members with a non-empty breakdown); `BreakdownView.memberSection` button "Show accounts"/"Hide accounts", member name, `BreakdownTables` with the day row | Compliant |
| FR-004 | `@AppStorage("showsMemberTables")`, one key for all groups | Compliant |
| FR-005 | group and members share the one `@AppStorage("detailsMode")` `mode` | Compliant |
| FR-006 | subscriptions, Codex and Unassigned call `BreakdownView` without member tables; own budgets pass no members | Compliant |
| FR-007 | `MemberDisplay` in UsageCore with `MemberDisplayTests`; `ScenarioCoverage.memberDisplays`; `DefaultScenarioTests` checks `default` (2 lines, button) and `variants` (one-member group, none) | Compliant |
| FR-008 | `totalLine` and `DetailsTotal` removed; the picker is the first element | Compliant |
| FR-009 | `DayRowTotal.make` (sum, format, "Total" tooltip, incomplete note), `DayRowLayout.sumRowIndex`, Σ cell in `dayTrend` on the last row | Compliant |
| FR-009a | `dayColumnWidth = 30`, `horizontalSpacing: 6`; member tables have no leading padding | Compliant |
| FR-010 | `VStack { ScrollView(sections) ; pinnedFooter }`, panel height = sections + footer | Compliant |
| FR-010a | `FooterLayout.room`, `FooterLayout.cap` (min(640, room), 640 when unknown); `DropdownView.measureScreenRoom` on open, on finding the panel and on `didChangeScreenParametersNotification` | Compliant |
| FR-011 | `FooterErrors.visible` (3 lines, "+N more" with all errors); `FooterLayout.sectionsHeight` with the 160 pt floor, yielding to the screen room | Compliant |
| FR-012 | `statusRow`: refresh icon, status text with "stale", spacer, Settings, Quit; no separate line | Compliant |
| FR-013 | `ViewThatFits` with a fixed and a truncating `Text`, `FooterText.statusTooltip`, accessibility value = pace text | Compliant |
| FR-014 | footer order errors, update line, status row; button labels, identifiers and shortcuts unchanged; no gear menu | Compliant |
| FR-015 | vertical `ScrollView` with `showsIndicators: false`, fixed width 360 | Compliant |
| FR-016 | specs 003, 004, 016, 025 (spec and contract) amended; the review round also amended spec 025 US2-5, US5-3 and spec 007 FR-013 | Compliant |
| FR-017 | `docs/usage.md`, `docs/accounts-and-budgets.md` describe the single budget Details, "Show accounts", Σ and the pinned status row | Compliant |
| FR-018 | `capture.sh` launches with `-showsMemberTables NO`; `test_screenshots.sh` asserts it; recapture deferred by decision | Compliant |

## Edge cases

All nine are handled: no usage entry (no lines, no button), one of two with usage (two lines, no button), three with two using it (two tables in member order), the remembered state (FR-004), many errors (FR-011), 8 local days plus Σ (one row, 318 pt), the capture crops (FR-018), VoiceOver order (sections, then footer; pace text as value), and a short visible screen (FR-010a).

## Extra behavior (not in the spec)

- `CompactFormat.usd` now takes its "<1" and "1K" cut-offs from the whole-dollar value it shows (review fix). This makes the existing FR-009 wording hold at 0.50 and 999.50; no spec change needed.

## Spec evolution candidates

- Screen-aware height cap (Deep Review FINDING-1): adopted as FR-010a after the maintainer's decision.

## Conclusion

The code matches the spec. The one Important production finding (the fixed 640 pt cap on small screens) was fixed after the maintainer chose the screen-aware cap (FR-010a).

## Code Review Guide

Where a human reviewer gets the most out of their time:

1. `Sources/UsageCore/Dropdown/MemberDisplay.swift`: the member line and member table rules (FR-002, FR-003, FR-007) and their tests.
2. `Sources/UsageCore/Dropdown/DayRowTotal.swift` and `CompactFormat.swift`: Σ value, tooltip, row placement and the dollar cut-offs.
3. `Sources/AgentTacho/DropdownView.swift`: the pinned footer layout, the two measured heights and the status row with `ViewThatFits`.
4. `Sources/AgentTacho/BreakdownView.swift`: "Show accounts" and the shared `BreakdownTables`.
5. The walkthrough: tall content with two expanded Details, a long "Last refreshed" on an earlier day, a monthly budget row.

## Deep Review Report

**Gate:** PASS (after fix round 1 of 3; FINDING-1 fixed after the maintainer's decision)
**Details:** specs/026-dropdown-layout-polish/review-findings.md

| Agent | Found | Fixed | Remaining | Status |
|---|---|---|---|---|
| Correctness | 2 | 1 | 1 | completed (1 Notable) |
| Architecture & Idioms | 5 | 2 | 3 | completed (1 Notable) |
| Security | 0 | 0 | 0 | completed |
| Production Readiness | 1 | 1 | 0 | completed (fixed after decision) |
| Test Quality | 4 | 4 | 0 | completed |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR) |
| CodeRabbit (external) | 3 | 2 | 1 | completed |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 0 | 0 | 0 | completed |
| Re-review round 1 (CodeRabbit, Codex) | 0 | 0 | 0 | completed |
| Test Suite (regression) | 0 | 0 | 0 | passed |
| **Total** | **16** | **11** | **5** | |

Severity: 0 Critical, 3 Important (3 fixed), 11 Minor (8 fixed, 3 remaining), 2 Notable.

MVP: Architecture & Idioms (5 findings).

Key fixes applied:

1. `CompactFormat.usd` showed "0" for $0.50 and "1,000" for $999.50 to $999.99; the cut-offs now come from the rounded value, with boundary tests (test quality, confirmed by failing tests first).
2. Test that Σ adds all four token kinds (test quality).
3. FR-011 height formula moved into `FooterLayout.sectionsHeight` in UsageCore with tests (test quality, constitution II).
4. The view shows "Show accounts" from the tested `MemberDisplay.showsAccountsButton` (architecture).
5. Locale test for the compact formats; legend wording for monthly Σ; stale `paceTooltip` comment (test quality, correctness, architecture).
6. Stale wording in spec 025 (US2-5, US5-3) and spec 007 FR-013 (CodeRabbit).

Fixed after the maintainer's decision:

- FINDING-1 (Important, fixed), `Sources/AgentTacho/DropdownView.swift`: the 640 pt cap ignored the screen's visible height, so on a short screen the pinned footer could sit below the screen edge. The maintainer chose option (a): the cap is now min(640, room from the panel's top to the bottom of `screen.visibleFrame` minus 8 pt), recomputed on open and on screen changes (spec 026 FR-010a, `FooterLayout.room`, `FooterLayout.cap`, `ScreenAwareCapTests`).

Remaining Minor: FINDING-5 (day cell format still in the view), FINDING-8 (constant comments), FINDING-13 (spec 020 gear menu wording, out of scope).

Post-fix spec coverage: no code removed; all 20 requirements verified.

Test results after fixes: `make test` 1568 + 64 passed (after FINDING-1), `make test-release` 252 passed, `make app` and `make app-demo` built.
