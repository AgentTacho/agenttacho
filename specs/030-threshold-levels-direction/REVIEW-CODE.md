# Code Review: Threshold Levels and Budget Direction

**Spec:** specs/030-threshold-levels-direction/spec.md
**Date:** 2026-10-20
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 100% (21 of 21 functional requirements, 17 of 17 edge cases)**

- Functional requirements: 21 of 21 compliant (FR-001 to FR-021)
- Edge cases: 17 of 17
- Acceptance scenarios: US1 1 to 6, US2 1 to 6, US3 1 to 3 and US4 1 to 4 are traced to code and covered by UsageCore tests. US4 3 and 4 (notification timing) got a tracker test during review.
- Success criteria:
  - By tests: SC-001, SC-004, SC-005.
  - By code: SC-002 (row and header percents take the level colors; the bar is unchanged at the default thresholds).
  - In the walkthrough: SC-003.

The spec has no `## Constants` section, so the constants check was skipped.

## Functional requirements

| FR | Implementation | Status |
|---|---|---|
| FR-001 | `LevelThresholds.decide`, used by every bar entry (`BarLayout`), section header (`HeadlineWindow.claudeHeader`/`codexHeader`), row and budget (`RowBar.make`/`budget`) | Compliant |
| FR-002 | `LevelThresholds.init`: lowest positive threshold, then the second lowest; duplicates count; defaults 80 and 100; critical wins | Compliant |
| FR-003 | `decide(atRealLimit:)`: at or above 100%, a reached Codex limit (`codexLevel`), the 7-day window at or above 100% (`subscriptionLevel`) | Compliant |
| FR-004 | `BarItem.overLimit`; `BarPresentation.accessibilityText` says "critical" below a real limit and "over limit" at one; members use the group's thresholds | Compliant |
| FR-005 | `RowBar.percentTone` (rows and budgets, own value and own limit only); `HeadlineHeader.percentTone` with the cross-window rules; member lines unchanged | Compliant |
| FR-006 | `RowBar.tone`: red only at critical; the warning level never colors the bar; attention orange kept | Compliant |
| FR-007 | `ThresholdDisplay.explanation`: both levels, the real limit and empty fields, in both directions | Compliant |
| FR-008 | `Configuration.displayDirection` with a lenient decoder and notes; General tab "Display" section after "Refresh", segmented control and caption | Compliant |
| FR-009 | `DirectedPercent.text`/`accessibilityText` in the bar, headers, rows, budget percent, preview (`segments(configuration: draft)`) and accessibility text | Compliant |
| FR-010 | `DirectedPercent.fill`/`tick`, clamped, from the leading edge | Compliant |
| FR-011 | `RunOutGlyph` in `BarItem.runOutGlyph`, the preview and the Menu Bar tab's toggle label | Compliant |
| FR-012 | `BudgetAmountLine` ("left"/"over" from the rounded percent); U+2212 minus; "over budget" and "over the limit" accessibility words | Compliant |
| FR-013 | Member shares, breakdown, trend, Σ, tokens, costs and pace notes untouched | Compliant |
| FR-014 | Levels decided on the used value; the direction is passed only to presentation | Compliant |
| FR-015 | `ThresholdDisplay` (conversion, validation, caption, placeholders, suffix, further-thresholds note, `replacing`) through the `displayDirection` environment value | Compliant |
| FR-016 | `ThresholdNotificationText.make` with the direction read by `NotificationPresenter` at posting time | Compliant |
| FR-017 | `ThresholdNotificationText.logDescription` in used percent | Compliant |
| FR-018 | All decisions in UsageCore with tests; the SwiftUI layer maps tones to colors | Compliant |
| FR-019 | Amendments in specs 001 (FR-003, FR-027, FR-028), 011 FR-012, 012 (FR-017, FR-018), 017 FR-008, 025 (FR-002, FR-003, FR-007); `docs/usage.md` and `docs/configuration.md` | Compliant |
| FR-020 | `default.json` Side project budget critical below 100 (`thresholdCriticalRows`/`thresholdCriticalEntries`); budget above 100% in `variants.json` (`someScenarioHasABudgetAboveHundred`) | Compliant |
| FR-021 | The plan's "Screenshots and website" section lists the shots, the copy and the no-remaining-shot decision | Compliant |

## Edge cases

All 17 are handled:

- Swapped, equal and single thresholds, more than two thresholds, and a critical threshold above 100 (`LevelThresholds` table test).
- A stored threshold above 100 in the editor ("−20", "(20% over)").
- A direction change while a notification is pending.
- The Codex limit and the full 7-day window.
- Rounding at 99.6%.
- "…" and "--", the stale marker, and a budget without a positive amount.
- The pace tick and pace notes.
- Member entries, the breakdown, the trend and Σ.
- An older configuration file.
- Settings redrawing on a direction change.

