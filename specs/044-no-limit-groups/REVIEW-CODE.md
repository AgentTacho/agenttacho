# Code Review: Budget Groups Without an Amount (spec 044)

**Spec:** specs/044-no-limit-groups/spec.md (with contracts/config.md, contracts/ui-strings.md)
**Date:** 2026-11-10 (re-run after the cleanup round)
**Reviewer:** Claude (speckit-spex-gates-review-code)

## Compliance Summary

**Overall Score: 100% (39/39)**

- Functional Requirements: 25/25 (FR-001 to FR-025)
- Edge Cases: 14/14
- Spec-declared constants: none (no `## Constants` section)

## Functional Requirements

| FR | Implementation | Status |
|---|---|---|
| FR-001 | `BudgetGroup.budgetUSD: Decimal?`; absent or `null` decodes to nil (null wins over a legacy key since 26ead76); `checkBudget` (> 0) only with an amount | Compliant |
| FR-002 | Period, thresholds, shownInBar kept and encoded; `GroupBudgetForm.applied` keeps them; `checkThresholds` without an amount | Compliant |
| FR-003 | `budgetOwners` excludes groups without an amount; `BarLayout` guard; `ThresholdTracker` iterates owners only; `NoLimitSection` has no bar or pace | Compliant |
| FR-004 | `BarLayout` skips members; `isShownInBar(.member)` false; `memberShownInBar` kept | Compliant |
| FR-005 | Owner key leaves `liveKeys`; re-entered amount starts a new key with a baseline (ThresholdTrackerTests) | Compliant |
| FR-006 | No membership rule added | Compliant |
| FR-007 | `Aggregator` prices member records from the effective table in both cases | Compliant |
| FR-008 | `NoLimitPresentation.make(group:)` uses the group's `valueAs` only without an amount; account editor shows `OwnBudgetFields` (and so Price tokens as) only when `groupId == nil` | Compliant |
| FR-009 | Shared `NoLimitPresentation.make` over the group's `NoLimitEntry` | Compliant |
| FR-010 | `BudgetGroup.show`, written only when not Automatic, masked in `dataRelevant` | Compliant |
| FR-011 | `hasPricedUsage` from the split of the members' window records; Percent falls back via spec 043's resolve | Compliant |
| FR-012 | `BudgetSection(show: group.show)` with an amount; `NoLimitPresentation` without | Compliant |
| FR-013 | `MemberLineText.lines` with `Rule.share` (full priced spend and share, clarification of 2026-11-10) or `Rule.measure` (spend or tokens, tooltip naming unpriced tokens), never "≈" | Compliant |
| FR-014 | `NoLimitEntry.details(showsCost:)` for the group, `TokenAccountEntry.details(showsCost:)` for the member tables (token-ranked under Tokens since 6ae64a1) | Compliant |
| FR-015 | `HeadlineText`, `NoLimitPresentation`, `MemberLineText` in UsageCore, tested | Compliant |
| FR-016 | `GroupBudgetFields` renders `OwnBudgetFields` through `GroupBudgetForm.ownForm`; rules from `OwnBudgetForm.budgetControlsEnabled/Help`, `valueAsEnabled/Help`, `DropdownShowMenu` | Compliant |
| FR-017 | Empty amount saves; Groups > Add defaults unchanged, `valueAs` nil, `show` Automatic | Compliant |
| FR-018 | `GroupListSubtitle.text/accessibilityText` on the draft; `AccountBudgetDescription` "Free models, no limit / month" | Compliant |
| FR-019 | `offersShownInBar`, `shownInBarHelp`, `budgetCaption` "No limit"; preview via `BarLayout` | Compliant |
| FR-020 | `memberShareToggle` reads `offersShownInBar` and `shownInBarHelp(for:)` of the member row | Compliant |
| FR-021 | `ownBudgetMembership` used by `movingAccountToOwnBudget` and group removal; remove sheet note | Compliant |
| FR-022 | Lenient `show` with the contract's load note; trimmed `valueAs`; old files load unchanged | Compliant |
| FR-023 | docs/configuration.md, docs/accounts-and-budgets.md, README updated; release notes come from the `feat` subjects | Compliant |
| FR-024 | Demo group `grp-open` with Claude Code and Codex members; `defaultScenarioShowsANoLimitGroup` checks headline, member lines, no bar values | Compliant |
| FR-025 | `noLimitLine("no limit group <name>", entry)` in `RefreshCoordinator` | Compliant |

## Edge Cases

All 14 trace to the code above (mixed members, paid member, empty group, one member, no usage, member's own settings, Price tokens as with an amount, amount 0 or less, kept thresholds, switch to own budget, removal, remaining mode, refresh log, "$0" member line, older versions). Compliant.

## Extra Features (Not in Spec)

- The Groups list VoiceOver text and the remove sheet note are in the contracts. None outside the spec.

## Deviations Fixed During Review

- FR-001 with a leftover legacy key: `"budgetUSD": null` plus `weeklyBudgetUSD` now means no amount (26ead76).
- FR-013 for a model with priced and unpriced records in a group with an amount: maintainer decision, full priced spend, recorded as a clarification (c7276ed).
- FR-014 for member tables under a Tokens headline: ranked by tokens, not by cost (6ae64a1, re-run).

## Deep Review Report

Re-run after the cleanup round (fc56922 to cfed06e), over the cleanup round and the whole feature diff. The first run ended PASS with 1 Important fixed; its results are summarized in `review-findings.md`.

**Gate: PASS** (0 Critical, 0 Important remaining after 1 fix round). Details: `review-findings.md`.

| Agent | Found | Fixed | Remaining | Status |
|---|---|---|---|---|
| Correctness | 0 | 0 | 0 | completed |
| Architecture & Idioms | 4 | 4 | 0 | completed |
| Security | 0 | 0 | 0 | completed |
| Production Readiness | 1 | 0 | 1 | completed |
| Test Quality | 4 | 3 | 1 | completed |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR) |
| CodeRabbit (external) | 0 | 0 | 0 | completed |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 1 | 1 | 0 | completed |
| Test Suite (regression) | 0 | 0 | 0 | passed |

The unused `GroupBudgetForm` rules were reported by architecture and test quality and are counted once below.

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 2 | 2 | 0 |
| Minor | 7 | 5 | 2 |
| Notable | 0 | - | 0 |

MVP: Architecture & Idioms (4 findings)

Key fixes applied:
1. Member tables of a group without an amount rank by tokens under a Tokens headline (FR-014; Codex).
2. The budget editor's enabling rules live in `OwnBudgetForm` and are read by `OwnBudgetFields` for own budgets and groups; the unused copies in `GroupBudgetForm` are gone (FR-015, FR-016; architecture, test quality).
3. Tests: whole-group `ownForm` round trip with a non-default time format; account editor toggle for a missing group and a weekly group.
4. `memberSpend` and `memberDisplay` doc comments corrected; `MemberLineText.withAmount/withoutAmount` internal.

Remaining (Minor):
- `Sources/UsageCore/Notifications/ThresholdTracker.swift:170-179`: clearing and re-entering an amount within one running refresh can keep the old threshold state, so the next refresh may notify instead of setting a baseline. This race already exists for own budgets (spec 043 FR-009), and fixing it means changing the shared tracker.
- `Tests/UsageCoreTests/HeadlineTextTests.swift:222-230`: `memberLinesStayAsUnderAutomatic` duplicates a `MemberLineTextTests` case. The Show-independence it names is structural (`Rule.share` takes no measure).

Post-fix spec coverage: 25/25 requirements verified (the removed `GroupBudgetForm` rules live on in `OwnBudgetForm`).
