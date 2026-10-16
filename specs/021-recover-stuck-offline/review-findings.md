# Deep Review Findings

**Date:** 2026-10-16
**Branch:** 021-recover-stuck-offline
**Rounds:** 1
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 3 | 3 | 0 |
| Minor | 17 | 4 | 13 |
| Notable | 6 | - | 6 |
| **Total** | **26** | **7** | **19** |

**Agents completed:** 5/5 internal (Goal Alignment skipped, no PR found) + 2 external tools (CodeRabbit, Codex; Copilot disabled in config)
**Agents failed:** none

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift:1041-1044 (updateQuickRetry), 357-373 (runLoop)
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
A "Refresh now" click during a running refresh is outranked by a queued `.quickRetry` (rank 2 over rank 1), so only `pendingManual` records it. When the running refresh ends the grace period (for example, the running request got no answer again), `updateQuickRetry` drops the queued quick retry (`pendingTrigger = nil`). `runLoop` then finds no pending trigger and ends, and the click is lost.

**Why this matters:**
FR-003a names the quick retry as a trigger a click may be merged into, and FR-006 says clicks during a run collapse into one follow-up refresh. In this path neither holds: the user clicks and nothing is sent.

**How it was resolved:**
`updateQuickRetry` now replaces a dropped queued quick retry with `.manual` when a click was merged into it: `pendingTrigger = pendingManual ? .manual : nil`. New regression test `NoAnswerRetryCoordinatorTests.clickMergedIntoADroppedQuickRetryStillRuns` failed before the fix (2 runs instead of 3) and passes after.

### FINDING-2
- **Severity:** Important
- **Confidence:** 85
- **File:** Tests/UsageCoreTests/RefreshCoordinatorTests.swift (NoAnswerRetryCoordinatorTests)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
No test covered the mixed case named in the spec's edge cases and SC-002: one service got no answer while the other answered. The two paths differ: Codex-only no-answer runs as a Claude reprice with the gated Codex source still bypassing, and Claude-only no-answer runs as `.fetchNoAnswer` while Codex must stay spaced.

**Why this matters:**
A change that collects gated sources only in `.full` mode, or leaks the Claude restriction into Codex, would have passed every test.

**How it was resolved:**
Added `manualAsksOnlyCodexWhenOnlyCodexGotNoAnswer` and `manualAsksOnlyClaudeWhenOnlyClaudeGotNoAnswer`, using the real sources and request counts per token.

### FINDING-3
- **Severity:** Important
- **Confidence:** 85
- **File:** Tests/UsageCoreTests/CodexLimitsSourceTests.swift:577-690
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, source level)

**What is wrong:**
Every Codex bypass test used `trigger: .manual`. No test passed `manualRequested: true` with another trigger (a scheduled run the pace holds back, or a wake), which is the FR-003a merged-click case for Codex homes.

**Why this matters:**
Moving the `manualRequested && gate.lastNoAnswer` check below the `switch trigger` would have broken FR-003a for Codex without failing a test.

**How it was resolved:**
Added `mergedClickBypassesTheOtherTriggersRule`. It checks that without the click, a pace-held scheduled run and a wake inside the spacing send nothing, and that with `manualRequested` each sends one request. A coordinator-level test of `codexPaceBypassed` is still missing; see FINDING-16.

### FINDING-4
- **Severity:** Minor
- **Confidence:** 75
- **File:** README.md:202
- **Category:** security (FR-010)
- **Source:** security-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The README said a click adds "one more request" for each no-answer account. The code allows one request per click, as long as the failures continue.
**Why this matters:** The bullet is the README's full list of token uses, and it must state the real request volume (AGENTS.md).
**How it was resolved:** It now reads "each time you click 'Refresh now' within a minute of a request that could not reach the service, one request for each account that got no answer (a rate-limit wait still holds these back)".

### FINDING-5
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift:816
- **Category:** architecture (observability)
- **Source:** architecture-agent (round 1), codex (round 2, P3)
- **Round found:** 1
- **Resolution:** fixed (round 1, wording refined in round 2)

**What is wrong:** The log line "endpoint not called (no no-answer account requested)" was a double negative and wrong: the no-answer accounts were requested, but no request was sent (for example, a credential failure). Codex then noted in round 2 that the first rewording claimed no request at all, even when a Codex request was sent.
**How it was resolved:** The line now reads "endpoint not called (no Claude request sent for no-answer accounts)".

### FINDING-6
- **Severity:** Minor
- **Confidence:** 75
- **File:** docs/superpowers/specs/2026-10-13-endpoint-call-policy-design.md:43
- **Category:** architecture (doc accuracy)
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** Rule 4 ("retry" when not rate limited means "already fresh") did not mention that a merged click after a no-answer failure now yields `.fetchNoAnswer`.
**How it was resolved:** Added the same kind of spec 021 amendment note as rule 5.

