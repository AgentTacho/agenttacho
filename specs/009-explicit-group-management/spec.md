# Feature Specification: Explicit Group Management

**Feature Branch**: `009-explicit-group-management`

**Created**: 2026-10-15

**Status**: Draft

**Input**: User description: "Explicit group management (from brainstorm/08-explicit-group-management.md). Budget groups become first-class: the Groups tab gets Add and Remove buttons; empty groups are valid and never deleted implicitly; removing a group with members asks where the members go; membership stays editable only from the account editor."

This feature replaces the group lifecycle rules of earlier specs: the deletion of a group with its last member in `specs/001-agentmeter/spec.md` FR-019 ("a group MUST contain one or more accounts", "Removing the last member of a group MUST delete the group") and in `specs/004-icon-labels-standalone-budgets/spec.md` FR-014 ("Removing an account from a group that leaves the group without members MUST delete the group"). Spec 008's edge case for a group deleted because it has no members left, and the "group deleted as a result" clause of spec 008 FR-006, now apply only to an explicit group removal (FR-011). Everything else in those requirements (one budget per group, membership choice when creating an account, moving between own budget and group) stays.

## Clarifications

### Session 2026-10-15

- Q: What does an empty group's dropdown section contain besides the note? → A: The same header as any group (icon, name, 0%, budget with period, reset time), the note "No accounts in this group yet" in place of the member list, and no breakdown or trend.
- Q: Does the remove dialog name the members that will move? → A: Yes; it lists the member accounts by name before the destination choice.
- Q: Where does an added group appear in the Groups tab list? → A: At the end of the list, selected.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A group survives losing its members (Priority: P1)

A user moves the only account of their "Vertex" group to its own budget, for example to try a separate budget for a week. Today the group disappears with its budget, thresholds and position in the bar. After this feature the group stays, empty, and the account can be moved back into it later.

**Why this priority**: This is the dead end that started the feature: an action in Settings silently destroys configuration the user did not ask to remove.

**Independent Test**: Move the only member of a group to its own budget (or remove that account) and check that the group is still listed in the Groups tab with its budget, thresholds and bar position, then move the account back into it.

**Acceptance Scenarios**:

1. **Given** a group "Vertex" whose only member is account A, **When** the user switches A to its own budget, **Then** "Vertex" stays in the Groups tab with its name, icon, period, amount, thresholds and shown-in-bar setting, and A appears as its own budget.
2. **Given** that empty "Vertex" group, **When** the user switches A back to "Vertex" in the account's Budget picker, **Then** A is a member of "Vertex" again.
3. **Given** a group whose only member is account A, **When** the user removes account A, **Then** the group stays, empty.
4. **Given** an empty group shown in the bar, **When** the bar is displayed, **Then** the group shows 0%, and its dropdown section says it has no accounts yet.

---

### User Story 2 - Create a budget group on its own (Priority: P1)

A user wants to set up the company's monthly Vertex budget before configuring the account that uses it. In the Groups tab they press Add, a new group appears selected with defaults, and they adjust name, period and amount.

**Why this priority**: Without it, groups can still only be created as a side effect of creating an account, which is the second half of the original problem.

**Independent Test**: Press Add in the Groups tab and check that a new group with the defaults appears, is selected and editable, and shows up in the Menu Bar tab and the bar.

**Acceptance Scenarios**:

1. **Given** the Groups tab, **When** the user presses Add, **Then** a new group named "Budget group" appears selected, with the default icon, a weekly budget of 60 US dollars, shown in the bar, and thresholds 80% and 100%.
2. **Given** a newly added group, **When** the user opens the Accounts tab and edits a token-based account, **Then** the new group is offered in the Budget picker.
3. **Given** a newly added group, **When** the user looks at the Menu Bar tab, **Then** the group is listed at the end of the arrangement.

---

### User Story 3 - Remove a group, members included (Priority: P2)

A user no longer needs a group that still has two member accounts. They select it and press Remove. A dialog asks where the members go: their own budgets, or another group. After confirming, the group is gone and the members continue under the chosen destination.

**Why this priority**: Completes explicit management; less frequent than creating or keeping groups.

**Independent Test**: Remove a group with two members, once choosing own budgets and once choosing another group, and check the members' budgets afterwards; remove an empty group with a plain confirmation; undo a removal.

**Acceptance Scenarios**:

1. **Given** group G with members A and B, **When** the user removes G and chooses "own budgets", **Then** G is gone, and A and B each have their own budget with G's period, amount, thresholds and shown-in-bar setting.
2. **Given** groups G (members A, B) and H, **When** the user removes G and chooses H, **Then** G is gone and A and B are members of H.
3. **Given** an empty group, **When** the user presses Remove, **Then** a plain confirmation appears and, once confirmed, the group is gone.
4. **Given** a group was just removed, **When** the user chooses Undo in Settings, **Then** the group and its members' previous membership are back.
5. **Given** a removed group, **When** the bar and the Menu Bar tab are displayed, **Then** the group is no longer listed and the other entries keep their order.

---

### Edge Cases

- **The only group is removed with members**: the "another group" choice is unavailable; only "own budgets" is offered.
- **Destination group with a different period**: allowed; members simply count against that group's budget and period from then on.
- **New-account sheet**: it offers the groups that exist when it opens, including empty ones.
- **Empty group in a hand-edited configuration**: valid, loaded and kept like any other group.
- **Empty group's threshold state**: an empty group never crosses a threshold. When it gets members again, the first refresh sets a new baseline without notifying for thresholds the new spend already exceeds (FR-006).
- **New account joins an empty group**: works like joining any group (spec 004 FR-013).
- **Removing the last member of a group with the account's Remove button**: the group stays (User Story 1, scenario 3).
- **Several empty groups**: each is shown, ordered and editable on its own.

