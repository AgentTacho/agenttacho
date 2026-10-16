# Deep Review Findings

**Date:** 2026-10-15
**Branch:** 010-keep-last-good-values
**Rounds:** 3 (initial review, then 3 fix rounds, each re-reviewed)
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 7 | 7 | 0 |
| Minor | 30 | 12 | 18 |
| Notable | 2 | - | 2 |
| **Total** | **39** | **19** | **20** |

Counts are after deduplication. Two compliance deviations found in stage 1 (FR-020, FR-021) were fixed before the deep review (commit 2cadf81) and are listed in REVIEW-CODE.md.

**Agents completed:** 5/5 internal (goal alignment skipped: no pull request), plus CodeRabbit and Codex. Copilot is disabled in config.
**Agents failed:** none. The first CodeRabbit call failed because the CLI dropped `--files`; the rerun used `--base main --committed`.

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 85
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift (`updateQuickRetry`), SubscriptionSource.swift, CodexLimitsSource.swift
- **Category:** correctness
- **Source:** correctness-agent (also reported by: production-readiness-agent, codex)
- **Round found:** 1
- **Resolution:** fixed (round 1, commit 67826b1)

**What is wrong:**
The retry time was the refresh start plus 30 s. Both clients time out after 30 s, so a request that timed out finished at or after its own retry time. `updateQuickRetry` kept only future times, which dropped the retry without a log line. The entry stayed `.retrying`: unmarked, with "retrying at" a past time, until the next scheduled refresh.

**Why this matters:**
This is the main wake-from-sleep scenario of US1. FR-004's quick retry never ran, and FR-005's grace period lasted minutes instead of 30 s.

**How it was resolved:**
Both sources now count the retry from the failure time (`max(failedAt, now)`). The coordinator fires at once a retry time that passed during the refresh but is still inside its due window. `endingGrace` clears `quickRetryAt`. New tests cover the timeout in both sources and the coordinator's "fires at once" path.

**External tool analysis (Codex):**
> When a transport failure arrives at or just after the 30-second request timeout, the source computes `quickRetryAt` from the refresh start, but this filter discards that now-past time. The snapshot remains `.retrying` and no retry task is created.

### FINDING-2
- **Severity:** Important
- **Confidence:** 72
- **File:** Sources/AgentMeter/App.swift (`observeWake`, `restartTimer`)
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, commit 174f7ef)

**What is wrong:**
`Task.sleep(for:)` uses a continuous clock, so a scheduled tick that came due during sleep fires right at wake. When the wake refresh failed first, that tick sent a request seconds later. That request took the quick retry's place (FR-008) and usually failed too.

**Why this matters:**
About half of all wakes would lose the grace period (SC-001) and add a second request right after the first.

**How it was resolved:**
The wake observer restarts the refresh timer before it requests the wake refresh.

### FINDING-3
- **Severity:** Important
- **Confidence:** 80
- **File:** Sources/AgentMeter/App.swift, Sources/UsageCore/Notifications/ThresholdTracker.swift
- **Category:** architecture
- **Source:** architecture-agent (also reported by: test-quality-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1, commit 174f7ef)

**What is wrong:**
The FR-019 rule lived only in the SwiftUI layer, with no test: saved Claude values in the early result must neither notify nor set the baseline.

**Why this matters:**
The rule is a MUST requirement and it was untested. AGENTS.md keeps logic in UsageCore.

**How it was resolved:**
`ThresholdTracker.observe` now skips Claude subscriptions of a preliminary snapshot. A test shows that 75% early and then 85% on the first refresh gives no crossing (85% is the baseline). App.swift passes the snapshot unchanged.

### FINDING-4
- **Severity:** Important
- **Confidence:** 85
- **File:** Tests/UsageCoreTests/RefreshCoordinatorTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, commit d31b517)

**What is wrong:**
The coordinator tests for US3-1 and FR-020 used a fake source that throws. The real sources never throw, so the tests ran a path production never takes. This hid the FR-020 deviation found in stage 1.

**Why this matters:**
The tests gave false confidence for the launch-offline flow.