### FINDING-7
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift:529-531, 570-578
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** A settings edit merged with a click inside the spacing schedules its follow-up at the old `last + 60`. The bypass request then moves `lastAttemptAt` (FR-003b), so the follow-up is spaced again and gets pushed back by up to 60 s.
**Why this matters:** Low impact. The restricted run already fetches new or moved accounts. The comment "at the end of the spacing" is slightly off.
**What needs to happen:** Compute the follow-up from `policy.lastAttemptAt` after the fetch.

### FINDING-8
- **Severity:** Minor
- **Confidence:** 72
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift:768-769 (lastSuccessfulRefreshAt), 457-458
- **Category:** external
- **Source:** codex (round 1, P2)
- **Round found:** 1
- **Resolution:** remaining (ambiguous, product decision)

**What is wrong:** Take a Codex-only bypass: Claude answered less than 60 s ago, and a Codex home got no answer. The run is a Claude reprice, so `endpointCalled` stays false. The footer's "Last refreshed" time and the summary log ("endpoint reused") then do not reflect the successful Codex request.
**Why this matters:** `lastSuccessfulRefreshAt` has always followed the Claude usage endpoint. Codex requests during a Claude reprice existed before (for example, a new Codex home), and Codex entries show their own live state. Making the footer time count Codex requests changes the meaning of spec 006 and spec 007, which needs a product decision.

**External tool analysis (Codex):**
> When Claude was successfully fetched less than 60 seconds ago but a Codex home had a no-answer failure, the Claude policy selects `.reprice` here while the gated Codex source still sends the manual bypass request. Because `endpointCalled` remains false on the reprice path, the successful Codex recovery leaves `lastSuccessfulRefreshAt` unchanged and logs the endpoint as reused, so the dropdown continues to show an outdated refresh time despite fresh Codex limits.

### FINDING-9
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/UsageCore/Subscription/UsageEndpointClient.swift:152-157, CodexUsageClient.swift:47-54
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** remaining

`init(session:)` is public and skips the per-request session (FR-001). Every caller is a `@testable` test, so it could be `internal`.

### FINDING-10
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/UsageCore/Subscription/UsageEndpointClient.swift:168-180, CodexUsageClient.swift:71-85
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** remaining

The URLError mapping to `.network(_, detail:)` is copied in both clients. It could move into `SessionSource.data(for:)`. A non-URLError no-answer failure (for example, `CancellationError`) logs no domain or code, which FR-007 permits because FR-007 is about URL errors.

### FINDING-11
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift:26-29, 72-74; EndpointPolicy.swift:62-67
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** remaining

Doc comments say the no-answer-only run happens "inside the spacing". It also happens on the pace path and on the "already fresh" retry path.

### FINDING-12
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift:21-38, 504-507
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** remaining

The new `RefreshContext` fields are `public var` and set after init. The existing fields are `let` init parameters.

### FINDING-13
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift:449-456, 525-531
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** remaining

The follow-up `scheduleRetry` with the same trigger expression is written twice, once for `.reuse` and once for `.fetchNoAnswer`. A `Decision.followUpAt` property would state the rule once.

### FINDING-14
- **Severity:** Minor
- **Confidence:** 72
- **File:** Sources/UsageCore/Subscription/CodexLimitsSource.swift:474-476
- **Category:** production-readiness
- **Source:** production-agent
- **Resolution:** remaining

The Codex per-account log note does not say that a request was sent because of the "Refresh now" bypass, and the coordinator summary does not name a merged click.

### FINDING-15
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Subscription/SubscriptionSource.swift:195
- **Category:** production-readiness
- **Source:** production-agent
- **Resolution:** remaining

`noAnswer` is pruned only in a full collect. A removed account can force one extra full run that sends no request, and the set then heals itself.

### FINDING-16
- **Severity:** Minor
- **Confidence:** 80
- **File:** Tests/UsageCoreTests/SubscriptionSourceTests.swift:1042-1067; RefreshCoordinatorTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** remaining

Three cases are not tested: (1) a pre-request failure leaves the no-answer set unchanged; (2) a changed credential directory clears it; (3) Codex `.noRequest` leaves `lastNoAnswer` unchanged. The `codexPaceBypassed` exclusion has no coordinator-level test either.

### FINDING-17
- **Severity:** Minor
- **Confidence:** 80
- **File:** Tests/UsageCoreTests/RefreshCoordinatorTests.swift (bypassCountsForSpacingPaceAndDropdownOpen)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** remaining

`!logText().contains("pace: claude interval")` cannot fail for a `.manual` trigger. The merged-scheduled test covers R7 properly.

### FINDING-18
- **Severity:** Minor
- **Confidence:** 70
- **File:** Tests/UsageCoreTests/RefreshCoordinatorTests.swift (manualMergedIntoPendingQuickRetrySendsOneRequest, clickMergedIntoADroppedQuickRetryStillRuns)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** remaining

