# Code Review: Adaptive Refresh

**Spec:** specs/016-adaptive-refresh/spec.md
**Date:** 2026-10-16
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 100%** (after commit 0d18ecd; 95% before it, with two minor deviations)

- Functional Requirements: 22/22 (100%), FR-001 to FR-020 with FR-003a and FR-010a
- Edge Cases: 15/15 (100%)
- Acceptance Scenarios: 16/16 covered. US2-4 is covered by the unchanged local scan path but has no dedicated test (review-findings FINDING-20). The app-layer hooks (`onAppear`, system condition reads) are walkthrough items.
- Success Criteria: SC-001, SC-002, SC-004, SC-005 are supported by code and tests. SC-003 and SC-006 are checked by code reading and in the walkthrough.

## Detailed Review

### Functional Requirements

| FR | Implementation | Status |
|----|----------------|--------|
| FR-001 toggle next to the interval, on by default, non-boolean behaves as on with a log note | `Configuration.adaptiveRefresh`, `decodeAdaptiveRefresh`; `GeneralSettingsTab` toggle under the interval | Compliant |
| FR-002 toggle off: fixed timer, no open refresh | `AdaptivePace.enabled` gates every decision; `AppModel.runFixedTimer`; `dropdownOpened` guard; `idleReturn` returns `.none` | Compliant |
| FR-003 base is the fastest pace, cap 30 min unless the base is longer | `AdaptivePace.bound`, `timerInterval`, doubling `min(2x, bound)` | Compliant |
| FR-003a endpoints in use, one Codex pace, last refresh of any trigger | `PacedEndpoint.isInUse`, `recordPacedCalls` aggregation, `refreshCompleted` | Compliant |
| FR-004 activity per endpoint by harness and timestamp, OpenCode for both | `PacedEndpoint.harnesses`, `newestActivity`, comparison with the last call | Compliant |
| FR-005 doubling on quiet scheduled calls, base on activity, only answered calls count | `recordCall`; `reachedService` set by both sources (transport and 5xx excluded) | Compliant |
| FR-006 call only when due or activity plus timer interval; scan first; 5 s tolerance | `shouldCall`; record sources collected before endpoint sources; `tickTolerance` | Compliant (tolerance also on the activity branch, see FINDING-8) |
| FR-007 paced reuse not stale | reprice path with reused entries, `pacedReuseIsNotStale` | Compliant |
| FR-008 idle: 30 min | `timerInterval`, `SystemConditionsMonitor` (input 10 min, lock, display sleep, unlock counts as input) | Compliant |
| FR-009 Low Power Mode or serious/critical thermal: twice the base, capped | `timerInterval` | Compliant |
| FR-010 longest applies; back to base from the last refresh | `timerInterval`, `nextScheduledRefresh`, re-arm on `setConditions` | Compliant |
| FR-010a due time and next scheduled refresh | `dueAt`, `nextScheduledRefresh` (handled by scheduled refresh or try) | Compliant |
| FR-011 return from idle refreshes within 60 s, spaced, not after a wake | `AdaptivePace.idleReturn`, `RefreshCoordinator.setConditions`, `.idleReturn` spacing in `EndpointPolicy` and the Codex gate | Compliant |
| FR-012 dropdown open refresh, per endpoint 60 s, never in a block | `shouldRefreshOnOpen` (last try), `refreshOnOpenIfDue`, `.dropdownOpen` spacing | Compliant (a try counts like a call, see FINDING-2) |
| FR-013 unscheduled calls count as last call, never double, carry activity | `recordCall(scheduled:)`, `recordTry` | Compliant |
| FR-014 launch, wake, manual, settings, retries unchanged | the pace applies to `.scheduled` only; merged runs are exempt; failed tries handle the due time | Compliant |
| FR-015 notifications follow refreshes | `ThresholdTracker` unchanged in `apply` | Compliant |
| FR-016 one pace line, reason ranking, time | `AdaptivePace.status`, `RefreshPaceStatus.text`, `DropdownView` | Compliant |
| FR-017 log timer and endpoint interval changes and paced reuse | `logTimer` (conditions and configuration), `recordPacedCalls`, reuse lines | Compliant |
| FR-018 README Configuration and Security and privacy | General tab paragraph, request frequency bullet, system state row | Compliant |
| FR-019 decisions in the tested core | `AdaptivePace` as a plain value; the app only reads conditions, runs the timer and renders | Compliant |
| FR-020 no new hosts, credential reads, files or prompts | permission-free APIs; the open spacing by try reduces credential reads | Compliant |

### Edge Cases

All 15 are handled:
- **Launch:** paces start at the base.
- **Wake, manual and settings:** they count as calls and never double the interval.
- **Rate-limit blocks win:** a block always stops the call.
- **Retries keep their timing:** the merged-run exemption covers them.
- **Several conditions at once:** the longest interval applies.
- **Base of 30 minutes or more:** no stretching, tested at exactly 1800.
- **1-minute base:** the interval goes 1, 2, 4, 8, 16, 30.
- **Usage elsewhere:** bounded by the 30-minute cap and the open refresh.
- **No endpoints in use:** only the timer conditions apply.
- **OpenCode and Unassigned records:** both count as activity.
- **Refresh already running:** opening the dropdown starts no refresh.
- **Dropdown kept open:** `onAppear` fires once per opening.
- **Clock moved backwards:** `normalize`, now tested in the coordinator.
- **Toggle switched while slowed:** handled in both directions.

