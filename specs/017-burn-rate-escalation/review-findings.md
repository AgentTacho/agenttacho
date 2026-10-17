# Deep Review Findings

**Date:** 2026-10-16
**Branch:** 017-burn-rate-escalation
**Rounds:** 1 (fix round 1, re-review clean of Critical and Important)
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline, review-code stage)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 1 | 1 | 0 |
| Minor | 11 | 3 | 8 |
| Notable | 2 | - | 2 |
| **Total** | **14** | **4** | **10** |

**Agents completed:** 5/6 internal (Goal Alignment skipped: no pull request for the branch) + Codex (external)
**Agents failed:** CodeRabbit (rate limit exceeded on both attempts in this pass; see History)
**Skipped:** Copilot (disabled in config, CLI not installed)

The review agents ran in parallel (teams extension not enabled, but the harness supports parallel dispatch; each agent had an isolated context and only the spec and the code).

## History

This is the second deep review pass of the feature. The first pass ran the review and its fix loop but did not write this file or the report section in REVIEW-CODE.md. Its outcome, for the record:

- Commit 2757ff1 `fix(pace): discard budget observations when a reprice lands mid-refresh`: a price import during an in-flight refresh could show a transient false "↑"; a reprice requested while a refresh runs now discards the budget observations of that refresh and of the follow-up refresh.
- Commit a64af21 `refactor(pace): derive pace and burn rate from one set of inputs`: one `PaceInputs` source for pace and burn rate; the fast run-out at the average rate reuses spec 011's run-out; `CodexLimitsEntry.barWindow`; observations after a backward clock step are dropped (`futureTolerance`); `Pace.usesAttentionColor` moved into the core; observation log types made internal; new SC-002 hand-calculation tests and recent-rate bar tests.
- Commit 43f5237 `test(pace): tighten burn rate tests after re-review`.
- External results of the first pass: CodeRabbit 0 findings (`coderabbit.txt`, and round 1 on a64af21..43f5237: 0 findings); Codex first run no actionable issues; a later Codex P1 "Restore the documented public burn-rate API" was rejected as a false positive (the types are new on this branch, nothing released depends on them).

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 85
- **File:** Sources/UsageCore/Pace/BurnRate.swift:122-123, 147-148; Sources/UsageCore/Pace/ObservationLog.swift:90-93
- **Category:** correctness
- **Source:** codex (also confirmed by the fix-round re-review)
- **Round found:** 1
- **Resolution:** fixed (round 1, commit 74e8948)

**What is wrong:**
`BurnWindowKey.budget(String)` identified a budget by owner id only. `burnWindowKeys` dropped the own-budget key whenever a group had the same id (`accountBudgets.keys.filter { groups[$0] == nil }`), `burnInputs(for: .budget(id))` preferred `groups[id]`, and budget fingerprints were stored per id.

**Why this matters:**
A group and an account with its own budget may share an id (spec 008, `Configuration.swift` around line 747, `Arrangement`). In that configuration the own budget never recorded observations, and its bar entry and dropdown meter showed the group's burn rate: a wrong "↑" or a missing one (FR-003, FR-008, FR-012).

**How it was resolved:**
The key has separate cases `.group(String)` and `.accountBudget(String)`. `UsageSnapshot.budgetEntry(for:)` resolves a budget key without any cross-dictionary fallback; `burnWindowKeys` emits both keys; fingerprints are keyed by `BurnWindowKey`; `BarLayout.budgetItem` receives the key from its caller (account path or group path); the dropdown's `BudgetSection` picks the case by `isGroup`. New tests: `groupAndOwnBudgetWithTheSameIdStaySeparate` (BurnRateTests, ObservationLogTests) and `sharedIdBudgetsFollowTheirOwnBurnRate` (BarLayoutTests). data-model.md and research.md R2 updated.

**External tool analysis (Codex):**
> [P2] Qualify budget burn keys by owner kind. A group and an account are explicitly allowed to share an id, but this filter drops the own-budget key whenever a group has that id. `burnRate(for: .budget(id))` also prefers the group, so the account's bar and dropdown can use the group's observations and fast-burn result, or never record its own observations at all. Include the owner kind in the budget key (and its fingerprint/lookup call sites) so the two valid budget owners remain independent.

