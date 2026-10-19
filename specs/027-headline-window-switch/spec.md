# Feature Specification: Headline Window Switch

**Feature Branch**: `027-headline-window-switch`

**Created**: 2026-10-19

**Status**: Draft

**Input**: User description: "Headline window switch (from brainstorm/26-headline-window-switch.md). In a Claude or Codex subscription section, clicking a limit-window row makes it the account's headline window; a ● marks the chosen row. The headline window drives the bold header percent, the menu bar value, the bar's color level and the ↗ / ↑ markers. With a non-default window the menu bar shows a short window tag before the value (for example '✳ 5h 58%'); with the default window the bar looks as today. The choice is stored per account, survives a restart, returns to the default when the user clicks the default row, and falls back to the default when the chosen window no longer exists. Threshold notifications, budgets, member shares and the window order are unchanged."

Each subscription account has one fixed **headline window** today: the 7-day window for a Claude subscription (spec 001 FR-005) and the longest effective window for a Codex plan (spec 007 FR-012). It decides four things: the bold percent in the section header of the dropdown, the account's menu bar value, that value's color level (spec 012) and the `↗` / `↑` markers after it (spec 011 FR-012, spec 017 FR-008). During heavy work another window is the one about to bite, usually the 5-hour window or a model limit such as Fable, and the user wants that number in the menu bar instead. This spec lets the user pick the headline window per account by clicking its row in the dropdown. It came from the spec 025 walkthrough (idea inbox `headline-percent-switch`).

In this spec a **window** is one limit row of a subscription section: for a Claude subscription the 5-hour window, the 7-day window and each model limit (spec 025 FR-001); for a Codex subscription each plan window, named as spec 007 FR-009 names it ("5-hour", "weekly", "N-day", "N-hour"). The **default window** is the one the account uses today: the 7-day window for Claude, the longest effective window for Codex. The **chosen window** is the one the user picked and the configuration stores. The **headline window** is the window in effect: the chosen window when it applies (FR-006), otherwise the default window. A **fixed window** is the Claude 5-hour or 7-day window, which every Claude subscription has; model limits and Codex windows are **dynamic windows**, which come and go with the provider's answer.

## Clarifications

### Session 2026-10-19

- Q: What does the hover highlight of a window row look like? → A: A rounded rectangle behind the whole row (name line and bar) in the system's subtle fill color, with the hollow ○ in the marker slot; the pointer stays the arrow. The dropdown has no hover background yet, so this is new and used only by window rows.
- Q: Is the ● shown on the default row when the user never chose a window? → A: Yes. Every subscription section always marks its headline row, the default one included, so the rows read as a choice from the first look.
- Q: How is the tag drawn in the section header? → A: In the secondary color and regular weight, directly before the bold percent ("5h **58%**"); in the bar it takes the icon's tone (FR-009).
- Q: With another window chosen on a Claude account, does a full 7-day window still make the entry critical? → A: Yes. A Claude entry is critical when the headline window or the default 7-day window is at or above 100%; Codex keeps its "any window reached" rule (FR-007).
- Q: What does hovering the headline row show? → A: Nothing; only rows that a click would change show the hover state (FR-002).

### Amendment 2026-10-19 (after brainstorm 28 was rejected)

- Q: Should the ● on a default headline row look the same as on a chosen one? → A: No. On the default window's row the ● is drawn in the secondary color; on a chosen (non-default) row it stays in the primary color. Every section still marks exactly one row, so the rows keep reading as a choice, but a section the user never changed looks quieter (FR-002).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Watch the 5-hour window in the menu bar (Priority: P1)

A user with a Claude Max subscription is deep in a long coding session. The menu bar reads "✳ 70%" (the 7-day window), but the 5-hour window at 58% is the one that will stop them. They open the dropdown and click the "5-hour" row. A ● appears in front of "5-hour", the section header now reads "5h 58%", and the menu bar entry reads "✳ 5h 58%", colored and marked by the 5-hour window. Next morning they click the "7-day" row and the bar is back to "✳ 70%".

**Why this priority**: It is the whole feature: the number the user watches is the number about to run out.

**Independent Test**: With the demo build, click the 5-hour row of the Claude section, check the ●, the header and the bar entry; click the 7-day row and check that all three return to today's look.

**Acceptance Scenarios**:

