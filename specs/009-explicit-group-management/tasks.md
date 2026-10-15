# Tasks: Explicit Group Management

**Input**: Design documents from `/specs/009-explicit-group-management/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/groups-tab.md, quickstart.md

**Tests**: Included. Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`). Write each test task before its implementation and confirm it fails once the package compiles.

**Global constraints** (from plan.md):
- Existing configurations load and behave as before, apart from groups no longer disappearing (SC-004).
- Membership is edited only from the account side (FR-013).
- No em dash or en dash characters. Doc comments cite spec 009 FR ids.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on incomplete tasks)
- **[Story]**: US1 (group survives), US2 (add), US3 (remove)

---

## Phase 1: Setup

- [X] T001 Run `make test` and confirm all existing suites pass (baseline).

---

## Phase 2: Foundational (blocking): no implicit deletion

- [X] T002 Update tests for FR-001 to FR-003 in `Tests/UsageCoreTests/ConfigurationTests.swift`: an empty group validates (replace the `.emptyGroup` expectations at about lines 256 and 401); replace `pruningEmptyGroupsDropsGroupsLeftWithoutMembers` with tests that `removingAccount` (last member), `movingAccountToOwnBudget` (last member) and `movingAccountToGroup` (last member of the former group) keep the former group with all its settings; a hand-written configuration with an empty group decodes and validates. Invert every other test that asserts implicit deletion: `removingLastMemberDeletesGroup` (ConfigurationTests ~360) and the deleted "solo" group in `movingToOwnBudgetPrefillsFromTheGroup` and `movingToGroupDiscardsTheOwnBudget` (ConfigurationTests ~881 to 903) now expect the group to stay. In `Tests/UsageCoreTests/ArrangementReconcileTests.swift` keep `ownBudgetTakesThePlaceOfAPrunedGroup` and `reorderBaseWithMovedAccountAndPrunedGroup` (~105, ~214) but delete the group directly in the test (`next.groups.removeAll { $0.id == ... }`) instead of `.pruningEmptyGroups()`, since they are the only coverage of the group-deleted placement FR-011 relies on; add separate tests that a group left empty stays at its position with the moved account directly after it (spec 008 FR-006 first clause); replace `settingsCandidatePrunesEmptyGroups` (~293) with a test that `settingsCandidate` keeps empty groups. In `removalKeepsTheRelativeOrder` (~144) delete h directly (`groups.removeAll { $0.id == "h" }`) to keep the FR-008 group-removal coverage, and assert separately that `removingAccount` alone keeps h at its position. In `ownBudgetTakesThePlaceOfAPrunedGroup` also the `unstored` half (~112 to 114) relies on implicit deletion: delete h directly there as well. Add a test that moving an account into an empty group and reconciling makes it that group's only member at the group's position (edge case: joining an empty group). In `Tests/UsageCoreTests/ThresholdTrackerTests.swift` `removedEntitiesAreDropped` (~120), remove the group explicitly (`groups.removeAll`) so it still tests that a removed entity loses its state.
- [X] T003 Implement in `Sources/UsageCore/Config/Configuration.swift`: remove the empty-group check from `validate()` and the `emptyGroup` case from `ConfigurationError.Kind`; drop the `deletingGroupIfEmpty` calls from `removingAccount`, `movingAccountToOwnBudget`, `movingAccountToGroup` and delete `deletingGroupIfEmpty` and `pruningEmptyGroups`; update their doc comments and the `// MARK: Group lifecycle (FR-019)` header (spec 009 FR-002). In `Sources/UsageCore/Config/Arrangement.swift` make `settingsCandidate` call `reconcilingArrangement` without pruning, and update the stale comment in `Sources/AgentMeter/SettingsView.swift` `applyNow` (~113) that says empty groups are deleted. Fix any remaining callers (`rg pruningEmptyGroups`). `make test` green.

**Checkpoint**: groups survive every membership change and account removal.

---

## Phase 3: User Story 1 - A group survives losing its members (P1) MVP

- [X] T004 [US1] Add tests to `Tests/UsageCoreTests/AggregatorTests.swift` and `Tests/UsageCoreTests/BarLayoutTests.swift`: an empty group yields a group entry with spend 0 and percent 0 whose window and reset follow its period; the bar shows "0%" with normal level for it when shown, and the usual placeholder before the first snapshot (FR-004, FR-005).
- [X] T005 [US1] Add tests to `Tests/UsageCoreTests/ThresholdTrackerTests.swift`: an empty group never notifies; when it gets a member whose spend already exceeds a threshold, the first refresh records a baseline without notifying, and a later crossing notifies (FR-006, research R5). Expected: no production change.
- [X] T006 [US1] In `Sources/AgentMeter/DropdownView.swift`, give `BudgetSection` an explicit flag (for example `isGroup: Bool`, set in `section(for:)`), because own budgets also pass `members: []`; when a group (not an own budget) has no members show the note "No accounts in this group yet" instead of members, breakdown and trend, keeping the header (FR-005). In `Sources/AgentMeter/AccountSettingsView.swift` `GroupEditor`, show the same note in the Members section when empty (FR-013).
- [X] T007 [US1] In `Sources/AgentMeter/AccountSettingsView.swift` update the account removal message (`removalMessage`) and its doc comment (~91): drop the "This also removes the budget group" text; for the last member of a group add `The group "<name>" stays, without accounts.` (FR-016). `make app` builds.

