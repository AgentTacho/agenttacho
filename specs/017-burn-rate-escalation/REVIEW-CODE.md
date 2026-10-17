# Code Review: Burn Rate Escalation

**Spec:** specs/017-burn-rate-escalation/spec.md
**Date:** 2026-10-16
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 100%**

- Functional Requirements: 15/15 (100%)
- Success Criteria: 5/5 (100%)
- Edge Cases: 12/12 (100%)
- Spec-declared constants: none (no `## Constants` section)

## Detailed Review

### Functional Requirements

| FR | Implementation | Status |
|----|----------------|--------|
| FR-001 sustainable rate at the observation time | `BurnRate.compute` (`Sources/UsageCore/Pace/BurnRate.swift`): `(100 - used) / hours(resetsAt - observedAt)`; nil when the observation is at or after the reset | Compliant |
| FR-002 average rate, linear model of spec 011 | `BurnRate.compute`: `used / hours(observedAt - windowStart)`, nil without elapsed time | Compliant |
| FR-003 in-memory observation log | `ObservationLog.updated(with:budgetPricesChanged:)`: adds only later observations, drops `< now - 60 min` (exactly 60 min kept), discards on a reset moved by 60 s or more, a lower percent, a changed `BudgetFingerprint` (amount, period, sorted members) or changed prices (`RefreshCoordinator.requestReprice`, override diff in `performRefresh`); keys without a pace are not carried over; the preliminary snapshot from saved values feeds the log; nothing is encoded (`UsageSnapshot` is not `Codable`) | Compliant |
| FR-004 recent rate | `ObservationLog.recentRate(for:now:)`: oldest and newest within `[now - 60 min, ...]`, span >= 15 min, change >= 2 points | Compliant |
| FR-005 k = 2 | `BurnRate.factor = 2.0`, `>=` comparisons for both rates | Compliant |
| FR-006 which rate qualifies | average only with `pace.runOut` (spec 011's counted run-out, hold back respected); recent whenever it exists, on pace, behind or inside the hold back | Compliant |
| FR-007 fast run-out | average: spec 011's linear run-out (same formula); recent: newest observation + remaining / rate; `runOuts.min()`; run-outs at or before `now` are dropped | Compliant |
| FR-008 "↑" instead of "↗" on the bar value's window | `BarLayout.markers` with the 7-day key (Claude), `CodexLimitsEntry.barWindow` (Codex), `.group(id)` or `.accountBudget(id)` (budgets, after the deep review fix); `BarPresentation` emits one of the two glyphs | Compliant |
| FR-009 suppression like "↗" | `markers` guard: enabled, `.normal` level, not stale, has a pace; member shares use `memberItem` without markers | Compliant |
| FR-010 toggle label and preview | `MenuBarSettingsTab` label "Show ↗ or ↑ when an entry will run out before it resets", same `showsRunOutMarker` key; preview uses `BarLayout.segments` with the live snapshot (observations attached) | Compliant |
| FR-011 accessibility phrase | `BarItem.accessibilitySuffix`: ", burning fast, projected to run out well before reset" | Compliant |
| FR-012 dropdown pace text and color | `Pace.summary(runOutText:fastRunOut:)`, `Pace.usesAttentionColor(burn:)`, `PaceMeter(burn:)` on Claude 5-hour, 7-day, model limit, Codex window and budget rows, independent of the toggle | Compliant |
| FR-013 no requests, files or notifications | log lives in the `RefreshCoordinator` actor and on the snapshot only; README security section untouched; `observationsWriteNothing` test | Compliant |
| FR-014 README | markers paragraph and Menu Bar tab entry describe "↑" and the new label | Compliant |
| FR-015 tested core | all rules in `UsageCore` (`BurnRate`, `ObservationLog`, `BarLayout`, `BarPresentation`, `Pace`); `Sources/AgentTacho` only passes `burnRate(for:)` to `PaceMeter` | Compliant |

### Success Criteria

| SC | Evidence | Status |
|----|----------|--------|
| SC-001 burst shows "↑" at that refresh | `RefreshCoordinatorTests.burstShowsUpArrowOnTheSecondRefresh`, `BarLayoutTests.burstShowsUpArrowForEveryKind` | Compliant |
| SC-002 hand calculation within one minute per kind | `BurnRateTests.handCalculatedFastRunOutPerKind` (5-hour, 7-day, model, Codex, weekly and monthly budget) | Compliant |
| SC-003 single whole-percent step never qualifies | `minimumChange = 2`, `ObservationLogTests.storyOneScenarioTwo` | Compliant |
| SC-004 toggle off equals the pre-011 bar | `markers` returns `(false, false)` when disabled; `BarLayoutTests.toggleOffRemovesBothMarkers` | Compliant |
| SC-005 zero requests and files | no new I/O in the diff; `observationsWriteNothing` | Compliant |

### Edge Cases

All 12 edge cases map to code paths with tests: right after launch (`savedValuesCountAsTheFirstObservation`), same observation repeated (`appendsOnlyLaterObservations`, `codexSourcesShareOneList`), window reset (`changedResetDiscardsEarlierObservations`, `lowerPercentDiscardsEarlierObservations`), budget amount, members or prices edited (`budgetChangesDiscardBudgetObservations`, `priceChangeDiscardsBudgetsOnly`, the reprice coordinator tests), quiet after a burst (`quietCodexExpires`), single step (`storyOneScenarioTwo`), rate falls (`burnsFastFollowsTheFastRunOut`), early in the window (`recentQualifiesOnPaceAndInsideTheHoldBack`), no pace (`claudeWithoutPaceHasNoBurnRate`, `budgetWithoutPaceHasNoBurnRate`, `keysWithoutPaceAreRemoved`), suppression (`suppressedLikeTheRunOutMarker`, `recentBurstFollowsTheSuppressionRules`), fast run-out already passed (`recentRunOutAtOrBeforeTheSnapshotDoesNotQualify`, `averageRunOutAtOrBeforeTheSnapshotDoesNotQualify`), slow refresh (no recent rate with one observation in the lookback, `storyOneScenarioFourMinimumSpan`).

### Extra Features (Not in Spec)

- `ObservationLog.resetTolerance` (60 s): reset times that differ by less than a minute count as the same reset, because Codex reports raw epochs that differ by seconds between a live result and a session log. Helpful; it refines "a changed reset time" of FR-003 and is documented in research R4.
- `ObservationLog.futureTolerance` (10 min): observations more than 10 minutes after the snapshot time are dropped after a backward clock step, so the log cannot freeze. Helpful robustness; not a behavior change for a monotonic clock.
- A stale budget adds no observation (carried-over values with a fresh snapshot time) but a moved window still discards. Consistent with FR-003's "observation time" (a stale budget has no new observation).

## Recommendations

### Critical (Must Fix)
- None.

### Spec Evolution Candidates
- FR-003 could mention the 60-second reset tolerance and the backward clock step handling, both currently documented only in research.md and code comments.
- FR-003 lists amount, period, members and prices as budget discard triggers; other configuration edits that change a budget's spend (log directories, Codex homes, OpenCode directories, attribution) are not listed (deep review NOTABLE-1).

### Optional Improvements
- See the Deep Review Report below for remaining Minor findings.

## Conclusion

Every functional requirement, success criterion and edge case is implemented in `UsageCore` and covered by tests; the app layer only renders `burnRate(for:)`. Compliance is 100%, so the deep review ran. It found one Important issue (a group and an own budget sharing an id shared one burn-rate key), fixed in commit 74e8948; compliance stays at 100% after the fix.

## Deep Review Report

**Gate: PASS** (after fix round 1). Full details: `specs/017-burn-rate-escalation/review-findings.md`.

| Agent | Found | Fixed | Remaining | Status |
|-------|-------|-------|-----------|--------|
| Correctness | 1 | 0 | 1 (Notable) | completed |
| Architecture & Idioms | 6 | 1 | 5 (4 Minor, 1 Notable) | completed |
| Security | 0 | 0 | 0 | completed |
| Production Readiness | 1 | 0 | 1 (Minor) | completed |
| Test Quality | 3 | 0 | 3 (Minor) | completed |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR found) |
| Fix-round re-review (internal) | 2 | 2 | 0 | completed |
| CodeRabbit (external) | 0 | 0 | 0 | failed (rate limit exceeded on both attempts in this pass; first pass: 0 findings) |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 1 | 1 | 0 | completed (branch: 1 P2; re-review of the fix: 0) |
| Test Suite (regression) | 0 | 0 | 0 | passed (1031 tests) |
| **Total** | **14** | **4** | **10** | |

