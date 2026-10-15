# Tasks: Menu Bar Arrangement

**Input**: Design documents from `/specs/008-menu-bar-arrangement/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/config-file.md, contracts/menu-bar-tab.md, quickstart.md

**Tests**: Included. The project covers every `UsageCore` type with Swift Testing suites (`import Testing`, `@Suite`, `@Test`, `#expect`). Write each test task right before its implementation and confirm that it fails once the package compiles.

**Organization**:
- Phase 2 holds the stored arrangement and its resolution. Every story depends on it.
- Stories run in priority order: US1 (one order for bar and dropdown, P1), US2 (rearrange in Settings, P1), US3 (show and hide from the same list, P2).

**Global constraints** (from plan.md):
- Existing configs load with an unchanged bar order and are never rewritten only to add an arrangement (FR-004, SC-003).
- Arrangement problems never raise a `ConfigurationError` (FR-011).
- A group and an account may share an id; entry references are kind-qualified (research R1).
- Account and group editors keep working unchanged (FR-015). Existing tests pass unchanged unless a task says otherwise.
- No em-dash or en-dash characters. Doc comments cite FR ids of spec 008.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on incomplete tasks)
- **[Story]**: US1 to US3

---

## Phase 1: Setup

- [X] T001 Run `make test` and confirm all existing suites pass (baseline).

---

## Phase 2: Foundational (blocking)

**Purpose**: The stored arrangement, its coding, and the tolerant resolution used by the bar, the dropdown and the tab.

- [X] T002 Write `Tests/UsageCoreTests/ArrangementTests.swift`: (a) `Arrangement` JSON round trip with `entries` of kind `account` and `group` and a `members` map; (b) `Configuration` without the `arrangement` key decodes with `arrangement == nil` and re-encodes without the key; (c) with an arrangement it round-trips; (d) `arrangedEntries` with nothing stored equals the spec 004 FR-020 order (subscription, Codex subscription and own-budget accounts in accounts-list order, then groups in groups-list order, members in accounts-list order), using a config like `BarLayoutTests.config()`; (e) a stored order is followed; (f) unknown ids, unknown kinds, duplicates, a member listed among entries, an entry listed as a member, a member under the wrong group are ignored and the missing items appended in default order; (g) a group and an own-budget account sharing an id are distinct entries with independent positions, and `ArrangedEntry.id` values are unique; (h) a token-based account with neither group nor own budget is not listed; (i) `defaultArrangement` lists every entry and every member in default order.
- [X] T003 Create `Sources/UsageCore/Config/Arrangement.swift` with `EntryKind` (`account`, `group`, Codable as lowercase strings, unknown values decoded tolerantly so the containing reference is dropped), `EntryRef` (kind, id), `Arrangement` (entries, members), `ArrangedEntry` (`.account(Account)`, `.group(BudgetGroup, members: [Account])`, kind-qualified `id`, `ref`), and a `Configuration` extension with `arrangedEntries`, `defaultArrangement`, `isEntry(_ account:)` and `asArrangement(_ entries: [ArrangedEntry])` per data-model.md and research R2. Decoding of `entries` must skip individual malformed references instead of failing the whole file.
- [X] T004 Add `public var arrangement: Arrangement?` to `Configuration` in `Sources/UsageCore/Config/Configuration.swift`: init parameter defaulting to nil, `arrangement` coding key, `decodeIfPresent` in `init(from:)`, encoded only when non-nil (synthesized `encodeIfPresent`). In `dataRelevant()` set `copy.arrangement = nil` (research R3a) and add a test to `Tests/UsageCoreTests/ConfigurationTests.swift` that `needsRefresh(comparedTo:)` is false when only the arrangement changes. Run `make test`: T002 and the new test pass, all other suites unchanged.

**Checkpoint**: `make test` green.

---

## Phase 3: User Story 1 - Bar and dropdown follow one order (P1) MVP

**Goal**: The bar and the dropdown sections follow `arrangedEntries` (FR-002, FR-003).

**Independent test**: With and without a stored arrangement, the sequence of bar entries equals the dropdown sections with hidden entries removed (SC-001); an existing config shows the same bar order as before (SC-003).

