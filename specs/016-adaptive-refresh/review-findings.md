# Deep Review Findings

**Date:** 2026-10-16
**Branch:** 016-adaptive-refresh
**Rounds:** 3
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 11 | 10 | 0 (1 reclassified Minor, by design) |
| Minor | 17 | 8 | 10 (9 + FINDING-8) |
| Notable | 7 | - | 7 |
| **Total** | **35** | **18** | **17** |

**Agents completed:** 5/5 internal (Goal Alignment skipped: no PR found), plus CodeRabbit (4 runs) and Codex (2 of 3 runs; the third hit the Codex usage limit).
**Re-review:** one focused agent per fix round (rounds 1, 2 and 3).
**Test suite:** `make test` passed after every round (965, 976, 977, 978 tests); `make app` builds.

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 80
- **File:** Sources/UsageCore/Snapshot/AdaptivePace.swift (`nextScheduledRefresh`), Sources/AgentMeter/App.swift (wake handler)
- **Category:** production-readiness
- **Source:** production-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** After a wake or return-from-idle refresh whose endpoint call failed by transport, the endpoint's last call did not move, so its past due time was not "handled" by a scheduled refresh. The adaptive timer therefore asked for a scheduled refresh about 1 s later. That second request used up the spec 010 quick retry episode.

**Why this matters:** This is the exact problem the pre-feature wake handler avoided (spec 010 FR-008, SC-001). It breaks spec 016 FR-014 ("adaptation never delays or cancels" the quick retry) in the common case of a wake with the network still down. It also adds an extra request.

**How it was resolved:** `EndpointPace` gained `lastTriedAt` (a request was sent, whatever the answer, or no request was possible because of the sign-in). `RefreshCoordinator.recordPacedCalls` records tries: Claude when its source ran in full mode, Codex from the new transient `CodexLimitsEntry.attempted`. `nextScheduledRefresh` treats a due time at or before `max(lastScheduledAt, lastTriedAt)` as handled. Tests: `failedTryHandlesTheDueTime`, `failedWakeCallKeepsTheTimerAtTheBase`.

### FINDING-2
- **Severity:** Important
- **Confidence:** 80
- **File:** Sources/UsageCore/Snapshot/AdaptivePace.swift (`shouldRefreshOnOpen`)
- **Category:** correctness
- **Source:** correctness-agent (also reported by: production-agent, security-agent as Minor)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The open decision looked only at the last call that reached the service. With an expired or missing sign-in (`lastCallAt` nil) or while offline, every opening of the dropdown started a full refresh. For an expired Claude sign-in that meant a keychain read through `/usr/bin/security` on every opening, because `EndpointPolicy` spacing never moved either.

**Why this matters:** This is unbounded user-driven work and repeated credential reads (FR-020), in states where the refresh gains nothing.

**How it was resolved:** `shouldRefreshOnOpen` uses `lastTriedAt` per endpoint. Within 60 s of a try the refresh could not call the endpoint (spacing) or would only read the sign-in again. Tests: `openWaitsAMinuteAfterATry`, `openWaitsAMinuteAfterATryWithoutAnswer`. Spec evolution candidate: FR-012 could say "last call or try".

### FINDING-3
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift (`requestRefresh`, `performRefresh`)
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** fixed (rounds 1 to 3)

**What is wrong:** While a refresh runs, a `.scheduled` tick replaces a pending manual, wake, retry or quick retry (or absorbs a lower-ranked one). The merged run was then paced like any scheduled run, so the absorbed request's endpoint call could be cancelled. A rate-limit retry had no recovery path.

**Why this matters:** FR-014: the manual, wake and retry refreshes keep their behavior, and adaptation never cancels them.

**How it was resolved:** `requestRefresh` remembers merged exempt triggers in two flags: `pendingPaceExempt` for the spaced triggers and `pendingRetryMerged` for retry and quick retry. A merged scheduled run ignores the pace for an endpoint when a retry merged, or when a spaced trigger merged and the endpoint was not tried in the last 60 s. Calls of a merged run never double the interval. Rounds 2 and 3 tightened this after re-review (FINDING-10, FINDING-11, FINDING-24). Tests: `scheduledRunMergedWithAManualRefreshIgnoresThePace`, `mergedRunKeepsTheSpacing`, `mergedRateLimitRetryIsNeverPaced`.

