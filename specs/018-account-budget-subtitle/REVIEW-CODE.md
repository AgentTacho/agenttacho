# Code Review: Account Budget Subtitle

**Spec:** specs/018-account-budget-subtitle/spec.md
**Date:** 2026-10-16
**Reviewer:** Claude (speckit-spex-gates-review-code)

## Compliance Summary

**Overall Score: 100%**

- Functional Requirements: 10/10 (100%)
- Acceptance Scenarios: 8/8 (100%)
- Edge Cases: 5/5 (100%)
- Success Criteria: 4/4 (100%)

## Detailed Review

### Functional Requirements

| Requirement | Implementation | Status |
|-------------|----------------|--------|
| FR-001 provider, middle dot, group icon + name or "own budget", comma, amount | `AccountBudgetDescription.init` (Sources/UsageCore/Config/AccountBudgetDescription.swift:67-94); icon drawn between `visiblePrefix` and `visibleSuffix` in `AccountSettingsView.budgetSubtitleText` | Compliant |
| FR-002 missing group: "Vertex · no group", no amount | `make(for:in:)` maps an unknown group id to `.missingGroup` (AccountBudgetDescription.swift:104-109) | Compliant |
| FR-003 USD, rounded to cents, no decimals when whole, two otherwise, " / month" or " / week", locale formatting | `BudgetAmountFormatter.amount/text` (AccountBudgetDescription.swift:11-22), `NSDecimalRound` `.plain` then `Decimal.FormatStyle.Currency(code: "USD", locale:)` | Compliant |
| FR-004 Groups list "$400 / month, N member(s)" | `GroupListSubtitle.text`, used in `GroupSettingsView` row | Compliant |
| FR-005 subtitles follow the unsaved draft | both subtitles are built from the `@Binding draft` on every render; tests cover provider, membership, group removal, group name/icon/period/amount and own budget edits | Compliant |
| FR-005a one line, tail truncation | `.lineLimit(1).truncationMode(.tail)` on the Accounts subtitle | Compliant |
| FR-006 subscription subtitles unchanged | `subscriptionSubtitle` (exhaustive switch since commit e7f6325) | Compliant |
| FR-007 same icon as the Budget picker, sized to the subtitle | `labelText(iconId, size: caption1 pointSize)`; unknown ids draw "?" exactly as `IconFont.attributed` in the picker | Compliant |
| FR-007a VoiceOver text without the glyph | `.accessibilityLabel(description.accessibilityText)`; strings "<provider>, group <name>, <amount> per <period>", "own budget", "no group" | Compliant |
| FR-008 text logic testable without the UI | all text in UsageCore; the view draws the glyph (and adds the one separating space, see FINDING-5) | Compliant |

### Acceptance Scenarios and Success Criteria

US1 scenarios 1 to 6 and US2 scenarios 1 and 2 map to tests in `Tests/UsageCoreTests/AccountBudgetDescriptionTests.swift`; scenario 5 is covered by `make` returning nil for both subscription kinds plus the unchanged view strings. SC-001 (read from the list alone) follows from FR-001; SC-002, SC-003 and SC-004 are covered by the unit tests.

### Edge Cases

Long group names (tail truncation), unknown icon ids (same "?" fallback as the picker), moving to an own budget keeps the group's period and amount (test `movingToOwnBudgetKeepsTheGroupsAmountAndPeriod`), zero and negative amounts shown as entered, and locale-driven symbol placement with fixed " / month" wording (test `otherLocalesKeepThePeriodWording`, strengthened in this review): all compliant.

### Extra Features (Not in Spec)

None.

## Recommendations

### Critical (Must Fix)

None.

### Spec Evolution Candidates

None.

### Optional Improvements

- Derive the description's view fields instead of storing them (FINDING-5).
- Add `BudgetPeriod.unit` and reuse it (FINDING-6).

## Conclusion

Every requirement, scenario and edge case is implemented and tested, so compliance is 100% and the deep review ran. It found one Important test-quality issue (the de_DE test could not detect an ignored locale) and three Minor issues, all fixed in commit e7f6325. Two Minor refactors and two Notable observations remain.

## Deep Review Report

**Gate: PASS** (after fix round 1). Full details: `specs/018-account-budget-subtitle/review-findings.md`.

| Agent | Found | Fixed | Remaining | Status |
|-------|-------|-------|-----------|--------|
| Correctness | 1 | 1 | 0 | completed |
| Architecture & Idioms | 4 | 1 | 3 (2 Minor, 1 Notable) | completed |
| Security | 0 | 0 | 0 | completed |
| Production Readiness | 0 | 0 | 0 | completed |
| Test Quality | 4 | 3 | 1 (Notable) | completed |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR found) |
| Fix-round re-review (internal) | 0 | 0 | 0 | completed |
| CodeRabbit (external) | 0 | 0 | 0 | completed (rerun with `--committed --base main`; CLI 0.7.6 rejects `--files`) |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 0 | 0 | 0 | completed |
| Test Suite (regression) | 0 | 0 | 0 | passed (1369 tests) |
| **Total** | **9** | **5** | **4** | |

The `default:` switch finding was reported by both Correctness and Architecture and merged into one (8 unique findings, 4 fixed). By severity: 0 Critical, 1 Important (fixed), 5 Minor (3 fixed, 2 remaining), 2 Notable.

MVP: Architecture & Idioms (4 findings; tied with Test Quality, first alphabetically)

Key fixes applied (commit e7f6325):
1. The de_DE test pins German grouping, decimals and symbol placement, so an ignored locale fails it (test-quality).
2. `subscriptionSubtitle` switch is exhaustive again (correctness, architecture).
3. Tests for "$99.50 / month", a fractional own budget's visible and VoiceOver text, "-$5.50" and half-cent rounding of a negative amount (test-quality).

Remaining findings: none Critical or Important. Minor: FINDING-5 (derived stored fields in `AccountBudgetDescription`, AccountBudgetDescription.swift:52-94) and FINDING-6 (`BudgetPeriod` unit wording, AccountBudgetDescription.swift:24-29).

Post-fix spec coverage: 10/10 requirements verified (no implementation code removed).

Notable observations: 2, captured to brainstorm/idea-inbox.md.