- [X] T005 [US1] Extend `Tests/UsageCoreTests/BarLayoutTests.swift`: (a) existing tests still pass with no arrangement (FR-020 order unchanged); (b) with a stored arrangement putting a group first and an own-budget account before a subscription, `segments` follows it; (c) members shown in bar follow their group in stored member order, and take a hidden group's position; (d) a group and an account sharing an id both appear at their own positions; (e) hidden entries are skipped without affecting the others' order.
- [X] T006 [US1] Rewrite `BarLayout.segments` in `Sources/UsageCore/Bar/BarLayout.swift` to iterate `configuration.arrangedEntries`: `.account` dispatches on kind to `subscriptionItem`, `codexItem` or `budgetItem` (own budget, `snapshot.accountBudgets`), honoring each shown-in-bar setting; `.group` appends the group item when shown, then its members shown in bar in the resolved member order. Update the doc comment (spec 008 FR-002). T005 passes.
- [X] T007 [US1] Rewrite the section loop in `Sources/LLMUsageMenuBar/DropdownView.swift` to `ForEach(configuration.arrangedEntries) { entry in ... }`, rendering `SubscriptionSection`, `CodexPlanSection` or `BudgetSection` by kind (members passed in resolved member order for groups, `[]` for own budgets), keeping `UnassignedSection` last and the empty-state text unchanged (FR-003).
- [X] T008 [US1] Run `make test` and `make app`; both succeed.

**Checkpoint**: US1 delivers one consistent order; with no stored arrangement nothing visible changes in the bar.

---

## Phase 4: User Story 2 - Rearrange entries in Settings (P1)

**Goal**: The Menu Bar tab reorders entries and members by drag and by Move Up/Down; placement rules keep the order sensible on structural changes; changes apply and undo like other settings (FR-004a to FR-010a, FR-013, FR-014).

**Independent test**: Drag an entry, check preview, bar, dropdown, relaunch; Option-Command-Up moves the selected row; Undo restores the order.

