# Code Review: Minimal dropdown

**Spec:** specs/025-minimal-dropdown/spec.md
**Date:** 2026-10-18
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 98% (56 of 57)**

- Functional requirements: 35 of 36 compliant, 1 partial (FR-035)
- Edge cases: 14 of 14
- Success criteria: 7 of 7 compliant or covered by a manual walkthrough step (SC-002)

The screenshot recapture and the website copy of FR-035 are manual release steps outside the code (the capture script and the site repository are not run or touched in this stage). They are open, not code deviations.

## Functional requirements

| FR | Implementation | Status |
|---|---|---|
| FR-001 | `DropdownView.swift` `LimitRowLayout`: name, percent, reset text in one `HStack`, `RowBarView` below at full content width | Compliant |
| FR-002 | `UsageCore/Dropdown/RowBar.swift` `RowBar.make`: fill = used/100 clamped to 0...1, tick = pace expected percent clamped, nil without a reading | Compliant |
| FR-003 | `RowBar.make`: red when the rounded percent is 100+ or the Codex limit is reached, else orange when `PaceReading.callsForAttention`, else neutral; level colors never consulted | Compliant |
| FR-004 | `PaceNote.text` uses `Pace.summary` with the section's `TimeText.runOut`; note set exactly when the tone is attention; `PaceNoteText` renders it in orange | Compliant |
| FR-005 | old `PaceMeter` and `Pace.meterOffset` removed; `RowBarView` has no `.help` | Compliant |
| FR-006 | `LimitRowLayout` and `BudgetBarRow` are one accessibility element each; the label comes from `RowText` (UsageCore, since the review fix round) and includes the pace summary, also without a note | Compliant |
| FR-007 | `LimitRowLayout` percent red when the bar tone is over limit (all window rows); "Limit reached" kept for Codex | Compliant |
| FR-008 | `RowText.window` reads "not started" unless the fetched (Claude) or observed (`CodexLimitsEntry.observedWithReset`) window had a reset; unavailable shows "unavailable" and no bar; no reading means no tick | Compliant |
| FR-009 | `BudgetSection` header with icon, name, bold percent; `BudgetBarRow` amount line with right-aligned reset, bar from `GroupEntry.usedPercent`, note | Compliant |
| FR-010 | `BudgetSection` lists members only when `members.count >= 2`; empty group keeps `SectionNote.emptyGroup` | Compliant |
| FR-011 | `DropdownView.content`: divider before every section but the first, before Unassigned when entries exist, one before the footer | Compliant |
| FR-012 | Subscription, Codex and budget headers keep the bold percent | Compliant |
| FR-013 | `CodexPlanSection`: plan line removed, "ChatGPT <plan> plan" is the name's tooltip | Compliant |
| FR-014 | "Tokens this week" removed; `BreakdownView.totalLine` from `DetailsTotal.weekly` is the first line of the expanded Details for Claude and Codex | Compliant |
| FR-015 | Notes keep their texts and colors through `SectionNote` and `SectionNotesView`; configuration error unchanged | Compliant |
| FR-016 | `Configuration.timeFormat(for:)` (account for subscriptions and own budgets, group for groups); `DropdownView.times(for:now:)` | Compliant |
| FR-017 | `TimeText.relative(from:to:)` | Compliant |
| FR-018 | `TimeText.absolute`: calendar days from `now`, same day, 1 to 6 days, other days long form, midnight reset without time, run-out always with time | Compliant |
| FR-019 | `TimeText.resetTooltip`, `runOutTooltip`, `PaceNote.tooltip`; reset texts and note carry `.help` | Compliant |
| FR-019a | `ModelLimitRow` puts the limit tooltip on the name only (`nameHelp`) | Compliant |
| FR-020 | `DropdownView` passes its `now` to every section and the footer; opening the panel sets it and a task keyed on the open state updates it every 30 s until the panel resigns key; no refresh started | Compliant |
| FR-021 | `Account.timeFormat`, `BudgetGroup.timeFormat` (decoded with default and load note, always encoded); `TimeFormatPicker` "Times" segmented in subscription, Codex, own budget and group editors through the draft; not offered to a group member; value kept | Compliant |
| FR-022 | `timeFormat` read only by the dropdown, Settings and demo coverage; normalized out of the structural comparison | Compliant |
| FR-023 | `DropdownView.footer`: source errors, update line, "Last refreshed", icon row | Compliant |
| FR-024 | `FooterText.lastRefreshed` (time today, date and time otherwise, Refreshing, No successful refresh yet); "stale" marker on the line | Compliant |
| FR-025 | `FooterText.paceTooltip` as `.optionalHelp` and accessibility value of the line; no separate pace line | Compliant |
| FR-026 | Update line still from `UpdateDisplay.lineState`; the dropdown never starts a check, so no transient result reaches it | Compliant |
| FR-027 | `iconRow`: refresh left, Settings and Quit right, `.help` and `.accessibilityLabel` each, ⌘, and ⌘Q on the buttons | Compliant |
| FR-028 | gear menu (`appMenu`) removed; About and "Check for Updates…" only in Settings > About | Compliant |
| FR-029 | `UsageCore/Dropdown/SectionNote.swift` with every listed note and its style; `SectionNoteTests` | Compliant |
| FR-030 | `PaceReading` (pace plus burn rate from one input); `RowBar.make` derives tick, tone and note from it | Compliant |
| FR-031 | `TimeText` takes format, `now`, calendar and locale; never reads the clock | Compliant |
| FR-032 | `RowBar` geometry, tone and note in UsageCore; `RowBarTests` | Compliant |
| FR-033 | specs 004, 007, 011, 013 (spec and update-ui contract), 016, 017, 019, 020, 024 amended | Compliant |
| FR-034 | README: pace text, update line, Settings icon, `timeFormat` reference, Times in Accounts and Groups, footer, Codex lines | Compliant |
| FR-035 | `default.json` stays relative, `variants.json` with absolute times and a single-member group, `DefaultScenarioTests` covers both; `capture.sh` opens Settings with `agenttacho.settingsButton` and cuts the pace shot from the dropdown | Partial: shots not recaptured and website copy not changed in this branch (manual release steps) |