### Error Handling

- **Transport failures and HTTP 5xx:** they do not count as calls. They count as tries for scheduling and the open spacing.
- **Expired or missing sign-ins:** they make no request and count as tries.
- **Non-boolean `adaptiveRefresh` value:** it behaves as on and leaves a log note.

### Extra Features (Not in Spec)

- The coordinator logs "pace: scheduled run merged with an earlier request, pace not applied". This is diagnostic support for FR-014.

### Spec-Declared Constants

The spec has no `## Constants` section. Skipped.

## Code Quality Notes

The pace logic is a plain value with no clock of its own, and it has a dense test table. The coordinator glue grew during the review: the merged-run flags and the try accounting. It is still covered by coordinator tests for each path.

## Recommendations

### Critical (Must Fix)
- None.

### Spec Evolution Candidates
- FR-006: state that the 5 s tick tolerance also applies to "at least the timer interval has passed" (FINDING-8).
- FR-012: "the last call or try of any usage endpoint", so an expired sign-in is not read on every opening (FINDING-2).

### Optional Improvements
- Run the scan and the network sources concurrently for non-scheduled triggers (FINDING-18).
- Accurate Codex paced-reuse log line (FINDING-12). Per-endpoint retry merge (FINDING-28).
- Tests for US2-4 and multi-account FR-003a aggregation (FINDING-20, FINDING-23).
- Walkthrough: `onAppear` fires on every opening of the menu bar window; unlock with Touch ID ends idle; Low Power Mode and thermal transitions are logged.

## Conclusion

The code implements every requirement of the spec. Deep review passed after three fix rounds. All 11 Important findings are resolved: 10 fixed with tests, and 1 is a by-design tolerance reclassified as Minor, with a spec clarification candidate.

## Deep Review Report

**Gate: PASS** (after fix round 3). Full details: `specs/016-adaptive-refresh/review-findings.md`.

| Agent | Found | Fixed | Remaining | Status |
|-------|-------|-------|-----------|--------|
| Correctness | 3 | 2 | 1 (Minor) | completed |
| Architecture & Idioms | 8 | 3 | 5 (3 Minor, 2 Notable) | completed |
| Security | 4 | 1 | 2 Notable (1 merged into FINDING-2) | completed |
| Production Readiness | 5 | 1 | 3 (1 Minor, 2 Notable) (1 merged into FINDING-2) | completed |
| Test Quality | 9 | 4 | 4 (3 Minor, 1 Notable) (1 merged into FINDING-4) | completed |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR found) |
| Fix-round re-review agents | 7 | 6 | 1 (Minor) | completed (rounds 1, 2, 3) |
| CodeRabbit (external) | 0 | 0 | 0 | completed (branch, rounds 1, 2, 3) |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 3 | 2 | 1 (reclassified Minor) | completed (branch, round 1); round 2 failed (usage limit) |
| Test Suite (regression) | 0 | 0 | 0 | passed (978 tests) |
| **Total** | **39 (35 after dedup)** | **18** | **17** | |

By severity after dedup: 0 Critical, 11 Important (10 fixed, 1 reclassified), 17 Minor (8 fixed), 7 Notable.

MVP: Test Quality (9 findings)

Key fixes applied (commits 0d18ecd, 9abafb0):
1. **Failed wake or return-from-idle call:** it no longer pulls a scheduled call to "now" and so no longer uses up the quick retry. Per-endpoint `lastTriedAt` handles the due time (production; FR-014).
2. **Dropdown open:** it waits a minute after a try, so an expired sign-in is not read on every opening (correctness, production, security; FR-012, FR-020).
3. **Merged scheduled runs:** they no longer cancel a manual, wake, retry or quick retry call. The 60 s spacing still holds for spaced triggers, and retries are never paced (correctness and re-reviews; FR-011, FR-012, FR-014).
4. **Return-from-idle decision:** it moved into the core with tests (architecture; FR-011, FR-019).
5. **Timer changes on the configuration path:** they are logged, both toggle on while idle and toggle off while slowed (architecture, Codex; FR-017).
6. **Base change:** it is logged (FR-017), and the README 30-minute bound names the longer-base exception (FR-018).
7. **Unlock:** it counts as input, so a Touch ID or Apple Watch unlock ends idle (Codex; FR-011).
8. **Settings caption:** it now says "still at least every 30 minutes".
9. **README security section:** it lists the system state reads and the idle notes in the log (security).
10. **New tests:** clock moved backwards (coordinator), base of exactly 30 minutes, a tightened clock assertion, and Codex `attempted` (test quality).

Remaining findings: none Critical or Important.

Post-fix spec coverage: 22/22 requirements verified.

Notable observations: 7 captured to brainstorm/idea-inbox.md.
