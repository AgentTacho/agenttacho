# Deep Review Findings

**Date:** 2026-11-03
**Branch:** 043-unified-token-accounts
**Rounds:** 0 (no Critical or Important findings, so no fix loop was needed; 7 Minor findings fixed directly)
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline, review-code stage)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 0 | 0 | 0 |
| Minor | 17 | 7 | 10 |
| Notable | 3 | - | 3 |
| **Total** | **20** | **7** | **13** |

**Agents completed:** 5/5 internal (Goal Alignment skipped: no PR), plus 2 external tools (CodeRabbit 0 findings, Codex 0 findings). Copilot disabled in config.
**Agents failed:** none. The first CodeRabbit call used `--files`, which CLI 0.7.6 does not support; it was rerun with `--base main --committed`.

## Findings

### FINDING-1
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/UsageCore/Snapshot/Aggregator.swift:79-86, Sources/AgentTacho/DropdownView.swift:1237
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** fixed (03b9f6e)

**What is wrong:** `NoLimitEntry.breakdown` is always priced, and the section passed it to `BreakdownView` for both measures. A priced breakdown sorts projects and harnesses by cost first, so token Details under a Tokens headline ranked by a cost the section does not show.

**Why this matters:** FR-014 says token Details look like spec 041's. On an account that mixes free and priced models with "Dropdown shows" set to Tokens, a large free project could end up in "Other" while a small priced one was listed.

**How it was resolved:** `NoLimitEntry` now also keeps the token-only breakdown that the aggregator already computes, and `details(showsCost:)` picks the breakdown for the measure shown. The view calls it. A new test, `detailsRankByTheShownMeasure`, checks both orders.

### FINDING-2
- **Severity:** Minor
- **Confidence:** 90
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift:811-817
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Round found:** 1
- **Resolution:** fixed (51269f0)

**What is wrong:** The refresh log line for an account without an amount logged only its tokens. It left out the spend and the unpriced models, and those decide the Automatic headline and the note.

**Why this matters:** A report like "my free account suddenly shows $3" could not be explained from the log.

**How it was resolved:** The line now adds "<spent> USD spent" and the unpriced models.

### FINDING-3
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/UsageCore/Config/Configuration.swift:778-781
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Round found:** 1
- **Resolution:** remaining (ambiguous, needs a maintainer decision)

**What is wrong:** The spec 041 `noLimit` form is converted without a load note. Other one-way migrations do write one ("the log names each migrated account once", docs/configuration.md).

**Why this matters:** Any later save rewrites the file, including a headline click in the dropdown. Older builds cannot read the result, and nothing in the log says when or why the file changed.

**What needs to happen:** Spec 043 and contracts/config.md do not ask for a note. To add one, pass `notes` into `decodeMembership` and append a single note in the legacy branch. Then update the spec and docs to match.

### FINDING-4
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Dropdown/NoLimitPresentation.swift:92-93 (via SectionNote.budgetIncomplete)
- **Category:** security
- **Source:** security-agent
- **Round found:** 1
- **Resolution:** remaining (unambiguous, follow-up)

**What is wrong:** The "incomplete, unpriced" note joins every unpriced model id with no limit on the count and no clipping. Accounts without an amount can now show this note under a Money headline.

**Why this matters:** Model ids come from third-party session records. Many ids, or very long ones, make the section and its VoiceOver label grow without bound. Own budgets with an amount already behave this way.

**What needs to happen:** Clip each name and show at most N names plus "and K more" inside `SectionNote.budgetIncomplete`, with a test. This changes a shared note, so it fits a separate pull request.

### FINDING-5
- **Severity:** Minor
- **Confidence:** 85
- **File:** Sources/UsageCore/Snapshot/Aggregator.swift:60-86, Sources/UsageCore/Pricing/ReferenceValue.swift:28
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining (unambiguous)