1. **Given** a Claude subscription with its default window, **When** the dropdown opens, **Then** the 7-day row carries the ● marker, the header shows the 7-day percent without a tag, and the bar entry looks as today.
2. **Given** the dropdown is open, **When** the user clicks the 5-hour row, **Then** the ● moves to the 5-hour row, the header reads "5h" followed by the 5-hour percent, and the bar entry reads the icon, "5h" and the 5-hour percent, without closing the dropdown.
3. **Given** the 5-hour window is chosen, **When** the 5-hour percent reaches the account's warning threshold, **Then** the bar entry takes the warning level, although the 7-day window is below it.
3a. **Given** the 5-hour window is chosen at 40% and the 7-day window is at 100%, **When** the bar is drawn, **Then** the entry reads "5h 40%" in the at-or-above-100% style.
4. **Given** the 5-hour window is chosen and its pace runs out before its reset, **When** the bar is drawn, **Then** the entry shows "↗" (or "↑" when the 5-hour window burns fast), following the 5-hour window and not the 7-day window.
5. **Given** the 5-hour window is chosen, **When** the user clicks the 7-day row, **Then** the choice returns to the default: the ● is on the 7-day row, the header and the bar entry have no tag.
6. **Given** the 5-hour window is chosen, **When** AgentTacho quits and starts again, **Then** the bar entry still reads "5h" and the 5-hour percent, and the ● is on the 5-hour row.
7. **Given** a model limit "Fable" is shown, **When** the user clicks its row, **Then** the header and the bar entry show the tag "Fable" before the Fable percent.

---

### User Story 2 - Pick a Codex window (Priority: P1)

A user with a ChatGPT Plus plan used through Codex sees two windows, "5-hour" and "weekly"; the bar shows the weekly percent. They click "5-hour" and the bar entry reads "5h 40%", the Codex section header the same.

**Why this priority**: Codex plans have the same problem as Claude plans; one rule for both keeps the dropdown predictable.

**Independent Test**: With the demo build, click the Codex section's 5-hour row; check the ●, the header and the bar entry; click "weekly" and check they return.

**Acceptance Scenarios**:

1. **Given** a Codex plan with a 5-hour and a weekly window, **When** the user clicks the 5-hour row, **Then** the ● moves there and the header and the bar entry show "5h" before the 5-hour percent, with its level and markers.
2. **Given** the 5-hour window is chosen, **When** the plan reports a window reached its limit, **Then** the bar entry keeps the at-or-above-100% style as today (spec 007 FR-012), whichever window is the headline.
3. **Given** the 5-hour window is chosen, **When** the user clicks the longest window's row, **Then** the choice returns to the default.

---

### User Story 3 - A window that disappears (Priority: P2)

A user chose the Fable model limit. A week later the provider no longer reports a Fable limit. The bar entry goes back to the 7-day percent without a tag and the ● sits on the 7-day row. When the Fable limit is reported again, the bar shows it again with its tag.

**Why this priority**: A stale choice must never leave the bar empty or showing a number for a window the dropdown no longer lists.

**Independent Test**: Choose a model limit or Codex window, then refresh with values that lack it (unit test with a snapshot without it, or the demo `variants` scenario); check the bar and the ● show the default window; restore the window and check the choice comes back.

**Acceptance Scenarios**:

1. **Given** the chosen window is a model limit or Codex window that the latest values no longer contain, **When** the bar and the dropdown are drawn, **Then** they use the default window without a tag and the ● is on the default row.
2. **Given** that fallback, **When** later values contain the chosen window again, **Then** the bar and the dropdown use it again with its tag, without any action by the user.
3. **Given** that fallback, **When** the user clicks the default row, **Then** the stored choice is cleared.
4. **Given** the chosen window is the Claude 5-hour window and the latest values have no 5-hour window, **When** the bar is drawn, **Then** the entry reads "5h --" (unavailable), as the 7-day window does today when it is missing (spec 001 FR-005), and does not switch to another window.

---

### User Story 4 - Find and operate the switch (Priority: P2)

A user moves the pointer over the window rows and sees that they react; VoiceOver users hear that a row can be shown in the menu bar and which row is shown there.

**Why this priority**: A hidden interaction is a missing interaction; the affordance must be visible without crowding the dropdown.

**Independent Test**: Hover each window row and check the hover state; with VoiceOver, check each row's action name and the chosen row's state.

**Acceptance Scenarios**:

1. **Given** the dropdown is open, **When** the pointer rests on a window row that is not the headline, **Then** the row shows a hover highlight and a hollow ○ in the marker slot.
2. **Given** VoiceOver is on, **When** a window row is focused, **Then** it offers the action "Show in menu bar", and the headline row is announced as selected with "shown in menu bar".
3. **Given** the Settings Menu Bar tab is open, **When** its preview is drawn, **Then** it shows the tag exactly as the bar does.

---

### Edge Cases

