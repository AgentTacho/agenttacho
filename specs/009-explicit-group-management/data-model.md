# Data Model: Explicit Group Management

## BudgetGroup (unchanged fields)

id, name, icon, period, budgetUSD, shownInBar, thresholds. Change: may have zero members (no validation error).

## GroupRemovalDestination (new, UsageCore/Config/GroupLifecycle.swift)

| Case | Meaning |
|---|---|
| `.ownBudgets` | Every member gets its own budget with the group's budget settings. |
| `.group(id: String)` | Every member joins that group, share hidden from the bar. |

## Operations

| Operation | Result | Requirement |
|---|---|---|
| `Configuration.addingGroup(id:)` | appends a group with the default settings | FR-007 |
| `Configuration.removingGroup(id:destination:)` | removes the group, moves its members per destination | FR-010, FR-011 |
| `Configuration.removingAccount(id:)` | removes the account, keeps its group | FR-002 |
| `Configuration.movingAccountToOwnBudget(accountId:)` | moves out, keeps the group | FR-002 |
| `Configuration.movingAccountToGroup(accountId:groupId:)` | moves, keeps the former group | FR-002 |
| `Configuration.settingsCandidate(applied:undoTarget:)` | reconciles the arrangement, no pruning | FR-002, FR-011 |

Removed: `pruningEmptyGroups()`, `deletingGroupIfEmpty(_:)`, `ConfigurationError.Kind.emptyGroup`.