- [X] T009 [P] [US2] Write `Tests/UsageCoreTests/ArrangementEditorTests.swift` for `ArrangementEditor` (Sources/UsageCore/Bar/ArrangementEditor.swift): (a) `rows` lists entries in order with each group's members right after it; (b) `move` of an entry row to another entry slot returns the new full arrangement; (c) moving a group row moves its member block along; (d) moving a member within its group reorders members; (e) moving a member outside its group, or an entry into a member block, returns nil; (f) `moveUp`/`moveDown` move one position within the level, a group with its members, and return nil at the first or last position; (g) `canMoveUp`/`canMoveDown` are false for a nil row, for the first or last row of a level, and for the only member of a group; (h) row ids are unique when a group and an account share an id; (i) destination boundaries per research R4 with `onMove` pre-removal coordinates: moves up and down for entries and members, a member accepted for destinations f...l+1 of its block, an entry rejected at the start of or inside a member block, no-op destinations (source and source+1, or inside the moved group block) return nil, and an `IndexSet` with two elements returns nil.
- [X] T010 [US2] Implement `Sources/UsageCore/Bar/ArrangementEditor.swift` (`ArrangementRow` with `id`, `rows(_:)`, `move(_:from:to:)`, `moveUp`, `moveDown`, `canMoveUp`, `canMoveDown`) per data-model.md and research R4. Every returned arrangement is complete (all entries, all members). T009 passes.
- [X] T011 [P] [US2] Write `Tests/UsageCoreTests/ArrangementReconcileTests.swift` for `Configuration.reconcilingArrangement(previous:)`: (a) unrelated change (refresh interval, an icon) with nil arrangement stays nil (FR-004); (b) adding a subscription account while a group exists stores an order with the account last (FR-004a, FR-005); (c) adding an account that lands last in default order anyway keeps nil; (d) a new member is appended last in its group; (e) `movingAccountToOwnBudget` places the account directly after its former group (FR-006); (f) when the former group is pruned (`pruningEmptyGroups`) the account takes the group's position; (g) own budget to group and group to group place the account last in the new group and keep the rest (FR-007); (h) removing an account or group drops it and keeps the relative order (FR-008); (i) a reorder (next arrangement differs from previous) is kept and stored, with placement rules applied on top: a reorder plus an account leaving its group in the same apply puts the account directly after its group (FR-006); (j) with a stored arrangement, structural changes keep it stored; (k) two accounts leaving the same group in one apply are inserted after it in accounts-list order; (l) a reorder base from the draft that already contains the moved account, with its group pruned, puts the account at the anchor of research R3 step 2.2 exactly once; (m) reconciling a configuration against itself returns it unchanged, both with nil and with a hand-edited stale arrangement (no-op check).
- [X] T012 [US2] Implement `reconcilingArrangement(previous:)` in `Sources/UsageCore/Config/Arrangement.swift` per research R3 and the reconciliation table in data-model.md. T011 passes.
- [X] T013 [US2] In `Sources/LLMUsageMenuBar/SettingsView.swift` `applyNow`, compute the candidate as `draft.pruningEmptyGroups()` and, unless it equals the configuration the last undo restored (keep it in a `@State var undoTarget: Configuration?` set in `registerUndo`'s handler and cleared after use), `.reconcilingArrangement(previous: applied)` (research R3: an undo restores an already reconciled state). Keep the existing equality, save, draft write-back and undo logic. Undo after a reorder and after moving an account to its own budget must restore the previous order.
- [X] T014 [US2] Create `Sources/LLMUsageMenuBar/MenuBarSettingsTab.swift` per contracts/menu-bar-tab.md: preview (`BarLabelView(items: BarLayout.segments(snapshot: model.snapshot, configuration: draft))` on a dark capsule with a "Preview" caption; the bar image is a black template image, so render it with `.renderingMode(.template)` and a white foreground, adding a parameter to `BarLabelView` if needed), a `List(selection:)` over `ArrangementEditor.rows(draft)` with indented member rows, icon, name, kind caption, secondary styling for hidden rows, `.onMove` calling `ArrangementEditor.move` and assigning `draft.arrangement` when non-nil, Move Up/Move Down buttons with `.keyboardShortcut(.upArrow/.downArrow, modifiers: [.option, .command])` disabled via `canMoveUp/canMoveDown` (the moved row stays selected, row ids are stable), the explanatory caption, and the empty state. Use the existing icon rendering helper used by the account list (`labelText` or `IconFont`).
- [X] T015 [US2] Add the tab to `SettingsView` in `Sources/LLMUsageMenuBar/SettingsView.swift` as the second tab: `MenuBarSettingsTab(draft: $draft, model: model)`, `Label("Menu Bar", systemImage: "menubar.rectangle")`, tag `"menubar"` (FR-009).
- [X] T016 [US2] Run `make test` and `make app`; both succeed.

**Checkpoint**: Entries can be rearranged and the order persists; structural changes place entries per FR-005 to FR-008.

---

## Phase 5: User Story 3 - Show and hide entries from the same list (P2)

**Goal**: Each row's "Show in bar" checkbox changes the same setting as the editors (FR-012).

**Independent test**: Toggle a checkbox in the tab and see the editor toggle, preview and bar follow; toggle in the editor and see the checkbox follow.

- [X] T017 [US3] Add tests to `Tests/UsageCoreTests/ArrangementEditorTests.swift` for `Configuration.isShownInBar(_:)` and `settingShownInBar(_:_:)`: subscription (`SubscriptionSettings.shownInBar`), Codex subscription (`CodexSubscriptionSettings.shownInBar`), own budget (`BudgetSettings.shownInBar` inside `.ownBudget`), group (`BudgetGroup.shownInBar`), member (`TokenMembership.group(id:shownInBar:)`); a group and an account sharing an id are toggled independently; toggling does not change the arrangement.
- [X] T018 [US3] Implement `isShownInBar` and `settingShownInBar` in `Sources/UsageCore/Config/Arrangement.swift` (research R6). T017 passes.
- [X] T019 [US3] Add the "Show in bar" `Toggle` (checkbox style, label hidden for layout, accessibility label kept) to every row in `Sources/LLMUsageMenuBar/MenuBarSettingsTab.swift`, bound through a `Binding` that reads `draft.isShownInBar(row)` and writes `draft = draft.settingShownInBar(row, value)`.
- [X] T020 [US3] Run `make test` and `make app`; both succeed.

---

## Phase 6: Polish

- [X] T021 [P] Update `README.md`: the settings section lists five tabs including "Menu Bar" (order of the bar and the dropdown, drag or Option-Command-Up/Down, show-in-bar checkboxes); the configuration section mentions the optional `arrangement` key (contracts/config-file.md).
- [X] T022 [P] Check every changed file for em-dash and en-dash characters (`rg -n '[\x{2013}\x{2014}]'`) and remove any.
- [X] T023 Run the full `make test` and `make app`, then walk through quickstart.md steps 1 to 9 as far as possible without user interaction; note any step that needs the user.

---

## Dependencies

- Phase 1 then Phase 2 (T002 to T004) block everything.
- US1 (T005 to T008) depends on Phase 2.
- US2: T009/T010 and T011/T012 depend on Phase 2 and are independent of each other; T013 needs T012; T014 needs T010; T015 needs T014.
- US3: T017/T018 depend on T010 (they use `ArrangementRow` and extend `ArrangementEditorTests.swift`); T019 needs T014 and T018.
- Polish after all stories.

## Parallel opportunities

- T009 and T011 (different test files), then T010 and T012 (different source files).
- T017 can be written while T014 is in progress (after T010).
- T021 and T022.

## Implementation strategy

MVP is Phase 2 plus US1: one consistent order with no visible change for existing users. US2 adds the tab and the placement rules; US3 adds the checkboxes. Each phase ends with a green `make test`.