### FINDING-4
- **Severity:** Important
- **Confidence:** 85
- **File:** Sources/AgentMeter/App.swift (`conditionsChanged`)
- **Category:** architecture
- **Source:** architecture-agent (also reported by: test-quality-agent as Notable)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** Return-from-idle detection, the toggle gate and the 60 s quiet period after a wake lived in the app layer, used `Date()` and a literal 60, and had no tests.

**Why this matters:** FR-019 puts pace decisions in the tested core as plain values without a clock of their own.

**How it was resolved:** `AdaptivePace.idleReturn(from:now:)` and `wakeRequested(at:)` plus `wakeQuietPeriod`. `RefreshCoordinator.requestRefresh(.wake)` records the wake, and `setConditions` requests `.idleReturn` or logs the suppression. The app only forwards the conditions. Tests: `idleReturnDecision`, `returnFromIdleRefreshesUnlessRightAfterWake`, `toggleOffIgnoresConditions` (extended).

### FINDING-5
- **Severity:** Important
- **Confidence:** 78
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift (`applyPaceConfiguration`)
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, refined in rounds 2 and 3)

**What is wrong:** Two timer changes on the configuration path were never logged with value and reason: the toggle switched on while idle, and a base change under Low Power Mode.

**Why this matters:** FR-017 requires each change of the timer interval to be logged with its reason.

**How it was resolved:** `applyPaceConfiguration` compares the timer interval and reason before and after, and logs through the shared `logTimer()`. Test: `toggleOnWhileIdleLogsTheTimer`.

### FINDING-6
- **Severity:** Important
- **Confidence:** 72
- **File:** Tests/UsageCoreTests/RefreshCoordinatorTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** No coordinator test moved the clock backwards, so the `normalize` calls in `RefreshCoordinator` were untested.

**Why this matters:** Removing `normalize` from `nextScheduledRefresh()` would have pushed the timer up to 65 minutes into the future after a one-hour backwards jump (edge case "Clock moved backwards", SC-005).

**How it was resolved:** Added `clockMovedBackwardsNeverBlocksTheTimer`.

### FINDING-7
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/AgentMeter/SystemConditionsMonitor.swift
- **Category:** external
- **Source:** codex
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** An unlock after more than 10 minutes without keyboard or mouse input, such as with Touch ID or an Apple Watch, left `inputIdle` true, so idle never ended and no return-from-idle refresh ran.

**Why this matters:** FR-011 names unlock as a return from idle.

**How it was resolved:** The monitor records `unlockedAt` and treats it like an input event when computing idle seconds.

**External tool analysis (Codex):**
> When a screen is unlocked after more than 10 minutes without keyboard or mouse input, such as through Touch ID or Apple Watch, `inputIdle` remains true after `screenLocked` is cleared. `next.idle` therefore stays true, no condition transition is published, and no `.idleReturn` refresh is requested until a later input and poll.

### FINDING-8
- **Severity:** Important (reclassified Minor)
- **Confidence:** 75
- **File:** Sources/UsageCore/Snapshot/AdaptivePace.swift (`shouldCall`, activity branch)
- **Category:** external
- **Source:** codex
- **Round found:** 1
- **Resolution:** not changed, by design (reclassified Minor)

**What is wrong:** The activity branch also applies the 5 s tick tolerance, so an endpoint with new activity can be called at 4:55 instead of after a full 5-minute timer interval.

**Why this matters:** FR-006 states the tolerance only for the due time.

**How it was resolved:** Kept on purpose. The "timer interval has passed" condition is the timer's own tick, and the tolerance exists so that a tick waking a few milliseconds early (wall-clock `Date` versus the sleep's continuous clock) does not skip the activity call for a whole base interval. Without it, SC-002 ("reflected within one base interval") could be missed. Spec evolution candidate: FR-006 should state that the 5 s tolerance applies to both conditions.

