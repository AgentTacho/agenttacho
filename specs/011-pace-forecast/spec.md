# Feature Specification: Pace Forecast

**Feature Branch**: `011-pace-forecast`

**Created**: 2026-10-15

**Status**: Draft

**Input**: User description: "Pace forecast (from brainstorm/10-pace-forecast.md). Show pace per window and budget in the dropdown: a secondary line per row saying \"on pace\" inside a tolerance band, otherwise \"X% ahead · runs out <when>\" or \"X% behind\"; the run-out appears only when it falls before the reset. Forecast = linear extrapolation of the average rate since window start, computed purely from the snapshot; no new requests, no stored history. Menu bar: a small hint marker on bar entries projected to run out before reset, suppressed while the warning or over-limit glyph shows, on by default with one toggle in the Menu Bar tab."

AgentMeter shows how much of a window or budget is used and when it resets, but not whether that is a lot for this point in the window: 62% of a 7-day limit is fine on day six and alarming on day two. This feature adds a pace meter to every window and budget in the dropdown and a run-out hint in the menu bar. Everything is computed from values the snapshot already holds (percent or spend and budget, window length or start, reset time, and the time the value was observed). There are no new requests, credentials or stored files, so the README's "Security and privacy" section stays true unchanged.

## Clarifications

### Session 2026-10-15

- Q: The linear model projects a run-out before the reset for every entry even slightly ahead of even use; should an entry inside the "on pace" band show a run-out or the bar marker? → A: No. A run-out (in the dropdown and as the bar marker) counts only when the entry is ahead beyond the band, that is when the rounded delta is greater than 5.
- Q: Is the "on pace" band checked against the rounded delta, and are its limits included? → A: Yes; a rounded delta from -5 to +5 inclusive is "on pace", so the rule matches the number the user could compute from the shown values.
- Q: Which Codex window decides the bar marker when a plan has several windows? → A: The longest effective window, whose percent the bar already shows (spec 007 FR-012).
- Q: What happens to the pace of a value whose window has already reset by the time of the snapshot (a stale Claude value, a Codex window past its reset)? → A: No pace and no marker; this replaces the narrower rule for values observed at or after their reset.
- Q: What if a projected run-out is already in the past at the snapshot time (an old observation not marked stale, found in code review)? → A: It does not count: no run-out text and no bar marker; the delta still shows (FR-005).
- Q: The extra text line under every row took too much space in the walkthrough; how can the pace be shown more compactly? → A: A pace meter at the end of the row (tick for even use, bar left for behind, right for ahead, length by the delta, full at 50 points); the exact text, including the run-out time, moves to the meter's tooltip and accessibility label (FR-008, FR-010).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Will the budget last until the reset? (Priority: P1)

A user has a monthly Vertex budget of 300 US dollars. At the start of 10 October they have spent 145 dollars (48% of the budget, with 29% of the month elapsed). The dropdown shows "$145 of $300/month, resets 1 Nov" but not whether that pace is a problem. After this feature, a line under the budget says "19% ahead · runs out Mon 19 Oct 14:53", so the user knows to slow down long before the month ends.

**Why this priority**: "Will the monthly budget last until the 1st?" is the question users actually ask, and budgets are where overspending costs real money.

**Independent Test**: Configure a monthly and a weekly budget, produce spend at different points of the window, and check that each budget's pace meter shows the expected delta, and a run-out time only when the budget is more than 5 points ahead and at least 10% of its window has elapsed.

**Acceptance Scenarios**:

1. **Given** a monthly budget at 48% with 33% of the month elapsed, **When** the user opens the dropdown, **Then** the budget's pace meter reads "15% ahead · runs out <time>", with the run-out time before the reset.
2. **Given** a weekly budget at 50% with 50% of the week elapsed, **When** the user opens the dropdown, **Then** the budget's pace meter reads "on pace".
3. **Given** a weekly budget at 20% with 60% of the week elapsed, **When** the user opens the dropdown, **Then** the budget's pace meter reads "40% behind" and no run-out.
4. **Given** a budget at 104%, **When** the user opens the dropdown, **Then** the budget shows no pace meter (the limit is already reached).

---

### User Story 2 - Will the subscription limit hold until the reset? (Priority: P1)

A user on a Claude subscription sees "7-day 62%, resets Thu 09:00" on Sunday at 09:00, three days into the window. They want to know whether they can keep working at this pace. After this feature, the 7-day row says "19% ahead · runs out Tue 05:07", and the 5-hour row says "on pace". The same applies to model-scoped weekly limits and Codex plan windows.

**Why this priority**: Running into a subscription limit mid-week stops work entirely; budgets and subscription windows matter equally to users.

**Independent Test**: With a subscription snapshot whose windows are at known percentages and known elapsed shares, check each window row's pace meter in the dropdown, for Claude (5-hour, 7-day, model limits) and Codex (each plan window).

**Acceptance Scenarios**:

1. **Given** a Claude 7-day window at 62% observed with 43% of the window elapsed, **When** the user opens the dropdown, **Then** the 7-day row's pace meter reads "19% ahead · runs out <time>" with a run-out time before the reset.
2. **Given** a Claude 5-hour window that has not started (no reset time), **When** the user opens the dropdown, **Then** the 5-hour row shows no pace meter.
3. **Given** a model-scoped weekly limit at 30% with 50% of its week elapsed, **When** the user opens the dropdown, **Then** its row's pace meter reads "20% behind".
4. **Given** a Codex plan with a 5-hour and a weekly window, **When** the user opens the dropdown, **Then** each window row shows its own pace meter.
5. **Given** a Codex window whose limit is reported as reached, **When** the user opens the dropdown, **Then** that row shows no pace meter.

---

### User Story 3 - See a coming run-out without opening the menu (Priority: P2)

A user glances at the menu bar. One entry shows "62%↗": the marker says this entry will run out before it resets at the current pace, even though it has not reached its warning threshold yet. Once the entry reaches the warning threshold, the existing "⚠" takes over and the marker disappears. A user who wants the bar as minimal as before turns the marker off in the Menu Bar tab.

**Why this priority**: Useful early warning, but it builds on the computation of stories 1 and 2 and the dropdown already answers the question when opened.

**Independent Test**: With an entry projected to run out before its reset and below its warning threshold, check that the bar shows the marker; raise it to the warning threshold and check the marker gives way to "⚠"; turn the toggle off and check no entry shows the marker.

**Acceptance Scenarios**:

1. **Given** a bar entry at 40% (below its warning threshold), with 25% of its window elapsed, **When** the bar is displayed, **Then** the entry shows its value followed by "↗".
2. **Given** that entry reaches its warning threshold, **When** the bar is displayed, **Then** the entry shows "⚠" and its value, without "↗".
3. **Given** an entry projected to run out before its reset with only 5% of its window elapsed, **When** the bar is displayed, **Then** no marker is shown (early-window hold back).
4. **Given** the "Show ↗ when an entry will run out before it resets" toggle is off, **When** the bar is displayed, **Then** no entry shows the marker, and the dropdown pace meters are unchanged.
5. **Given** an entry with the marker, **When** VoiceOver reads the status item, **Then** the entry's description says it is projected to run out before its reset.

---

### Edge Cases

- **Window not started**: a Claude window without a reset time shows no pace meter and no marker.
- **Value at or above 100%, or limit reached**: no pace meter, no marker; the existing over-limit styling covers it.
- **Empty group**: shows no pace meter and no marker (its spend is always 0, spec 009 FR-005).
- **Entry without data** (placeholder, "No data", "unavailable"): no pace meter, no marker.
- **0% usage**: the delta is computed normally ("on pace" early in the window, "X% behind" later); there is never a run-out.
- **Early in the window**: the delta is shown from the start, but the run-out and the bar marker appear only once the minimum elapsed share has passed (FR-006).
- **Window already reset**: when the window's reset time is at or before the snapshot time (a stale value from a past window, or a Codex window past its reset, which shows 0% without a reset time), no pace meter and no marker are shown.
- **Slightly ahead**: an entry 1 to 5 points ahead of even use shows "on pace" with no run-out and no marker, even though the linear projection would reach 100% shortly before the reset.
- **Stale entries**: the dropdown shows the pace computed at the value's observation time, next to the existing stale note; the bar marker is not shown for an entry marked stale.
- **Projection runs out exactly at or after the reset**: no run-out is shown; the delta is shown as usual.
- **Run-out already passed**: an old observation that is not marked stale (for example local Codex values) can project a run-out at or before the snapshot time; it is not shown and gives no bar marker, while the delta is shown as usual.
- **Group member shares in the bar**: a member's share entry never carries the marker; the group's own entry does.
- **Time passing while the dropdown is open**: the pace does not change until the next refresh, because it is computed at the observation time, not the current time.
- **Configuration without the new toggle**: the marker is on.

## Requirements *(mandatory)*

### Functional Requirements

**Pace computation**

- **FR-001**: For every entry with a known window, the app MUST compute the expected use as the elapsed share of the window at the time the value was observed: (observation time minus window start) divided by the window length, as a percent between 0 and 100. The window start is the reset time minus the window length for subscription and plan windows (5 hours or 7 days for Claude windows, 7 days for model-scoped weekly limits, the reported length for Codex windows) and the budget's own window for budgets (the weekly window of spec 001 FR-021 and FR-022, the calendar month of spec 003 FR-005). For budgets the window length is the window end minus the window start, so a monthly window is 28 to 31 days long.
- **FR-002**: The observation time MUST be the time the value was obtained: the subscription fetch time for Claude windows and model limits, the observation time of the Codex limits, and the snapshot time for budgets.
- **FR-003**: The pace delta MUST be the unrounded actual percent minus the expected percent, in percentage points, rounded to the nearest whole number.
- **FR-004**: The run-out time MUST be the linear extrapolation of the average rate since the window start: the observation time plus the time the remaining percent (100 minus actual) takes at that rate. There is no run-out when the actual percent is 0.
- **FR-005**: A run-out MUST count only when the entry is ahead beyond the "on pace" band (rounded delta greater than 5, FR-008) and the run-out falls strictly after the snapshot time and strictly before the window's reset time. A run-out at or before the snapshot time (an old observation that is not marked stale) does not count; the delta is still shown.
- **FR-006**: The run-out MUST be withheld (from the dropdown and the bar) until at least 10% of the window has elapsed at the observation time. The delta is not withheld.
- **FR-007**: No pace (neither delta nor run-out) MUST be computed for: a window without a reset time (a Claude window that has not started), a value at or above 100%, a Codex window reported as reached, an empty group, an entry without values, or a window whose reset time is at or before the snapshot time. The reset check uses the observed reset time compared with the snapshot time; for Codex it applies before the 0% display of spec 007 FR-010, so a Codex window past its reset never has a pace.

