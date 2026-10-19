# Feature Specification: Dropdown Layout Polish

**Feature Branch**: `026-dropdown-layout-polish`

**Created**: 2026-10-19

**Status**: Draft

**Input**: User description: "Dropdown layout polish (from brainstorm/25-dropdown-layout-polish.md). A budget group shows one Details disclosure, the group's; member summary lines stay without Details of their own, and a 'Show account details' button inside the group's Details reveals each member's tables. The member-line rule moves into tested core logic (idea inbox member-line-rule-in-core). The 'This week: ...' line in Details goes; every per-day calendar row ends with a Σ column holding the period's sum. The footer (source errors, update line, status row) stays pinned below the scrolling sections, and 'Last refreshed' sits beside the refresh icon in the status row, with the pace text as its tooltip."

Spec 025 (minimal dropdown) left four places where the dropdown spends lines or attention it does not need, found in its walkthrough. A **budget group** with members shows one **Details** disclosure per member and one for the group, so a two-member group has three. A subscription's expanded Details start with a "This week: 188.7M tokens" line (spec 025 FR-014) that only sums the **day row** below it (the per-day calendar of spec 003 FR-013). The **footer** (source errors, the update line of spec 013, "Last refreshed" and the icon row, spec 025 FR-023 to FR-027) scrolls out of view once the content is taller than the panel's height cap. And "Last refreshed" takes a line of its own above the icon row.

In this spec a **member** is a token-based account in a budget group (spec 004); a **member line** is its summary row (icon, name, amount and share, spec 004 FR-018a); a section's **tables** are the Models, Projects or Harnesses table shown by the view picker, followed by the day row. A member **with usage** is one whose breakdown for the group's period is not empty.

## Clarifications

### Session 2026-10-19

- Q: How does the pinned footer handle many source errors without crowding out the sections? → A: It shows at most 3 error lines; further errors collapse into one line "+N more" whose tooltip lists them all. The sections keep a minimum visible height of 160 pt.
- Q: Is the "Show account details" state remembered per group or once for all groups? → A: Once for all groups, like the view picker choice.
- Q: What does the Σ column's tooltip say? → A: The exact sum in the same wording as a day column's tooltip, prefixed with "Total" (for example "Total: 188.7M tokens" or "Total: $430.12").

## User Scenarios & Testing *(mandatory)*

### User Story 1 - One Details per budget (Priority: P1)

A user with a "Company budget" shared by two accounts opens the dropdown. Under the budget's bar they see the two member lines ("Claude via Vertex  $181 (36%)", "OpenAI API  $249 (50%)") and a single "Details" disclosure. Expanding it shows the group's tables and day row, then a "Show account details" button. Pressing it adds each member's tables below, each under the member's name; pressing it again hides them.

**Why this priority**: Three disclosures for one budget is the busiest spot left in the dropdown; one disclosure with a deliberate expand step keeps the closed view calm and the detail one click away.

**Independent Test**: With a two-member group, open the dropdown, count the Details disclosures in the group's section, expand it, press "Show account details", and check each member's tables appear under its name.

**Acceptance Scenarios**:

1. **Given** a group with two or more members, **When** the dropdown opens, **Then** the section shows each member line without a Details disclosure of its own and exactly one Details disclosure for the group.
2. **Given** the group's Details are expanded, **When** the user looks below the group's tables and day row, **Then** a "Show account details" button is shown.
3. **Given** the user presses "Show account details", **When** the Details redraw, **Then** each member with usage appears in member order with its name, its tables for the selected view, and its day row; the button reads "Hide account details".
4. **Given** accounts are shown, **When** the user switches the view picker, **Then** the group's and every member's tables switch together.
5. **Given** accounts are shown, **When** the user presses "Hide account details", **Then** the member tables disappear and the group's tables stay.
6. **Given** a group with exactly one member or none, **When** the dropdown opens, **Then** it has no member lines and no "Show account details" button (spec 025 FR-010, spec 009 FR-005).
7. **Given** an own-budget account, a subscription or Unassigned, **When** the dropdown opens, **Then** its single Details work as before.

---

### User Story 2 - The week's sum where the days are (Priority: P1)

A user expands the Claude section's Details. Instead of a "This week: 188.7M tokens" line above the picker, the day row ends with a "Σ" column holding the week's total. A budget's day row ends with the period's dollar sum the same way.