**External tool analysis (Codex):**
> For a stretched endpoint interval, a scheduled refresh with new activity can call the endpoint up to five seconds before the timer interval has elapsed.

### FINDING-9
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift (`applyPaceConfiguration`)
- **Category:** external
- **Source:** codex (round 1 re-review)
- **Round found:** 2
- **Resolution:** fixed (round 2)

**What is wrong:** Switching Adapt refresh off while idle or in Low Power Mode returned the timer to the base without a log line.

**Why this matters:** FR-017.

**How it was resolved:** The timer change is logged whenever the toggle was or is on. `toggleOnWhileIdleLogsTheTimer` now also covers switching off.

### FINDING-10
- **Severity:** Important
- **Confidence:** 80
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift (`performRefresh`)
- **Category:** correctness
- **Source:** re-review agent, round 1
- **Round found:** 2
- **Resolution:** fixed (round 2)

**What is wrong:** The first fix for FINDING-3 removed the pace from a merged run without restoring the 60 s spacing the absorbed trigger would have had. `.scheduled` has no spacing in `EndpointPolicy` or the Codex gate, so a manual press merged right after a call produced a back-to-back request.

**Why this matters:** FR-011 and FR-012 spacing; requests to rate-limited endpoints.

**How it was resolved:** For spaced triggers the pace is lifted only for endpoints not tried in the last 60 s. Test: `mergedRunKeepsTheSpacing`.

### FINDING-11
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift (`performRefresh`)
- **Category:** correctness
- **Source:** re-review agent, round 2
- **Round found:** 3
- **Resolution:** fixed (round 3)

**What is wrong:** After FINDING-10, a rate-limit retry with `Retry-After` under 60 s merged into a scheduled run was paced again, because the 429 counted as a call less than 60 s earlier.

**Why this matters:** FR-014. The rate-limit retry is not re-armed afterwards.

**How it was resolved:** The separate `pendingRetryMerged` flag lifts the pace without the spacing check, since retries have no spacing of their own and `EndpointPolicy` still enforces any block. Test: `mergedRateLimitRetryIsNeverPaced`.

### FINDING-12
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift (Codex reuse log)
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** "pace: codex reused (adaptive pace, next call ...)" is logged before `CodexLimitsSource.decide`, which may still fetch for a new account or a changed home, or report a block.

**What needs to happen:** Log from the source's `.notDue` path with the next call time carried in the context, or log after collection.

### FINDING-13
- **Severity:** Minor
- **Confidence:** 78
- **File:** Sources/AgentMeter/SettingsView.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The caption "(at most every 30 minutes)" said the opposite of the bound. It now reads "(still at least every 30 minutes)".

### FINDING-14
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/AgentMeter/App.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** partly fixed (round 1), remaining

**What is wrong:** Several unordered Tasks read `paceStatus` for the same snapshot. `restartTimer` takes interval and toggle arguments but sends `self.configuration` to the coordinator.

**What happened:** `conditionsChanged` no longer reads the status twice. The `apply` path still reads it in two tasks; harmless, cleanup candidate.

### FINDING-15
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/UsageCore/Snapshot/AdaptivePace.swift (`PaceReason`)
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** The `Comparable` order of `PaceReason` is used only in tests. `timerReason` repeats the ranking as an if-chain.

### FINDING-16
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/AgentMeter/SystemConditionsMonitor.swift, Sources/UsageCore/Snapshot/AdaptivePace.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** `SystemConditionsMonitor.stop()` is never called. `IntervalChange.from` and `.reason` are read only by tests, while the log text is hard-coded.

### FINDING-17
- **Severity:** Minor
- **Confidence:** 70
- **File:** README.md (Security and privacy)
- **Category:** security
- **Source:** security-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The README did not mention the new system state reads, or that the log now records idle and power transitions.

**How it was resolved:** Added a "System state" row to "What it reads, and why", and a sentence to the plain-text log bullet.