**Dropdown**

- **FR-008**: Every window and budget row that has a pace MUST show a pace meter at the end of the row, adding no extra line: a short track with a tick in the middle for even use. Within the "on pace" band (rounded delta from -5 to +5 inclusive) only the tick shows; ahead (above +5) a bar extends right of the tick, behind (below -5) a bar extends left of it, its length proportional to the delta's absolute value and full length at 50 points or more. The meter's pace text, shown as its tooltip and used as its accessibility label, is "on pace", "<delta>% ahead" or "<delta>% behind" with the delta's absolute value, followed by " · runs out <time>" when a run-out counts (FR-005) and is not withheld (FR-006). This applies to the Claude 5-hour and 7-day rows, model-scoped weekly limit rows, Codex plan window rows, and the budget rows of groups and own budgets.
- **FR-009**: The run-out time MUST be shown as the time only when it is today, and otherwise as weekday, day, month and time. Unlike budget reset times, a run-out always includes its time, also when it falls on local midnight.
- **FR-010**: A pace meter with a run-out MUST use the orange attention color used for other dropdown notes; a pace meter without a run-out MUST use the secondary text color.
- **FR-011**: Member lines inside a group, token-based accounts without a budget, and the Unassigned section MUST NOT show a pace meter.

**Menu bar**

- **FR-012**: A bar entry MUST show the marker "↗" directly after its value when its window or budget has a run-out that counts (FR-005) and is not withheld (FR-006). The window is the one the bar value already shows: the 7-day window for a Claude subscription (spec 001 FR-005), the longest effective window for a Codex plan, whose percent the bar shows (spec 007 FR-012), and the budget itself for groups and own budgets.
- **FR-013**: The marker MUST NOT be shown while the entry shows the warning or over-limit glyph (spec 001 FR-003), while the entry is marked stale, or on a group member's share entry (spec 004 FR-016).
- **FR-014**: The Menu Bar tab MUST have a toggle "Show ↗ when an entry will run out before it resets", on by default. It is stored in the configuration; a configuration without it behaves as on. Turning it off removes the marker from every entry and leaves the dropdown unchanged. The Menu Bar tab's bar preview (spec 008 FR-013) shows the marker by the same rules and follows the toggle.
- **FR-015**: When an entry shows the marker, the accessibility description of that entry MUST say it is projected to run out before its reset.

**Scope and constraints**

- **FR-016**: Pace MUST be computed only from values already in the snapshot. The feature MUST NOT add network requests, credential reads or stored files, and the README's "Security and privacy" section MUST remain accurate without change.
- **FR-017**: The pace computation, the hold-back rule, the tolerance band and the marker decision MUST be part of the tested core, with the app layer only rendering their results.

### Key Entities *(include if feature involves data)*

- **Pace**: for one window or budget at one observation time: expected percent, delta in percentage points, run-out time if it counts and is not withheld, and whether it is "on pace", ahead or behind.
- **Run-out marker setting**: one on or off value in the menu bar settings, default on.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can tell from the dropdown alone, in under five seconds per entry, whether each budget and subscription window will last until its reset at the current pace.
- **SC-002**: For every entry kind (Claude 5-hour, 7-day, model limit, Codex window, weekly budget, monthly budget), the pace meter matches a hand calculation from the shown percent, window length and reset time to within one percentage point.
- **SC-003**: In the first 10% of any window, no run-out time and no bar marker is ever shown, whatever the usage.
- **SC-004**: With the toggle off, the menu bar is identical to the bar before this feature.
- **SC-005**: The feature adds zero network requests and zero files written, verified by the unchanged security statement and diagnostic log.

## Assumptions

- The tolerance band is a fixed plus or minus 5 percentage points for every window; a relative band is not needed at the window lengths involved.
- The hold back is 10% of the window for every kind (30 minutes for a 5-hour window, about 17 hours for a 7-day window, about 3 days for a month); the 5-hour window needs no separate minimum.
- The delta and the run-out use the same linear model; recent-rate forecasting, history and burndown charts are out of scope.
- Pace does not trigger notifications; threshold notifications stay as they are.
- The marker glyph "↗" renders in the monochrome menu bar like the existing "⚠" and "‼" glyphs; the planned colored bar levels can later restyle it.
- The 5-hour window gets a pace meter like any other window; it is short, but "will this session hit the limit" is a real question.
