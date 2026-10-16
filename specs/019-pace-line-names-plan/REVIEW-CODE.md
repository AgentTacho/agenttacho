# Code Review: Pace Line Names the Plan

**Spec:** specs/019-pace-line-names-plan/spec.md
**Date:** 2026-10-16
**Reviewer:** Claude (speckit-spex-gates-review-code)

## Compliance Summary

**Overall Score: 100%**

- Functional Requirements: 7/7 (100%)
- Acceptance Scenarios: 7/7 (100%)
- Edge Cases: 5/5 (100%)
- Success Criteria: 2/2 (100%)

## Detailed Review

### Functional Requirements

| Requirement | Implementation | Status |
|-------------|----------------|--------|
| FR-001 one slowed plan: "<Plan> limits next checked at <time> (no <Agent> activity)" | `RefreshPaceStatus.text` (Sources/UsageCore/Snapshot/RefreshPaceStatus.swift:46-52), `PacedEndpoint.planName` and `agentName` (AdaptivePace.swift:30-48; `agentName` comes from `Harness.displayName`) | Compliant |
| FR-002 both slowed: "Claude and Codex ..." (no agent activity), the earlier time, always Claude then Codex | `status(now:)` sets `plans` to `PacedEndpoint.allCases.filter { stretched.contains($0) }`, so the declared order is fixed, and the time is `stretched.map(nextCall).min()` (AdaptivePace.swift:409-412) | Compliant |
| FR-003 timer reasons keep today's wording | timer-reason statuses carry no plans (AdaptivePace.swift:403-407), and `text` names plans only for `.noAgentActivity` | Compliant |
| FR-004 visibility, ranking and time unchanged | the only change to `status(now:)` is the new `plans` argument | Compliant |
| FR-005 logic outside the UI, accessibility text is the same string | the text is built in UsageCore; DropdownView.swift:159 renders a plain `Text` with no label override, so SwiftUI reads the same string | Compliant |
| FR-006 time formatting unchanged | the `Date.FormatStyle` code is unchanged; tests cover the weekday and the 12-hour time | Compliant |
| FR-007 wraps, never truncated | `.lineLimit(1)` is replaced by `.fixedSize(horizontal: false, vertical: true)` inside the 360 pt content frame, the same pattern as the error lines. Panel height follows the content height (DropdownView.swift:27-62) | Compliant |

### Acceptance Scenarios and Success Criteria

| Scenario | Test |
|---|---|
| 1. Only Codex slowed | `onlyCodexSlowedNamesCodex` |
| 2. Only Claude slowed | `l2NoAgentActivity` |
| 3. Both slowed, Claude due first | `bothSlowedClaudeDueFirst` (added in this review); Codex-first order in `bothSlowedNameClaudeThenCodex` |
| 4. Timer reason, a plan in use | `timerReasonKeepsTodaysWording` (away, Low Power Mode, high temperature; added in this review), `timerReasonNamesNoPlan`, `l3...` |
| 5. Timer reason, no plan in use | `timerReasonKeepsTodaysWording`, `l4NoEndpointInUse` |
| 6. Every pace at the base | `l1NoLineWhileEveryPaceIsAtTheBase` |
| 7. Another day | `bothPlansOnAnotherDay`, `bothPlansTwelveHour`, `l5...` |
| SC-001 | covered by the tests above |
| SC-002 | `claudeActivityLeavesOnlyCodexNamed` (added in this review) |

### Edge Cases

| Edge case | Coverage | Status |
|---|---|---|
| Only one plan in use | `planNotInUseIsNotNamed` (text assertion added) | Compliant |
| One plan at the base, the other slowed | `onlyCodexSlowedNamesCodex`, `l2NoAgentActivity` | Compliant |
| OpenCode not named | `agentName` names only the main agent | Compliant |
| 12 or 24 hour time, weekday | `bothPlansTwelveHour`, `bothPlansOnAnotherDay` | Compliant |
| Old wording kept until the next refresh | `claudeActivityLeavesOnlyCodexNamed` | Compliant |

### Extra Features (Not in Spec)

None. The spec 016 FR-016 note and contract row L2 were updated, as the spec's Assumptions require.

## Recommendations

### Critical (Must Fix)

None.

### Spec Evolution Candidates

None.

### Optional Improvements

- Remove the `plans` default in `RefreshPaceStatus.init` (FINDING-6, Minor).

## Conclusion

Every requirement, scenario and edge case is implemented, so the deep review ran. It found 2 Important issues, both test gaps (the timer-reason grid of SC-001 and the SC-002 transition), plus 3 Minor test gaps. All 5 are fixed with new tests. One Minor architecture finding and three Notable observations remain.

## Deep Review Report

**Gate: PASS** (after fix round 1). Full details: `specs/019-pace-line-names-plan/review-findings.md`.

| Agent | Found | Fixed | Remaining | Status |
|-------|-------|-------|-----------|--------|
| Correctness | 0 | 0 | 0 | completed |
| Architecture & Idioms | 2 | 0 | 2 (1 Minor, 1 Notable) | completed |
| Security | 0 | 0 | 0 | completed |
| Production Readiness | 0 | 0 | 0 | completed |
| Test Quality | 7 | 5 | 2 (Notable) | completed |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR found) |
| CodeRabbit (external) | 0 | 0 | 0 | completed (`--committed --base main`, because CLI 0.7.6 rejects `--files`; fix round `--uncommitted`: 0) |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 0 | 0 | 0 | completed |
| Test Suite (regression) | 0 | 0 | 0 | passed (1380 tests) |
| **Total** | **9** | **5** | **4** | |

By severity: 0 Critical, 2 Important (both fixed), 4 Minor (3 fixed, 1 remaining), 3 Notable.

MVP: Test Quality (7 findings)

Key fixes applied (test-only, Tests/UsageCoreTests/RefreshPaceStatusTests.swift):
1. A parameterized timer-reason test checks the wording of away, Low Power Mode and high temperature, each with and without a plan in use (test-quality).
2. The SC-002 transition test: both plans slowed, then Claude Code activity, then only Codex named (test-quality).
3. A mirror test for both plans slowed with Claude due first (scenario 3) (test-quality).
4. A guard test: a timer reason keeps "Plan limits" even when the status carries plans (test-quality).
5. A text assertion for a single plan in use (test-quality).

Remaining findings: none Critical or Important. Minor: FINDING-6, the `plans = []` default in `RefreshPaceStatus.init` (RefreshPaceStatus.swift:23).

Post-fix spec coverage: 7/7 requirements verified (no implementation code removed).

Notable observations: 3, captured to brainstorm/idea-inbox.md.
