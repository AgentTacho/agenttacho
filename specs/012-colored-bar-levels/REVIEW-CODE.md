# Code Review: Colored Bar Levels

**Spec:** specs/012-colored-bar-levels/spec.md
**Date:** 2026-10-16
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 100%**

- Functional Requirements: 21/21 (100%)
- Edge Cases: 10/10 (100%)
- Acceptance Scenarios: 17/17 (100%), automated where they concern presentation decisions; visual checks are walkthrough items
- Success Criteria: SC-001, SC-003, SC-004, SC-005, SC-006 supported by code and tests; SC-002 and SC-007 are manual walkthrough checks by definition

## Detailed Review

### Functional Requirements

| FR | Implementation | Status |
|----|----------------|--------|
| FR-001 level color Text/Pill/Off, Text when absent | `LevelColorStyle`, `Configuration.levelColor` (`decodeLevelColor`, default `.text`) | Compliant |
| FR-002 show level symbols, off when absent | `Configuration.showLevelSymbols` (`decodeIfPresent ?? false`) | Compliant |
| FR-003 old files load unchanged; unknown value falls back to Text, noted in the log, no problem notice; save writes the value in effect | `decodeLevelColor` + `ConfigurationLoadNotes`; `ConfigStore` keeps notes only after decode and validate; `RefreshCoordinator` logs them with source `config`; synthesized encoding writes `"text"` | Compliant |
| FR-004 Menu Bar tab controls, apply immediately, no refresh | `MenuBarSettingsTab.levelSettings` (segmented picker, checkbox) bound to the draft; `dataRelevant()` resets both fields | Compliant |
| FR-005 preview shows the chosen style, rendered as a dark bar | `BarLabelView(preview: true)`: dark appearance (high-contrast variant with nil fallback), white neutral override, same pill rules | Compliant |
| FR-006 threshold help text names no marker | `ThresholdsEditor` text | Compliant |
| FR-007 Text: value (and glyph) orange/red, icon neutral | `BarPresentation.entry` `.text` case; `BarLabelBuilder.color` | Compliant |
| FR-008 Pill: rounded fill covers icon, glyph, stale marker, value; black/white by contrast; pills do not touch; bounded width growth | `Layout` pill ranges + kern on separators + leading/trailing padding; `pillTextColor` via `PillContrast` under the drawing appearance | Compliant |
| FR-009 Off: no color | default branch, neutral tones; `usesColor` false keeps the template image | Compliant |
| FR-010 glyphs only with symbols on, in the previous positions | glyph before stale marker and value, as in the previous `levelValueText` | Compliant |
| FR-011 system orange and red | `.systemOrange` / `.systemRed`, resolved at draw time | Compliant |
| FR-012 Off without symbols valid; note in the tab | `LevelDisplaySettings.hidesLevels`; conditional caption in the tab | Compliant |
| FR-013 neutral parts in the menu bar text color; template when no color | template image when `usesColor` is false; `labelColor` in the full-color path | Compliant (runtime check in walkthrough) |
| FR-014 follows appearance changes | `.id(colorScheme-contrast)` rebuild, `cacheMode = .never`, colors resolved per draw | Compliant (runtime check in walkthrough) |
| FR-015 highlighted state | template path tinted by the system; full-color path resolves per draw | Compliant (runtime check in walkthrough) |
| FR-016 stale marker directly before the value | `valueText = "~" + value`, glyph prepended before it | Compliant |
| FR-017 level computation unchanged | levels come from `BarLayout` untouched | Compliant |
| FR-018 accessibility text names levels, never glyphs | `BarPresentation.accessibilityText`, tested in all six combinations | Compliant |
| FR-019 notifications, thresholds, dropdown unchanged | no changes in those paths | Compliant |
| FR-020 decisions computable without drawing | `BarPresentation`, `PillContrast`, `LevelDisplaySettings` in UsageCore with tests | Compliant |
| FR-021 README and spec 001 note | README Alerts, configuration and Menu Bar paragraphs; spec 001 FR-003 note | Compliant |

