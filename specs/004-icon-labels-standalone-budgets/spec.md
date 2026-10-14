# Feature Specification: Icon Labels and Standalone Budgets

**Feature Branch**: `004-icon-labels-standalone-budgets`

**Created**: 2026-10-14

**Status**: Draft

**Input**: User description: "Build the feature described in brainstorm/03-icon-labels-standalone-budgets.md: remove text labels and require exactly one icon per account and group (with a default, duplicates allowed); allow token-based accounts without a group but with their own budget; allow group members to appear individually in the menu bar."

## Context

This feature changes rules from `specs/001-llm-usage-menubar/spec.md`: FR-002, FR-003, FR-019, FR-027, FR-031, FR-032, User Story 3 scenario 5 (label length), and the Account entity ("no shown-in-bar flag or thresholds" for token-based accounts). From `specs/003-monthly-budget-period/spec.md` it replaces FR-012's "label" with the icon and the label attribute of the Budget group entity. It also extends FR-018 with the "Own budget" choice. All other budget-period rules of spec 003 apply to an account's own budget as well.

Today:
- Every account and budget group has a 1 to 3 character text label (empty only when an icon is set) and an optional icon. Whatever is shown must be unique across all entries.
- Every token-based account must belong to exactly one budget group.
- Only subscription accounts and budget groups can appear in the menu bar.

The user wants three changes:
- Icon-only labelling, so that the same icon (for example Claude) can mark several accounts.
- A single token-based account with its own budget, without an artificial one-member group.
- The option to watch one member of a shared group directly in the bar.

## Clarifications

### Session 2026-10-14

- Q: Should the dropdown also show a group member's share of the group budget, or only the bar? → A: The dropdown shows every group member's share as a percent next to its spend, whether or not the member is shown in bar, so the bar value can always be checked against the dropdown.
- Q: How is an account's own budget validated when the configuration is edited by hand? → A: With exactly the same rules as a group budget: the amount must be greater than 0, the period must be weekly or monthly (absent means weekly), and thresholds are whole numbers greater than 0. Any violation makes the configuration invalid (spec 001 FR-033).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Icon-only labels with defaults (Priority: P1)

The developer opens settings to add a second Claude subscription account. The new account already shows the Claude icon, and there is no text label field. They keep the Claude icon even though the first subscription account uses it too, and saving works. In the bar and the dropdown, both accounts show the Claude icon. The dropdown and settings also show each account's name next to its icon.

**Why this priority**: Labelling is visible everywhere and currently blocks a natural setup (the same icon for several Claude Code accounts).

**Independent Test**: Create two accounts and one group with the same icon, save, and confirm that the configuration is accepted. Confirm that no text label field exists and that every entry shows exactly one icon in the bar, the dropdown, and settings.

**Acceptance Scenarios**:

1. **Given** the user creates a new subscription account, **When** the creation form opens, **Then** the Claude icon is preselected and no text label field is offered.
2. **Given** the user creates a new token-based Vertex account, **When** the form opens, **Then** the Google icon is preselected. A new budget group starts with the wallet icon.
3. **Given** two accounts use the same icon, **When** the user saves, **Then** the configuration is accepted, and both show that icon in the bar and the dropdown.
4. **Given** the icon picker, **When** the user tries to clear the icon, **Then** this is not possible: an entry always has exactly one icon.

---

### User Story 2 - Token-based account with its own budget (Priority: P1)

The developer adds a personal Vertex project that has its own spending limit and no relation to the team group. In settings they choose "Own budget" instead of a group and set Monthly and $100. The account then appears in the dropdown as its own entry: spend, budget, percent, reset, and breakdown. It can be shown in the bar and notifies at its thresholds, exactly like a group.

**Why this priority**: This removes the most awkward part of the current model (one-member groups for independent accounts).

**Independent Test**: Configure one token-based account with its own monthly budget and no group. Confirm that the dropdown, the bar, and threshold notifications behave as they would for a group with that budget.

**Acceptance Scenarios**:

1. **Given** a token-based account with its own budget of $100 per month and $25 spent this month, **When** the refresh runs, **Then** the dropdown shows the account with "$25.00 of $100.00 per month (25%)" and a reset on the 1st of next month.
2. **Given** the same account is marked as shown in bar, **When** the refresh runs, **Then** the bar shows its icon with 25%.
3. **Given** the account has a 50% threshold, **When** spend crosses 50% of its budget, **Then** one notification names the account and the window.
4. **Given** the account has its own budget, **When** the user moves it into an existing group and saves, **Then** its spend counts toward that group from the next refresh, and its own budget is gone.
5. **Given** an account in a group, **When** the user switches it to "Own budget" and saves, **Then** it leaves the group, carries its own budget, and the group keeps its remaining members. A group that loses its last member is deleted.

---

### User Story 3 - Group member shown individually in the bar (Priority: P2)

The team shares one Vertex group with a budget of $300 per month. The developer wants to see their own account's share directly in the bar. They enable "Show in menu bar" on their account, which stays in the group. The bar then shows the group's icon and percent, followed by the account's icon with its spend as a percent of the group budget.

