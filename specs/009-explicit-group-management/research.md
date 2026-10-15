# Research: Explicit Group Management

## R1: Where groups are deleted today

- **Decision**: Remove every implicit deletion path:
  - `Configuration.validate()` throws `ConfigurationError.Kind.emptyGroup` for a group without members: remove the check and the error kind.
  - `Configuration.settingsCandidate(applied:undoTarget:)` (Arrangement.swift) calls `pruningEmptyGroups()`: call `reconcilingArrangement` directly; delete `pruningEmptyGroups`.
  - `removingAccount(id:)`, `movingAccountToOwnBudget(accountId:)`, `movingAccountToGroup(accountId:groupId:)` call `deletingGroupIfEmpty`: drop the calls and delete the helper.
- **Rationale**: FR-001 to FR-003. Keeping any of these would reintroduce the dead end.
- **Alternatives considered**: Keeping `pruningEmptyGroups` for hand-edited files (rejected: an empty group in a file is now valid, FR-001).

## R2: Adding a group

- **Decision**: `Configuration.addingGroup(id: String) -> Configuration` appends `BudgetGroup(id:, name: "Budget group", icon: IconDefaults.group, period: .weekly, budgetUSD: 60, shownInBar: true, thresholds: [80, 100])`. The app passes `UUID().uuidString`. The arrangement needs no explicit step: reconciliation appends new entries (spec 008 FR-005).
- **Rationale**: FR-007; same defaults as the new-account sheet (`AccountSettingsView.swift`, `newBudgetAmount = 60`, `.weekly`). The id is injected so tests are deterministic.

## R3: Removing a group

- **Decision**: `enum GroupRemovalDestination { case ownBudgets; case group(id: String) }` and `Configuration.removingGroup(id:destination:) -> Configuration`:
  - `.ownBudgets`: each member (in arrangement member order) gets `.ownBudget(group.budget)` (period, amount, thresholds, shownInBar copied), as `movingAccountToOwnBudget` does today.
  - `.group(id: H)`: each member becomes `.group(id: H, shownInBar: false)`.
  - The group is removed from `groups`. A destination equal to the removed group, or an unknown group id, falls back to `.ownBudgets` (defensive; the UI never offers it).
- **Rationale**: FR-010; one destination for all members. Pure and testable; the dialog only collects the choice.

## R4: Arrangement placement after a removal

- **Decision**: In `reconcilingArrangement` step 2.2 (accounts that became entries) and step 2.3 (accounts that joined a group), order the accounts by their position in the previous resolved member list of their former group (`previous.arrangedEntries`), using a stable sort on (position of the former group in the previous order, index in its previous member list); accounts without a previous position go last, in accounts-list order. When a group is removed, the base usually still holds the group's reference, so the members are inserted right after it and resolution then drops the stale reference: they end up at the group's position (spec 008 FR-006). The "group not in base" branch of step 2.2 only runs when a reordered base already omits the group.
- **Rationale**: FR-011. Today both steps use accounts-list order, which differs from the user's member order when the user reordered members in the Menu Bar tab.

## R5: Notifications

- **Decision**: No change to `ThresholdTracker`. It keys state per owner and re-baselines when an owner is new or a group's `memberIds` change (ThresholdTracker.swift, spec 004 FR-015). An empty group has percent 0 and crosses nothing. A refilled group, a destination group with new members and a member's new own budget all re-baseline on the next refresh; a removed group's keys are dropped as no longer live.
- **Rationale**: FR-006, FR-011, FR-012 are satisfied by existing behavior; tests pin it.

## R6: Empty group display

- **Decision**: The aggregator already produces a `GroupEntry` with spend 0 and percent 0 for a group without members (window and reset come from the period), so the bar shows 0% with the existing rules (FR-005). `DropdownView.BudgetSection` shows "No accounts in this group yet" in place of members, breakdown and trend when `members` is empty. `GroupEditor` shows the same note in its Members section.
- **Rationale**: FR-005, FR-013; no new data paths.

## R7: Dialogs

- **Decision**: Groups tab Remove... opens a sheet (not a confirmation dialog, which cannot hold a picker): title "Remove "<name>"?", the member names, and for a group with members a picker "Move its accounts to" with "Own budgets" and the other groups in Groups tab order; buttons Remove (destructive) and Cancel. Without members the sheet shows a plain confirmation. The account removal message (FR-016) drops the "also removes the budget group" text and, for a last member, adds: The group "<name>" stays, without accounts.
- **Rationale**: FR-008 to FR-010, FR-016.
