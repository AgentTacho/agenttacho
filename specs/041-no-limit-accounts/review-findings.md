# Deep Review Findings

**Date:** 2026-11-02
**Branch:** 041-no-limit-accounts
**Rounds:** 2
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline, ask=smart)
**Stage 1 spec compliance:** 98% (one minor deviation, FR-018 amount field; fixed in round 1)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 1 | 1 | 0 |
| Minor | 12 | 4 | 8 |
| Notable | 3 | - | 3 |
| **Total** | **16** | **5** | **11** |

Minor counts are after deduplication: the production-readiness and architecture reports of the double breakdown are one finding, and the two round 2 re-review findings are folded into FINDING-3 and FINDING-4.

**Agents completed:** 5/6 internal (Goal Alignment skipped: no PR yet) + 2 external tools (CodeRabbit, Codex)
**Agents failed:** none
**External tools:** CodeRabbit completed, 0 findings (first attempt failed on an unsupported `--files` option, rerun with `--base main --committed`); Codex completed, 0 findings; Copilot skipped (disabled in config).

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 85
- **File:** Tests/DemoModeTests/DemoSourcesTests.swift (code: Sources/DemoMode/DemoSources.swift:111-118)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, commit 2eee56b)

**What is wrong:** The demo record source moves a monthly No limit account's records before the launch month to the month's first day, but no test covered it. The demo coverage test only checks the headline suffix "M", so a reverted move (8.5M instead of about 48M at an early-month launch) would pass.

**Why this matters:** Early-month screenshots would silently show a much smaller No limit total.

**How it was resolved:** Added `monthlyNoLimitRecordBeforeTheMonthMovesToItsFirstDay` and `weeklyNoLimitRecordNeverMoves`, which build the context with `acc-vertex` switched to No limit. The monthly test fails without the `noLimit?.period` branch, since `budgetOwner(forAccount:)` is nil for a No limit account.

### FINDING-2
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/UsageCore/Snapshot/Aggregator.swift:57-67
- **Category:** production-readiness
- **Source:** production-readiness-agent (also reported by: architecture-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1, commit bd37aa3)

**What is wrong:** The unpriced breakdown and stale flag of a No limit account were computed twice per refresh, once for `tokenAccounts` and once for `noLimitAccounts`, with identical arguments.

**Why this matters:** Doubles the per-account grouping work over up to a month of records on every refresh, and the two entries could drift.

**How it was resolved:** Computed once and shared by both entries; a comment states that `tokenAccounts` stays for every token-based account because `UsageSnapshot.usedModels` reads it.

### FINDING-3
- **Severity:** Minor (spec deviation from stage 1)
- **Confidence:** 90
- **File:** Sources/AgentTacho/AccountSettingsView.swift (BudgetFields), Sources/UsageCore/Config/Configuration.swift (BudgetSettings)
- **Category:** correctness
- **Source:** spec compliance (stage 1); re-review flagged the first fix as view-only logic
- **Round found:** 1
- **Resolution:** fixed (round 1, commit bd37aa3; moved to core in round 2, commit ad09768)

**What is wrong:** FR-018 says the amount is empty after switching No limit to an own budget; the field showed "0" with the red error.

**Why this matters:** Spec deviation in the Settings switch path.

**How it was resolved:** `BudgetSettings.enteredAmount` reads 0 as nil and stores nil as 0 (tested in `NoLimitTransitionTests.enteredAmountReadsZeroAsEmpty`); the amount field binds to it. Saving is still refused until an amount above 0 is entered.

### FINDING-4
- **Severity:** Minor
- **Confidence:** 72
- **File:** Tests/UsageCoreTests/AggregatorTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent; extended by the round 2 re-review (perHarness)
- **Round found:** 1
- **Resolution:** fixed (rounds 1 and 2)

**What is wrong:** All No limit aggregator fixtures had `cost: nil`, so the "no cost shown" assertions held regardless of the `priced` flag.

**How it was resolved:** `pricedRecordsShowNoCost` adds a priced record and checks perModel, perDay, perProject and perHarness costs of both the No limit and token entries, plus `incomplete == false`.

### FINDING-5
- **Severity:** Minor
- **Confidence:** 80
- **File:** Tests/UsageCoreTests/ValueAsOptionsTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, commit 2eee56b)

**What is wrong:** `ValueAsOptions.missingLabel` (contract string `<model id> (no price)`) had no test.

**How it was resolved:** Exact-match assertion added.

## Remaining Findings (all Minor)