By severity: 0 Critical, 1 Important (1 fixed), 11 Minor (3 fixed, 8 remaining), 2 Notable.

MVP: Architecture & Idioms (6 findings)

Key fixes applied (commit 74e8948):
1. Budget burn keys qualified by owner kind: `BurnWindowKey.group` and `.accountBudget` replace `.budget`, with `UsageSnapshot.budgetEntry(for:)`, fingerprints per key, and the owner kind passed from the bar and the dropdown; tests at snapshot, log and bar level (codex).
2. `BurnRate.secondsPerHour` shared with `ObservationLog.recentRate` (architecture).
3. research.md R2 and data-model.md describe the two budget key cases (fix-round re-review).

Remaining findings: none Critical or Important. Minor: FINDING-5 to FINDING-12 (marker enum, initializer cleanup, `CodexPlanSection` parameters, override flag side channel, burn-state log lines, three test refinements).

Post-fix spec coverage: 15/15 requirements verified.

Notable observations: 2, captured to brainstorm/idea-inbox.md.

### Review history

1. First pass (before this report): deep review and fix loop with commits 2757ff1 (discard budget observations when a reprice lands mid-refresh, which removed a transient false "↑"), a64af21 (single `PaceInputs` source for pace and burn rate, average-rate fast run-out reuses spec 011's run-out, `CodexLimitsEntry.barWindow`, future observations dropped after a backward clock step, `Pace.usesAttentionColor` in the core, observation log types internal, SC-002 hand-calculation and recent-rate bar tests) and 43f5237 (tightened tests after re-review). CodeRabbit reported 0 findings; a Codex P1 asking to make the burn-rate types public again was rejected as a false positive, since the types are new on this branch and nothing released depends on them.
2. This pass: spec compliance 100%, five internal agents, Codex and a CodeRabbit attempt (rate limited), fix round 1 (commit 74e8948), re-review by an internal agent and Codex with no Critical or Important findings.
