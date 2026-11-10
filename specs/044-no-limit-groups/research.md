# Research: Budget Groups Without an Amount

Decisions for spec 044, based on a map of the code as left by spec 043 (file and line references as of branch start).

## R1: A group without an amount is not a budget owner

- **Decision**: `BudgetGroup` gets an optional amount. Its `budget: BudgetSettings` accessor becomes optional (nil without an amount), and `Configuration.budgetOwners` includes only groups with an amount. A new `Configuration.noLimitGroups` lists the groups without one, with their period.
- **Rationale**: spec 043 made accounts without an amount disappear from every budget path by never making them budget owners (`budgetOwners`, `accountBudgets`); the menu bar, `ThresholdTracker.observe`, pace keys, burn rate, `RowBar.budget` and run-out markers all iterate owners. Using the same exclusion for groups gives FR-003 and FR-005 for free: when the amount is removed, the group's threshold keys are no longer observed and are dropped (`ThresholdTracker` line 243), and when it returns, the next observation sets a baseline (spec 004 FR-015 path). `BudgetOwner.budget` stays non-optional.
- **Alternatives considered**: an optional amount on `BudgetOwner` (every caller would need a nil check, the opposite of 043's design); a separate `NoLimitGroup` type next to `BudgetGroup` (two group types in Settings, the arrangement and the Groups tab; rejected as approach C in the brainstorm).

## R2: Collection window and member attribution

- **Decision**: `Configuration.countingPeriod(forAccount:)` includes no-limit groups: a member's counting period is its group's period with or without an amount. `WindowResolver.collectionWindow` already widens the window through `countingPeriod` for every token-based account, so it needs no change (plan review).
- **Rationale**: today both take periods from `budgetOwners`; without this, members of a group without an amount would fall out of the collection window. Spec 043 handled `.noLimit` accounts the same way.
- **Alternatives considered**: none; required for correctness.

## R3: Aggregation reuses `NoLimitEntry`

- **Decision**: `Aggregator.aggregate` builds one `NoLimitEntry` per group without an amount from the combined records of its members, through the existing generic `splitByPrice`, and stores it in a new `UsageSnapshot.noLimitGroups[groupId]`. Members keep their priced `tokenAccounts` entries as today, which feed member lines and member tables.
- **Rationale**: `NoLimitEntry` already carries everything spec 043's presentation needs (breakdown, `unpricedUsage`, `spentUSD`, `hasPricedUsage`, `tokenBreakdown`, stale). Building it from the members' records means the group's spend equals the sum of the members' priced spend to the cent (SC-003), because both come from the same records and price table.
- **Alternatives considered**: summing member entries (duplicates the unpriced-model merge and Details breakdown logic).
- **Performance**: one more `splitByPrice` pass over the group's records per refresh, the same cost as one more account without an amount. The idea inbox entry `single-pass-no-amount-aggregation` stays open: no measurable cost is expected with a handful of groups.

## R4: Presentation reuses `NoLimitPresentation`

- **Decision**: `NoLimitPresentation.make(name:entry:show:value:...)` is already generic. Add a `make(group:snapshot:prices:...)` wrapper next to `make(account:...)` that reads `snapshot.noLimitGroups[group.id]`, the group's `valueAs` and `show`. `DropdownShow`'s doc comment is widened to groups.
- **Group with an amount**: `HeadlineText.budget(entry:show:direction:)` already takes a Show argument; the group section passes the group's stored `show` instead of `.automatic`. Nothing else in that section changes (FR-012, review-spec decision).
- **Rationale**: FR-015 asks for shared rules, not copies.

## R5: Member lines move into core

- **Decision**: new `MemberLineText` (UsageCore, `Dropdown/`) produces a member line's trailing text, tooltip and accessibility text from the member's priced `tokenAccounts` entry, the group's resolved measure and whether the group has an amount: with an amount, "$181 (36%)" as today plus a tooltip with the exact amount and share; without one, `HeadlineText.spent` or `HeadlineText.tokens` formats without a share, with the unpriced-tokens clause under Money (FR-013). `BudgetSection` and a new group branch of `NoLimitSection` call it. `MemberDisplay.make` keeps deciding which lines and tables appear (spec 025 FR-010, spec 026).
- **Rationale**: today the line is a string built in `DropdownView.swift` (lines 1109 to 1122), outside tests; FR-013 and FR-015 need its new variants tested.

## R6: Menu bar and Settings rules for groups

- **Decision**:
  - `BarLayout.segments` (groups at lines 158 to 167) and `BarLayout.memberItem` skip groups without an amount and their members (FR-003, FR-004).
  - `Arrangement`: `offersShownInBar` and `shownInBarHelp` cover groups and members of a group without an amount ("Set a monthly budget to show this group in the menu bar."; members "Set a monthly budget for the group to show this account in the menu bar."); `budgetCaption` returns "No limit" for such a group (FR-019).
  - `GroupListSubtitle.text` gives "no limit / month, 2 member(s)" plus a VoiceOver text; `AccountBudgetDescription` names a member's group with "no limit / month" (FR-018).
  - A new core `GroupBudgetForm` mirrors `OwnBudgetForm` for the group editor: amount text with placeholder "No limit", enabling rules, help strings shared with `OwnBudgetForm` (FR-016). `GroupEditor` binds to it and reuses the own budget editor's controls (`BudgetAmountRow`, `ValueAsMenu`, `DropdownShowMenu`).
  - `AccountBudgetDescription` names a member's group as "Free models, no limit / month" (FR-018).
  - The account editor's member toggle (line 294) takes its state from `Configuration.memberShareToggle(forAccount:)`, disabled with the help text while the group has no amount (FR-020); the account's own `valueAs` and `show` are already hidden for members because `OwnBudgetFields` shows only when `groupId == nil` (FR-008).
- **Rationale**: every rule with a branch lives in UsageCore (constitution II).

## R7: Lifecycle

- **Decision**: `movingAccountToOwnBudget` and `GroupLifecycle.removingGroup(.ownBudgets)` give `.noLimit(NoLimitSettings(period:thresholds:shownInBar:))` when the group has no amount, else today's `.ownBudget(group.budget)` (FR-021). `RemoveGroupSheet.destinationNote` drops "amount" from its wording for such a group. `addingGroup` keeps 60 US$ weekly (FR-017).

## R8: Configuration form

- **Decision**: decoding accepts an absent or `null` `budgetUSD` on a group (absent `weeklyBudgetUSD` too) as no amount; a present amount must still be greater than 0 (`checkBudget` runs only with an amount). `valueAs` and `show` are read with the account decoders, the unknown-`show` note naming the group (`group "<name>": unknown show value ...`). Encoding writes `budgetUSD` only with an amount, `valueAs` when set, `show` only when not Automatic. `dataRelevant()` masks a group's `valueAs` and `show`, as for accounts, so changing them never refreshes (FR-010), and for a group without an amount also its kept `thresholds` and `shownInBar`, as spec 043 masks them for an account without an amount.
- **Rationale**: matches spec 043 FR-002 and FR-010 for own budgets; old files load unchanged because every new key is optional.

## R9: Log line

- **Decision**: `RefreshCoordinator` logs `no limit group <name> (<period>, <window>): <tokens> tokens, <spend> USD spent[, unpriced: ...][, stale]` next to the account line (lines 815 to 820), through the same formatter (FR-025).

## R10: Demo scenario

- **Decision**: add a group "Open models" (`grp-open`, `solid:gift`, monthly, no amount) with two new members, "Open models (Claude Code)" (`acc-open-claude`, Claude Code, Other provider, its own directory `~/.claude-open`, condition model starts with `gateway-b/`) and "Open models (Codex)" (`acc-open-codex`, Codex, API key, codex home `~/.codex-open`, same condition), records of `gateway-b/open-model-12b` this month for both, priced through a demo price override. The prefix differs from `acc-free`'s `gateway-a/` so no overlap warning appears, arranged after `acc-api` and before Unassigned. `ScenarioCoverage` gains `noLimitGroupSections` (measure, headline, member lines).
- **Rationale**: FR-024; placing it last keeps every framed section of the existing shots in place.
- **Alternatives considered**: turning `acc-free` into a group (moves the `no-limit` shot's crop).