---

## Phase 4: User Story 2 - Create a budget group on its own (P1)

- [X] T008 [P] [US2] Create `Tests/UsageCoreTests/GroupLifecycleTests.swift` with tests for `addingGroup(id:)`: appends a group with name "Budget group", `IconDefaults.group`, weekly, 60 USD, shown in bar, thresholds [80, 100]; repeated calls create distinct groups with the same name; after `reconcilingArrangement` the new group is last in the arrangement (FR-007).
- [X] T009 [US2] Create `Sources/UsageCore/Config/GroupLifecycle.swift` with `Configuration.addingGroup(id:)` (research R2). T008 passes.
- [X] T010 [US2] In `GroupSettingsView` (`Sources/AgentMeter/AccountSettingsView.swift`) add an Add button below the list that applies `draft.addingGroup(id: UUID().uuidString)` (data-model.md) and selects the new group, replace the existing caption (~547) with the FR-015 text (contracts/groups-tab.md), and let the empty-selection placeholder mention Add. `make app` builds.

---

## Phase 5: User Story 3 - Remove a group, members included (P2)

- [X] T011 [P] [US3] Add tests to `Tests/UsageCoreTests/GroupLifecycleTests.swift` for `removingGroup(id:destination:)`: empty group removed; `.ownBudgets` gives each member an own budget equal to the group's budget settings; `.group(id: H)` makes each member a member of H with share hidden; destination equal to the removed group or unknown falls back to own budgets; unrelated accounts and groups unchanged (FR-010).
- [X] T012 [US3] Implement `GroupRemovalDestination` and `Configuration.removingGroup(id:destination:)` in `Sources/UsageCore/Config/GroupLifecycle.swift` (research R3, data-model.md). T011 passes.
- [X] T013 [US3] Add tests to `Tests/UsageCoreTests/ArrangementReconcileTests.swift`: after `removingGroup(.ownBudgets)` reconciled against the previous configuration, the members take the group's position in the previous member order (also when it differs from accounts-list order); after `removingGroup(.group(id: H))` they are last in H in the previous member order; the other entries keep their order; the removed group is gone from the arrangement (FR-011). Add an undo test: `previous.settingsCandidate(applied: removed, undoTarget: previous) == previous`, once for a group with members and once for an empty group, (group, arrangement position, membership and member shown-in-bar settings, FR-012). In `Tests/UsageCoreTests/ThresholdTrackerTests.swift` add tests that the destination group and the new own budgets re-baseline, that the removed group's key is cleared (`#expect(!tracker.trackedEntityIds.contains(removedGroupId))`), and that after an undo the restored group re-baselines (FR-006, FR-011, FR-012).
- [X] T014 [US3] Change `reconcilingArrangement` in `Sources/UsageCore/Config/Arrangement.swift` (steps 2.2 and 2.3) to order moved and joined accounts by a stable sort on (position of the former group in the previous order, index in its previous member list); accounts without a previous position go last in accounts-list order (research R4). T013 passes. Update `severalAccountsLeavingAGroup` (~203) and its doc comment: accounts leaving one group are now placed in the group's previous member order (consistent with FR-011; spec 008 FR-006 leaves that order open). All other reconcile tests stay green.
- [X] T015 [US3] In `GroupSettingsView` add a Remove... button (enabled with a selection) opening a sheet per contracts/groups-tab.md: plain confirmation for an empty group; for a group with members, the member names and a picker "Move its accounts to" with "Own budgets" (default) and the other groups in Groups tab order; Remove applies `draft.removingGroup(id:destination:)` and clears the selection; Cancel changes nothing (FR-008 to FR-010). Undo works through the existing Settings flow (FR-012). `make app` builds.

---

## Phase 6: Polish

- [X] T016 [P] Update `README.md`: the Budget groups description (~120, "one or more token-based accounts": groups may now be empty and are added and removed in the Groups tab), the Groups tab description (Add, Remove, removal destination) and any sentence saying groups are removed with their last account.
- [X] T017 [P] Check changed files for em dash and en dash characters and remove any.
- [X] T018 Run `make test` and `make app`; walk through quickstart.md steps that need no GUI, list the GUI steps for the user.

---

## Dependencies

- Phase 2 (T002, T003) blocks everything.
- US1 (T004 to T007) after Phase 2.
- US2: T008 then T009 then T010.
- US3: T011 then T012; T013 then T014 (T013 needs T012); T015 needs T012 and T014.
- Polish last.

## Parallel opportunities

T016 and T017.

## Implementation strategy

MVP is Phase 2 plus US1: groups no longer vanish. US2 and US3 add explicit creation and removal.
