# Code Review: Unified Token Accounts (spec 043)

**Spec:** specs/043-unified-token-accounts/spec.md (with contracts/config.md, contracts/ui-strings.md)
**Date:** 2026-11-03
**Reviewer:** Claude (speckit-spex-gates-review-code)

## Compliance Summary

**Overall Score: 100% (34/34) after one docs fix; 97% (33/34) before it**

- Functional Requirements: 24/24 (FR-001 to FR-023 with FR-018a)
- Edge Cases: 10/10
- Spec-declared constants: none (no `## Constants` section)

## Functional Requirements

| FR | Implementation | Status |
|---|---|---|
| FR-001 | `Account.decodeMembership` exactly-one rule over `groupId`, `budget`, `noLimit` (Configuration.swift) | Compliant |
| FR-002 | `budget` with absent or `null` `budgetUSD` decodes to `.noLimit`; present amount goes through `BudgetSettings` and `checkBudget` (> 0); group budget unchanged | Compliant |
| FR-003 | `NoLimitSettings` gains `thresholds`, `shownInBar`, encoded in `budget`; `OwnBudgetForm` carries them both ways; `checkThresholds` validates kept thresholds | Compliant |
| FR-004 | Legacy `noLimit` decodes to `NoLimitSettings(period:)` (80/100, shown in bar); forbidden keys still throw; encode writes `budget` only | Compliant |
| FR-005 | Aggregator prices `NoLimitEntry.breakdown` like an own budget; no per-account pricing setting | Compliant |
| FR-006 | `NoLimitEntry.unpricedUsage` + `ReferenceValue.make` filters `!priced`; `valueAs` only read for `.noLimit` | Compliant |
| FR-007 | `NoLimitPresentation.make`: `incomplete = money && !valued && unpriced`; missing model keeps the note under Money | Compliant |
| FR-008 | `budgetOwners`/`budgetOwner(forAccount:)` exclude `.noLimit`; `isShownInBar` false; no-limit section has no bar, pace | Compliant |
| FR-009 | `ThresholdTracker.observe` drops keys of vanished owners; a new owner key starts with a baseline | Compliant |
| FR-010 | `TokenBasedSettings.show`, `decodeShow`, written only when not Automatic, masked in the refresh-relevance comparison | Compliant |
| FR-011 | `DropdownShow.resolve(hasAmount:hasPricedUsage:)`; `hasPricedUsage` from window records | Compliant |
| FR-012 | `.percent` without amount falls through to the Automatic branch; stored value untouched | Compliant |
| FR-013 | `HeadlineText.tokens/spent/money` with `BudgetAmountLine` for remaining mode, U+2212 minus, half-up cents | Compliant |
| FR-014 | `BudgetSection` swaps only the headline; `NoLimitPresentation` period/value line and `showsCost` for Details | Compliant |
| FR-015 | Value tooltip switches on `hasPricedUsage` | Compliant |
| FR-016 | Texts and accessibility in `HeadlineText` / `NoLimitPresentation`, tested in HeadlineTextTests, NoLimitPresentationTests | Compliant |
| FR-017 | Budget pickers without "No limit"; new sheet keeps group preselection; `OwnBudgetForm(.noLimit(NoLimitSettings()))` start | Compliant |
| FR-018 | `OwnBudgetFields`: placeholder, disabled thresholds and toggle with help, disabled Value as with help, "Dropdown shows" with Percent disabled | Compliant |
| FR-018a | `OwnBudgetFields` shown only when `groupId == nil`; `movingAccountToGroup` keeps `show` | Compliant |
| FR-019 | `.noLimit` passes validation; `movingAccountToOwnBudget` prefills from the group | Compliant |
| FR-020 | `MenuBarSettingsTab` disabled unchecked toggle with `shownInBarHelp`; caption "No limit" from `budgetCaption` | Compliant |
| FR-021 | `AccountBudgetDescription` `.noLimit` case unchanged ("no limit / month") | Compliant |
| FR-022 | docs/configuration.md complete; docs/accounts-and-budgets.md lacked the `show` key and the migration (fixed in 33e4aa8); release notes come from the `feat` commit subjects | Compliant after fix |
| FR-023 | Demo `acc-free` in new form, `acc-api` with priced records after it; `defaultScenarioShowsTokensAndMoneyHeadlines` checks both measures and no bar values; plan section present | Compliant |

## Edge Cases

