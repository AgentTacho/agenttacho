# Deep Review Findings

**Date:** 2026-10-14
**Branch:** 003-monthly-budget-period
**Rounds:** 1 fix round (plus two Minor test follow-ups from the round 1 re-review)
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline stage 7, review-code)
**Review range:** `git diff main...HEAD -- Sources Tests README.md`

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 3 | 3 | 0 |
| Minor | 10 | 8 | 2 |
| Notable | 4 | - | 4 |
| **Total** | **17** | **11** | **6** |

**Agents completed:** 5/5 internal (Correctness, Architecture & Idioms, Security, Production Readiness, Test Quality), plus one combined re-review agent for round 1
**Skipped:** Goal Alignment (no PR found), Copilot (disabled in config)
**Failed:** CodeRabbit (3 runs, each "Review failed: Failed to start review", no findings), Codex (usage limit reached, no findings)

Two findings were reported by two agents and are counted once: Security's Notable on LogIndex memory is part of FINDING-1, and Production Readiness FINDING-3 (monthly window not logged) is part of FINDING-7.

## Findings

### FINDING-1 (Important, fixed round 1)
- **Severity:** Important
- **Confidence:** 80
- **File:** Sources/UsageCore/Logs/LogIndex.swift:59-199, Sources/UsageCore/Windows/WindowResolver.swift:63-67
- **Category:** production-readiness
- **Source:** production-readiness-agent (also reported by: security-agent, as Notable)
- **Round found:** 1
- **Resolution:** fixed (round 1, commit 800a889)

**What is wrong:**
A monthly group widens the collection window to the 1st of the month. On every full re-read (launch, a switch to monthly, an attribution change, an earlier aligned week), `LogIndex.update` read every changed file whole and kept the raw line bytes of every parsed record from every file until the merge phase. Peak memory therefore grew with the bytes of all files modified since the collection start. A measurement on real logs showed a 1,273 MB peak RSS for a 31-day lookback, against 685 MB for 7 days.

**Why this matters:**
A menu bar app that spikes above 1 GB on each full re-read risks memory pressure on 8 GB Macs. This contradicts the research claim that a monthly group only costs the extra records kept.

**How it was resolved:**
Phases 2 (read and parse) and 3 (merge) now run per batch of at most 64 MB of unread bytes (`LogIndex(batchBytes:)`). Only one batch's raw lines are in memory at a time. On the same real logs, the 31-day peak RSS dropped to 455 MB (7-day: 312 MB), with a 3.5 s full collect and a settled footprint of 86 MB. Tests `batchedReadMatchesSingleBatch` and `batchesSplitJobsByUnreadBytes` cover equal results and batch boundaries. Streaming reads and dropping `rawLine` were not done; batching alone was enough to bound the peak.

### FINDING-2 (Important, fixed round 1)
- **Severity:** Important
- **Confidence:** 80
- **File:** Tests/UsageCoreTests/RefreshCoordinatorTests.swift (MonthlyRefreshCoordinatorTests)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, commit dad5205)

**What is wrong:**
The re-run condition changed to `collection.start < initialCollection.start`, but no test had a monthly group together with an aligned week that starts before the 1st. That is the case where the re-run is needed and the re-run context must be the widened collection window.

**Why this matters:**
This branch runs at the start of a month whenever a 7-day reset falls in the first week. A regression that re-ran with the weekly window would drop month-to-date records from the monthly group.

**How it was resolved:**
Added `alignedWeekBeforeTheFirstRerunsWithTheWidenedCollection`. It checks one reset, collection starts `[Oct 1, Sep 30 07:00]`, a collection end at the month end, the aligned snapshot window, and that the monthly group counts only October usage.

### FINDING-3 (Important, fixed round 1)
- **Severity:** Important
- **Confidence:** 75
- **File:** Tests/UsageCoreTests/AggregatorTests.swift (MonthlyAggregatorTests)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, commit dad5205)

**What is wrong:**
Every monthly aggregator test used a weekly window inside the month, so filtering the monthly group by its own window and by the collection window gave the same result.

**Why this matters:**
US1 scenario 2 matters in practice during the first days of a month, when the weekly window straddles the 1st. An over-count at each month start would not have been caught.

