# Data Model: Budget Groups Without an Amount

## BudgetGroup (changed)

| Field | Type | Rule |
|---|---|---|
| id, name, icon, timeFormat | as today | unchanged |
| period | weekly or monthly | kept with or without an amount |
| amount (`budgetUSD`) | Decimal, optional | absent or `null`: no amount, no limit; present: must be > 0 (spec 003 FR-019) |
| thresholds | [Int] | kept without an amount, validated as today, no effect until an amount exists |
| shownInBar | Bool | kept without an amount, no effect until an amount exists |
| valueAs | model id, optional | new; values unpriced member records only without an amount (FR-008) |
| show | DropdownShow | new; Automatic when absent, never written as Automatic (FR-010) |

Derived:

- `budget: BudgetSettings?`: nil without an amount (R1).
- `hasAmount: Bool`.

## Configuration (changed accessors)

- `budgetOwners`: groups with an amount and accounts with an own budget with an amount (unchanged meaning, R1).
- `noLimitGroups`: groups without an amount, with their period (new).
- `countingPeriod(forAccount:)`: a member's group period, with or without an amount (R2).
- `movingAccountToOwnBudget`, `removingGroup(.ownBudgets)`: `.noLimit(NoLimitSettings)` from a group without an amount (R7).

## UsageSnapshot (changed)

- `noLimitGroups: [String: NoLimitEntry]`: new, one entry per group without an amount, built from the combined member records (R3).
- `groups: [String: GroupEntry]`: only groups with an amount (unchanged type).
- `tokenAccounts`: member entries priced as today.

## Presentation (new or widened, all UsageCore)

- `NoLimitPresentation.make(group:snapshot:prices:times:dates:)`: new wrapper (R4).
- `MemberLineText`: trailing text, tooltip, accessibility text for one member line; inputs: member breakdown, group measure, group amount (optional), direction (R5).
- `GroupBudgetForm`: group editor draft; amount text, enabling rules and help strings shared with `OwnBudgetForm` (R6).
- `GroupListSubtitle`: "no limit / month, N member(s)" and VoiceOver text (R6).
- `AccountBudgetDescription`: member of a group without an amount, "Free models, no limit / month" (R6).
- `Arrangement`: `offersShownInBar`, `shownInBarHelp`, `budgetCaption` for groups and their members (R6).
- `Configuration.memberShareToggle(forAccount:) -> (enabled: Bool, help: String?)`: the account editor's member share toggle (R6, FR-020).

## Transitions

| From | Action | To | Effects |
|---|---|---|---|
| group with amount | clear amount, save | group without amount | leaves `budgetOwners`; group and member bar entries disappear; threshold keys dropped at the next observation; period, thresholds, shownInBar, member shownInBar kept |
| group without amount | enter amount, save | group with amount | joins `budgetOwners`; kept thresholds and shownInBar apply; first observation sets a baseline without notifying (FR-005) |
| member of group without amount | switch to own budget | account with own budget without amount | `NoLimitSettings` from group period, thresholds, shownInBar (FR-021) |
| group without amount, with members | remove, "each to its own budget" | members with own budgets without amount | as above, for each member |
