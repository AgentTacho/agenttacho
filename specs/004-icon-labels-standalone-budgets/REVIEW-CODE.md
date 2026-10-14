# Code Review: Icon Labels and Standalone Budgets

**Spec:** specs/004-icon-labels-standalone-budgets/spec.md (config format from contracts/config-file.md and data-model.md; base specs specs/001-llm-usage-menubar/spec.md and specs/003-monthly-budget-period/spec.md)
**Date:** 2026-10-14
**Branch:** 004-icon-labels-standalone-budgets
**Reviewer:** Claude (speckit-spex-gates-review-code, ship pipeline stage 7)
**Scope:** `git diff main...HEAD -- Sources Tests README.md`: Sources/UsageCore (Config/Configuration, Config/ConfigStore, Bar/BarLayout (new), Notifications/ThresholdTracker, Snapshot/Aggregator, Snapshot/RefreshCoordinator, Snapshot/UsageSnapshot, Windows/WindowResolver), Sources/LLMUsageMenuBar (AccountSettingsView, App, BarLabel, DropdownView, IconFont, IconPickerSheet, SettingsView), the tests, and README.md

## Compliance Summary

**Overall Score: 100%** (before the fix loop)

- Functional Requirements: 21/21 (FR-001 to FR-020, including FR-018a)
- Edge Cases: 9/9
- Acceptance scenarios: US1 4/4, US2 5/5, US3 4/4, US4 3/3 traced to code; most are covered by tests (ConfigurationTests, BarLayoutTests, AggregatorTests, ThresholdTrackerTests, RefreshCoordinatorTests).
- Success Criteria: SC-002 to SC-005 are verified by code and tests. SC-001 is a UI timing goal that was not measured.
- Spec-declared constants: the spec has no `## Constants` section, so this check was skipped.
- Baseline `make test`: 343 tests in 36 suites passed.

## Detailed Review

### Functional Requirements

| Requirement | Implementation | Status | Notes |
|-------------|---------------|--------|-------|
| FR-001 exactly one icon, no text label | Account.icon / BudgetGroup.icon (String); label removed from model, encoder and UI | Compliant | |
| FR-002 defaults, changeable, not removable | IconDefaults; NewAccountSheet initial icon, newGroupIcon; IconField (no Remove); IconPickerSheet ("No icon" removed) | Compliant | Provider change resets the default until the user picks an icon |
| FR-003 duplicates allowed | Configuration.validate (uniqueness check removed) | Compliant | |
| FR-004 icon + name in settings/dropdown, icon + percent in bar, names in plain text | labelText/pickerText; BarLayout BarItem.name; BarItem.text; ThresholdCrossing.entityName; RefreshCoordinator log uses owner.name | Compliant | |
| FR-005 unknown icon invalid | Configuration.validate checkIcon | Compliant | |
| FR-006 legacy loads, default icon, label ignored | Account.init(from:), BudgetGroup.init(from:) | Compliant | absent, null and "" fall back |
| FR-007 no label written, no rewrite on load | encode(to:) of Account and BudgetGroup; ConfigStore.load never writes | Compliant | |
| FR-008 exactly one of group and own budget | Account.init(from:) throws on both or neither | Compliant | Decode error, file rejected |
| FR-009 own budget settings and validation | BudgetSettings; checkBudget shared with groups | Compliant | |
| FR-010 own budget in dropdown | Aggregator accountBudgets; DropdownView BudgetSection for own-budget accounts; BudgetFields | Compliant | |
| FR-011 own budget in bar | BarLayout.segments / budgetItem | Compliant | |
| FR-012 own budget thresholds | ThresholdTracker over budgetOwners, scope .account | Compliant | |
| FR-013 create: existing group, new group, own budget | NewAccountSheet BudgetChoice; new own budget weekly, shown, [80, 100] | Compliant | |
| FR-014 switch both directions, prefill, delete empty group | Configuration.movingAccountToOwnBudget / movingAccountToGroup; TokenBasedEditor budgetChoice | Compliant | Settings applies edits as they are made (existing behavior), so "edit before saving" means the prefilled budget can be edited right away |
| FR-015 drop state, baseline after change | ThresholdTracker memberIds reset, skipped old-member-set snapshots, liveKeys cleanup | Compliant | |
| FR-016 member shown-in-bar, off by default | TokenMembership.group(shownInBar:), decoder default false | Compliant | |
| FR-017 member percent of group budget | GroupEntry.memberSpendUSD / memberPercent | Compliant | |
| FR-018 member styling, no notifications, follows group data state | BarLayout.memberItem | Compliant | |
| FR-018a dropdown member share | BudgetSection member row | Compliant | |
| FR-019 members after group, or in its place | BarLayout.segments | Compliant | |
| FR-020 bar order | BarLayout.segments | Compliant | |