A 30 ms sleep orders the quick-retry timer before the click. Under heavy load the merge order could flip. A test hook for the pending trigger would remove the race.

### FINDING-19
- **Severity:** Minor
- **Confidence:** 70
- **File:** Tests/UsageCoreTests/UsageEndpointClientTests.swift:276-333, CodexUsageClientTests.swift:210-260
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** remaining

No test goes through the default `makeSession` argument that App.swift relies on. Changing the default back to a cached session would pass the tests.

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/Subscription/SubscriptionSource.swift:36-40; CodexLimitsSource.swift:365-374
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** A pre-request failure (expired or missing sign-in) leaves the no-answer flag set. Each click within 60 s then re-reads the credential (a keychain read for Claude) and writes log lines, but sends no request.
- **Rationale:** The spec says pre-request failures "keep today's behavior". Whether the flag should follow the last request or the last attempt is a product decision (ambiguous).

### NOTABLE-2
- **File:** Sources/UsageCore/Subscription/CodexLimitsSource.swift:52-60; EndpointPolicy.swift:88-122
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** The FR-003 bypass is implemented twice in different shapes: a per-home Bool for Codex, and a per-account Set plus policy flag for Claude.
- **Rationale:** A shared per-target gate type would keep the rules in sync.

### NOTABLE-3
- **File:** Sources/UsageCore/Snapshot/EndpointPolicy.swift:119-123; CodexLimitsSource.swift:477-478
- **Category:** security
- **Source:** security-agent
- **Description:** There is no minimum gap between bypass requests. Each click after a finished run sends one request per no-answer target, so the click rate is the only limit.
- **Rationale:** The spec allows this, and a rate-limit wait still wins. A 5 to 10 s floor would be a product decision (ambiguous).

### NOTABLE-4
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift:299-314
- **Category:** security
- **Source:** security-agent
- **Description:** A successful partial run (no-answer-only or quick retry) resets the global `consecutiveRateLimits` and `lastOutcome`, even for accounts that were not asked.
- **Rationale:** An active wait is still respected. Only the backoff history is weakened, and the quick retry already had the same pattern.

### NOTABLE-5
- **File:** Sources/UsageCore/Subscription/UsageEndpointClient.swift:16-36
- **Category:** production-readiness
- **Source:** production-agent
- **Description:** The stream error domain (`_kCFStreamErrorDomainKey`) and the elapsed time of the failed request are not logged.
- **Rationale:** Both are privacy-safe integers that would make the next incident easier to read. The spec's clarification limits the detail to codes.

### NOTABLE-6
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift:233-234, 362-366
- **Category:** production-readiness
- **Source:** production-agent
- **Description:** A double click during a fast-failing bypass run sends two requests per service back to back (the run plus its follow-up).
- **Rationale:** FR-006 allows this explicitly. It is the only gesture that yields more than one request per service.

## Post-Fix Spec Coverage

The fix loop removed no code (one changed line in `updateQuickRetry`, two wording changes, tests added). Coverage check:

| Requirement | Implementation | Status |
|-------------|---------------|--------|
| FR-001 | UsageEndpointClient.swift SessionSource.perRequest, UsageSession.make | ✓ |
| FR-002 | UsageSession.configuration, per-request timeoutInterval 30 | ✓ |
| FR-003 | EndpointPolicy.decide(noAnswerRetry:), CodexLimitsSource.decide | ✓ |
| FR-003a | RefreshCoordinator pendingManual/manualMerged, updateQuickRetry (fixed) | ✓ |
| FR-003b | policy.record in no-answer run, recordPacedCalls exclusions, gate.lastFetchAt | ✓ |
| FR-003c | SubscriptionSource restricted run, noAnswer set | ✓ |
| FR-004 | FailureCategory.isNoAnswer, noAnswer.remove / lastNoAnswer = false | ✓ |
| FR-005 | manual flag only for .manual or merged click | ✓ |
| FR-006 | pendingManual collapse, one request per account/home per run | ✓ |
| FR-007 | NetworkFailureDetail, logDescription in both source logs | ✓ |
| FR-008 | NetworkFailureDetail reads domains and codes only | ✓ |
| FR-009 | all logic in UsageCore, tested | ✓ |
| FR-010 | README "The tokens are powerful" bullet (reworded) | ✓ |

All spec requirements verified after fix loop.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| baseline | make test | 0 | 0 | passed (1427 tests) |
| 1 (red, new tests before fix) | make test | 2 | 1 test | failed as expected |
| 1 (after fix) | make test | 0 | 0 | passed (1431 tests) |
| 2 (wording fix) | make test | 0 | 0 | passed (1431 tests) |

`make app` built and signed build/AgentMeter.app after the fixes.

## Remaining Findings

No Critical or Important findings remain. Three items need a product decision and were not changed: FINDING-8 (footer refresh time after a Codex-only bypass), NOTABLE-1 (pre-request failure keeps the flag) and NOTABLE-3 (no floor between bypass clicks).