**Why this priority**: It saves a line in every expanded Details and puts the total next to the numbers it adds up.

**Independent Test**: Expand the Details of a subscription and a budget; check there is no line above the picker and the day row's last column is "Σ" with the sum of the shown days.

**Acceptance Scenarios**:

1. **Given** a subscription's Details are expanded, **When** the user reads them, **Then** the first element is the view picker, and no "This week" line is shown.
2. **Given** a day row, **When** it is shown, **Then** its last column has the label "Σ" and the sum of all shown days, in the same unit and format as the day values (tokens in millions for subscriptions and Unassigned, compact US dollars for budgets).
3. **Given** a monthly budget whose day row wraps over several rows, **When** it is shown, **Then** the Σ column follows the last day, after the last row's days.
4. **Given** a period without usage, **When** the day row is shown, **Then** Σ reads "0" like a day without usage.
5. **Given** the user points at the Σ column, **When** its tooltip shows, **Then** it gives the exact sum, like a day column's tooltip.

---

### User Story 3 - A footer that never scrolls away (Priority: P1)

A user with many sections expands two Details so the content passes the panel's height cap. The sections scroll; the footer stays at the bottom of the panel: any source errors, the update line when an update waits, and the status row with the refresh icon, "Last refreshed 7:23 AM" beside it, and the Settings and Quit icons on the right.

**Why this priority**: The icons and any error must stay reachable without scrolling; folding the status into the icon row saves a line at the same time.

**Independent Test**: Make the content taller than the cap (expand Details), scroll the sections, and check the footer stays in place; check the status row's layout and its tooltip.

**Acceptance Scenarios**:

1. **Given** the content is taller than the panel's height cap, **When** the user scrolls, **Then** only the sections scroll and the footer stays visible at the bottom of the panel.
2. **Given** the content fits, **When** the dropdown opens, **Then** the panel is as tall as the sections plus the footer, without empty space and without scrolling.
3. **Given** the dropdown is open, **When** the user looks at the bottom row, **Then** it shows, from left: the refresh icon, the "Last refreshed" text (with the "stale" marker when values are stale), and on the right the Settings and Quit icons.
4. **Given** a slowed pace (spec 016 FR-016), **When** the user hovers the status text, **Then** its tooltip is the pace line text of spec 019, as before (spec 025 FR-025).
5. **Given** source errors or an update line, **When** the footer is shown, **Then** they sit above the status row inside the pinned footer.
6. **Given** a refresh on an earlier day ("Last refreshed Oct 18, 4:54 PM"), **When** the status row is shown at the dropdown's width, **Then** the text fits on one line between the refresh and Settings icons, or is truncated with the full text in its tooltip, never wrapping the row.

---

### Edge Cases

- A group whose members have no usage entry yet: no member lines (as today) and no "Show account details" button.
- A two-member group where only one member has usage: both member lines show (as today), but there is no "Show account details" button, because the one member's tables would repeat the group's.
- Three members, two with usage: three member lines; "Show account details" lists the two with usage, in member order.
- The "Show account details" state when the dropdown closes and opens again: kept like the view picker choice (FR-004).
- Many source error lines: the footer shows at most 3 lines, the last as "+N more" with all errors in its tooltip; the sections keep at least 160 pt and scroll (FR-011).
- A short visible screen (a small laptop on a scaled resolution, a large Dock): the height cap shrinks to the room between the panel's top and the bottom of the screen's visible frame minus 8 pt, so the pinned footer stays on screen; with even less room than footer plus 160 pt the sections get only what is left above the footer (FR-010a). Moving to another display or changing the resolution or the Dock recomputes the cap.
- A weekly day row of 8 local days (spec 003): the Σ column is the 9th column and the row fits (FR-009a).
- The screenshot capture's `details` and `harnesses` crops: they now include the Σ column; the `budget` crop still covers header, amount line and bar.
- VoiceOver: the sections are read first, then the footer; the status text keeps the pace text as its accessibility value.

## Requirements *(mandatory)*

### Functional Requirements

**Budget Details**