**How it was resolved:**
Added `weekStraddlingTheFirstSplitsBetweenWeeklyAndMonthlyGroups` with a Sep 28 to Oct 5 window. The weekly group, its member and its trend include Sep 29. The monthly group, its member and its trend (Oct 1 and Oct 2) do not.

### FINDING-4 (Minor, fixed round 1)
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/AgentTacho/BreakdownView.swift:81-108
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** fixed (round 1, commit dad5205)

**What is wrong:** The 7-column wrapping applied to weekly windows too. An aligned week touches 8 local days, so one orphan column moved to a second row.
**Why this matters:** The weekly display changed although the feature was meant to leave weekly groups alone.
**How it was resolved:** Rows wrap after 7 columns only for monthly windows. Weekly trends stay on one row.

### FINDING-5 (Minor, fixed round 1)
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/UsageCore/Snapshot/UsageSnapshot.swift:171-191
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** fixed (round 1, commit dad5205)

**What is wrong:** `GroupEntry` stored both `window` and `resetAt`, with nothing keeping them in sync after `init`.
**Why this matters:** A later edit to `window` would leave `resetAt` stale without warning.
**How it was resolved:** `resetAt` is now computed from `window.end`.

### FINDING-6 (Minor, partly fixed round 1, remaining)
- **Severity:** Minor
- **Confidence:** 72
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift:5-11, Sources/UsageCore/Logs/LogIndex.swift:70-76, Sources/UsageCore/Logs/SessionLogSource.swift:58,69
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** partly fixed (comment and log wording); the rename remains

**What is wrong:** `RefreshContext.window` now holds the collection window, but it keeps a generic name, while the coordinator's local `window` is the weekly one. The LogIndex comment listed an incomplete set of reset causes, and the log lines said "window".
**Why this matters:** The two meanings are easy to mix up in later edits.
**How it was resolved:** The LogIndex comment now names the monthly widening, and the log lines say "collection start". Renaming `RefreshContext.window` to `collectionWindow` would touch every record source and test, so it was left for a human decision.

### FINDING-7 (Minor, fixed round 1)
- **Severity:** Minor
- **Confidence:** 72
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift:351-358
- **Category:** architecture
- **Source:** architecture-agent (also reported by: production-readiness-agent)
- **Resolution:** fixed (round 1, commit dad5205)

**What is wrong:** No log line recorded a monthly group's window or the time zone it was computed in.
**Why this matters:** A month boundary or a time zone move (FR-016) could not be diagnosed from the log.
**How it was resolved:** The per-group line now includes the group's window and `calendar.timeZone.identifier`.

### FINDING-8 (Minor, fixed round 1)
- **Severity:** Minor
- **Confidence:** 72
- **File:** Sources/UsageCore/Notifications/ThresholdTracker.swift:86-97
- **Category:** correctness
- **Source:** correctness-agent
- **Resolution:** fixed (round 1, commit 4eee325)

**What is wrong:** The tracker keyed state by the configuration's period but read values from the snapshot entry. A refresh that ran while the period was switched could set the new key's baseline from the old period's percent. When both windows end at the same instant (a week ending on a Monday the 1st), the stale baseline survived.
**Why this matters:** The first real snapshot could then notify for thresholds already exceeded, against FR-017.
**How it was resolved:** Entries with `entry.period != group.period` are skipped. `snapshotOfTheOldPeriodIsSkippedAfterASwitch` uses the same window in both snapshots, so only the guard makes it pass.

### FINDING-9 (Minor, fixed round 1)
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Notifications/ThresholdTracker.swift:46-50, 105-110
- **Category:** correctness
- **Source:** correctness-agent
- **Resolution:** fixed (round 1, commit 4eee325)

**What is wrong:** A window reset was detected only by a changed end. FR-016 says any change of a monthly group's window start counts, and two time zones can share the offset at the month end but not at the start.
**Why this matters:** The tracker would not re-arm in that edge case.
**How it was resolved:** Group state also stores the window start, and a moved start resets the state. Test `movedWindowStartWithTheSameEndResetsState`.

### FINDING-10 (Minor, fixed round 1)
- **Severity:** Minor
- **Confidence:** 75
- **File:** Tests/UsageCoreTests/ConfigurationTests.swift (BudgetGroupCodingTests)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** fixed (round 1, commit dad5205)