**Why this priority**: This gives useful visibility, but the core labelling and budget changes deliver value without it.

**Independent Test**: In a group with a $300 budget, mark one member as shown in bar. With $90 spent by that member, confirm the bar shows that member's icon with 30% right after the group's entry.

**Acceptance Scenarios**:

1. **Given** a group with a $300 budget and a member with $90 spent in the group's window, **When** the member is marked as shown in bar, **Then** the bar shows the member's icon with 30%.
2. **Given** the group itself is also shown in bar, **When** the bar is drawn, **Then** the member's entry directly follows the group's entry.
3. **Given** the group is not shown in bar, **When** the bar is drawn, **Then** the member's entry stands where the group's entry would have been.
4. **Given** the member's share reaches the group's warning threshold, **When** the bar is drawn, **Then** the member's entry uses the warning styling, and no notification is sent for the member.

---

### User Story 4 - Existing configurations keep working (Priority: P1)

The developer updates the app. Their configuration file still contains text labels, some entries without an icon, and groups shared by several accounts. The app loads it without errors and keeps every account, group, budget, and threshold. Each entry that had no icon gets its default icon.

**Why this priority**: An update must never lose or reject a working configuration.

**Independent Test**: Load a configuration written by the previous version that includes entries with text labels only, entries with icons, and duplicate-free labels. Confirm that every entry loads with an icon (its own or the default) and that all budgets and thresholds are unchanged.

**Acceptance Scenarios**:

1. **Given** an account with the text label "M" and no icon in a previous-version file, **When** the app loads it, **Then** the account shows the default icon for its type.
2. **Given** an account with both a text label and an icon, **When** the app loads it, **Then** its icon is kept and the text label is ignored.
3. **Given** such a file was loaded, **When** the user saves any change in settings, **Then** the file no longer contains text labels, and loading it again gives the same accounts, groups, icons, and budgets.

---

### Edge Cases

- **Duplicate icons in the bar.** Two bar entries share an icon: both are shown in configuration order, and the dropdown (icon plus name) tells them apart.
- **Unknown icon.** A hand-edited configuration uses an icon that is not in the bundled catalog: the configuration is rejected as invalid, and the last valid configuration stays in effect, as today.
- **Group and own budget together.** A hand-edited token-based account names a group and also carries its own budget: the configuration is rejected as invalid.
- **Neither group nor own budget.** A hand-edited token-based account has neither a group nor its own budget: the configuration is rejected as invalid.
- **Member shown, group hidden.** A member is shown in bar while its group is not: only the member's entry appears, at the group's position.
- **Several members shown.** Several members of one group are shown in bar: their entries follow the group's position in accounts-list order.
- **Over-budget share.** A member's spend exceeds the group budget on its own: its percent is shown as the actual value above 100%, as for groups.
- **Mid-window move.** An account with its own budget moves into a group mid-window, or out of one: its old threshold state is dropped, and the new budget's first refresh after the move establishes a baseline without notifications.
- **Unassigned entry.** It keeps its current fixed presentation. It is not a configurable entry and needs no icon setting.

## Requirements *(mandatory)*

### Functional Requirements

Labels:

- **FR-001**: Every account and every budget group MUST have exactly one icon from the bundled icon catalog. Accounts and groups MUST NOT have a text label.
- **FR-002**: New entries MUST start with a default icon: the Claude icon (`brands:claude`) for subscription accounts, the Google icon (`brands:google`) for Vertex token-based accounts, and the wallet icon (`solid:wallet`) for budget groups. The user MUST be able to change it to any catalog icon in settings, but MUST NOT be able to remove it.
- **FR-003**: Several accounts and groups MAY use the same icon. The uniqueness rule for labels (spec 001 FR-032) is removed.
- **FR-004**: Settings and the dropdown MUST show each account and group as its icon followed by its name. The menu bar MUST show each entry as its icon followed by its percent (spec 001 FR-002, with the icon in place of the text label). Wherever an entry is named in plain text (notifications, the diagnostic log, accessibility labels of bar entries), its name MUST be used, not its icon's name, so entries sharing an icon stay distinguishable.
- **FR-005**: A configuration entry with an icon that is not in the catalog MUST make the configuration invalid, handled as in spec 001 FR-033.

Legacy configurations:

- **FR-006**: A configuration written by the previous version MUST load without error. An entry without an icon MUST receive the default icon for its type (FR-002). An entry with an icon keeps it. Any stored text label MUST be ignored.
- **FR-007**: When the app saves the configuration, it MUST NOT write text labels. It MUST NOT rewrite the file solely because a legacy file was loaded.

Token-based account budgets:

- **FR-008**: Every token-based account MUST have exactly one of: membership in a budget group, or its own budget. A configuration where a token-based account has both, or neither, MUST be invalid (spec 001 FR-033). This replaces spec 001 FR-019's rule that every token-based account belongs to a group.
- **FR-009**: An account's own budget MUST have the same settings as a group budget: period (weekly or monthly, spec 003), amount in US dollars greater than 0, thresholds, and shown-in-bar. It MUST use the same window rules as a group with that period, and the same validation rules: the amount must be greater than 0, the period must be weekly or monthly (absent means weekly), and thresholds must be whole numbers greater than 0. A violation makes the configuration invalid (spec 001 FR-033).
- **FR-010**: A token-based account with its own budget MUST appear in the dropdown as its own budget entry. The entry shows spend to date, the budget with its period, the percent used, the reset time, and the per-model breakdown and per-day trend, as for a group (spec 001 FR-006, FR-008; spec 003 FR-011, FR-013). Period wording ("weekly"/"monthly", "per week"/"per month") MUST follow its period in the dropdown, settings, and notifications (spec 003 FR-014). Settings MUST reject an amount of 0 or less with a message naming the period (spec 003 FR-019).
- **FR-011**: When shown in bar, a token-based account with its own budget MUST appear with its icon and percent, styled by its warning threshold like a group (spec 001 FR-003).
- **FR-012**: Thresholds of an account's own budget MUST follow the same crossing, notification, and reset rules as a group's (spec 001 FR-027 to FR-029; spec 003 FR-015 to FR-017), and notifications MUST name the account.
- **FR-013**: Creating a token-based account in settings MUST offer the choice between joining an existing group, creating a new group, or an own budget. A new own budget starts like a new group does today: weekly, shown in bar, thresholds 80% and 100%. A member joining a group starts with its member shown-in-bar setting off (FR-016).
- **FR-014**: Settings MUST let the user switch an existing token-based account between its own budget and a group in both directions. Moving into a group discards the own budget. Moving out of a group creates an own budget, prefilled with the group's period, amount, thresholds, and shown-in-bar setting, which the user can edit before saving. The account's member shown-in-bar setting is discarded when it leaves the group and starts off when it joins one. Removing an account from a group that leaves the group without members MUST delete the group and its notification state (spec 001 FR-019).
- **FR-015**: When an account changes between its own budget and a group, threshold state tied to the previous budget MUST be dropped. The first refresh after the change MUST establish a baseline without notifying for thresholds already exceeded.

Group members in the bar:

- **FR-016**: Every token-based account that belongs to a group MUST have its own shown-in-bar setting, off by default.
- **FR-017**: A group member shown in bar MUST appear with its icon and its spend in the group's current window as a percent of the group's budget. The usual rounding and over-100% rules apply (spec 001 FR-009a).
- **FR-018**: A group member's bar entry MUST use warning and over-limit styling based on the group's warning threshold applied to the member's percent (spec 001 FR-003). The member MUST NOT have thresholds of its own and MUST NOT trigger notifications. A member's bar entry MUST follow its group's data state: it shows the same placeholder before the first refresh and is marked stale whenever the group's values are stale.
- **FR-018a**: In the dropdown, every group member MUST show its share of the group budget as a percent next to its spend (same computation as FR-017), regardless of its shown-in-bar setting.
- **FR-019**: In the bar, the entries of shown members MUST follow their group's entry in accounts-list order. When the group itself is not shown, they MUST take the group's position.

Ordering:

- **FR-020**: The bar MUST order entries as follows. First come subscription accounts and token-based accounts with their own budget that are shown in bar, in the order of the accounts list. Then come groups in the order of the groups list, each followed by its shown members in accounts-list order (or the members alone when the group is hidden). This extends spec 001 FR-002, where subscriptions come first, then groups.

### Key Entities

- **Icon**: A reference to one entry of the bundled icon catalog (style and name). Required on every account and group. It may repeat across entries.
- **Budget**: Period (weekly or monthly), amount in US dollars, thresholds, and shown-in-bar. Held either by a budget group or by a single token-based account.
- **Budget group**: A named set of one or more token-based accounts sharing one budget. It has an icon and a name. Its members may each be shown in bar as their share of the group's budget.
- **Token-based account**: An account whose usage comes from local session logs. It belongs to exactly one group or holds its own budget. When it belongs to a group, it has a shown-in-bar setting for its share.
- **Subscription account**: Unchanged apart from carrying exactly one required icon instead of a text label.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can set up an independent token-based account with its own monthly budget in under one minute, without creating a group.
- **SC-002**: 100% of configuration files written by the previous version load with unchanged accounts, groups, budgets, and thresholds, and every entry shows exactly one icon.
- **SC-003**: Two or more entries with the same icon can be saved without any error or warning.
- **SC-004**: A group member shown in bar displays the same percent as its spend divided by the group budget, within 1 percentage point of rounding.
- **SC-005**: Threshold notifications for an account with its own budget arrive at most once per threshold per window, as for groups.

## Assumptions

- The default icons (`brands:claude`, `brands:google`, `solid:wallet`) exist in the bundled catalog.
- Token-based accounts are Vertex-only today. A future provider will define its own default icon.
- The dropdown keeps group members listed under their group. An account with its own budget is listed as a top-level entry, like a group.
- The Unassigned entry is not configurable and keeps its current fixed presentation.
- The bar does not add any extra marker to tell duplicate icons apart. Ordering and the dropdown are enough.
- The visual layout of the settings window (where the icon picker and the budget choice sit) is left to planning.
