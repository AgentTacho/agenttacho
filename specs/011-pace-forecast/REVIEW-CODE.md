# Code Review: Pace Forecast

**Spec:** specs/011-pace-forecast/spec.md
**Date:** 2026-10-15
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 100%**

- Functional Requirements: 17/17 (100%)
- Edge Cases: 13/13 (100%)
- Acceptance Scenarios: 14/14 (100%)
- Success Criteria: 5/5 (SC-001 is a usability outcome, supported by FR-008)

## Detailed Review

### Functional Requirements

| FR | Implementation | Status |
|----|----------------|--------|
| FR-001 expected percent from window start and length | `Pace.compute` (elapsed clamped to the window); adapters: Claude reset minus 5 h / 7 d, model limits 7 d, Codex `lengthMinutes`, budgets `GroupEntry.window` | Compliant |
| FR-002 observation time | `SubscriptionStatus.fetchedAt` (accessors), Codex `observation.observedAt` (`CodexLimitsEntry.pace(of:)`), budgets `snapshot.generatedAt` | Compliant |
| FR-003 rounded delta of unrounded values | `PercentFormatter.rounded(usedPercent - expected)`; budgets use the unrounded spend share | Compliant |
| FR-004 linear run-out, none at 0% | `observedAt + (100 - used) * elapsed / used`, guarded by `used > 0` | Compliant |
| FR-005 only beyond the band and strictly before reset | `.ahead` (delta > 5) and `candidate < resetsAt` | Compliant |
| FR-006 hold back 10% | `share >= holdBackShare` (0.10) for the run-out only | Compliant |
| FR-007 exclusions | no reset, rounded used >= 100, Codex `limitReached`, empty group, `resetsAt <= now`; Codex past-reset windows lose their reset in `effectiveWindows` first | Compliant (see note) |
| FR-008 pace line text | `Pace.summary`, `PaceLine` under 5-hour, 7-day, model limit, Codex window and budget rows | Compliant |
| FR-009 run-out time format | `UsageFormat.runOutText` (time today, otherwise weekday day month time, midnight kept) | Compliant |
| FR-010 colors | `PaceLine`: orange with a run-out, secondary otherwise | Compliant |
| FR-011 no pace on members, budgetless accounts, Unassigned | only `BudgetSection` header rows and window rows render `PaceLine` | Compliant |
| FR-012 marker on the bar window | 7-day for Claude, `barPace` (longest effective window) for Codex, budget pace for groups and own budgets | Compliant |
| FR-013 no marker with glyph, stale, member share | `BarLayout.marker` requires `.normal` and not stale; `memberItem` never sets it | Compliant |
| FR-014 toggle, default on, preview follows | `Configuration.showsRunOutMarker` (`decodeIfPresent ?? true`), Menu Bar tab toggle, preview uses `segments(configuration: draft)`, excluded from `dataRelevant` | Compliant |
| FR-015 accessibility | `BarItem.accessibilitySuffix` in `text`, which feeds `accessibilityLabel` | Compliant |
| FR-016 no requests, credentials or files | pure computation; README "Security and privacy" unchanged | Compliant |
| FR-017 tested core | computation, band, hold back, marker decision and (after review) input selection in UsageCore with tests | Compliant |

Note on FR-007: "a value at or above 100%" is checked on the rounded percent, so 99.5% to 99.9% (shown as 100%) also has no pace. This matches the shown value and the spec's clarification that rules follow the shown numbers.

### Edge Cases

All 13 edge cases are handled: window not started, at or above 100% or reached, empty group, entry without data, 0% usage, early window (delta shown, run-out withheld), window already reset, slightly ahead (on pace, no run-out), stale entries (dropdown pace at observation time, no bar marker), run-out at or after reset, member shares, time passing while open (pace fixed to the observation), configuration without the toggle.

### Extra Features (Not in Spec)

- `Pace.compute` also returns nil for non-finite values and windows of length 0 or less. Defensive, helpful.

### Spec-Declared Constants

The spec has no `## Constants` section. Skipped.

## Recommendations

### Critical (Must Fix)
- None.

### Spec Evolution Candidates
- A run-out that has already passed at the snapshot time (old, non-stale observations such as local-only Codex values) still shows, and the bar marker stays until the reset. Resolved after review: the user chose to add the rule to FR-005 (a run-out at or before the snapshot time does not count), implemented with a test (review-findings FINDING-3).
- Optionally clarify in FR-007 that "at or above 100%" means the shown (rounded) value.

### Optional Improvements
- Derive `PaceLine.windowIndent` from a shared title width and explicit spacing (FINDING-5).
- Decode `showsRunOutMarker` leniently and document it in the README configuration section (FINDING-6).

## Conclusion

The code implements every requirement of the spec. Deep review ran and passed after one fix round, with one spec evolution decision left open.

## Deep Review Report

**Gate: PASS** (after fix round 1). Full details: `specs/011-pace-forecast/review-findings.md`.

| Agent | Found | Fixed | Remaining | Status |
|-------|-------|-------|-----------|--------|
| Correctness | 1 | 0 | 1 (Notable) | completed |
| Architecture & Idioms | 3 | 2 | 1 (Minor) | completed |
| Security | 0 | 0 | 0 | completed |
| Production Readiness | 2 | 0 | 2 (1 Important triaged as spec evolution, 1 Minor) | completed |
| Test Quality | 4 | 4 | 0 | completed |
| Re-review (round 1) | 1 | 1 | 0 | completed |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR found) |
| CodeRabbit (external) | 0 | 0 | 0 | completed (branch and fixes) |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 0 | 0 | 0 | completed (branch and fixes) |
| Test Suite (regression) | 0 | 0 | 0 | passed (728 tests) |
| **Total** | **11** | **7** | **4** | |

By severity: 0 Critical, 3 Important (2 fixed, 1 triaged as a spec evolution candidate), 6 Minor (4 fixed), 2 Notable (1 resolved with a comment).

MVP: Test Quality (4 findings)

Key fixes applied (commit 0a5c949):
1. Pace input selection (window length, observation time, Codex bar window) moved into core accessors used by both the bar and the dropdown (architecture, FR-017).
2. Bar tests where the observation time differs from the snapshot time, for Claude and local-only Codex, in both directions (test quality, FR-002).
3. Boundary tests for the first ahead delta (+6, also from +5.5) and for negative fractional deltas (test quality, FR-003, FR-005).
4. Tests for the new accessors, including a Codex entry without an observation (test quality, re-review).
5. `resetText` delegates to `runOutText`; comment on the run-out guard (architecture).

Remaining findings: none Critical or Important. FINDING-3 (run-out already passed at the snapshot time) was resolved after the review by a user decision: FR-005 now excludes it, Pace.compute drops it, and PaceTests.runOutAtOrBeforeTheSnapshotTimeDoesNotCount covers it.

Post-fix spec coverage: 17/17 requirements verified.

Notable observations: 2 (listed in review-findings.md; to be added to brainstorm/idea-inbox.md by the pipeline).