**What is wrong:** The "only unpriced records are valued" rule (FR-006) is coded twice. The aggregator splits the records, and `ReferenceValue` filters the rows by `!priced`. `unpricedUsage` is a full breakdown, of which only `perModel` is kept, rewritten row by row. There are also two sources for the unpriced model list: `entry.unpricedModels` and `entry.breakdown.unpricedModels`.

**What needs to happen:** Build `unpricedUsage` with a per-model-only helper. Keep exactly one of the two filters, and use one source for the unpriced model list.

### FINDING-6
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/AgentTacho/AccountSettingsView.swift:391-403, 430-443, 736-745
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining (unambiguous)

**What is wrong:** The amount row and its "must be greater than 0" message appear three times in the view layer, and the copies already differ: the new account sheet has no trailing alignment and no inline error.

**What needs to happen:** Add a tested `amountError` in UsageCore and a shared `BudgetAmountRow` view.

### FINDING-7
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/AgentTacho/AccountSettingsView.swift:722-732
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining (unambiguous)

**What is wrong:** The new account sheet chooses its budget caption in the view, and two of its three strings are inline literals.

**What needs to happen:** Move the choice and all three strings into `OwnBudgetForm` (or a small core helper) and test it.

### FINDING-8
- **Severity:** Minor
- **Confidence:** 85
- **File:** Sources/AgentTacho/DropdownView.swift:214-218, 245-248, plus comments in Arrangement.swift, Configuration.swift:626-628, SettingsView.swift, WindowResolver.swift, SectionNote.swift, BarLayout.swift, TimeFormatResolution.swift and UsageSnapshot.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** partially fixed (03b9f6e fixed the two DropdownView comments, one of which was wrong); the rest remain (unambiguous)

**What is wrong:** These comments still describe the removed "No limit" budget choice, or a section that shows only tokens, and cite spec 041 FRs that spec 043 superseded.

**What needs to happen:** Reword the remaining comments and cite spec 043 FR-017 to FR-019.

### FINDING-9
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Dropdown/HeadlineText.swift:90-95
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining (unambiguous)

**What is wrong:** `HeadlineText.whole` calls `NoLimitPresentation.amount`, and `NoLimitPresentation` calls `HeadlineText`, so each type depends on the other.

**What needs to happen:** Move the whole-dollar formatter to `BudgetAmountFormatter`.

### FINDING-10
- **Severity:** Minor
- **Confidence:** 90
- **File:** Sources/UsageCore/Pricing/ReferenceValue.swift:3-7, Sources/UsageCore/Config/Configuration.swift:1992-1996
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (5c0da23)

**What is wrong:** Two doc comments ran past the wrap width used in the rest of the codebase. Both were reflowed.

### FINDING-11
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/UsageCore/Config/Configuration.swift:1729-1735
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (2fc48fa)

**What is wrong:** The new check of kept thresholds on an account without an amount had no test.

**How it was resolved:** Added `keptThresholdsOfZeroOrLessAreInvalid`, which runs with 0 and -5 and checks the exact error.

### FINDING-12
- **Severity:** Minor
- **Confidence:** 75
- **File:** Tests/UsageCoreTests/NoLimitPresentationTests.swift:261-298, Tests/DemoModeTests/DefaultScenarioTests.swift:264
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** remaining (unambiguous)

**What is wrong:** No test follows the Money headline end to end, from records through the Aggregator to `NoLimitPresentation.make(account:...)`. No test puts a priced record outside the current window to check that FR-011 looks only at the current window. The demo test checks only that the headline starts with "$".

**What needs to happen:** Add an assembly test with priced records of 37.40 and 0.02, one unpriced record this month and one priced record last month. Assert "$37", "$37.42 spent this month", "spent this month" and the note. Add a variant where only last month has priced records and expect Tokens.

### FINDING-13
- **Severity:** Minor
- **Confidence:** 75
- **File:** Tests/UsageCoreTests/NoLimitConfigurationTests.swift:391-409
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (2fc48fa)

**What is wrong:** The `show` load-note tests asserted only how many notes there were, and the branch for a value that is not a string had no test.

