# Deep Review Findings

**Date:** 2026-10-16
**Branch:** 019-pace-line-names-plan
**Rounds:** 1
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 2 | 2 | 0 |
| Minor | 4 | 3 | 1 |
| Notable | 3 | - | 3 |
| **Total** | **9** | **5** | **4** |

**Agents completed:** 5/6 (Goal Alignment skipped, no PR found) + 2 external tools (CodeRabbit, Codex)
**Agents failed:** none

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 85
- **File:** Tests/UsageCoreTests/RefreshPaceStatusTests.swift:153-165 (before the fix)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
SC-001 asks for each timer reason with and without a plan in use to be checked against the line text. Only Low Power Mode went through `status(now:)` with a slowed plan. High temperature with a plan in use had no test, away (idle) had only a hand-built status, and the no-plan cases for away checked only the reason.

**Why this matters:**
A change that let away or high temperature reach the plan-naming path, or used the wrong display name, would pass every test. Scenario 4 names all three timer reasons.

**How it was resolved:**
The parameterized test `timerReasonKeepsTodaysWording` (RefreshPaceStatusTests.swift:192-214) runs each of away, Low Power Mode and high temperature on a state with Codex slowed and both plans in use, and on a state with no plan in use. It checks `plans == []` and the exact line text for each, for example "Plan limits next checked at 14:45 (away)" and "Next refresh at 14:20 (high temperature)".

### FINDING-2
- **Severity:** Important
- **Confidence:** 80
- **File:** Tests/UsageCoreTests/RefreshPaceStatusTests.swift (no transition test)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
No test covered SC-002 or the edge case "after new activity it keeps the old wording until the next refresh that sees it". All tests checked one fixed state.

**Why this matters:**
SC-002 is the user-visible bug this spec fixes: with Claude Code active and Codex idle, the line must name only Codex. A regression that left `plans` stale after the interval reset would not be caught.

**How it was resolved:**
`claudeActivityLeavesOnlyCodexNamed` (RefreshPaceStatusTests.swift:149-163) starts with both plans slowed, adds Claude Code activity at 14:22, checks that the line still names both plans before the next refresh, runs the 14:25 scheduled refresh (Claude called, Codex not), and then checks "Codex limits next checked at 14:40 (no Codex activity)". The both-slowed setup moved into the helper `bothSlowed(later:)` (lines 104-117), which the existing test now shares.

### FINDING-3
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/UsageCore/Snapshot/RefreshPaceStatus.swift:47
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The `reason == .noAgentActivity` half of the guard in `text` was never exercised, because every timer-reason test had empty `plans`.

**Why this matters:**
FR-003 requires a timer reason to keep "Plan limits" wording. Deleting the condition would not have failed a test.

**How it was resolved:**
`timerReasonIgnoresPlans` (RefreshPaceStatusTests.swift:218-222) builds an idle status that carries `[.claude]` and checks "Plan limits next checked at 14:35 (away)".

### FINDING-4
- **Severity:** Minor
- **Confidence:** 75
- **File:** Tests/UsageCoreTests/RefreshPaceStatusTests.swift:102-125 (before the fix)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The only both-slowed test that went through `status(now:)` had Codex due first. Scenario 3, with Claude due first, was never built.

**Why this matters:**
If a regression always took Codex's due time whenever both plans are slowed, the existing test would still pass.

**How it was resolved:**
`bothSlowedClaudeDueFirst` (RefreshPaceStatusTests.swift:135-145) builds the mirror state: Claude due at 14:35, Codex at 14:40. It asserts the order Claude, Codex and the time 14:35.

### FINDING-5
- **Severity:** Minor
- **Confidence:** 70
- **File:** Tests/UsageCoreTests/RefreshPaceStatusTests.swift:166-188
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
`planNotInUseIsNotNamed` checked only `plans == [.claude]`, never the line text.

**Why this matters:**
If the text took its names from all stretched endpoints and not from `plans`, this test would miss it.

**How it was resolved:**
The test now also checks "Claude limits next checked at 14:25 (no Claude Code activity)".

### FINDING-6
- **Severity:** Minor
- **Confidence:** 72
- **File:** Sources/UsageCore/Snapshot/RefreshPaceStatus.swift:23, 46-52
- **Category:** architecture
- **Source:** correctness-architecture-agent
- **Round found:** 1
- **Resolution:** remaining (Minor, does not block the gate)

**What is wrong:**
`init` defaults `plans` to `[]`. If `plans` is empty, `.noAgentActivity` falls back silently to the retired wording "Plan limits next checked at <time> (no agent activity)". Production code cannot reach that state today: the only `.noAgentActivity` construction (AdaptivePace.swift:411-412) runs after a guard that ensures at least one stretched endpoint.

**Why this matters:**
A future call site that builds `.noAgentActivity` without `plans` would compile and show the old wording.

**How to resolve:**
Remove the `= []` default so every call site passes `plans` explicitly: AdaptivePace.swift:405 and 407, and the timer-reason tests. Optionally, add `assert(reason != .noAgentActivity || !plans.isEmpty)` in `init`. It was left as is because the default keeps the timer-reason call sites short, and the new `timerReasonIgnoresPlans` test already pins the guard.

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/Snapshot/RefreshPaceStatus.swift:47-50
- **Category:** architecture
- **Source:** correctness-architecture-agent
- **Description:** The wording for several plans joins the names with " and " and reuses `reason.displayName`. That works for exactly two `PacedEndpoint` cases. A third endpoint would read "A and B and C".
- **Rationale:** If an endpoint is added, switch to `ListFormatter` or an explicit rule for two or more, and add a test.

### NOTABLE-2
- **File:** Tests/UsageCoreTests/RefreshPaceStatusTests.swift:248-252
- **Category:** test-quality
- **Source:** test-quality-agent
- **Description:** `bothPlansTwelveHour` hard-codes U+202F before "AM", which depends on ICU data.
- **Rationale:** The test could fail on a different toolchain even though the product behaves correctly. If that happens, normalize the space before comparing.

### NOTABLE-3
- **File:** Sources/AgentMeter/DropdownView.swift:158-163
- **Category:** test-quality
- **Source:** test-quality-agent
- **Description:** FR-005 (the accessibility text is the same string) and FR-007 (the line wraps and is not truncated) live in the SwiftUI layer and have no automated tests.
- **Rationale:** Check them by hand in the walkthrough: both plans, 12-hour time, on another day, with VoiceOver on.

## Goal Alignment

Skipped (no PR found for the branch).

## Post-Fix Spec Coverage

The fix round added or extended tests only. No implementation code was removed, so the Step 7b check did not apply. All of FR-001 to FR-007 are still implemented at the locations listed in REVIEW-CODE.md.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| baseline | make test | 0 | 0 | passed (1376 tests) |
| 1 | make test | 0 | 0 | passed (1380 tests) |

The test suite passed in all fix rounds.

## External Tools

- CodeRabbit 0.7.6: CLI 0.7.6 rejects `--files`, so it ran with `--agent --base main --committed`. It found 0 issues. The fix round re-review (`--uncommitted`) also found 0.
- Codex (`codex review --base main`): 0 findings ("No actionable regressions were identified in the diff").
- Copilot: skipped (disabled in config).

## Remaining Findings

No Critical or Important findings remain. FINDING-6 (Minor) is still open, as described above.