## Extra behavior (not in the spec)

- Integer clamping of the remaining value and the threshold conversions (review fix, FINDING-1 and FINDING-2 in review-findings.md). This is defensive and does not change any visible value for realistic data.

## Spec evolution candidates

None. FINDING-5 in review-findings.md (the save banner wording in direction remaining) may become a small spec note if the maintainer wants option (b) or (c).

## Conclusion

The code matches the spec. The deep review found no Critical issue and four Important ones, all fixed in one round:

- two integer-overflow traps reachable from the configuration file or a settings field;
- the real-limit rule repeated in five places;
- a missing SC-004 timing test.

Nine Minor findings were fixed. Two remain: a save-banner wording choice, and a structural duplication in the demo coverage report.

## Code Review Guide

Where a human reviewer gets the most out of their time:

1. `Sources/UsageCore/Bar/LevelThresholds.swift` `decide`, with `BarLayout.subscriptionLevel`/`codexLevel`, `RowBar.make`/`budget` and `LevelThresholdsTests`: the one level rule and where each real limit comes from (FR-001 to FR-006).
2. `Sources/UsageCore/Bar/DirectedPercent.swift`, `Dropdown/BudgetAmountLine.swift` and `Notifications/ThresholdNotificationText.swift`: every remaining-mode number and word (FR-009 to FR-012, FR-016), including the U+2212 minus and the "over" boundary at a rounded 100.
3. `Sources/AgentTacho/SettingsView.swift` `ThresholdsEditor` with `ThresholdDisplay`: the round trip from what is entered to what is stored in direction remaining (FR-015). In the walkthrough, enter 30, switch back to Used, and check that 70 shows.
4. `Sources/AgentTacho/DropdownView.swift`: percent colors in rows, budget headers and section headers; member lines stay uncolored.
5. Demo: `Resources/demo/default.json` (Side project at its second threshold) and `variants.json` (Team budget above 100%), for the recapture of the shots listed in the plan.

## Deep Review Report

**Gate:** PASS (after fix round 1; the re-review found one Minor, fixed)
**Details:** specs/030-threshold-levels-direction/review-findings.md

| Agent | Found | Fixed | Remaining | Status |
|---|---|---|---|---|
| Correctness | 2 | 1 | 1 | completed (FINDING-1 merged into Security's) |
| Architecture & Idioms | 6 | 5 | 1 | completed (+1 Notable) |
| Security | 2 | 2 | 0 | completed (+1 Notable) |
| Production Readiness | 1 | 1 | 0 | completed (+2 Notable) |
| Test Quality | 5 | 5 | 0 | completed (+1 Notable; FINDING-5 merged into Architecture's) |
| Re-review (fix round 1) | 1 | 1 | 0 | completed |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR) |
| CodeRabbit (external) | 0 | 0 | 0 | completed (branch and fix commits) |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 0 | 0 | 0 | completed (branch and fix commits) |
| Test Suite (regression) | 0 | 0 | 0 | passed |
| **Total** | **17** | **15** | **2** | |

Severity after merging duplicates: 0 Critical, 4 Important (all fixed), 11 Minor (9 fixed, 2 remaining), 5 Notable. Four Notables were captured to brainstorm/idea-inbox.md.

MVP: Architecture & Idioms (6 findings).

Key fixes applied:

1. The remaining value and the budget share are clamped, so a tiny budget can no longer crash-loop the app in direction remaining (84f86ee, security).
2. The threshold editor's conversions clamp, and its slot and validity logic moved to `ThresholdDisplay` with tests (45addb3, security, architecture, test quality).
3. One `LevelThresholds.decide` returns the level with `overLimit`. The dead `BarLayout.warningThreshold` and the unused `HeadlineHeader.overLimit` are removed, and doc comments cite FRs (2e25713, architecture, test quality).
4. New tests: SC-004 crossings in both directions and across a switch, plus decode notes (d5df4f1, test quality).
5. A budget's bar is built once per render (a69f117, production readiness).
6. The default threshold test is pinned to the literal 80 (bd40e66, re-review).

Remaining Minor findings (neither blocks):

- FINDING-5: the save banner says "got 0" in used percent for a remaining-mode entry of 100. Needs a human decision; the recommendation is to leave it.
- FINDING-8: the demo coverage report rebuilds the dropdown's row list. Better done as a separate refactor.

Post-fix spec coverage: 21 of 21 requirements verified.

Notable observations: 4 captured to brainstorm/idea-inbox.md (`bar-item-direction-default`, `log-direction-on-settings-save`, `downgrade-drops-global-keys`, `notification-queue-direction-test`).

Test results after fixes: `make test` 1731 + 66 passed, and `make build` is clean.