**How it was resolved:** The tests now assert the exact note texts, and a new `unreadableShowGivesOneNoteAndAutomatic` covers the non-string value.

### FINDING-14
- **Severity:** Minor
- **Confidence:** 70
- **File:** Tests/UsageCoreTests/ThresholdTrackerTests.swift:1140-1158
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (2fc48fa)

**What is wrong:** The rebaseline tests never crossed a threshold after the baseline, so they did not show that the kept thresholds work again once an amount is entered.

**How it was resolved:** Added `keptThresholdsNotifyAgainAfterTheBaseline`: a baseline at 40%, then 60% notifies 50, then 95% notifies 90.

### FINDING-15
- **Severity:** Minor
- **Confidence:** 72
- **File:** Sources/UsageCore/Config/OwnBudgetForm.swift:50-60
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (2fc48fa)

**What is wrong:** The editor's contract strings had no test.

**How it was resolved:** Added `editorTextsMatchTheContract`.

### FINDING-16
- **Severity:** Minor
- **Confidence:** 70
- **File:** Tests/UsageCoreTests/NoLimitConfigurationTests.swift:308-315
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** remaining (unambiguous)

**What is wrong:** `groupBudgetStillNeedsAnAmount` accepts any error.

**What needs to happen:** Assert the exact error for an absent amount and for `null`, and add a positive control in which the group has an amount and decodes.

### FINDING-17
- **Severity:** Minor
- **Confidence:** 70
- **File:** Tests/UsageCoreTests/NoLimitTransitionTests.swift:159-176
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** remaining (unambiguous)

**What is wrong:** The SC-005 round-trip paths only ever use `show == .automatic`, and Automatic is never written to the file. No test carries a stored Percent or Money through amount, group and back, and through save and load (FR-012, FR-018a).

**What needs to happen:** Give the account in the path test `show = .percent` and assert it after every step.

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/Snapshot/Aggregator.swift:60-86
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Description:** On every refresh, each account without an amount builds three full breakdowns, and one of them keeps only `perModel`.
- **Rationale:** Not visible today, but the cost per account roughly triples on heavy gateway months. Folding spend, priced usage and unpriced rows into one pass would fix it.

### NOTABLE-2
- **File:** Sources/UsageCore/Config/Configuration.swift:270-282, 438-455
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** Users see one own budget with an optional amount, but the code still has `.ownBudget` and `.noLimit`. The accessor `ownBudget` now means "own budget with an amount".
- **Rationale:** New code that calls `ownBudget?.x` will silently skip accounts without an amount. Renaming the accessor (for example to `budgetWithAmount`) and adding `hasOwnBudget` would make each caller's intent explicit.

### NOTABLE-3
- **File:** Sources/AgentTacho/AccountSettingsView.swift:444-446 vs Sources/AgentTacho/MenuBarSettingsTab.swift:108-114
- **Category:** correctness
- **Source:** correctness-agent
- **Description:** Without an amount, the editor's disabled "Show in menu bar" toggle shows the kept value, which is checked by default. The Menu Bar tab shows the same setting unchecked, as FR-020 requires.
- **Rationale:** Both follow the spec (FR-018 says only "disabled", FR-020 says "unchecked"), but the two places disagree visibly. The maintainer should decide whether the editor also shows the toggle unchecked while there is no amount.

## Post-Fix Spec Coverage

The fixes deleted only comment lines and one call argument; no requirement code was removed. FR-001 to FR-023 and FR-018a are still covered, as listed in REVIEW-CODE.md. All spec requirements were verified after the fixes.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| baseline | make test | 0 | 0 | passed (2620 + 78 tests) |
| after fixes | make test | 0 | 0 | passed (2625 + 78 tests) |

## Remaining Findings

No Critical or Important findings remain. The 10 remaining Minor findings are listed above: FINDING-3, 4, 5, 6, 7, 8 (partial), 9, 12, 16 and 17. FINDING-3 needs a maintainer decision because the spec does not ask for a migration note. The others are clear-cut follow-ups for maintainability and test depth.
