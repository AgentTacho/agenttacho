# Feature Specification: Menu Bar Arrangement

**Feature Branch**: `008-menu-bar-arrangement`

**Created**: 2026-10-15

**Status**: Draft

**Input**: User description: "Menu bar arrangement (from brainstorm/07-menu-bar-arrangement.md). The bar entries and the dropdown sections currently follow three different fixed orders. Add a new Menu Bar settings tab with one ordered list of every top-level entry that can appear, with each group's members indented under it. Drag reorders top-level entries anywhere and members only within their group, with a Move Up/Move Down alternative. Each row has a Show in bar checkbox bound to the same setting as the existing toggles. A live preview of the bar sits on top of the list. The bar and the dropdown sections both follow this order. The order is persisted in the configuration file."

This feature changes rules from earlier specs: the bar order of `specs/004-icon-labels-standalone-budgets/spec.md` FR-020 (accounts first, then groups) and the dropdown order of `specs/001-llm-usage-menubar/spec.md` and spec 004 FR-010 (subscription accounts, then groups, then accounts with their own budget), as extended for Codex subscription accounts by `specs/007-codex-plan-limits/spec.md` FR-012. The placement of group members (spec 004 FR-019: members follow their group, a hidden group's shown members take its place) is kept.

## Terms

- **Entry**: anything that can have its own place in the bar and its own section in the dropdown: a Claude subscription account, a Codex subscription account, a token-based account with its own budget, or a budget group.
- **Member**: a token-based account that belongs to a budget group. It can be shown in the bar on its own (spec 004 FR-016 to FR-019), but it has no place of its own in the order; it always belongs to its group.
- **Arrangement**: the user-defined order of all entries, plus the order of the members inside each group.

## Clarifications

### Session 2026-10-15

- Q: Where does an account land when it moves directly from one group to another group? → A: Last member of the new group; the other entries and members keep their order.
- Q: Is the default arrangement written to the configuration file on the first launch after the update, or only when the user first changes the order? → A: Only on the first change that affects the order (a reorder, or a change covered by FR-005 to FR-008, see FR-004a); until then the default order is derived on every load and the configuration file is not rewritten.
- Q: Which keyboard shortcuts move the selected row in the Menu Bar tab? → A: Option-Command-Up Arrow and Option-Command-Down Arrow.
- Q: Where does the Menu Bar tab sit among the Settings tabs? → A: Second, directly after General.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Bar and dropdown follow one order (Priority: P1)

A user opens Settings and sees their accounts in one order, but the bar shows a group after all accounts and the dropdown uses yet another order. After this feature, the bar and the dropdown follow the same arrangement, so what is first in one is first in the other.

**Why this priority**: This removes the impression that the order is random and is the base for every other story. Without a single order, rearranging would have no consistent effect.

**Independent Test**: Configure a subscription account, a Codex subscription account, a group and an account with its own budget, all shown in the bar. Without touching any order, compare the bar entries with the dropdown sections: both list the entries in the same sequence.

**Acceptance Scenarios**:

1. **Given** a configuration with entries A (subscription), G (group), B (own budget) arranged in that order, all shown in bar, **When** the bar and the dropdown are displayed, **Then** the bar shows A, G, B and the dropdown shows the sections A, G, B in that order.
2. **Given** entry G is hidden from the bar, **When** the bar and the dropdown are displayed, **Then** the bar shows A, B and the dropdown still shows A, G, B.
3. **Given** group G is hidden from the bar but its member M is shown in bar, **When** the bar is displayed, **Then** M appears at G's position between A and B.
4. **Given** an existing configuration from before this feature, **When** the app starts the first time after the update, **Then** the bar shows its entries in the same order as before the update, and the dropdown follows that order.
5. **Given** a group and an account with its own budget that share the same id, **When** the user moves the account to the first position, **Then** only the account moves and the group keeps its position.

---

### User Story 2 - Rearrange entries in Settings (Priority: P1)

A user wants the Vertex budget group first in the bar, before the Claude subscription. They open the new Menu Bar tab in Settings, drag the group to the top of the list, and the bar and the dropdown change immediately.

**Why this priority**: Manual arrangement is the main request; it is what makes the order the user's own.

**Independent Test**: In the Menu Bar tab, drag an entry to a new position and check the preview, the bar and the dropdown; quit and relaunch the app and check that the order is kept.

**Acceptance Scenarios**:

1. **Given** the Menu Bar tab lists A, G, B, **When** the user drags B above A, **Then** the list shows B, A, G, the preview at the top of the tab shows the bar in that order, and the bar and the dropdown follow within a moment.
2. **Given** group G with members M1 and M2 listed below it, **When** the user drags G to another position, **Then** M1 and M2 move with G and stay below it.
3. **Given** group G with members M1, M2, **When** the user drags M2 above M1, **Then** the members are listed M2, M1, and when both are shown in bar they appear in that order after G.
4. **Given** member M1 of group G, **When** the user tries to drag M1 outside G (to the top level or into another group), **Then** the drop is not accepted and M1 stays in G.
5. **Given** a selected row, **When** the user chooses Move Up or Move Down (by button or keyboard shortcut), **Then** the row moves one position within its level, the same way a drag would.
6. **Given** the user rearranged the entries, **When** the app is quit and started again, **Then** the arrangement is the same.
7. **Given** the user rearranged the entries, **When** the user chooses Undo in Settings, **Then** the previous arrangement is restored, as for other settings changes.

---

### User Story 3 - Show and hide entries from the same list (Priority: P2)

A user wants to decide in one place which entries appear in the bar. Each row of the Menu Bar tab has a "Show in bar" checkbox. Turning it off removes the entry from the bar and the preview, while the entry keeps its position for when it is turned on again.

**Why this priority**: Visibility and order belong together when arranging the bar, but the toggles already exist in the account and group editors, so this is a convenience on top of P1.

**Independent Test**: Turn off "Show in bar" for an entry in the Menu Bar tab and check that the bar, the preview and the toggle in the entry's editor all reflect the change; turn it on again and check the entry reappears at its old position.

**Acceptance Scenarios**:

1. **Given** entry A shown in bar, **When** the user clears its checkbox in the Menu Bar tab, **Then** A disappears from the preview and the bar, and the "Show in menu bar" toggle in A's account editor is off.
2. **Given** entry A hidden from the bar, **When** the user turns on "Show in menu bar" in A's account editor, **Then** the checkbox in the Menu Bar tab is on and A appears in the bar at its position in the arrangement.
3. **Given** a member M of group G, **When** the user turns on M's checkbox, **Then** M's share appears in the bar after G (or at G's position when G is hidden), and the member toggle in M's account editor is on.

---

### Edge Cases

- **New entry**: a newly added subscription account, Codex subscription account, account with its own budget, or group is placed at the end of the arrangement.
- **New member**: an account that joins a group is placed as the last member of that group.
- **Account leaves a group for its own budget**: the account becomes an entry placed directly after its former group. If the group is deleted because it has no members left (spec 004 FR-014), the account takes the group's position.
- **Account with its own budget joins a group**: it leaves the top level and becomes the last member of the group; the other entries keep their order.
- **Account moves from one group to another**: it becomes the last member of the new group; the members of the old group keep their order.
- **Removed account or group**: it disappears from the arrangement; the others keep their relative order.
- **Configuration edited by hand**: unknown ids in the stored order are ignored, duplicate ids count at their first position only, and entries or members missing from the stored order are appended in the default order (FR-011). None of these cases is a configuration error.
- **No stored order**: the default order applies (FR-011). The first change that affects the order (a reorder in the tab, or any change covered by FR-005 to FR-008) stores the order currently shown and then applies the change, so the placement rules hold even before the user ever reordered anything.
- **Ids at the wrong level** in a hand-edited arrangement (a member listed among the entries, an entry listed as a member, or a member listed under a group it does not belong to): treated like unknown ids; the item is then placed by the missing-item rule of FR-011.
- **A group and an account with the same id** (allowed by the configuration): they are distinct entries with independent positions.
- **Token-based account without group and without own budget** (not valid per spec 004 FR-008) or the Unassigned entry: neither appears in the Menu Bar tab; Unassigned stays the last section of the dropdown.
- **Empty bar**: when every entry and member is hidden, the preview shows the same placeholder the bar shows today.
- **Only row at its level** (a single entry, or a group's only member): Move Up and Move Down are unavailable for it and dragging has no effect; members of a group with two or more members can still be reordered.

## Requirements *(mandatory)*

### Functional Requirements

**Arrangement**

- **FR-001**: The app MUST keep one arrangement: an order of all entries, and for every group an order of its members.
- **FR-002**: The menu bar MUST show the entries that are shown in bar in arrangement order. After a group's position, its members that are shown in bar MUST follow in member order. When the group itself is hidden, its shown members MUST take the group's position (spec 004 FR-019 unchanged).
- **FR-003**: The dropdown MUST show one section per entry in arrangement order, whether or not the entry is shown in bar. Inside a group's section, the members MUST be listed in member order. The Unassigned section, when present, MUST remain the last section.
- **FR-004**: The arrangement MUST be stored in the configuration file and MUST survive app restarts. As long as nothing has changed the order, no arrangement is stored and the default order (FR-011) is derived on every load; loading a configuration, or saving a settings change that does not affect the order, MUST NOT add an arrangement to the file.
- **FR-004a**: When a change that affects the order (a reorder in the Menu Bar tab, or a change covered by FR-005 to FR-008) is made while no arrangement is stored, the app MUST first take the order currently in effect, apply the change, and store the result whenever it differs from the default order (FR-011), so that FR-005 to FR-008 hold from the first change on. A result that equals the default order is not stored, since deriving it again gives the same order.
- **FR-005**: A newly created entry MUST be placed at the end of the arrangement. A newly joined member MUST be placed last in its group.
- **FR-006**: An account that leaves a group and gets its own budget MUST be placed directly after its former group; when that group is deleted as a result, the account MUST take the group's position.
- **FR-007**: An account that moves from its own budget into a group, or from one group into another, MUST be placed last in the new group and removed from its previous place. All other entries and members MUST keep their relative order.
- **FR-008**: Removing an account or group MUST remove it from the arrangement without changing the relative order of the rest.

**Menu Bar settings tab**

- **FR-009**: Settings MUST have a tab named "Menu Bar", placed second directly after General, that lists every entry in arrangement order, each with its icon, name and kind (subscription, Codex plan, own budget, budget group), and each group's members indented below the group in member order. Accounts that are neither an entry nor a member, and the Unassigned entry, MUST NOT be listed.
- **FR-010**: The user MUST be able to reorder entries by dragging them to any position among the entries, and members by dragging them to any position within their own group. Dragging a group MUST move its members along. A drop that would move a member out of its group, or an entry into a group, MUST NOT be accepted.
- **FR-010a**: Every reorder that is possible by dragging MUST also be possible without a pointer: Move Up and Move Down commands for the selected row, available as buttons in the tab and through the keyboard shortcuts Option-Command-Up Arrow and Option-Command-Down Arrow, moving the row one position within its level. Moving a group moves its members along. The commands MUST be disabled when no row is selected, and when the selected row is already first or last in its level.
- **FR-011**: When the configuration has no stored arrangement, or the stored arrangement misses entries or members, the missing ones MUST be appended after the stored ones in the default order: subscription accounts, Codex subscription accounts and accounts with their own budget in accounts-list order, then groups in groups-list order; missing members are appended last in their group in accounts-list order. For a configuration from before this feature (nothing stored) this reproduces the previous bar order (spec 004 FR-020). Unknown references in a stored arrangement, and references at the wrong level (a member among the entries, an entry among a group's members, a member under a group it does not belong to), MUST be ignored; duplicates MUST count at their first position. None of these cases is a configuration error.
- **FR-012**: Every row MUST have a "Show in bar" checkbox. For an entry it MUST change the same setting as the "Show in menu bar" toggle in the entry's account or group editor; for a member it MUST change the same setting as the member's "Show this account's share in the menu bar" toggle. Changing it in either place MUST show the new state in the other.
- **FR-013**: The tab MUST show a preview of the bar above the list, built by the same rules as the bar (FR-002, including icons, warning styling and placeholders), that updates as soon as the arrangement or a checkbox changes. The preview MUST reflect the order and visibility being edited in Settings, with values from the latest usage data; an entry without data yet shows the placeholder the bar uses before the first refresh.
- **FR-014**: Changes made in the tab MUST be applied and saved the same way as other settings changes: they take effect in the bar and the dropdown shortly after the edit, and Undo in Settings restores the previous state. Undoing the first order change restores the previous order; whether the arrangement stored by FR-004a stays in the file afterwards is not observable in the bar or the dropdown and is left to planning.
- **FR-015**: The Accounts and Groups tabs, and the account and group editors, MUST keep working as before; their lists are not required to follow the arrangement.

### Key Entities *(include if feature involves data)*

- **Arrangement**: stored with the configuration. An ordered list of entry references, each naming whether it is an account or a group plus its id (a group and an account may share an id), and for each group an ordered list of its member account ids. It holds only order; visibility stays in the existing shown-in-bar settings of accounts, own budgets, groups and members.
- **Entry**: a Claude subscription account, a Codex subscription account, a token-based account with its own budget, or a budget group, identified by its existing account or group id.
- **Member**: a token-based account in a group, identified by its account id, ordered within its group.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For any configuration, the sequence of entries in the bar equals the sequence of dropdown sections with hidden entries removed (and the Unassigned section ignored), in 100% of tested configurations.
- **SC-002**: Any entry can be moved to the first position of the bar with a single drag, or with at most N-1 Move Up commands for N entries, from the Menu Bar tab.
- **SC-003**: After an update from a version without this feature, the bar order is unchanged for 100% of existing configurations.
- **SC-004**: The arrangement survives 100% of app restarts and of settings edits that do not change entries or members.
- **SC-005**: Every reorder that can be done with the pointer can also be done with the keyboard alone.

## Assumptions

- The tab name is "Menu Bar"; it sits between the existing General and Accounts tabs.
- The default order for existing configurations is the previous bar order (accounts first, then groups), so the bar does not change on update; only the dropdown changes to match the bar.
- The "Show in menu bar" toggles stay in the account and group editors as well; the tab adds a second place to change the same settings.
- The Accounts and Groups lists in Settings keep their current order and are out of scope.
- Changing group membership by dragging, dragging inside the menu bar itself, and merging the Accounts and Groups tabs are out of scope.
- The exact storage format of the arrangement is a planning decision; any format must tolerate hand edits as described in FR-011.