- A row clicked that is already the headline: nothing changes.
- Clicking the reset text or the bar inside a row counts as clicking the row; the row's tooltips (window name, reset time) keep working.
- Before the first values ("…") and for a Claude account that is not signed in or a Codex account without windows ("--"), no window is resolved: the entry shows no tag and the stored choice is kept.
- Stale values: the tag stays, the stale marker sits before the value as today ("✳ 5h ~58%").
- A window whose reset passed shows 0% (spec 010 FR-016); as the headline it shows "5h 0%" and keeps the choice.
- A Codex plan whose windows change so that the chosen window becomes the longest one: it is the default window then and shows no tag; the stored choice stays until the user clicks a row.
- A Codex plan with one window: that window is the default; the row still shows the ● and clicking it changes nothing.
- An account hidden from the bar (`shownInBar` off): clicking rows still changes the header percent and the ●; the bar shows nothing for it, as today.
- Settings open while the user clicks a row in the dropdown: a later save from Settings keeps the choice made in the dropdown (FR-010).
- Two Claude accounts: each has its own choice.
- A model name longer than 8 characters: the tag is its first 7 characters followed by "…"; the full name is in the entry's accessibility text.
- Threshold notifications keep checking every window separately and do not change with the headline (spec 001, spec 007 FR-014).
- The pace line and the "Last refreshed" status (spec 019, spec 026) are unchanged.

## Requirements *(mandatory)*

### Functional Requirements

**Choosing the window**

- **FR-001**: In a Claude subscription section and a Codex subscription section, every window row MUST be clickable as a whole; a click MUST make that window the account's chosen window, or clear the choice when it is the default window. The dropdown MUST stay open and the header, the ● and the bar entry MUST update at once, without a refresh.
- **FR-002**: The headline row MUST show a ● marker in a marker slot at the row's leading edge; every window row MUST reserve that slot, so names stay aligned whichever row is the headline. The ● MUST be shown also when the headline is the default window, then in the secondary color; on a headline row that is not the default window it MUST be drawn in the primary color (amendment 2026-10-19). When the pointer rests on a row that is not the headline, the row MUST show a hover highlight (a rounded rectangle behind the name line and the bar in the system's subtle fill color) and a hollow ○ in its slot; the pointer stays the arrow. The headline row MUST show no hover state. The window order MUST stay as today (spec 025 FR-001, spec 007 FR-011).
- **FR-003**: Each window row MUST offer the accessibility action "Show in menu bar"; the headline row MUST carry the selected state and add "shown in menu bar" to its accessibility label (spec 025 FR-006).
- **FR-004**: Budgets (groups and own budgets), member shares, Unassigned and token-based accounts MUST NOT get the switch; their rows and bar entries stay unchanged.

**Resolving the headline**

- **FR-005**: The default window MUST be the 7-day window for a Claude subscription and the longest effective window for a Codex plan (spec 007 FR-012), as today.
- **FR-006**: The headline window MUST be resolved at drawing time from the chosen window and the latest values: a chosen fixed window (Claude 5-hour or 7-day) always applies; a chosen dynamic window applies only when the latest values contain a window with that identity, otherwise the default window is the headline. A model limit's identity is its model name as the provider reports and the dropdown shows it ("Fable"), a Codex window's identity its spec 007 FR-009 name ("5-hour", "weekly"); both match exactly, including case. The stored choice MUST NOT be changed by this fallback.
- **FR-007**: The headline window MUST decide the section header's bold percent, the bar entry's value, its color level (spec 012, with the account's thresholds) and its `↗` / `↑` markers (the headline window's pace and burn rate, spec 011 FR-012 to FR-014, spec 017 FR-008 to FR-010). These replace the 7-day and longest-window rules of spec 001 FR-005, spec 007 FR-012, spec 011 FR-012 and spec 017 FR-008 for the value and markers; a Codex entry still uses the at-or-above-100% style when any window reached its limit (spec 007 FR-012), and a Claude entry uses it when the headline window or the default 7-day window is at or above 100%, so choosing another window never hides a full 7-day window. A chosen fixed window without values MUST show "--" as the 7-day window does today.

**Menu bar tag**

- **FR-008**: When the headline window is not the default window, the bar entry and the section header MUST show a window tag directly before the value, separated by a space: "5h" for the Claude 5-hour window and a Codex "5-hour" window, "Nh" for a Codex "N-hour" window, "wk" for a Codex "weekly" window, "Nd" for a Codex "N-day" window, and the model name for a model limit, cut to its first 7 characters plus "…" when longer than 8. In the section header the tag MUST be drawn in the secondary color and regular weight before the bold percent. A chosen fixed window without values shows its tag with "--" ("5h --") in the bar and in the header. No tag is shown while no window can be resolved: before the first values ("…"), for a Claude account that is not signed in, and for a Codex plan without windows. With the default window as headline the bar entry and the header MUST look exactly as today.
- **FR-009**: The tag MUST sit after the icon and before the level glyph, the stale marker and the value ("✳ 5h ⚠ ~85%"), in the icon's tone (spec 012), inside the pill when the entry is drawn on one. When a tag is shown, the entry's accessibility text MUST name the window in full ("5-hour window", "Fable weekly limit", "weekly window") before the value; without a tag it stays as today. The Settings Menu Bar tab's preview (spec 008 FR-013) MUST show the tag as the bar does.