**How it was resolved:**
A new end-to-end test wires the real `SubscriptionSource`, a `LastGoodStore` and an offline stub. It checks the early `.ok` result, then `.stale` with the saved fetch time, the quick retry timer and no refresh time. The alignment test now uses a non-throwing source that returns a stale entry.

### FINDING-5
- **Severity:** Important
- **Confidence:** 85
- **File:** Tests/UsageCoreTests/CodexLimitsSourceTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, commit d31b517)

**What is wrong:**
SC-004, a search of the saved file for the token strings, was tested only for Claude.

**Why this matters:**
A future Codex field could leak the access token or the ChatGPT account id into the file without any test failing.

**How it was resolved:**
The Codex save test reads `last-good.json` as text. It checks that neither the token nor a unique ChatGPT account id appears.

### FINDING-6
- **Severity:** Important
- **Confidence:** 85
- **File:** Tests/UsageCoreTests/SubscriptionSourceTests.swift, CodexLimitsSourceTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, commit 67826b1)

**What is wrong:**
No test covered a scheduled or wake request during the grace period that fails (edge cases "Retry and timer collide" and "Retry while asleep").

**Why this matters:**
That branch decides whether the user sees `~` and whether a second retry can slip into the same episode.

**How it was resolved:**
New tests: a parameterized Claude test (`.scheduled`, `.wake`) and a Codex test. Each expects `.stale`, no `quickRetryAt`, and no retry on a later failure.

### FINDING-7
- **Severity:** Important
- **Confidence:** 80
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift (gather loop, `updateQuickRetry`)
- **Category:** regression
- **Source:** re-review agent, round 1
- **Round found:** 2
- **Resolution:** fixed (round 2, commit 1f2d8c0)

**What is wrong:**
FINDING-1's "fire at once" path re-armed the timer every second for a reused `.stale` entry that still had a passed `quickRetryAt`. Such an entry comes from saved values only, or from no values. This happened whenever the quick retry was suppressed by a rate limit, for up to 30 s.

**Why this matters:**
Up to about 29 back-to-back refreshes, with log spam and UI churn.

**How it was resolved:**
A reused entry drops a passed retry time in any state. A test (rate limited at the retry, stale entry with a retry time) checks that the timer is set only once.

### FINDING-8
- **Severity:** Minor (fixed with the Important findings because it breaks FR-015 on every launch with a record source failure)
- **Confidence:** 70
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift (record carry-over)
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, commit d31b517)

**What is wrong:**
The early result became the previous snapshot. When the record source failed on the first refresh after launch, the carry-over replaced the fresh budget entries with the early result's empty maps.

**Why this matters:**
Every launch after the first would show `…` and "No data" for groups and budgets until a later refresh succeeded, which FR-015 rules out.

**How it was resolved:**
The carry-over skips a preliminary previous snapshot. A test checks that the group entry is present and stale.

### Minor findings fixed

- LastGoodStore reads the saved file through one descriptor (`O_NOFOLLOW | O_NONBLOCK`, `fstat`, at most 1 MiB + 1 bytes). A directory, a symlink, a FIFO or a huge file is ignored unread, with no check-to-read race (security-agent, re-review; commits d31b517, 1f2d8c0). An empty file reads as empty data (re-review round 2; commit 911ff31).
- The temporary file is removed when `createFile` fails (CodeRabbit; commit d31b517).
- README "What it writes" now lists the UI preferences and price exports, and everything `last-good.json` holds (security-agent; commit d31b517).
- A reprice inside the second between a retry time and its timer no longer cancels the pending timer (re-review round 2; commit 911ff31).
- BarLayout uses `SubscriptionState.isStale` instead of its own copy of the rule (architecture-agent).
- RetryEpisodes due/overdue doc comments cite spec FR-007, FR-008 and the edge case (architecture-agent).
- `ErrorBox: @unchecked Sendable` replaced by `case failed(Error, at:)` (architecture-agent, with FINDING-1).
- The "not signed in, dropped at the next save" test now requires that the file loads (test-quality-agent).
- The coordinator test records `quickRetrySuppressed` calls and checks exactly one, at the retry time (test-quality-agent).

## Remaining Minor findings (not fixed, with reason)