### FINDING-18
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift (`performRefresh`)
- **Category:** production-readiness
- **Source:** production-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** The local scan now finishes before the network sources start, for every trigger, so a full refresh takes scan plus network time instead of the longer of the two. FR-006 requires this order only for scheduled refreshes.

**What needs to happen:** Run the sources concurrently for non-scheduled triggers and compute the activity afterwards.

### FINDING-19
- **Severity:** Minor
- **Confidence:** 75
- **File:** Tests/UsageCoreTests/RefreshCoordinatorTests.swift (`d3OnlyTheOldEndpointIsCalled`)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** The Codex `fetches` assertion is true by construction of the probe, which ignores the per-home spacing.

### FINDING-20
- **Severity:** Minor
- **Confidence:** 70
- **File:** Tests/UsageCoreTests/RefreshCoordinatorTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** No test covers US2 scenario 4: local spend of a token-based account updating on a paced-reuse tick.

### FINDING-21
- **Severity:** Minor
- **Confidence:** 70
- **File:** Tests/UsageCoreTests/AdaptivePaceTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** A base of exactly 30 minutes was not tested. Added `baseOfExactlyThirtyMinutesNeverStretches`.

### FINDING-22
- **Severity:** Minor
- **Confidence:** 70
- **File:** Tests/UsageCoreTests/RefreshCoordinatorTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1 to 3)

**What is wrong:** No test ran a retry while the pace was stretched. The merged-retry tests now cover it (FINDING-3, FINDING-11).

### FINDING-23
- **Severity:** Minor
- **Confidence:** 70
- **File:** Tests/UsageCoreTests/RefreshCoordinatorTests.swift (probes)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** FR-003a aggregation (one Codex pace for all homes, a call when any account reached the service) has no multi-account test.

### FINDING-24
- **Severity:** Minor
- **Confidence:** 70
- **File:** Tests/UsageCoreTests/AdaptivePaceTests.swift (`t11ClockMovedBackwards`)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** A `<=` assertion accepted any time up to the due time. It is now `== t(5)`.

### FINDING-25
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift (`merged`)
- **Category:** correctness
- **Source:** re-review agent, round 2
- **Round found:** 3
- **Resolution:** fixed (round 3)

**What is wrong:** The spaced-trigger merge measured 60 s from the last call that reached the service, while the triggers themselves are spaced by the last attempt. It now uses `lastTriedAt`.

### FINDING-26
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift
- **Category:** correctness
- **Source:** re-review agent, round 2
- **Round found:** 3
- **Resolution:** fixed (round 3)

**What is wrong:** The merge log line appeared with the toggle off and for endpoints not in use, and a plain base change logged a redundant "timer back to base". Both are now guarded.

### FINDING-27
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift (`runLoop`)
- **Category:** correctness
- **Source:** re-review agent, round 3
- **Round found:** 3
- **Resolution:** fixed (round 3)

**What is wrong:** A quick retry waiting behind a rate-limit retry lost its merge flag one iteration early. The flag now carries over while `pendingQuickRetry` is set.

### FINDING-28
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift (`merged`)
- **Category:** correctness
- **Source:** re-review agent, round 3
- **Round found:** 3
- **Resolution:** remaining

**What is wrong:** A merged retry lifts the pace for every endpoint. In a rare coincidence (a retry and a tick both arriving during a refresh that just called), the merged scheduled run can call an endpoint again that neither request alone would have called. This is not worse than with the toggle off.

**What needs to happen:** Decide the retry merge per endpoint by what that retry alone would have done.

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/Snapshot/UsageSnapshot.swift, Sources/UsageCore/Subscription/CodexLimits.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** `TransientFlag` is a public type whose `==` is always true, used to keep per-refresh facts (`reachedService`, now `attempted`) out of entry equality. Every carry-over path must reset them.
- **Rationale:** Per-refresh transport facts belong on the source result, not the entry.

### NOTABLE-2
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** Claude is paced by switching the run to reprice mode, while Codex is paced through a `codexPaceDue` flag on `RefreshContext`. The reuse logs also differ.
- **Rationale:** A third paced endpoint would need another special case; a per-endpoint decision set would unify both.