- **FR-001**: A budget group MUST show exactly one Details disclosure, the group's. Member lines MUST NOT have a Details disclosure of their own.
- **FR-002**: Member lines MUST show exactly when they do today: for a group with two or more members, one line per member that has a usage entry, with icon, name, amount and share (spec 004 FR-018a, spec 025 FR-010).
- **FR-003**: When the group has two or more members with usage, the group's expanded Details MUST end with a button "Show account details"; pressing it MUST reveal, below the group's tables and day row, each member with usage in member order (spec 008 FR-003) under its name, with its tables for the selected view and its day row, and change the button to "Hide account details"; pressing that MUST hide them again.
- **FR-004**: The shown or hidden state of the member tables MUST be one choice for all groups and MUST persist across dropdown openings and launches, like the view picker choice.
- **FR-005**: One view picker choice MUST apply to the group's and every member's tables.
- **FR-005a**: The expanded Details content (view picker, tables, day rows, member tables) MUST be left-aligned at the full Details width, so the picker and the tables do not move horizontally when the view, the member tables or the data change (walkthrough step 3).
- **FR-006**: Own-budget accounts, subscriptions and Unassigned MUST keep their single Details unchanged except for FR-007 to FR-009.
- **FR-007**: Which member lines and which member tables a group shows MUST be decided by tested core logic; the demo coverage test MUST check it for the `default` scenario (two-member group) and the `variants` scenario (one-member group) (idea inbox member-line-rule-in-core).

**Day row sum**

- **FR-008**: The "This week: …" line MUST be removed from every Details (it replaces spec 025 FR-014's total line).
- **FR-009**: Every day row MUST end with a column labeled "Σ" whose value is the sum of all shown days, formatted like that row's day values: tokens in whole millions ("<1" for small amounts) for subscriptions and Unassigned, compact US dollars for budgets ("<1", whole dollars below 1,000, then "1.6K"). For budgets Σ sums the days' cost; when the budget's breakdown has unpriced usage (the budget's incomplete note), Σ's tooltip adds "incomplete: some usage is unpriced". Its tooltip MUST give the exact sum in a day column's tooltip wording prefixed with "Total". In a monthly row that wraps after 7 days, Σ MUST be the column after the last day on the last row, also when that row already has 7 days.
- **FR-009a**: Day columns, including Σ, MUST have a minimum width of 28 pt with 4 pt spacing, and the header column of FR-009b 26 pt, so that a weekly row of header, 8 days and Σ (314 pt) and a monthly row of 7 days plus Σ fit within the Details' width without horizontal scrolling or clipping. Member tables under "Show account details" MUST NOT add a leading indent of their own, so they have the same width as the group's.

**Note tooltip**

- **FR-019b**: The tooltip of an orange pace note MUST be only the run-out time in the other time form (the fast run-out when the row burns fast), for example "Tue, Oct 20 at 10:47 PM" or "in 1d 12h"; it amends spec 025 FR-019's note tooltip (walkthrough step 3).

- **FR-009b**: Every day row MUST start with a header column: "Day" over the unit, "Tok" (tokens, counted in millions) for token rows or "$" for cost rows, in the secondary style, with the tooltip "Tokens per day, in millions" or "Cost per day, in US$". In a wrapped monthly row every row starts with it, so the columns stay aligned (walkthrough step 4).
- **FR-009c**: Day and Σ tooltips MUST give tokens in millions with at most one decimal ("Oct 19, 2026: 42.3M tokens", "Total: 188.7M tokens"); cost tooltips keep the exact dollar amount (walkthrough step 4).

**Footer**