**Storing the choice**

- **FR-010**: The chosen window MUST be stored per account in the configuration file, absent meaning the default window, and MUST survive a restart. A configuration file without it (written by an earlier version) MUST load unchanged; a value that names no known kind of window, or a kind that does not belong to the account (a Codex window on a Claude account, a Claude window on a Codex account), MUST be ignored (default window) and noted in the diagnostic log, without making the configuration invalid; the next save writes the value in effect. Saving from Settings MUST keep the account's current choice, also one made in the dropdown while Settings was open. Removing an account removes its choice.
- **FR-011**: A click that changes the choice MUST save the configuration and MUST NOT trigger a refresh or a threshold notification.

**Unchanged behavior**

- **FR-012**: Threshold notifications, the pace line, the dropdown's window order, each row's own percent, bar, reset text, note and tooltips, budgets and member shares MUST stay as today.

**Core logic and tests**

- **FR-013**: The headline resolution (FR-005, FR-006), the bar value, level and markers (FR-007), the tag text and accessibility wording (FR-008, FR-009) and the stored value's encoding and decoding (FR-010) MUST be decided by tested UsageCore logic; the SwiftUI layer only renders it and forwards clicks (constitution II).

**Specs, docs, demo and screenshots**

- **FR-014**: Earlier specs MUST be amended where they describe the fixed headline: spec 001 FR-005 (bar and header percent), spec 007 FR-012 (the longest window in the bar), spec 011 FR-012 and spec 017 FR-008 (which window the markers follow), spec 025's dropdown contract (the marker slot and the clickable rows). `docs/usage.md` MUST describe the switch and the tag, `docs/configuration.md` the stored field.
- **FR-015**: The demo `default` scenario MUST choose the 5-hour window for the Claude Max account, so the dropdown shows the ● on the 5-hour row and the menu bar shows "5h 58%"; the Codex account keeps its default. The demo coverage test MUST check the tag in the bar entry and the ● row for the `default` scenario, and its existing checks (all three levels, both markers `↗` and `↑`, the pace states, the 7-day attention row) MUST keep passing; the scenario's values MAY be tuned for that. The fallback for a missing model limit or Codex window is covered by UsageCore unit tests.
- **FR-016**: The changed shots (`menubar`, `menubar-settings` for the preview's tag, `plan-limits`, `pace` for the marker slot, `dropdown`), the README dropdown image (AGENTS.md step 6) and the website copy of the "Plan limits" card (the switch, AGENTS.md step 7) MUST be updated; the shots MUST be recaptured in the shared screenshot round after this spec, by the maintainer's decision of 2026-10-19 recorded in spec 026 FR-018 (idea inbox `minimal-dropdown-screenshots`), before the next release.

### Key Entities

- **Window identity**: names one window of a subscription account: Claude 5-hour, Claude 7-day, a Claude model limit by model name, or a Codex window by its name.
- **Headline choice**: the account's chosen window identity, absent for the default; stored with the account in the configuration.
- **Resolved headline**: the window in effect for one account at one snapshot, with its percent, level, markers, whether it is the default, its tag and its accessibility name.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user switches the menu bar value to another window with one click in the dropdown, and back with one click.
- **SC-002**: With a non-default window as headline, the bar entry always names its window, so it is never mistaken for the default window's value (checked by the coverage test and the walkthrough).
- **SC-003**: With every account on its default window, the bar and the dropdown header look exactly as before this feature; the only visible change for users who never click a row is the secondary-color ● on the default row and its marker slot.
- **SC-004**: The choice survives a restart in 100% of cases, and a missing dynamic window never leaves the bar entry empty or wrong: it shows the default window.
- **SC-005**: Headline resolution, tag text, level, markers and the stored value are covered by automated tests; all existing tests pass.

## Assumptions

- Settings gets no control for the choice in this spec; the dropdown is where the windows and their values are, and the docs describe the click. A Settings control can follow if the walkthrough shows a need.
- The choice is a configuration value, not a UI preference, because it changes what the bar shows and should travel with the configuration file.
- An earlier AgentTacho version reading a file that carries the new field ignores it, as it ignores other unknown account fields.
- Spec 026 (brainstorm 25) is merged; this spec builds on its dropdown and shares its screenshot round.