### NOTABLE-3
- **File:** Sources/UsageCore/Snapshot/EndpointPolicy.swift, Sources/UsageCore/Subscription/CodexLimitsSource.swift
- **Category:** security
- **Source:** security-agent
- **Description:** `.scheduled` has no minimum spacing of its own. The bound on endpoint calls now comes from the pace arithmetic and the app timer re-arm.
- **Rationale:** A cheap core invariant (no scheduled call within about a minute of the last attempt) would turn a future re-arm regression into a no-op instead of a request per second.

### NOTABLE-4
- **File:** Sources/AgentMeter/SystemConditionsMonitor.swift
- **Category:** security
- **Source:** security-agent
- **Description:** The `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked` notifications are undocumented. If they stop firing, idle falls back to the 10-minute input threshold.

### NOTABLE-5
- **File:** Sources/AgentMeter/App.swift
- **Category:** production-readiness
- **Source:** production-agent
- **Description:** Every snapshot cancels and re-creates the timer task with several actor hops. Correctness depends on how unstructured tasks interleave with the coordinator.
- **Rationale:** Returning the next scheduled time and the pace line from the coordinator with the snapshot would remove the ordering sensitivity.

### NOTABLE-6
- **File:** Sources/AgentMeter/SystemConditionsMonitor.swift
- **Category:** production-readiness
- **Source:** production-agent
- **Description:** The idle poll wakes the process every 60 s without a sleep tolerance, so the system cannot coalesce the wakeup.

### NOTABLE-7
- **File:** Sources/UsageCore/Snapshot/AdaptivePace.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Description:** The activity-branch tolerance (FINDING-8) has no boundary test.

## Goal Alignment

Skipped: no pull request exists for the branch yet.

## Post-Fix Spec Coverage

The fix rounds added and changed code but removed only app-layer code that moved into the core (the return-from-idle decision). All 22 functional requirements were re-checked after round 3:

| Requirement | Implementation | Status |
|-------------|---------------|--------|
| FR-001, FR-002 | `Configuration.adaptiveRefresh`, `AdaptivePace.enabled`, App fixed timer | ✓ |
| FR-003, FR-003a | `AdaptivePace.bound`, `PacedEndpoint.isInUse` | ✓ |
| FR-004 to FR-007 | `newestActivity`, `shouldCall`, `recordCall`, reprice reuse | ✓ |
| FR-008 to FR-010a | `timerInterval`, `dueAt`, `nextScheduledRefresh` | ✓ |
| FR-011 | `AdaptivePace.idleReturn`, `RefreshCoordinator.setConditions` | ✓ |
| FR-012 | `shouldRefreshOnOpen`, `refreshOnOpenIfDue`, `DropdownView.onAppear` | ✓ |
| FR-013 | `recordCall`, `recordTry` | ✓ |
| FR-014, FR-015 | merged-run flags, timer handled-skip | ✓ |
| FR-016 | `AdaptivePace.status`, `RefreshPaceStatus` | ✓ |
| FR-017 | `logTimer`, `recordPacedCalls`, reuse lines | ✓ |
| FR-018 | README Configuration and Security and privacy | ✓ |
| FR-019 | pace decisions in `AdaptivePace` | ✓ |
| FR-020 | no new hosts, files or permissions; fewer credential reads | ✓ |

All spec requirements verified after fix loop.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| 1 | make test | 0 | 0 | passed (976 tests) |
| 2 | make test | 0 | 0 | passed (977 tests) |
| 3 | make test | 0 | 0 | passed (978 tests; one intermediate run failed on a new assertion and was fixed in the same round) |

`make app` built the signed app after rounds 1 and 3.

## Remaining Findings

No Critical or Important findings remain. FINDING-8 was reclassified Minor by design, with a spec clarification candidate. The remaining Minor findings (FINDING-12, 14, 15, 16, 18, 19, 20, 23, 28) are cleanup and test-coverage items that need no change in behavior.