- **FR-010**: The footer (source errors, the update line, the status row) MUST stay pinned at the bottom of the panel; only the sections above it scroll when the content is taller than the panel's height cap (FR-010a). Below the cap the panel MUST be exactly as tall as sections plus footer.
- **FR-010a**: The screen room is the distance from the panel's top edge to the bottom of its screen's visible frame (`NSScreen.visibleFrame`, which excludes the Dock and the menu bar), minus a margin of 8 pt, never negative. The panel's height cap MUST be the smaller of 640 pt and the screen room; when the panel's screen is unknown the main screen is used, and when no screen is known the cap is 640 pt. Cap and room MUST be recomputed when the panel opens and when the screen parameters change (`NSApplication.didChangeScreenParametersNotification`). The panel MUST never extend below the screen room, so the footer always stays fully visible; when the screen room is smaller than the footer plus 160 pt, the 160 pt sections floor of FR-011 yields and the sections get what remains (screen room minus footer, never negative).
- **FR-011**: The pinned footer MUST show at most 3 source error lines, each on one line, truncated with its full text as tooltip; with more than 3 errors the third line MUST read "+N more" (N the hidden count) with a tooltip listing all errors. The sections area's height MUST be min(sections content height, screen room minus footer height, max(160 pt, height cap minus footer height)), never negative, with the screen room and the height cap of FR-010a.
- **FR-012**: The status row MUST show, from left: the refresh icon button, the "Last refreshed" text with the "stale" marker when stale, then on the right the Settings and Quit icon buttons. There MUST be no separate "Last refreshed" line.
- **FR-012a**: Pressing the Settings button (or ⌘, while the dropdown is open) MUST close the dropdown before the Settings window opens, so the two never overlap (walkthrough step 3).
- **FR-013**: The status text MUST stay on one line, truncated when too long. Its tooltip MUST be the full status text when truncated, the pace line text of spec 025 FR-025 when a pace is slowed, both joined by a line break when both apply, and absent otherwise. Its accessibility value MUST stay the pace line text (spec 025 FR-025).
- **FR-014**: These parts of spec 025 MUST stay true: the order source errors, then the update line, then the status row (FR-023, with the status row replacing "Last refreshed" plus icon row); the update line's states (FR-026); the three buttons with their tooltips, accessibility labels, identifiers and ⌘, and ⌘Q (FR-027); no gear menu (FR-028).
- **FR-015**: The dropdown MUST NOT show a visible scrollbar or scroll horizontally (spec 025 walkthrough).

**Specs, docs and screenshots**

- **FR-016**: Earlier specs MUST be amended where they describe what changes here: spec 025's scroll-mode edge case ("the footer stays the last content") and its height-cap assumption (now with a pinned footer), FR-010 (member Details), FR-014 (the total line), FR-023 and FR-024 ("Last refreshed" as its own line), FR-025 (the combined tooltip), FR-027 (the icon row now holds the status text) and its dropdown contract; spec 016 FR-016 (where the pace text shows); spec 003 FR-013 (the Σ column); spec 004 FR-018a (member lines without their own Details, member tables behind "Show account details").
- **FR-017**: The docs that describe the dropdown (`docs/usage.md`, `docs/accounts-and-budgets.md`) MUST describe the single budget Details, "Show account details", the Σ column and the pinned status row.
- **FR-018**: The capture script MUST keep finding the `details` container and MUST crop it with "Show account details" hidden; no published shot shows the member tables expanded, so no coverage check for that state is needed. The changed shots (`details`, `harnesses`, `dropdown`) are recaptured together with spec 025's in one screenshot round right after this spec and spec 027 (the headline window switch), by the maintainer's explicit decision on 2026-10-19 ("we will do the screenshots after this round"; idea inbox minimal-dropdown-screenshots), before the next release.

### Key Entities

- **Member display**: for one budget group, the list of member lines to show (members with usage when there are two or more) and the list of member tables available behind "Show account details".
- **Day row total**: the sum of a day row's values with its display text and exact tooltip text.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A two-member group's closed section shows one Details disclosure instead of three.
- **SC-002**: Every expanded subscription Details is one line shorter (no "This week" line), and the week's total is still visible without hovering.
- **SC-003**: With content taller than the cap, the refresh, Settings and Quit icons and any source error stay visible without scrolling (walkthrough).
- **SC-004**: The footer is one line shorter than in spec 025 when there are no errors and no update line (status and icons share a row).
- **SC-005**: The member-line and member-table rules are covered by automated tests, including the demo coverage for one- and two-member groups.
- **SC-006**: All existing automated tests pass.

## Assumptions

- The "Show account details" button uses the same caption style as the Details label; it is a text button, not an icon.
- Member tables under "Show account details" use the member's own breakdown (as the removed member Details did) and the group's period.
- The pinned footer has no divider above it; since spec 028 it sits on its own full-width band, a touch stronger than a tinted section, and the sections are set apart by alternating bands instead of dividers (amended by spec 028 FR-001, FR-007).
- The status text uses the caption font and secondary color as today.
- No configuration change; the "Show account details" state is a UI preference like the view picker, not part of the configuration file.