### Edge Cases

| Edge case | Status | Location |
|-----------|--------|----------|
| Duplicate icons in the bar | Compliant | BarLayout config order |
| Unknown icon | Compliant | validate checkIcon |
| Group and own budget together | Compliant | Account.init(from:) |
| Neither group nor own budget | Compliant | Account.init(from:) |
| Member shown, group hidden | Compliant | BarLayout.segments |
| Several members shown | Compliant | members(of:) order |
| Over-budget share | Compliant | PercentFormatter.rounded uncapped |
| Mid-window move | Compliant | ThresholdTracker member set and scope keys |
| Unassigned entry | Compliant | unchanged UnassignedSection; never in bar |

### Extra Features (Not in Spec)

- `ThresholdTracker.Scope` keeps a group and an own-budget account with the same hand-edited id apart. Helpful hardening, no behavior change for valid files.
- `IconFont.image` draws icons as template images for native picker menus. Supports FR-004 in menus.

## Recommendations

### Critical (Must Fix)
- None from the compliance check.

### Spec Evolution Candidates
- None.

## Deep Review Report

**Gate: PASS** (after fix round 1 of 3). Details: [review-findings.md](review-findings.md).

| Agent                   | Found | Fixed | Remaining | Status |
|-------------------------|-------|-------|-----------|--------|
| Correctness             |     1 |     1 |         0 | completed |
| Architecture & Idioms   |    10 |     3 |         7 | completed (incl. 1 Notable) |
| Security                |     3 |     1 |         2 | completed (incl. 1 Notable) |
| Production Readiness    |     4 |     0 |         4 | completed (incl. 1 Notable) |
| Test Quality            |     6 |     0 |         6 | completed (incl. 1 Notable) |
| Re-review (round 1)     |     1 |     0 |         1 | completed |
| Goal Alignment          |     0 |     0 |         0 | skipped (no PR found) |
| CodeRabbit (external)   |     0 |     0 |         0 | failed (service: "Failed to start review", 2 attempts) |
| Copilot (external)      |     0 |     0 |         0 | skipped (disabled in config) |
| Codex (external)        |     0 |     0 |         0 | failed (usage limit until 2026-10-17) |
| Test Suite (regression) |     0 |     0 |         0 | passed (344 tests) |
| **Total**               |  **25** | **5** | **20** | |

By severity: Critical 0; Important 1 found, 1 fixed; Minor 20 found, 4 fixed, 16 remaining; Notable 4.

MVP: Architecture & Idioms (10 findings)

Key fixes applied (commit b5aa587):
1. Validation rejects duplicate account ids and duplicate group ids (new `duplicateId` kind); the refresh coordinator no longer traps on duplicate subscription ids (security).
2. A member's share is nil for an account the group entry predates, so the bar shows the placeholder with the group's stale flag and the dropdown omits the percent instead of showing 0% (correctness, FR-018).
3. Error kind `invalidLabel` renamed to `unknownIcon`; `BudgetPeriod` doc comments and two README sentences now cover own budgets (architecture).

Remaining findings needing a human decision (all Minor):
- Sources/UsageCore/Config/Configuration.swift:625 `checkBudget` accepts tiny amounts such as 1e-20, giving overflowed percents; a minimum (for example one cent) is a rule the spec does not define.
- Sources/LLMUsageMenuBar/NotificationPresenter.swift:64 notification dedup and identifiers have no owner scope, so a hand-edited group and own-budget account sharing an id could replace each other's notification; either add the scope to `ThresholdCrossing` or reject group/account id overlap in validation.

Other remaining Minor findings are naming, duplication, observability and extra test cases (FINDING-8 to FINDING-21 in review-findings.md).

Post-fix spec coverage: 21/21 requirements verified, none dropped. Compliance score after the fix loop: 100%.