**What is wrong:** Decoding row 2 had no test for an explicit `"period": "weekly"` with only `weeklyBudgetUSD`, and row 5 had no `"monthly"` case.
**Why this matters:** A guard that rejected the legacy amount whenever a period key is present would have passed the suite.
**How it was resolved:** Both cases added.

### FINDING-11 (Minor, remaining)
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/AgentTacho/BreakdownView.swift:85-145
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Resolution:** remaining (needs a human decision on the cell format)

**What is wrong:** A Grid column is as wide as its widest cell across all rows. In a monthly trend each of the 7 columns holds up to 5 days. Cost cells use two-decimal currency ("$1,234.56", about 58 pt), but only about 40 pt per column fits in the 360 pt panel.
**Why this matters:** For heavy users, monthly trends can truncate or wrap, which hurts the readability part of SC-006.
**What needs to happen:** Choose a compact day-cell format (whole dollars or compact notation, with exact values in a tooltip), or derive the columns per row from the widest value. Then check with a 31-day fixture of $100 to $1,500 days.

### FINDING-12 (Minor, fixed in round 1 follow-up)
- **Severity:** Minor
- **Confidence:** 85
- **File:** Tests/UsageCoreTests/ThresholdTrackerTests.swift
- **Category:** test-quality
- **Source:** re-review agent (round 1)
- **Resolution:** fixed (commit 4eee325)

**What is wrong:** The first version of the period-guard test changed both the period and the window start, so the window-start check alone made it pass.
**How it was resolved:** The test now uses the same window in both snapshots.

### FINDING-13 (Minor, fixed in round 1 follow-up)
- **Severity:** Minor
- **Confidence:** 70
- **File:** Tests/UsageCoreTests/LogIndexTests.swift
- **Category:** test-quality
- **Source:** re-review agent (round 1)
- **Resolution:** fixed (commit 800a889)

**What is wrong:** The batching test showed equal output but not that batching happened or where batches split.
**How it was resolved:** `batches(of:maxBytes:)` is internal, and `batchesSplitJobsByUnreadBytes` asserts the boundaries, including oversized files and offsets.

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/Snapshot/Aggregator.swift:5, 28-38
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** The coordinator resolves the weekly and collection windows with its injected `WindowResolver`, while the aggregator creates its own resolver to compute the monthly window.
- **Rationale:** Today the resolver is stateless. If it ever becomes configurable, the collection range and the group filter could diverge. Passing the monthly window into `aggregate` would keep one source of truth.

### NOTABLE-2
- **File:** Sources/UsageCore/Config/Configuration.swift:182-190
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** `BudgetPeriod.windowKind` makes the configuration model depend on the notification tracker's `WindowKind`.
- **Rationale:** An extension in ThresholdTracker.swift would keep the config layer free of one consumer's keying scheme.

### NOTABLE-3
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift:336-349
- **Category:** correctness
- **Source:** correctness-agent
- **Description:** While the record source keeps failing, carried-over group entries keep their old period. A group just switched to monthly then shows weekly wording and a weekly reset (marked stale) until the source recovers.
- **Rationale:** Notifications skip stale entries, so only the display disagrees with FR-014 during the failure. Dropping or relabelling mismatched carried-over entries would remove that.

### NOTABLE-4
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift:56, 88
- **Category:** test-quality
- **Source:** test-quality-agent
- **Description:** The time zone path (FR-016) depends on the default `Calendar.autoupdatingCurrent`, stored as a `let`. No test can change the zone between two refreshes.
- **Rationale:** An injected calendar provider read on each refresh would make the time zone move testable end to end.

## Post-Fix Spec Coverage

The fix round removed no behavior. LogIndex phases moved into a helper, and `resetAt` became computed. All spec requirements verified after fix loop (FR-001 to FR-020, FR-004a).

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| baseline | make test | 0 | 0 | passed (300 tests, 27 suites) |
| 1 | make test | 0 | 0 | passed (305 tests) |
| 1 follow-up | make test | 0 | 0 | passed (306 tests, 27 suites) |

`make build` (app target) also succeeded after round 1.

## Remaining Findings

No Critical or Important findings remain. Two Minor findings remain for a human decision:
- FINDING-6: rename `RefreshContext.window` to `collectionWindow` (broad, mechanical change across record sources and tests).
- FINDING-11: compact day-cell format for the monthly trend (visual design choice).