## Edge cases

All 14 edge cases are handled: window without reset ("not started" or no text, no tick), unavailable window (no bar), no pace (no tick, no note), under 10% elapsed (run-out withheld in `Pace`, fast burn still shows), fast burn while on pace or behind ("on pace · burning fast · …"), past times ("now" or the time itself), seven calendar days away (long form, tested), "<1m" and whole units (tested), budget without pace and at 0%, budget at 532% (full red bar, full header percent), group member without its own setting, unknown `timeFormat` (relative, load note, no problem notice, next save writes relative), scroll mode (footer stays last), no accounts (empty text, then footer).

## Success criteria

- SC-001, SC-003, SC-005: met by the layout (one text line per window, "Last refreshed" the only text line under the update line, two Codex lines removed).
- SC-004: Settings and Quit are one click on the icon row.
- SC-006: `TimeTextTests` covers every case with a fixed calendar, time zone, locale and reference time.
- SC-007: `make test` passes (1520 + 63 tests); `ConfigurationTests` loads files without `timeFormat` as relative with no note.
- SC-002: walkthrough on the demo build (manual).

## Extra behavior (not in the spec)

- `Configuration` structural comparison resets `timeFormat`, so a format change alone does not count as a data-affecting change. In line with FR-022.
- `ScenarioCoverage` reports `attentionRows`, `singleMemberGroups` and `absoluteTimeOwners` for the FR-035 coverage tests.
- `UsageSnapshot.paceKeys` replaces the internal `burnWindowKeys` and is public for the coverage report.

All are inside the spec's intent.

## Spec evolution candidates

None. FR-035's open items are release steps, not spec mismatches.

## Conclusion

The code matches the spec. The only open item is the manual recapture of the published screenshots and the website copy (FR-035). Ready for the deep review.

