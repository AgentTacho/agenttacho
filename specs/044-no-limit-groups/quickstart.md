# Quickstart: Validating Budget Groups Without an Amount

## Automated

```bash
make test           # UsageCore and DemoMode tests, including the new group cases
make test-release   # script tests (unchanged stems)
```

Expected: all pass. New tests cover decoding and encoding (contracts/config.md), `budgetOwners` and `noLimitGroups`, the aggregated `NoLimitEntry` (group spend equals the sum of member spend to the cent), `NoLimitPresentation.make(group:)`, `MemberLineText`, `GroupBudgetForm`, `GroupListSubtitle`, `Arrangement` rules, `BarLayout` gating, threshold rebaseline after an amount returns, lifecycle transitions, and the demo coverage.

## Demo build

```bash
make app-demo
```

1. Open the dropdown. The "Open models" section is last before Unassigned: a Money headline, "spent this month", two member lines with spend and no percent, no bar.
2. The menu bar has no entry for "Open models" or its members.
3. Settings > Groups > "Open models": the Amount field shows "No limit"; thresholds and "Show in menu bar" are disabled with "Set a monthly budget to use thresholds and the menu bar."; "Price tokens as" and "Dropdown shows" are enabled.
4. Set "Dropdown shows" to Tokens: the headline and both member lines switch to token counts, no refresh happens.
5. Enter 100 as the amount: the section shows a percent, bar and member shares; the Menu Bar tab row becomes "Budget group" with an enabled checkbox. Clear it again: everything returns to step 1.
6. Settings > Menu Bar: the group row reads "No limit" with a disabled, unchecked checkbox and its help text; member rows likewise.

## Real configuration (maintainer)

Put `acc-free-claude` and `acc-free-codex` into a new group "Free models" without an amount. The dropdown shows one section whose spend equals the sum of the two former sections, and the log has one `[refresh] no limit group Free models ...` line per refresh.