## Requirements *(mandatory)*

### Functional Requirements

**Group lifecycle**

- **FR-001**: A budget group MUST be allowed to have zero member accounts. A configuration with an empty group MUST be valid.
- **FR-002**: The app MUST NOT delete a group implicitly: not when its last member moves to its own budget or to another group, not when its last member is removed, and not when the configuration is loaded or applied. This replaces the group deletion of spec 001 FR-019 and spec 004 FR-014.
- **FR-003**: A group MUST only be deleted by the user's explicit Remove action in the Groups tab (FR-008) or by removing it from the configuration file by hand.

**Empty groups**

- **FR-004**: An empty group MUST keep its name, icon, period, amount, thresholds, shown-in-bar setting and position in the menu bar arrangement (spec 008).
- **FR-005**: An empty group shown in the bar MUST show 0% with normal styling after the first refresh, and the usual placeholder before it. Its dropdown section MUST show the usual group header (icon, name, 0%, budget with period, reset time) and the note "No accounts in this group yet" instead of members, breakdown and trend.
- **FR-006**: An empty group MUST never trigger a notification, since its spend is zero. When an empty group gets a member, or a removal moves members to their own budgets or to another group, every affected budget re-baselines in the same way as spec 004 FR-015 (also for members moved from one group to another): the first refresh after the change sets the baseline without notifying for thresholds already exceeded.

**Adding a group**

- **FR-007**: The Groups tab MUST have an Add button. Add MUST create a group named "Budget group" with the default group icon, a weekly budget of 60 US dollars, shown in the bar, and thresholds 80% and 100% (the defaults of a group created in the new-account sheet), append it to the Groups tab list and to the end of the menu bar arrangement (spec 008 FR-005), and select it for editing. Pressing Add again creates another group with the same default name; group names need not be unique.

**Removing a group**

- **FR-008**: The Groups tab MUST have a Remove... button, enabled when a group is selected. After any group removal, no group is selected.
- **FR-009**: Removing an empty group MUST ask for a plain confirmation naming the group.
- **FR-010**: Removing a group with members MUST list the member accounts by name and ask for one destination for all of them before removing it: "Own budgets", which gives each member its own budget with the group's period, amount, thresholds and shown-in-bar setting (the values moving out of a group starts with, spec 004 FR-014), or one of the other existing groups, listed in Groups tab order, which makes each member a member of that group with its share hidden from the bar (spec 004 FR-016). When no other group exists, only "Own budgets" MUST be offered. Cancelling MUST change nothing.
- **FR-011**: A removed group MUST disappear from the configuration, the bar, the dropdown and the menu bar arrangement, and its notification state MUST be cleared. The remaining entries keep their order (spec 008 FR-008). Members that got their own budget take the removed group's position in the arrangement, in the group's member order (spec 008 FR-001, FR-006); this is now the only case in which spec 008 FR-006's "group deleted as a result" applies. Members moved to another group are placed last in that group, in the removed group's member order (spec 008 FR-007).
- **FR-012**: Undo in Settings MUST restore a removed group together with its arrangement position and its members' previous membership, positions and member shown-in-bar settings, like any other settings change. Every budget affected by the undo re-baselines as in FR-006.

**Unchanged and clarified behavior**

- **FR-013**: Group membership MUST stay editable only from the account side: the account editor's Budget picker and the new-account sheet. The group editor lists the members but does not change them; for an empty group it shows "No accounts in this group yet".
- **FR-014**: The new-account sheet MUST keep its "New group" choice (spec 004 FR-013).
- **FR-015**: The Groups tab caption MUST read: "Add and remove groups here. A group stays when its last account leaves; membership is set in each account's Budget picker."
- **FR-016**: The confirmation for removing an account MUST no longer say that its group is removed. When the account is the last member of a group, it adds: "The group \"<name>\" stays, without accounts."

### Key Entities *(include if feature involves data)*

- **Budget group**: unchanged fields (id, name, icon, period, amount, thresholds, shown in bar); it may now have zero members.
- **Removal destination**: the choice made when removing a group with members: own budgets, or one other existing group.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: No sequence of membership changes or account removals in Settings deletes a group; a group disappears only after the user removes it.
- **SC-002**: A user can create a new budget group and attach an existing account to it in under one minute, without creating a new account.
- **SC-003**: Removing a group with members leaves none of its former members without a budget (each has its own budget or belongs to the chosen group) in 100% of cases.
- **SC-004**: Configurations from before this feature load unchanged and behave as before, apart from groups no longer disappearing.

## Assumptions

- The default amount for an added group is the same as in the new-account sheet (60 US dollars per week); the user edits it right after adding.
- The remove dialog offers every other existing group as a destination, regardless of its period.
- Older AgentMeter versions reject a configuration with an empty group as invalid; this matters only if someone downgrades, and the release notes can mention it.
- The configuration format is unchanged: existing files stay valid, and a group with no members, previously a validation error, is now accepted.
- With "Own budgets", each former member gets the full group amount as its own budget, so the total budget across them grows (for example two members of a 60 USD group get 60 USD each); this is intended, and each budget can be edited afterwards.