### FINDING-2
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/UsageCore/Pace/ObservationLog.swift:130; Sources/UsageCore/Pace/BurnRate.swift:35
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, commit 74e8948)

**What is wrong:** `recentRate` converted to points per hour with a literal `3600` while `BurnRate` used a private `secondsPerHour`.
**Why this matters:** the recent rate is compared with the sustainable rate; two copies of the unit conversion could drift.
**How it was resolved:** `BurnRate.secondsPerHour` is internal and used by `recentRate`.

### FINDING-3
- **Severity:** Minor
- **Confidence:** 80
- **File:** specs/017-burn-rate-escalation/research.md:11
- **Category:** architecture
- **Source:** fix-round re-review
- **Round found:** 2 (re-review)
- **Resolution:** fixed (round 1 follow-up, commit 74e8948)

**What is wrong:** research R2 still described `.budget(ownerId)` with the false reason "group ids and account ids are distinct".
**Why this matters:** the recorded rationale would invite merging the cases again.
**How it was resolved:** R2 now names `.group` and `.accountBudget` with the spec 008 reason.

### FINDING-4
- **Severity:** Minor
- **Confidence:** 75
- **File:** Tests/UsageCoreTests/BarLayoutTests.swift (BurnRateBarLayoutTests)
- **Category:** test-quality
- **Source:** fix-round re-review
- **Round found:** 2 (re-review)
- **Resolution:** fixed (round 1 follow-up, commit 74e8948)

**What is wrong:** no bar-level test covered a group and an own budget with the same id.
**Why this matters:** the snapshot and log tests did not check that each bar item receives its own owner kind.
**How it was resolved:** `sharedIdBudgetsFollowTheirOwnBurnRate`: own budget "x" at 50% burns fast, group "x" at 25% is on pace; items looked up by name.

### FINDING-5
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/UsageCore/Bar/BarLayout.swift:24-52; Sources/UsageCore/Bar/BarPresentation.swift:101
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** `BarItem` carries `runOutMarker` and `burnsFast` as two Bools; the invariant "burnsFast only with runOutMarker" is documented but not enforced, and each consumer repeats the nesting.
**Why this matters:** four representable states for three valid ones.
**What needs to happen:** optionally replace both with one marker enum (`none`, `runOut`, `burnsFast`). Not a behavior issue: `BarLayout.markers` is the only producer and always sets them consistently.

### FINDING-6
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/UsageCore/Pace/ObservationLog.swift:22-46; Sources/UsageCore/Pace/BurnRate.swift:37-42, 57-58
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** hand-written memberwise initializers on internal types, `var` fields that are never mutated, a misaligned continuation line.
**What needs to happen:** optional cleanup (synthesized inits, `let` fields, re-indent).

### FINDING-7
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/AgentTacho/DropdownView.swift:70-71, 594-599, 613-618
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** `CodexPlanSection` takes `limits`, `now` and `snapshot`, two of which are projections of the third, unlike its sibling sections.
**What needs to happen:** optionally derive `limits` and `now` from `snapshot` inside the view.

### FINDING-8
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift:128-138, 283-289, 322-325
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** `overridesChangedInLastRefresh` is a hidden output of `performRefresh` passed through actor state.
**Why this matters:** correct today (single run loop, written before the first suspension), but the coupling is implicit.
**What needs to happen:** optionally return the flag from `performRefresh`.

### FINDING-9
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift:285-295
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** the diagnostic log records nothing about burn-rate transitions or observation discards.
**Why this matters:** a "wrong ↑" report cannot be diagnosed after the fact, since the log is in memory only.
**What needs to happen:** a follow-up could log one line per key when `burnsFast` changes and when observations are discarded (no new files or requests, so FR-013 holds). The spec requires no such log lines.

### FINDING-10
- **Severity:** Minor
- **Confidence:** 80
- **File:** Tests/UsageCoreTests/BarLayoutTests.swift:672-685 (`noBarPercentNoMarker`)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** the test claims to cover the `let pace` guard in `markers()` but would pass without it, because the 7-day key has no burn inputs either.
**What needs to happen:** rename it or document the guard as defensive.

