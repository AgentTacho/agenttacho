# Deep Review Findings

**Date:** 2026-11-10
**Branch:** 044-no-limit-groups
**Rounds:** 1 (re-run after the cleanup round)
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline)

The first run of this gate (findings FINDING-1 to FINDING-12 and NOTABLE-1 to NOTABLE-6 of that run) ended PASS. Its cleanup round resolved all of them except its FINDING-11, two breakdown passes per group without an amount, which stays with the idea inbox entry `single-pass-no-amount-aggregation`. Its Notables are in `brainstorm/idea-inbox.md`. This file records the re-run that reviewed the cleanup round and the whole feature diff again.

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 2 | 2 | 0 |
| Minor | 7 | 5 | 2 |
| Notable | 0 | - | 0 |
| **Total** | **9** | **7** | **2** |

**Agents completed:** 5/5 internal (Goal Alignment skipped: no PR) + 2 external tools (CodeRabbit, Codex; Copilot disabled in config)
**Agents failed:** none

Fix commits: `6ae64a1 fix(groups): member tables of a group without an amount rank by its measure`, `3a555b1 refactor(settings): the budget editor reads its enabling rules from OwnBudgetForm`. `make test` passed after the fix round (2720 + 79 tests). A re-review of the fix round (one combined agent and Codex on the uncommitted diff) found nothing.

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/AgentTacho/DropdownView.swift:1209-1215
- **Category:** external
- **Source:** codex
- **Round found:** 1
- **Resolution:** fixed (round 1, 6ae64a1)

**What is wrong:** Under a Tokens headline of a group without an amount, the member tables behind "Show account details" got the member's priced breakdown. Its projects are ordered by cost, and `topProjects(byCost: false)` keeps that order, so the top five could leave out the member's highest-token projects. The group's own Details use a token-ranked breakdown.

**Why this matters:** FR-014 says the member tables use the same measure as the group's Details. A member with many projects showed a token table that was not the top five by tokens.

**How it was resolved:** `TokenAccountEntry` gained `tokenBreakdown`, which the Aggregator computes only for members of a group without an amount. `details(showsCost:)` returns it under Tokens, as `NoLimitEntry.details(showsCost:)` does. `NoLimitSection.memberTables` reads it. Test `memberTablesRankByTheGroupsMeasure`: a cheap high-token project ranks first under Tokens and second under Money, and a member of a group with an amount has no token breakdown.

**External tool analysis (Codex, P2):**
> When a group without an amount selects Tokens and a member has projects whose cost ranking differs from their token ranking, this passes the member's priced breakdown into Details. The token view hides costs but `topProjects(byCost: false)` still takes its top five from the cost-sorted projects, so it can omit the member's highest-token projects, unlike the group's token-only Details. Pass a token-only member breakdown in Tokens mode so member tables use the same measure as the group.

### FINDING-2
- **Severity:** Important
- **Confidence:** 85
- **File:** Sources/UsageCore/Config/GroupBudgetForm.swift:53-71; Tests/UsageCoreTests/GroupBudgetFormTests.swift:54-103, 130-132
- **Category:** architecture
- **Source:** architecture-agent (also reported by: test-quality-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1, 3a555b1)

**What is wrong:** After `GroupBudgetFields` started rendering `OwnBudgetFields`, the rule members of `GroupBudgetForm` (`thresholdsEnabled`, `shownInBarEnabled`, `shownInBarDisplayed`, `amountError`, `needsBudgetHelp`, `valueAsEnabled`, `valueAsHelp`, `amountPlaceholder`) had no production caller. The editor applied its rules inline in the SwiftUI view. The FR-016 tests checked the unused copy, and two assertions compared a value with itself.

**Why this matters:** Constitution II and FR-015 want the rules in tested core logic that the view uses. The tested rules were not the applied ones, so the editor could drift with every test green.

**How it was resolved:** `OwnBudgetForm` gained `budgetControlsEnabled`, `budgetControlsHelp`, `valueAsEnabled` and `valueAsHelp`, and `OwnBudgetFields` reads them for both editors. `GroupBudgetForm` keeps only its fields, `init`, `applied(to:)` and `ownForm`. Its tests read `ownForm` with literal expectations, and `OwnBudgetFormTests.enablingRulesFollowTheAmount` pins the new rules.