All ten edge cases trace to the code above (mixed priced and free, no usage gives Tokens "0", migrated account with priced records, Value as with an amount disabled, amount 0 invalid, legacy forbidden keys invalid, both forms invalid, remaining mode, group members, demo). Compliant.

## Extra Features (Not in Spec)

- `show` on a subscription account gives a load note and is ignored (Configuration.swift `noteForeignShow`). Helpful, consistent with the `headlineWindow` handling; candidate for a one-line spec mention.

## Deviations Fixed During Review

- FR-022: docs/accounts-and-budgets.md now names the `show` key and the migration of the No limit form (commit 33e4aa8).

## Deep Review Report

**Gate: PASS** (0 Critical, 0 Important; no fix loop needed). Details: `review-findings.md`.

| Agent | Found | Fixed | Remaining | Status |
|---|---|---|---|---|
| Correctness | 1 (+1 Notable) | 1 | 0 | completed |
| Architecture & Idioms | 6 (+1 Notable) | 1 (+1 partial) | 5 | completed |
| Security | 1 | 0 | 1 | completed |
| Production Readiness | 2 (+1 Notable) | 1 | 1 | completed |
| Test Quality | 7 | 4 | 3 | completed |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR) |
| CodeRabbit (external) | 0 | 0 | 0 | completed |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 0 | 0 | 0 | completed |
| Test Suite (regression) | 0 | 0 | 0 | passed (2625 + 78 tests) |
| **Total** | **17 Minor, 3 Notable** | **7** | **10 Minor** | |

MVP: Test Quality (7 findings)

Key fixes applied:

1. Token Details of an account without an amount rank by tokens under a Tokens headline (FR-014). Commit 03b9f6e.
2. The refresh log names the spend and the unpriced models of accounts without an amount. Commit 51269f0.
3. New tests for the kept-threshold validation, the exact `show` load notes, the editor contract strings, and kept thresholds that notify again once an amount is entered. Commit 2fc48fa.
4. Two doc comments reflowed. Commit 5c0da23.
5. Docs: `docs/accounts-and-budgets.md` now names the `show` key and the migration of the No limit form (FR-022). Commit 33e4aa8.

Post-fix spec coverage: 24/24 requirements verified.

## Review-code follow-ups

Maintainer decisions on the remaining findings of `review-findings.md`, applied on this branch.

| Item | Finding | What was done | Commit |
|---|---|---|---|
| 1 | FINDING-3 | One load note per converted spec 041 `noLimit` account (`account "<name>": No limit is now an own budget without an amount; the next save writes the new form`); FR-004, contracts/config.md and docs/configuration.md amended | ea7cc49 |
| 2 | NOTABLE-3 | The editor's disabled "Show in menu bar" toggle shows unchecked without an amount (`OwnBudgetForm.shownInBarDisplayed`); the kept value applies again with an amount; FR-018 and contracts/ui-strings.md amended | 799e9d9 |
| 3 | FINDING-8 | The remaining doc comments about the removed "No limit" choice name an own budget without an amount and cite spec 043 | 9194f42 |
| 4 | FINDING-6 | One `BudgetAmountRow` view for groups, the account editor and the new account sheet; the error text from `BudgetPeriod.amountError(for:)` / `OwnBudgetForm.amountError` (the new account sheet now also shows it) | d9984dd |
| 5 | FINDING-7 | The new account sheet's caption from `OwnBudgetForm.newAccountCaption(ownBudget:)`, all three strings in contracts/ui-strings.md | d9984dd |
| 6 | FINDING-4 | `SectionNote.budgetIncomplete` clips each model id to 32 characters and names at most three, then "and K more"; contracts/ui-strings.md amended | b922fca |
| 7 | FINDING-9 | Whole-dollar text moved to `BudgetAmountFormatter.wholeDollars`; `HeadlineText` and `NoLimitPresentation` no longer call each other | 89f49fb |
| 8 | FINDING-5, NOTABLE-1 | The aggregator's `splitByPrice` builds the unpriced rows, spend and priced flag in one pass; `ReferenceValue.make(unpricedUsage:)` no longer filters | 1dac60d |
| 9a | FINDING-12 | End-to-end test from records through the aggregator to the Money headline, with a priced record of last month | 2a8c66d |
| 9b, 9c | FINDING-16, FINDING-17 | `groupBudgetStillNeedsAnAmount` asserts the exact errors plus a positive control; a stored Percent and Money `show` survive amount, group, own budget, empty amount and save and load | 4c2a033 |

Not changed: NOTABLE-2 (renaming the `ownBudget` accessor) was not part of the decisions.
