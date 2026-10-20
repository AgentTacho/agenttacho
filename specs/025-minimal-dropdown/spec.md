# Feature Specification: Minimal Dropdown

**Feature Branch**: `025-minimal-dropdown`

**Created**: 2026-10-18

**Status**: Draft

**Input**: User description: "Minimal dropdown (from brainstorm/23-minimal-dropdown.md). Redesign the dropdown to layout B: window rows with label, percent and reset on one line, a full-width bar with the pace tick below, and an orange note only on a run-out or a fast burn. Reset and run-out times are relative or absolute, configurable per account and per group (relative by default, the other form in the tooltip). Section headers keep their percent; dividers separate sections. Codex drops its plan line and its 'Tokens this week' line (the token total moves into Details, for Claude and Codex alike); a group with one member drops its member line. The footer shows source errors, the update line, 'Last refreshed' (with the pace line as its tooltip) and a row of icons (refresh, Settings, Quit); the gear menu goes. Folds in the idea inbox items dropdown-note-view-model, single-pace-and-burn-value and run-out-text-in-core."

AgentTacho should feel calm: the dropdown shows what matters at a glance, and nothing the user has to read only to dismiss it. Today a **window row** (Claude's 5-hour, 7-day and model limits, each Codex plan window) shows the window name, its percent, a long absolute reset time ("resets Fri 23. Oct at 09:00") and a small **pace meter** whose meaning (on pace, ahead, behind, the projected run-out, a fast burn; spec 011, spec 017) is readable only in its tooltip. A **budget** (a group or a token-based account with its own budget, spec 004) shows a header with its percent, an amount line with the reset time and the same meter. The Codex section adds a plan type line and a "Tokens this week" line; a group with one member repeats the group's numbers in its member line; the sections run into each other; and the footer holds "Last refreshed", the refresh **pace line** of spec 016 and spec 019, source errors, the quiet update line of spec 013, a "Refresh now" button and a gear menu (About, Check for Updates, Settings, Quit).

In this spec a row's **pace** is its pace at the snapshot time (spec 011), its **burn rate** the burn rate of spec 017; a row **calls for attention** when its pace has a projected run-out or its burn rate burns fast, the condition that colors today's meter orange (spec 011 FR-010, spec 017 FR-012).

## Clarifications

### Session 2026-10-18

- Q: How does the absolute format decide between time only, weekday and time, and a date, and does a date beyond six days carry the time? → A: By calendar days from the reference time: the same day shows the time, the next six calendar days weekday and time, later days weekday, day, month and time; a reset at local midnight shows weekday, day and month without a time.
- Q: Should the bar's fill follow the warning and over-limit level colors of spec 012, or only the pace? → A: Only the pace and the limit: orange when the row calls for attention, red at 100% or more or a reached Codex limit, neutral otherwise. The level colors of spec 012 stay a menu bar matter.
- Q: Should the published screenshots show one section with absolute times? → A: No. The demo `default` scenario keeps the default (relative) everywhere, so the images show what a new user sees; the absolute format is covered by core tests.
- Q: What control and label edit the time format in Settings? → A: A segmented picker labeled "Times" with the options "Relative" and "Absolute", in the account's detail and the group's detail.
- Q: How does the week's token total read inside Details? → A: As the first line of the expanded Details, "This week: 45.1M tokens", in the compact token format used elsewhere in the dropdown. (Amended by spec 026: the line is gone; the total is the Σ column at the end of the day row.)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Read every limit at a glance (Priority: P1)

A user opens the dropdown while Claude Code works. Each limit window shows its name, its percent and when it resets ("5-hour  38%  resets in 2h 26m"), and below it a bar across the section: filled to the used percent, with a thin tick where even use would be now. The user sees at once that the 7-day window is ahead of the tick, and an orange line under it says "15% ahead · runs out in 2d 13h". The 5-hour and model rows, which are on pace or behind, have no extra line. Nothing needs hovering.

**Why this priority**: This is the core of the feature: the pace becomes visible without a tooltip, and text appears only where it calls for action.

**Independent Test**: Open the dropdown with a Claude plan whose 7-day window is ahead of pace with a projected run-out and whose other windows are on pace or behind; check the bars, the tick positions and that exactly one orange note appears, without hovering.

**Acceptance Scenarios**:

1. **Given** a Claude plan with 5-hour at 38% and 7-day at 48%, **When** the dropdown opens, **Then** each window shows its name, percent and reset time on one line and a full-width bar below it, filled to its percent.
2. **Given** a window with a pace, **When** its row is shown, **Then** the bar shows a tick at the pace's expected percent, the share of the window that had elapsed when the value was observed (spec 011 FR-001, FR-002).
3. **Given** a window ahead of pace with a projected run-out, **When** its row is shown, **Then** an orange note under the bar reads like "15% ahead · runs out in 2d 13h" and the bar's fill is orange.
4. **Given** a window that burns fast (spec 017), **When** its row is shown, **Then** the note reads like "15% ahead · burning fast · runs out in 3h 10m".
5. **Given** a window on pace or behind without a fast burn, **When** its row is shown, **Then** no note appears and the fill uses the neutral color.
6. **Given** a window at 100% or more, or a Codex window whose limit is reached, **When** its row is shown, **Then** the percent and the fill are red and a reached Codex limit keeps its "Limit reached" text.
7. **Given** any window row, **When** the user hovers the bar, **Then** no pace tooltip appears; all pace information is already on screen.
8. **Given** VoiceOver, **When** it reads a window row, **Then** it reads the window, the percent, the reset time and the pace summary, including "on pace" or "behind".

---

### User Story 2 - Budgets read the same way (Priority: P1)

A user with a Vertex budget of 300 US$ per month sees the budget's header with its percent, the line "1,596 of 300 US$/month" with "resets in 13d 7h" on the right, and a bar below it with the tick at the elapsed share of the month. Because the budget has one member, there is no member line repeating the same amount.

**Why this priority**: Budgets are the other half of the dropdown; mixing two row styles would undo the calm look.

**Independent Test**: Configure a group with one member and a group with two members, each with spend; open the dropdown and check the amount line, bar, tick and member lines.

**Acceptance Scenarios**:

1. **Given** a budget with spend, **When** the dropdown opens, **Then** its section shows the header with icon, name and bold percent, the amount line with the reset time, and a bar filled to the spend share (capped at full) with the pace tick.
2. **Given** a budget whose pace calls for attention, **When** its section is shown, **Then** the same orange note as for a window appears under its bar.
3. **Given** a budget over 100%, **When** its section is shown, **Then** the bar is full and red.
4. **Given** a group with exactly one member, **When** its section is shown, **Then** no member line appears; the group's own lines and its Details stay.
5. **Given** a group with two or more members, **When** its section is shown, **Then** each member keeps its line with amount and share; the member lines have no Details of their own, and the member tables sit in the group's Details behind "Show accounts" (amended by spec 026 FR-001 to FR-003).
6. **Given** a group without members, **When** its section is shown, **Then** it keeps the header and the "No accounts in this group yet" note as today (spec 009 FR-005).

---

### User Story 3 - A footer that stays put (Priority: P1)

A user glances at the bottom of the dropdown. Above a row of three icons (refresh on the left, Settings and Quit on the right) the last text line always reads "Last refreshed 16:54". When AgentTacho slows its checks because Claude Code is idle, hovering that line says "Claude limits next checked at 17:04 (no Claude Code activity)". A source error or an available AgentTacho update appears above "Last refreshed", never below it. There is no gear menu; About and "Check for Updates…" live in Settings > About.

**Why this priority**: The footer is on screen every time; its fixed order and the removal of a menu step are the most visible simplification.

**Independent Test**: Open the dropdown in each footer state (no extras, a source error, an available update, a slowed pace) and check the order of lines, the tooltip and the three icons with their tooltips and shortcuts.

**Acceptance Scenarios**:

1. **Given** the dropdown is open, **When** the user looks at the bottom, **Then** the last row holds three icon buttons: refresh, Settings, Quit, each with a tooltip ("Refresh now", "Settings…", "Quit AgentTacho") and the same accessibility label.
2. **Given** the dropdown is open, **When** the user presses ⌘, or ⌘Q, **Then** Settings opens or AgentTacho quits, as today.
3. **Given** a successful refresh at 16:54 today, **When** the footer is shown, **Then** the line above the icons reads "Last refreshed 16:54"; for a refresh on an earlier day it names the date too.
4. **Given** a slowed pace (spec 016 FR-016), **When** the user hovers "Last refreshed", **Then** the tooltip shows the pace line text of spec 019 and no separate pace line is shown.
5. **Given** a source error and an available update, **When** the footer is shown, **Then** the order from the top is: the error lines, the update line, "Last refreshed", the icons.
6. **Given** the dropdown, **When** the user looks for About or "Check for Updates…", **Then** neither is in the dropdown; both are in Settings > About.
7. **Given** stale values, **When** the footer is shown, **Then** the "stale" marker stays on the "Last refreshed" line.

---

### User Story 4 - Choose how times read (Priority: P2)

A user who prefers clock times opens Settings > Accounts, selects the Claude subscription and sets its time format to Absolute. Settings applies the change by itself, and the Claude section reads "resets 17:20" and "resets Fri 09:00", and hovering a time shows "in 2h 26m". The Codex section, still on the default, keeps "resets in 2h 57m", and hovering shows the full date and time.

**Why this priority**: Relative times are the new default and serve most users; the setting serves those who think in clock times, so it is secondary to the layout itself.

**Independent Test**: Switch one account and one group to Absolute and check that only their sections change, that tooltips show the other form, and that the choice survives a restart.

**Acceptance Scenarios**:

1. **Given** a configuration without a time format, **When** the dropdown opens, **Then** every reset and run-out time reads relative ("resets in 4d 16h", "runs out in 2d 13h").
2. **Given** the Claude account is set to Absolute, **When** the dropdown opens, **Then** its section's times read absolute and other sections stay relative.
3. **Given** a relative time, **When** the user hovers it, **Then** the tooltip shows the absolute date and time; **Given** an absolute time, **Then** the tooltip shows the relative form.
4. **Given** the user changes the time format in Settings, **When** Settings applies the change (after its short pause, like every setting), **Then** the dropdown follows and the choice is still set after a restart; **When** the user presses ⌘Z, **Then** the previous time format is back.
5. **Given** a group set to Absolute, **When** the dropdown opens, **Then** the group's reset and run-out times read absolute.
6. **Given** the dropdown stays open, **When** a minute passes, **Then** relative times count down without a refresh.

---

### User Story 5 - Lighter Codex section (Priority: P2)

A ChatGPT Plus user sees the Codex section with its header and window rows only. The plan type line and the "Tokens this week" line are gone; the week's token total shows inside Details, the same way it does for the Claude subscription.

**Why this priority**: It removes two lines that only one section had, but the information stays one click away.

**Independent Test**: Open the dropdown with a Codex plan and token usage; check that the section has no plan type and token lines and that the expanded Details of both the Claude and the Codex section show the week's total.

**Acceptance Scenarios**:

1. **Given** a Codex plan with known plan type, **When** the dropdown opens, **Then** the section shows no "ChatGPT <plan> plan" line and the section's name has no tooltip; the header names the plan.
2. **Given** Codex token usage this week, **When** the dropdown opens, **Then** the section shows no "Tokens this week" line.
3. **Given** the Details of a Claude or Codex subscription section are expanded, **When** the user reads them, **Then** the day row ends with the Σ column holding the week's total; there is no "This week" line (amended by spec 026 FR-008, FR-009).
4. **Given** Codex values are stale, from local data, or unavailable, **When** the section is shown, **Then** the corresponding note stays visible as today.

---

### User Story 6 - Clear separation of sections (Priority: P3)

A user with three sections scans the dropdown and sees the sections set apart by full-width background bands, alternating plain and faintly tinted, and the pinned footer on its own band; there are no divider lines (amended by spec 028: alternating bands, no dividers).

**Why this priority**: A small visual aid; useful, but the redesign works without it.

**Independent Test**: Open the dropdown with three or more sections and check there is no divider, the bands alternate plain, tinted, plain, and the footer has its own band (amended by spec 028: alternating bands, no dividers).

**Acceptance Scenarios**:

1. **Given** N sections, **When** the dropdown opens, **Then** it shows no divider; the sections alternate plain and tinted bands starting plain, and the footer sits on its own band (amended by spec 028: alternating bands, no dividers).

---

### Edge Cases

- A window without a reset time ("not started", or reset since the observation, spec 010 FR-016): the row shows its percent and "not started" (or no reset text) and a bar without a tick.
- A window that is unavailable: the row shows "unavailable" and no bar.
- A row without a pace (spec 011 FR-007: no reset time, at or over 100%, a reached Codex limit, an empty group, reset since the observation): the bar has no tick and no note.
- A row less than 10% into its window (spec 011 FR-006): the tick shows and the run-out is withheld, so no note appears unless the row burns fast by its recent rate (spec 017 FR-006).
- A fast burn while on pace or behind: the note shows ("on pace · burning fast · runs out in 3h 10m"), because the row calls for attention.
- A run-out or reset that is no longer in the future while the dropdown stays open: the relative form reads "now" ("resets now"), the absolute form the time itself.
- A 7-day window that resets next week on today's weekday reads "Sun 25. Oct 09:00" in the absolute format (seven calendar days away), not "Sun 09:00".
- A relative time under one minute reads "in <1m"; a whole number of days reads "in 4d" without "0h"; a whole number of hours reads "in 3h" without "0m".
- A budget without a pace (an empty group, spec 011 FR-007): its bar shows the fill without a tick. A budget at 0% spend has a pace and shows the tick.
- A budget far over its limit (532%): the bar is full and red; the header keeps the full percent.
- A token-based account inside a group has no section of its own; its time format setting is not offered (the group's applies).
- A configuration file with an unknown time format value: it reads as Relative, the problem is noted in the diagnostic log without a problem notice, the rest of the file loads (as spec 012 handles an unknown level color), and the next save from Settings writes Relative.
- The dropdown in its scroll mode (content taller than the cap): the footer keeps its order and stays pinned below the scrolling sections (amended by spec 026 FR-010, FR-011).
- No accounts configured: the empty-state text stays, followed by the footer.

## Requirements *(mandatory)*

### Functional Requirements

**Window rows**

- **FR-001**: Each limit window row (Claude 5-hour, 7-day and model-scoped limits; each Codex plan window) MUST show on one line the window's name, its percent and its reset text, and directly below a bar spanning the section's content width.
- **FR-002**: The bar's fill MUST show the used percent, capped at a full bar. When the row has a pace, the bar MUST show a tick at the pace's expected percent, the elapsed share of the window at the observation time (spec 011 FR-001, FR-002), so the gap between fill and tick matches the note's delta; without a pace (spec 011 FR-007) it MUST show no tick. (Amended by spec 030 (2026-10-20): in direction remaining the fill shows the remaining share from the leading edge and the tick sits at the expected remaining share, spec 030 FR-010.)
- **FR-003**: The fill MUST be red when the percent is 100 or more or a Codex window's limit is reached (spec 007 FR-012), otherwise orange when the row calls for attention, otherwise a neutral color. The warning level colors of spec 012 MUST NOT color the bar; a row at or above its warning threshold that does not call for attention keeps the neutral fill. (Amended by spec 030 (2026-10-20): the fill is red at the row's critical level, from its owner's second threshold or a real limit, and the warning level still never colors the bar, spec 030 FR-005, FR-006.)
- **FR-004**: When a row calls for attention, a note MUST appear under its bar in orange: the pace summary of spec 011 and spec 017 ("<N>% ahead", "<N>% behind" or "on pace", then " · burning fast" for a fast burn, then " · runs out <time>"), with the time in the section's time format (FR-016). A row that does not call for attention MUST show no note.
- **FR-005**: The pace meter and its tooltip MUST be removed from window rows and budgets. Pace information MUST NOT be available only through a tooltip.
- **FR-006**: Each window row, and each budget's amount line with its bar, MUST expose one accessibility element whose label names the window or budget, the percent (for a budget, the amount and budget), the reset time and the pace summary, also when no note is shown.
- **FR-007**: A percent of 100 or more and a reached Codex limit MUST show red percent text in every window row (today only model-limit and Codex rows do), and a reached Codex limit MUST keep its "Limit reached" text. (Amended by spec 030 (2026-10-20): every window row's and budget's percent, and each section header's bold percent, is orange at the warning level and red at the critical level of its owner's thresholds, spec 030 FR-005.)
- **FR-008**: A window without a reset time MUST show "not started" (or, when reset since the observation, no reset text, spec 010 FR-016) and a bar without a tick. An unavailable window MUST show "unavailable" and no bar.

**Budgets**

- **FR-009**: A budget section (group or own budget) MUST keep its header with icon, name and bold percent, then show the amount line ("<spent> of <budget>/<period>") with the reset text right-aligned, then a bar with the spend share (capped at a full bar) and the budget's pace tick, colored as in FR-003 (red at 100% or more), and the note of FR-004.
- **FR-010**: A group with exactly one member MUST NOT show the member line. A group with two or more members MUST show its member lines, with amount and share; the member lines have no Details of their own, and the group's single Details reveal the member tables behind "Show accounts" (amended by spec 026 FR-001 to FR-003). An empty group MUST keep its note (spec 009 FR-005).

**Sections**

- **FR-011**: The dropdown MUST set the sections (accounts, groups and Unassigned in arrangement order, spec 008 FR-003) apart by full-width background bands, alternating plain and tinted starting plain, and the footer by its own band; it shows no divider (amended by spec 028: alternating bands, no dividers; spec 028 FR-001, FR-002, FR-007).
- **FR-012**: Section headers of subscription plans and budgets MUST keep their bold headline percent.
- **FR-013**: The Codex section MUST NOT show the plan type line; the plan type is not repeated anywhere in the dropdown (the account's name in the header already names the plan; a tooltip added nothing and Claude had none, walkthrough step 5).
- **FR-014**: The Codex section MUST NOT show the "Tokens this week" line. The week's total tokens of every subscription section (Claude and Codex) MUST be the Σ column at the end of its Details' day row; there is no "This week" line above the view picker (amended by spec 026 FR-008, FR-009). A section without usage this week has no Details, as today, and therefore no total.
- **FR-015**: Every section note (FR-029) and the configuration error MUST stay visible in their place with their current texts and colors.

**Times**

- **FR-016**: Every reset and run-out time in the dropdown MUST use the time format of its section: the account's for a subscription section or an own budget, the group's for a group.
- **FR-017**: The relative format MUST read "in" followed by the two largest units of the remaining time, rounded down to whole minutes: days and hours from one day on ("in 4d 16h"), hours and minutes from one hour on ("in 2h 26m"), minutes below ("in 45m"), and "in <1m" below one minute. A zero second unit MUST be omitted ("in 4d", "in 3h"). A time not in the future MUST read "now".
- **FR-018**: The absolute format MUST count calendar days from the reference time and read the time alone on the same day ("17:20"), the abbreviated weekday and time on the next six calendar days ("Fri 09:00"), and weekday, day, month and time on later days ("Sun 25. Oct 09:00") and on earlier days (a time already past), following the user's locale (the examples are illustrative; day, month and clock styles follow the locale). A run-out always includes its time, also at local midnight (spec 011 FR-009). A reset at local midnight that is not on the same day MUST read weekday, day and month without a time ("Sun 1. Nov"), as today.
- **FR-019**: Hovering a time MUST show the other form: for a relative time, the absolute long form (abbreviated weekday, day, month and time, for example "Fri 23. Oct 09:00"; without the time for a reset at local midnight); for an absolute time, the relative form. The note's tooltip MUST show only its run-out time in the other form, for example "Wed 21. Oct 05:30" (spec 026 FR-019b).
- **FR-019a**: The tooltip of a model-limit row ("Fable weekly limit, 31% of the 7-day limit") MUST cover only the limit's name, so the reset time keeps the tooltip of FR-019.
- **FR-020**: The reference time of both formats MUST be the current time, re-evaluated at least once a minute while the dropdown is open, without starting a refresh, so relative times count down and absolute times switch form when the day changes.
- **FR-021**: Each subscription account (Claude, Codex), each token-based account with its own budget, and each group MUST have a time format setting with the values Relative and Absolute. It MUST default to Relative when absent from the configuration, MUST be stored in the configuration file, and MUST be edited in that account's or group's detail in Settings with a segmented picker labeled "Times" (options "Relative" and "Absolute"), through the Settings draft like every other setting. A token-based account in a group MUST NOT offer it; a value stored for it is kept and applies again when the account gets its own budget. The Unassigned section shows no times and has no setting.
- **FR-022**: The time format MUST affect only the dropdown; the menu bar and notifications MUST stay unchanged.

**Footer**

- **FR-023**: Below the last section, on the footer's own band (amended by spec 028: alternating bands, no dividers), the dropdown MUST show, in this order: source errors (red, as today), the update line (FR-026), the status row with the refresh icon, "Last refreshed" and the Settings and Quit icons. The footer is pinned below the scrolling sections (amended by spec 026 FR-010 to FR-012).
- **FR-024**: The "Last refreshed" line MUST read "Last refreshed <time>" for a refresh today and add the date for an earlier day; "Refreshing…" and "No successful refresh yet" stay as today, and the "stale" marker stays beside it. The text sits in the status row next to the refresh icon, not on a line of its own (amended by spec 026 FR-012).
- **FR-025**: While a pace is slower than its base (spec 016 FR-016), the pace line text (spec 019) MUST NOT be a line of its own; it MUST be the tooltip of the "Last refreshed" text and that text's accessibility value. When the status row truncates the text, the tooltip also holds the full status text, joined to the pace text by a line break; with neither, there is no tooltip (amended by spec 026 FR-013).
- **FR-026**: The update line MUST show every state it shows today (spec 013 FR-009, FR-013, FR-018, FR-019), with its actions, except the transient result of a manual check, which the dropdown no longer starts (FR-028). An install that fails during this run and a failed install reported by the previous run keep their line.
- **FR-027**: The status row (amended by spec 026 FR-012: it also holds the "Last refreshed" text right of the refresh button) MUST hold a refresh button on the left (the action of today's "Refresh now") and Settings and Quit buttons on the right, as icons without text, each with a tooltip and accessibility label ("Refresh now", "Settings…", "Quit AgentTacho"). ⌘, and ⌘Q MUST work while the dropdown is open.
- **FR-028**: The gear menu MUST be removed. The dropdown MUST NOT offer "About AgentTacho" or "Check for Updates…"; both remain in Settings > About (spec 020).

**Testable core logic**

- **FR-029**: The text and style (neutral, warning, alert) of every section note MUST be decided by tested core logic; the view only renders it (idea inbox: dropdown-note-view-model). The section notes are: retrying (grace), stale, rejected sign-in, not signed in, expired credentials, Codex local-only data, Codex newer snapshot, Codex unavailable, no data or refreshing, the budget's incomplete-prices note ("incomplete, unpriced: …", warning), the empty-group note ("No accounts in this group yet", neutral), the plain "stale" marker of the Codex and Unassigned sections and the budget's "stale since <time>" note (warning). Neutral renders in the secondary color, warning in orange, alert in red, as today.
- **FR-030**: Each row's bar tick, note and fill color MUST be derived from one value that carries both the row's pace and its burn rate, so they cannot disagree (idea inbox: single-pace-and-burn-value).
- **FR-031**: The relative and absolute formats of FR-017 and FR-018 MUST be tested core logic that takes the calendar (with its time zone), the locale and the reference time as inputs; the reference time MUST be passed in as an input and never read inside the formatter, and whether a time is "today" MUST be decided against it (idea inbox: run-out-text-in-core).
- **FR-032**: The bar's geometry (fill share, tick position, color) and the note's presence and text MUST be decided by tested core logic.

**Documentation, specs and website**

- **FR-033**: These earlier specs MUST be amended where they describe what this feature changes: spec 004 FR-018a (member line of a single member), spec 007 FR-011 and FR-013 (Codex section lines), spec 011 FR-008, FR-009 and FR-010 (pace meter, its tooltip, run-out text), spec 013 FR-003 and FR-009 (dropdown check, update line placement above the footer), spec 016 FR-016 and spec 019 (pace line placement), spec 017 FR-012 (burn text in the meter tooltip), spec 020 FR-010 (the gear menu's "Check for Updates…" no longer exists), spec 024 FR-014 (pace states shown by bars and notes instead of pace meters), and spec 024 FR-019 (the `plan-limits` shot shows bars instead of pace meters; the `pace` shot shows a row with its bar and orange note instead of the meter tooltip).
- **FR-034**: The README MUST describe the new dropdown wherever it describes the old one (pace meter tooltip, Codex lines, pace line, gear menu, footer) and document the time format setting in its configuration reference.
- **FR-035**: The demo `default` scenario MUST keep the default time format (relative) in every section and MUST show at least one row with an orange note and a group with two or more members; the scenario coverage test MUST check these states. The absolute format and the single-member group MUST be shown by a second bundled demo scenario that is not used for published shots, and the coverage test MUST check them there; core tests cover the formats as well. The capture script MUST open Settings through the dropdown's Settings icon button instead of the removed gear menu and MUST crop the `pace` shot from the row with its orange note. Recapturing the shots, the README image and the website copy are deferred (see Known Deviations).

### Key Entities

- **Time format**: a per-account and per-group choice, Relative (default) or Absolute, stored in the configuration file; it decides how the section's reset and run-out times read and which form the tooltip shows.
- **Row bar**: what a window row or budget draws below its first line: fill share (0 to 1), optional tick position (0 to 1), fill color (neutral, attention, over limit), and an optional note text.
- **Section note**: a text and a style (neutral, warning, alert) for the state of a section's values; the list of notes is in FR-029.

## Known Deviations

### Deferred: screenshots, README image and website copy (2026-10-19)

- **Requirement**: constitution V and the original FR-035 ask that the changed shots (`plan-limits`, `pace`, `budget`, `details`, `harnesses`, `groups`, `dropdown`) be recaptured from the demo build and reviewed, the README image `docs/images/agenttacho-dropdown.png` replaced, and the site copy that mentions the pace tooltip or the gear menu changed, when the pull request merges.
- **Deviation**: spec 025 merges without them. The published site and the README image still show the previous dropdown until the follow-up lands.
- **Reason**: the maintainer chose to merge after the walkthrough (9 of 9 steps passed) and to do the capture in a separate session, because the capture quits AgentTacho and takes over the Mac. Follow-up polish from the walkthrough (idea inbox `minimal-dropdown-round-2`) changes the same shots again.
- **Plan**: idea inbox entry `minimal-dropdown-screenshots`. The capture, image review, README image and site pull request (AGENTS.md steps 4 to 8) MUST happen before the next release that ships this dropdown.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With every row on pace or behind, the Claude section with three windows takes no more text lines than before (header plus one text line per window); bars add height but no text.
- **SC-002**: A user can tell which windows are ahead of pace and when they run out without hovering anything (checked in the walkthrough on the demo build).
- **SC-003**: The footer never shows more than one text line below the update line ("Last refreshed"), and the icon row is always the last row.
- **SC-004**: Opening Settings or quitting takes one click from the open dropdown (instead of two through the gear menu).
- **SC-005**: The Codex section shows two fewer lines than before (plan type and "Tokens this week").
- **SC-006**: Every relative and absolute time case of FR-017 and FR-018 (under a minute, minutes, hours, days, whole units, past, today, within six days, beyond, midnight reset) is covered by an automated test with a fixed calendar and reference time.
- **SC-007**: All existing automated tests pass, and a configuration file written before this feature loads without a problem notice and shows relative times.

## Assumptions

- The dropdown keeps its width (360 pt), its always-dark panel and its height cap with scrolling; past the cap only the sections scroll and the footer stays pinned (amended by spec 026 FR-010).
- The bar is a thin capsule (about the height of today's meter line, a little thicker) in the panel's secondary color for the track; the tick is a short vertical mark in the primary text color.
- The note reuses the pace summary words of spec 011 and spec 017; only the time inside it changes format.
- The Unassigned section keeps its content; it is the last section and takes the next band in the alternation like every section, but has no times (amended by spec 028: alternating bands, no dividers).
- Absolute times use 24-hour or 12-hour clock as the user's locale says; published images use English and the US locale (constitution).
- No change to refresh logic, pace or burn-rate computation, notifications, the menu bar label or the update logic.
