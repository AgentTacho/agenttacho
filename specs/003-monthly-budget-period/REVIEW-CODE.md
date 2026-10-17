# Code Review: Monthly Budget Period

**Spec:** specs/003-monthly-budget-period/spec.md (config format from contracts/config-file.md and data-model.md; base spec specs/001-agenttacho/spec.md)
**Date:** 2026-10-14
**Branch:** 003-monthly-budget-period
**Reviewer:** Claude (speckit-spex-gates-review-code, ship pipeline stage 7)
**Scope:** `git diff main...HEAD -- Sources Tests README.md`: Sources/UsageCore (Config/Configuration, Notifications/ThresholdTracker, Snapshot/Aggregator, RefreshCoordinator, UsageSnapshot, Windows/WindowResolver; Logs/LogIndex and SessionLogSource after the fix loop), Sources/AgentTacho (AccountSettingsView, BreakdownView, DropdownView, SettingsView), the tests, and README.md

## Compliance Summary

**Overall Score: 100%** (before and after the fix loop)

- Functional Requirements: 21/21 (FR-001 to FR-020, including FR-004a)
- Edge Cases: 10/10
- Success Criteria: SC-002, SC-003, SC-004 and SC-005 are verified by code and tests. SC-006 timing was measured on real logs (31-day full collect 3.5 s, incremental 0.23 s). Trend readability for very large daily amounts is open as a Minor finding (FINDING-11). SC-001 is a UI timing goal that was not measured.
- Spec-declared constants: the spec has no `## Constants` section, so this check was skipped.

## Detailed Review

### Functional Requirements

| Requirement | Implementation | Status | Notes |
|-------------|---------------|--------|-------|
| FR-001 one period, one amount > 0 | BudgetGroup.period, budgetUSD; Configuration.validate | Compliant | |
| FR-002 absent period means weekly; new groups weekly | BudgetGroup.init(from:); NewAccountSheet newGroupPeriod = .weekly | Compliant | |
| FR-003 legacy file loads unchanged | BudgetGroup.init(from:) legacy weeklyBudgetUSD path | Compliant | ConfigStore and contract-example tests |
| FR-004 save writes new form, no rewrite on load | BudgetGroup.encode(to:); ConfigStore.load never writes | Compliant | |
| FR-004a decoding table | BudgetGroup.init(from:) | Compliant | Every row tested after the fix loop |
| FR-005 month window at local midnight | WindowResolver.monthWindow (calendar.dateInterval(of: .month)) | Compliant | 28 to 31 days and DST tested |
| FR-006 independent of resets and fallback | Aggregator.groupWindow(.monthly) | Compliant | US1 scenario 4 tested |
| FR-007 weekly unchanged | WindowResolver.resolve untouched | Compliant | |
| FR-008 usage inside the group's own window | Aggregator.inWindow per group and member account | Compliant | Straddling-week test added |
| FR-009 Unassigned weekly, subscriptions unaffected | Aggregator (weekly window for Unassigned and subscription breakdowns) | Compliant | |
| FR-010 period change at next refresh | needsRefresh includes period; collection window per refresh | Compliant | |
| FR-011 dropdown values and rules | GroupSection, PercentFormatter | Compliant | |
| FR-012 bar entry | unchanged bar path reads group percent | Compliant | |
| FR-013 breakdown and trend over the month | Aggregator.groupWindow lastDay = min(today, month end); BreakdownView day labels | Compliant | |
| FR-014 labels follow the period | BudgetPeriod.adjective, perUnit, budgetLabel; NotificationPresenter via WindowKind.displayName | Compliant | |
| FR-015 crossing rules, "monthly" in notifications | ThresholdTracker key per period; WindowKind.monthly | Compliant | |
| FR-016 reset on month rollover or moved start | ThresholdTracker resets on window end or start change; Calendar.autoupdatingCurrent | Compliant | Start check added in the fix loop |
| FR-017 period switch resets with baseline | Key per period; old-period snapshots skipped | Compliant | Guard added in the fix loop |
| FR-018 period picker in edit and create | PeriodPicker in GroupEditor and NewAccountSheet | Compliant | |
| FR-019 reject amount <= 0, message names period | GroupEditor inline message; validate() message uses budgetLabel | Compliant | |
| FR-020 week settings visible with note | GeneralSettingsTab note | Compliant | |