- Codex: `lastSuccessfulRefreshAt` advances during a Codex-only grace period. Not changed: spec 007 FR-006 treats one Codex account's failures as isolated, so a Codex transport failure after the grace period does not hold back that time either. Holding it back only during grace would be inconsistent. Each Codex entry shows its own "as of" time.
- FR-003 per-account "dropped" log lines. The coordinator logs the timer as dropped or moved, and each source logs the per-account outcome, but a replaced grace is not named per account (architecture, production).
- Episode bookkeeping (`liveThisRun`, overdue loop) is duplicated between the two sources and could move into `RetryEpisodes` (architecture).
- `GraceNote` re-derives the note from error text (`hasPrefix`, `"offline"`). `SubscriptionEntry.failureCategory` is read only by tests (architecture).
- The redundant `lastEntries` update in `quickRetrySuppressed`, the dead version clause in `replace` and `failure.category ?? .transport` remain (architecture).
- The coordinator logs "quick retry suppressed (rate limited)" when only a Codex quick retry is due, though Codex sends its own request (known, log wording).
- A successful quick retry can cancel a pending rate-limit retry for another account, in a narrow window where the block just ended (correctness F3).
- Timer identity: an old timer task that hops onto the actor after a reschedule can clear the new handle. The sources gate requests by `isRetryDue`, so no extra request is sent (production F3).
- Log detail: "quick retry sent" without a due account, decode error paths, write recovery, the missing-file wording, and leftover unique temp files after a crash (production F4 to F6).
- Test gaps: US3-3 (saved values replaced by a first success), removing an account from the configuration, a symlinked credential directory, an unreadable 0o000 file, trigger recording in `pendingRetryAndQuickRetryBothRun`, and fixed-sleep negative assertions (test-quality F6 to F12).
- Codex review round 2 P2 (a suppressed Codex retry rescheduling every second) was rejected. `CodexLimitsSource` is not network-bound and runs live on every refresh, reprices included. On `.quickRetry` it fetches or, when blocked, expires the episode, and its `quickRetryAt` is recomputed from the episodes on every collect. The round 2 re-review confirmed this.

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/Snapshot/LastGoodStore.swift
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Description:** The file is written on every successful refresh (the fetch time always changes), and twice when both providers fetched.
- **Rationale:** FR-013 requires this, and it is cheap. A combined `replace(claude:codex:)` per refresh would halve the writes.

### NOTABLE-2
- **File:** Sources/AgentMeter/DropdownView.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Description:** The dropdown builds the spec-required notes and colors itself (grace note with the retry time in gray, rejected sign-in in red with the time, "Refreshing…" for the early result). Only the note strings are tested.
- **Rationale:** A small note view-model in UsageCore (text plus style per state) would make US1-1, US2-1 and US2-4 testable.

## Post-Fix Spec Coverage

The fix rounds removed code in two places. The FR-019 rule moved from App.swift into ThresholdTracker. `ErrorBox` was replaced by an `Error` payload. Coverage after the fixes:

| Requirement | Implementation | Status |
|-------------|---------------|--------|
| FR-001 to FR-003 | FailureCategory.classify, source logs | ✓ |
| FR-004 to FR-009 | RetryEpisodes, both sources, RefreshCoordinator quick retry | ✓ |
| FR-010 to FR-012 | `.signInRejected`, SignInRejectedNote, Codex `signInRejected` | ✓ |
| FR-013 to FR-018 | LastGoodStore, source save and seed, publishSavedValues | ✓ |
| FR-019 | ThresholdTracker preliminary skip (moved, tested) | ✓ |
| FR-020 | publishSavedValues, accountsFetchedThisRun, dropPassedSavedAlignmentReset | ✓ |
| FR-021 | README "What it writes" | ✓ |

All spec requirements verified after the fix loop.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| baseline | make test | 0 | 0 | passed (778 tests) |
| stage 1 fix | make test | 0 | 0 | passed (780 tests) |
| 1 | make test | 0 | 0 | passed (789 tests) |
| 2 | make test | 0 | 0 | passed (790 tests) |
| 3 | make test | 0 | 0 | passed (790 tests) |

Test suite passed in all fix rounds. Each new regression test was run red before its fix.