## Code Review Guide

Where a human reviewer gets the most out of their time:

1. `Sources/UsageCore/Dropdown/TimeText.swift`: the relative and absolute forms (FR-017 to FR-019), calendar-day counting and the midnight rules.
2. `Sources/UsageCore/Dropdown/RowBar.swift` and `Sources/UsageCore/Pace/PaceReading.swift`: one pace-and-burn value drives tick, tone and note (FR-030).
3. `Sources/UsageCore/Dropdown/RowText.swift`: reset text, tooltip and accessibility labels of rows (added in the review fix round).
4. `Sources/AgentTacho/DropdownView.swift`: layout B rows, dividers, footer order, icon row, the 30 s time updates while the panel is open (FR-020).
5. `Sources/UsageCore/Config/TimeFormatResolution.swift` and `Configuration.swift`: `timeFormat` decoding and the per-section resolution.
6. `scripts/screenshots/capture.sh`: the pace shot is now a crop, Settings opens with the icon button.

## Deep Review Report

**Gate:** PASS (after fix round 1 of 3)
**Details:** specs/025-minimal-dropdown/review-findings.md

| Agent | Found | Fixed | Remaining | Status |
|---|---|---|---|---|
| Correctness | 1 | 1 | 0 | completed |
| Architecture & Idioms | 8 | 5 | 3 | completed |
| Security | 1 | 0 | 1 | completed |
| Production Readiness | 2 | 1 | 1 | completed |
| Test Quality | 7 | 3 | 4 | completed (1 Notable) |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR) |
| CodeRabbit (external) | 1 | 1 | 0 | completed |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 0 | 0 | 0 | completed |
| Re-review round 1 | 2 | 1 | 1 | completed |
| Test Suite (regression) | 0 | 0 | 0 | passed |
| **Total** | **22** | **12** | **10** | |

Severity: 0 Critical, 1 Important (fixed), 20 Minor (11 fixed, 9 remaining), 1 Notable. Four Minor findings were fixed in a second round after the user's decision (FINDING-9, FINDING-10, FINDING-14, FINDING-17).

MVP: Architecture & Idioms (8 findings).

Key fixes applied:

1. Row reset text, tooltip and accessibility labels moved from the view into tested core logic (`RowText`, `CodexLimitsEntry.observedWithReset`), constitution II (architecture).
2. `absoluteTimeOwners` counts only the time format that takes effect, with a test (correctness, re-review).
3. Tests for midnight resets on the same and an earlier day, the spring clock change and the tick clamp (test quality).
4. Stale gear menu section in the spec 013 update UI contract and stale comments on the pace text and the update line (CodeRabbit, architecture).

Findings that needed judgment (all Minor), fixed after the user chose to fix all four:

- FINDING-9, fixed: `CheckOrigin.dropdown`, `showsResultOnLine` and the dropdown join rule were removed with their spec 013 tests; the failed install reported by the previous run still shows on the line until the dropdown closes. Spec 013 FR-003 and contracts/update-ui.md amended citing spec 025 (commit f6ca65e).
- FINDING-10, fixed: the 30 s time updates run only while the panel is open, from a task keyed on the panel's key state; opening sets the time at once (commit 6abaf90).
- FINDING-14, fixed: `RowBar` keeps its pace reading once and derives tick, tone, note and accessibility summary; only `RowBar.make` and `RowBar.budget` build one (commit b943ada).
- FINDING-17, fixed: `RowBar.budget` turns the bar red from the header's rounded percent, with tests for 99.5% and 99.4% (commit a08aab8).

The other 9 remaining Minor findings are listed in review-findings.md.

Post-fix spec coverage: all requirements verified; FR-035's screenshot recapture and website copy stay open as manual release steps.

Test results after fixes: `make test` 1531 + 64 passed, `make app` and `make app-demo` built, `make test-release` 252 passed. After the second round: `make test` 1530 + 64 passed (five dropdown-origin tests removed, four RowBar tests added), `make test-release` 252 passed, `make app` and `make app-demo` built.