### Edge Cases

All 10 edge cases are handled. The tests cover month lengths, DST, the time zone (in the resolver, and the tracker reset on a moved window), switching periods mid-window, launching mid-month, logs past retention (only what the logs contain is counted), mixed weekly and monthly groups, months with no usage, invalid hand edits, and Unassigned staying weekly.

### Extra Features (Not in Spec)

- The diagnostic log names each group's period, window and time zone. This is a helpful addition for FR-016 diagnosis.
- LogIndex reads in byte-bounded batches (added in the fix loop). It is an internal performance safeguard with no behavior change.

## Code Quality Notes

The decoding table maps directly onto spec FR-004a. Per-group windows are confined to the aggregator. The collection window keeps record sources unaware of periods.

## Recommendations

### Critical (Must Fix)
- None.

### Spec Evolution Candidates
- None. The code matches the spec.

### Optional Improvements
- The 2 remaining Minor findings in review-findings.md (FINDING-6 rename, FINDING-11 compact trend cells).
- The 4 Notable observations, captured in brainstorm/idea-inbox.md.

## Conclusion

Compliance is 100%, and no Critical or Important findings remain. Ready for verification.

## Deep Review Report

**Gate: PASS** (after fix round 1)
**Agents completed:** 5/5 internal + 1 re-review agent (round 1)
**Skipped:** Goal Alignment (no PR), Copilot (disabled in config)
**Failed:** CodeRabbit (3 runs, "Failed to start review", no findings), Codex (usage limit, no findings)

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 3 | 3 | 0 |
| Minor | 10 | 8 | 2 |
| Notable | 4 | - | 4 |
| **Total** | **17** | **11** | **6** |

Review Agents:

| Agent                   | Found | Fixed | Remaining | Status    |
|-------------------------|-------|-------|-----------|-----------|
| Correctness             |     3 |     2 |         1 | completed |
| Architecture & Idioms   |     6 |     3 |         3 | completed |
| Security                |     1 |     1 |         0 | completed |
| Production Readiness    |     3 |     2 |         1 | completed |
| Test Quality            |     4 |     3 |         1 | completed |
| Re-review (round 1)     |     2 |     2 |         0 | completed |
| Goal Alignment          |     0 |     0 |         0 | skipped (no PR found) |
| CodeRabbit (external)   |     0 |     0 |         0 | failed (service error, 3 runs) |
| Copilot (external)      |     0 |     0 |         0 | skipped (disabled in config) |
| Codex (external)        |     0 |     0 |         0 | failed (usage limit) |
| Test Suite (regression) |     0 |     0 |         0 | passed (306 tests, 27 suites) |
|-------------------------|-------|-------|-----------|-----------|
| Total                   |    19 |    13 |         6 |           |

The per-agent rows count two findings twice: the LogIndex memory issue (Security and Production Readiness) and the missing window logging (Architecture and Production Readiness). The severity table above is deduplicated. Remaining counts include Notable observations. The architecture rename (FINDING-6) counts as remaining because only its comment and log parts were fixed.

Agent Leaderboard MVP: Architecture & Idioms (6 findings)

Key fixes applied:
1. LogIndex reads, parses and merges in batches of at most 64 MB. Month-long full re-read peak RSS dropped from 1,273 MB to 455 MB on real logs (production-readiness, security).
2. Coordinator test for an aligned week that starts before the 1st with a monthly group (test-quality).
3. Aggregator test for a weekly window straddling the 1st (test-quality).
4. The threshold tracker skips snapshots computed for the old period, and resets when the window start moves (correctness, FR-016, FR-017).
5. Weekly day trends stay on one row; only monthly trends wrap after 7 columns (architecture).
6. `GroupEntry.resetAt` is derived from `window.end` (architecture).
7. Per-group log line includes the group window and time zone; log wording says "collection start" (architecture, production-readiness).
8. Decoding table rows completed (test-quality); batching and period-guard tests tightened (re-review).

Post-fix spec coverage: 21/21 requirements verified, all covered.

Notable observations: 4 captured to brainstorm/idea-inbox.md

Details: specs/003-monthly-budget-period/review-findings.md