### Edge Cases

All 10 are handled. Stale entries at a level keep the full color, and the `~` stays inside the pill. Entries without a percent are never colored. Group members use their group's level, which comes unchanged from `BarLayout`. The highlighted dropdown state is handled per FR-015. Inactive, tinted and accessibility display variants are covered by the template path and by colors resolved per draw. An unknown level color in the file is handled per FR-003. The placeholder is drawn neutral (template). An older version reading a newer file ignores the keys, which is accepted. A Codex entry at a reached limit is over limit (tested). The spec 011 run-out marker stays neutral and is spelled out after the level words (tested).

### Error Handling

Unknown, wrong-case, non-string and null `levelColor` values fall back to Text with one log note. After the review, long values are clipped in that note. A non-boolean `showLevelSymbols` is a decoding error, consistent with `startAtLogin`. Notes are dropped when the file fails validation.

### Extra Features (Not in Spec)

- The `levelColor` value in the log note is clipped to 32 characters (review fix). This is defensive and keeps README's log promises true.

### Spec-Declared Constants

The spec has no `## Constants` section. Skipped.

## Code Quality Notes

The presentation logic is cleanly separated: UsageCore decides tones, glyphs, pills and accessibility text, and the app only maps tones to colors and draws. The decision table test covers all 18 combinations of style, symbols and level, fresh and stale.

## Recommendations

### Critical (Must Fix)
- None.

### Spec Evolution Candidates
- None. The null `levelColor` behavior now matches data-model.md.

### Optional Improvements
- Carry the run-out marker's tone in `BarEntryPresentation` (review-findings FINDING-10).
- Decide on the `showLevelSymbols` / `showsLevelSymbols` key name before release (FINDING-11).
- Walkthrough: verify the full-color image in the menu bar under wallpaper tinting, the highlighted state, a second display and Increase contrast (NOTABLE-3, NOTABLE-4).

## Conclusion

The code implements every requirement of the spec. Deep review passed after two fix rounds. All four Important findings were fixed.

## Deep Review Report

**Gate: PASS** (after fix round 2). Full details: `specs/012-colored-bar-levels/review-findings.md`.

| Agent | Found | Fixed | Remaining | Status |
|-------|-------|-------|-----------|--------|
| Correctness | 1 | 1 | 0 | completed |
| Architecture & Idioms | 7 | 3 | 4 (3 Minor, 1 Notable) | completed |
| Security | 2 | 1 | 1 (Notable) | completed |
| Production Readiness | 1 | 0 | 1 (Notable) | completed |
| Test Quality | 3 | 2 | 1 (Notable) | completed |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR found) |
| CodeRabbit (external) | 0 | 0 | 0 | completed (branch and fixes) |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 2 | 2 | 0 | completed (branch, round 1 and round 2 fixes) |
| Test Suite (regression) | 0 | 0 | 0 | passed (760 tests) |
| **Total** | **16** | **9** | **7** | |

By severity: 0 Critical, 4 Important (all fixed), 8 Minor (5 fixed, 3 accepted), 4 Notable.

MVP: Architecture & Idioms (7 findings)

Key fixes applied (commit 8423ad6):
1. Settings preview appearance: the high-contrast dark appearance is used when Increase contrast is on, with `.darkAqua` as the fallback when AppKit returns nil for the accessibility name (correctness, Codex; FR-005, FR-011).
2. SC-004 is now tested against `systemOrange`/`systemRed` as resolved on the running system. The reference table gained the macOS 26 palette (test quality).
3. An explicit null `levelColor` leaves a log note like any other unreadable value, with a test (Codex, test quality; FR-003).
4. Unknown `levelColor` values are clipped to 32 characters in the log note, with a test (security).
5. The preview follows the builder's template decision (`isTemplate`). Doc comments and FR citations were corrected (architecture).

Remaining findings: none Critical or Important.

Post-fix spec coverage: 21/21 requirements verified.

Notable observations: 4 captured to brainstorm/idea-inbox.md.