### FINDING-11
- **Severity:** Minor
- **Confidence:** 75
- **File:** Tests/UsageCoreTests/BarLayoutTests.swift:818-835 (`recentBurstFollowsTheSuppressionRules`)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** the stale loop's `"own"` case passes vacuously (a stale budget never has a recent rate); stale suppression of a budget is covered on the average path in `suppressedLikeTheRunOutMarker`.
**What needs to happen:** drop `"own"` from the loop or assert its non-fast burn rate explicitly.

### FINDING-12
- **Severity:** Minor
- **Confidence:** 75
- **File:** Tests/UsageCoreTests/BurnRateTests.swift:387-434; ObservationLogTests.swift:294-297, 330-340
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** SC-002 hand calculations through `UsageSnapshot.burnRate(for:)` cover the average path for every kind; the recent path is checked at `BurnRate.compute` level (including run-out anchoring at the newest observation) and through `burnsFast` end to end, but not the fast run-out value per kind. US1 AS3 (monthly budget) and AS4 (short span, average decides) are covered in parts rather than end to end.
**What needs to happen:** optional end-to-end tests per kind for the recent-rate run-out.

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/Pace/ObservationLog.swift:88-96, 134-145
- **Category:** correctness
- **Source:** correctness-agent
- **Description:** Configuration edits other than amount, period, members and prices (log directories, Codex homes, OpenCode directories, attribution) can make a budget's spend jump without new usage, and they do not discard the observations, so a false "↑" can show for up to an hour.
- **Rationale:** a gap in the spec's list (FR-003 names amount, period, members and prices only), not a deviation. Captured to brainstorm/idea-inbox.md.

### NOTABLE-2
- **File:** Sources/AgentTacho/DropdownView.swift; Sources/UsageCore/Pace/BurnRate.swift:94-99, 127-134
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** dropdown rows compute the pace from the row's value and the burn rate again from a key; a single value carrying both would remove the double resolution. Some burn-rate constants and `barWindow(now:)` are public but used only inside UsageCore, matching spec 011's habit.
- **Rationale:** design follow-up. Captured to brainstorm/idea-inbox.md.

## Goal Alignment

Skipped: no pull request exists for the branch.

## Post-Fix Spec Coverage

The fix removed the `.budget` case and the id filter in `burnWindowKeys`, so the coverage check ran:

| Requirement | Implementation | Status |
|-------------|---------------|--------|
| FR-001, FR-002 rates | `BurnRate.compute` | ✓ |
| FR-003 observation log | `ObservationLog.updated`, fingerprints per `BurnWindowKey`, `RefreshCoordinator` price flags | ✓ |
| FR-004 recent rate | `ObservationLog.recentRate` | ✓ |
| FR-005 to FR-007 escalation, fast run-out | `BurnRate.compute` | ✓ |
| FR-008, FR-009 bar marker and suppression | `BarLayout.markers`, `budgetItem(key:)`, `BarPresentation` | ✓ |
| FR-010 toggle label and preview | `MenuBarSettingsTab` | ✓ |
| FR-011 accessibility | `BarItem.accessibilitySuffix` | ✓ |
| FR-012 dropdown text and color | `Pace.summary`, `Pace.usesAttentionColor`, `PaceMeter(burn:)` on every row | ✓ |
| FR-013, FR-014 constraints, README | no new I/O; README unchanged by the fix | ✓ |
| FR-015 tested core | logic in UsageCore | ✓ |

All spec requirements verified after the fix loop.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| baseline | make test | 0 | 0 | passed (1028 tests) |
| 1 | make test | 0 | 0 | passed (1030 tests) |
| 1 follow-up | make test | 0 | 0 | passed (1031 tests) |

`make app` also built and signed the app after round 1. Test suite passed in all fix rounds.

## Remaining Findings

None Critical or Important. Minor FINDING-5 to FINDING-12 are optional cleanups and test refinements; the two Notable observations are in brainstorm/idea-inbox.md.