1. **Period rule repeated in three places** (architecture, Aggregator.swift:55, DemoSources.swift:114-118, WindowResolver.swift:66-69). A `Configuration.countingPeriod(forAccount:)` helper would keep them in sync. Unambiguous refactor.
2. **Stale doc comments** (architecture): `ArrangedEntry`, `reconcilingArrangement` step 2, `DropdownView.section(for:)`, `Aggregator.aggregate`, `TokenBasedSettings.groupId` and `memberShownInBar`, `AccountBudgetDescription.iconId`, `NewAccountSheet`, `UsageSnapshot.usedModels` still say "own budget" where No limit now applies too. Unambiguous.
3. **No limit section wiring duplicated** (architecture, DropdownView.swift:244-252 and ScenarioCoverage.swift:137-157): breakdown choice, `ReferenceValue.make` and `NoLimitPresentation.make` are assembled in the view and copied in DemoMode, so the FR-022 coverage test checks its own copy. A single core entry point would fix it. Unambiguous refactor.
4. **`ValueAsOptions` lives in `UsageCore/Dropdown/`** although it serves a Settings pop-up (architecture). Move to `Config/` or `Pricing/`. Unambiguous.
5. **Second USD whole-dollar formatter** (architecture, NoLimitPresentation.swift:70-85) next to `BudgetAmountFormatter`. Unambiguous refactor.
6. **No limit row drawn in secondary color in the Menu Bar tab** (correctness, MenuBarSettingsTab.swift:129-130): `isShownInBar` is always false for No limit, so the row looks like a hidden entry. Ambiguous: secondary can also read as "not in the bar"; needs a design decision.
7. **No non-en_US locale test for the value line** (test-quality, NoLimitPresentationTests.swift). Unambiguous.
8. **`NoLimitThresholdTests` cannot fail** (test-quality, ThresholdTrackerTests.swift:1070-1092): the snapshot only holds `noLimitAccounts`, which the tracker and `paceKeys` never read. Real protection lives in `NoLimitAggregationTests` and `NoLimitOwnerTests`; building the snapshot through `Aggregator` would make it meaningful. Unambiguous.

## Notable Observations

### NOTABLE-1
- **File:** Sources/AgentTacho/MenuBarSettingsTab.swift:104-119
- **Category:** architecture
- **Description:** A hidden constant toggle reserves the checkbox width in a No limit row.
- **Rationale:** A spacer or fixed leading column would avoid a phantom control.

### NOTABLE-2
- **File:** Sources/AgentTacho/AccountSettingsView.swift:276-279, 521-524
- **Category:** architecture
- **Description:** Budget picker sentinel tags are declared twice, and the two pickers order the choices differently.
- **Rationale:** One shared enum would keep both pickers consistent.

### NOTABLE-3
- **File:** Sources/AgentTacho/AccountSettingsView.swift:516-518, 642-646, 735-739
- **Category:** correctness
- **Description:** The new-account sheet shares one period state between Own budget and No limit, so a Monthly choice carries over.
- **Rationale:** Visible and editable, so not a bug; strict FR-016 would reset to weekly.

## Goal Alignment

Skipped: no pull request exists for the branch yet.

## Post-Fix Spec Coverage

No requirement code was removed; the aggregator change only shares one value between two entries. All spec requirements verified after the fix loop (full suite green).

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| 1 | make test | 0 | 0 | passed (2431 + 76 tests) |
| 2 | make test | 0 | 0 | passed (2432 + 76 tests) |

## Fixed after review

Remaining findings 1 to 5, 7 and 8, plus NOTABLE-3 (strict FR-016), fixed on the branch after the review:

- **NOTABLE-3, FR-016** (`41115e4`): the new account sheet keeps a separate `NoLimitSettings` for No limit, so a new No limit account starts weekly whatever the own budget had. The idea inbox entry `new-sheet-period-carries-over` is removed.
- **8, `NoLimitThresholdTests` cannot fail** (`77923bb`): the snapshots come from `Aggregator`, with priced records, and a control shows the same records under an own budget notify at 80% and 100% and get a pace key.
- **7, no non-en_US locale test** (`5c683ec`): `valueLineInAnotherLocale` checks the de_DE value line (`≈ 1.235 $`, `≈ <1 $`, `≈ 0 $`).
- **5, second whole-dollar formatter** (`cf33cf4`): `BudgetAmountFormatter.wholeAmount` rounds half up to whole units; `NoLimitPresentation` keeps only the `<$1` rule on top of it.
- **1, period rule in three places** (`ed034b1`): `Configuration.countingPeriod(forAccount:)`, used by `Aggregator`, `DemoSources` and `WindowResolver.collectionWindow`, with `CountingPeriodTests`.
- **3, No limit section wiring duplicated** (`a1c1685`): `NoLimitPresentation.make(account:snapshot:prices:times:dates:)` assembles the section for `DropdownView` and `ScenarioCoverage`, tested in `NoLimitSectionAssemblyTests`.
- **4, `ValueAsOptions` in `Dropdown/`** (`293c469`): moved to `UsageCore/Pricing/`; plan and research name the new place.
- **2, stale doc comments** (`d24202b`, plus `NewAccountSheet` in `41115e4`): the listed comments, and `Account.timeFormat`, `timeFormat(for:)` and `AccountEditor`, name No limit.

Finding 6 (No limit row in secondary color in the Menu Bar tab): decided by the maintainer during the walkthrough (step 10), drawn like a shown entry; fixed in "fix(settings): draw No limit rows like shown entries in the Menu Bar tab".