### FINDING-3
- **Severity:** Minor
- **File:** Tests/UsageCoreTests/GroupBudgetFormTests.swift:108-133
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** fixed (round 1, 3a555b1)

The `ownForm` round trip did not check icon or time format, and the fixture used the default time format. The fixture now uses `.absolute`, and the test compares the whole group.

### FINDING-4
- **Severity:** Minor
- **File:** Tests/UsageCoreTests/ArrangementTests.swift:330-335
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** fixed (round 1, 3a555b1)

`memberShareToggle` now depends on the `?? true` default of `offersShownInBar` for a member whose group is missing, and only monthly groups were tested. Added a dangling group id (enabled, no help) and a weekly group's help text.

### FINDING-5
- **Severity:** Minor
- **File:** Sources/UsageCore/Config/AccountBudgetDescription.swift:29-33
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** fixed (round 1, 3a555b1)

The `memberSpend` doc said "$1" rather than "<$1" below one dollar, but a spend below 50 cents reads "$0". Reworded.

### FINDING-6
- **Severity:** Minor
- **File:** Sources/UsageCore/Dropdown/MemberLineText.swift:66, 83
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** fixed (round 1, 3a555b1)

`withAmount` and `withoutAmount` were public although only `lines` calls them, inviting the app to bypass the `MemberDisplay` rule. They are internal now; tests reach them through `@testable import`.

### FINDING-7
- **Severity:** Minor
- **File:** Sources/AgentTacho/DropdownView.swift:1053-1057, 1199-1202
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** fixed (round 1, 6ae64a1 and 3a555b1)

Both `memberDisplay` doc comments said the property decides the member lines, which now come from `MemberLineText.lines`. Reworded to the member tables, naming `lines` as the source of the lines.

### FINDING-8
- **Severity:** Minor
- **Confidence:** 72
- **File:** Sources/UsageCore/Notifications/ThresholdTracker.swift:170-179
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Resolution:** remaining

**What is wrong:** The threshold state of a group is dropped only when an observation runs while the group has no amount. If the user clears the amount and enters a new one within one running refresh (the save debounce is 600 ms, a local refresh can take seconds), no observation sees the group without an amount. The old `lastPercent` survives, and the follow-up refresh against the new amount can notify thresholds at once instead of setting a baseline (FR-005, US4 scenario 2).

**Why it stays:** It needs two saves inside one refresh, and own budgets have had the same race since spec 043 FR-009. The fix belongs in the tracker for both kinds of owner: compare the entry's amount with the owner's, or drop owner keys on a configuration change, as `credentialTracker.configurationChanged` does. That is a change to shared notification code beyond this feature's scope.

### FINDING-9
- **Severity:** Minor
- **Confidence:** 72
- **File:** Tests/UsageCoreTests/HeadlineTextTests.swift:222-230
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** remaining

**What is wrong:** `memberLinesStayAsUnderAutomatic` no longer loops over the Show settings and directions. It calls the share rule once and duplicates a `MemberLineTextTests` case.

**Why it stays:** The guarantee is structural. `MemberLineText.Rule.share` takes no measure or direction, and `BudgetSection` exists only for groups with an amount, so the Show setting cannot reach a member line there. Moving the rule choice into core for a test would add an API without a behavior to pin. The test's doc comment states this. Deleting the duplicate is optional.

## Informational: acceptance scenario coverage (test-quality-agent)

Every acceptance scenario of User Stories 1 to 4 and FR-024 maps to at least one test. The view-only parts are the US1-4 member tables (now ranked by the core `details(showsCost:)`, FINDING-1) and US3-3's unchanged amount line and bar for a group, which reuse the spec 043 code for accounts. US2-1 and US2-3 now test the rules the editor reads (FINDING-2).

## Post-Fix Spec Coverage

The fix round removed code: the rule members of `GroupBudgetForm`. FR-016 is still implemented, now through `OwnBudgetForm.budgetControlsEnabled`, `budgetControlsHelp`, `valueAsEnabled` and `valueAsHelp`, read by `OwnBudgetFields` for groups too. All spec requirements were verified after the fix loop (FR-001 to FR-025). FR-014 is now also met for member tables with many projects under Tokens.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| 1 | make test | 0 | 0 | passed (2720 tests in 297 suites, 79 tests in 7 suites) |

The test suite passed in all fix rounds.
