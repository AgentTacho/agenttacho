# Feature Specification: Burn Rate Escalation

**Feature Branch**: `017-burn-rate-escalation`

**Created**: 2026-10-16

**Status**: Draft

**Input**: User description: "Burn rate escalation (from brainstorm/16-burn-rate-escalation.md). Escalate the spec 011 run-out marker from ↗ to ↑ when the burn rate (average since window start, or the recent rate over the last 60 minutes from in-memory samples) is at least k = 2 times the sustainable rate (remaining percent over time left until reset). Same suppression rules and toggle as ↗; no new requests, no stored files, no notifications; the dropdown pace meter tooltip and accessibility text name the fast burn."

The pace forecast (spec 011) puts "↗" after a bar value when the average rate since the window start projects a run-out before the reset. The marker is binary: an entry that runs out on the last day of the week looks the same as one that will hit its limit within the hour. And because the average reacts slowly, a burst right now (a long agent run this afternoon after a quiet week) can go unnoticed until the warning threshold is reached. This feature measures how fast an entry burns compared with what the remaining time allows, and escalates the marker to "↑" when it burns at least twice as fast. Everything is computed from values AgentMeter already observes; the only new data is a short list of recent observations kept in memory. There are no new requests, credentials or stored files, so the README's "Security and privacy" section stays true unchanged.

## Clarifications

### Session 2026-10-16

- Q: A price import or a price override edit recomputes a budget's spend without any new usage; should that discard the budget's observations so the jump does not look like a burst? → A: Yes. A change of the prices used for a budget's spend discards its observations, like a change of its amount, period or members (FR-003).
- Q: When an entry burns fast, does the dropdown pace text show the fast run-out in addition to spec 011's run-out, or instead of it? → A: Instead of it. The text shows one run-out, the fast run-out of FR-007, after "burning fast" (FR-012).
- Q: What exact phrase does the bar's accessibility description use for "↑"? → A: ", burning fast, projected to run out well before reset", appended after the value in place of spec 011's ", projected to run out before reset" (FR-011).
- Q: Verification found three rules in the code that the spec did not state (a 60-second tolerance for reset times, dropping observations after the clock is set back, stale budgets adding no observation); should the spec describe them? → A: Yes, FR-003 and FR-007 now state them; the code is unchanged.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See a burst that will hit the limit soon (Priority: P1)

A user had a quiet week on their Claude subscription: on Wednesday until 13:10 the 7-day window stays at 30% with 60% of the week elapsed, so the bar shows "30%" with no marker. They start a long agent run, and the 7-day value climbs from 30% at 13:10 to 36% at 14:00. At that pace (7.2 points per hour) the remaining 64% would be gone in about 9 hours, while the reset is almost three days away. After this feature, the bar shows "36%↑" within the next refresh, long before the warning threshold, so the user can slow down or switch agents.

**Why this priority**: Bursts are what actually stop work mid-week, and the average-since-start model of spec 011 cannot see them while the overall pace is still behind.

**Independent Test**: Feed a sequence of observations of one window spanning at least 15 minutes within the last hour, with a change of at least 2 points, whose recent rate is at least twice the sustainable rate, with the average pace behind; check that the bar entry shows "↑". Feed a sequence whose recent rate is below twice the sustainable rate; check that it shows no "↑".

**Acceptance Scenarios**:

1. **Given** a 7-day window observed at 30% at 13:10 and at 36% at 14:00, with the reset about 66 hours after 14:00, **When** the bar is displayed after the 14:00 refresh, **Then** the entry shows its value followed by "↑" (recent rate 7.2 points per hour, sustainable rate 64 / 66 = 0.97, doubled 1.94).
2. **Given** a 7-day window observed at 30% at 13:10 and at 31% at 14:00, with the reset 66 hours away, **When** the bar is displayed, **Then** the entry shows no "↑" (a change of 1 point is below the 2-point minimum, and 1.2 points per hour is below twice the sustainable rate: sustainable 69 / 66 = 1.05, doubled 2.09).
3. **Given** a monthly budget with 50% of the month elapsed, observed at 37% 40 minutes before the snapshot and at 40% at the snapshot (behind, no "↗"), with no earlier observation within the lookback, **When** the bar is displayed, **Then** the budget entry shows "↑".
4. **Given** the only observations within the last hour span less than 15 minutes, **When** the bar is displayed, **Then** the recent rate does not count and the entry shows "↑" only if the average rate qualifies (FR-006).

---

### User Story 2 - Tell a close run-out from a distant one (Priority: P1)

A user's 7-day window is well ahead of even use. With "↗" alone they cannot tell whether it runs out on Wednesday evening, a day before the Thursday reset, or this afternoon. After this feature, an entry whose average rate is at least twice the sustainable rate shows "↑" instead of "↗": at the current average pace it runs out in half the remaining time or less.

**Why this priority**: It turns the existing marker into a two-step scale with no extra UI, and it needs no samples, so it works right after launch.

**Independent Test**: With entries whose average rate is between one and two times the sustainable rate, and at or above two times, check that the first shows "↗" and the second "↑", with the same values in the dropdown.

**Acceptance Scenarios**:

1. **Given** a 7-day window at 62% with 43% of the window elapsed (run-out Tuesday, reset Thursday), **When** the bar is displayed, **Then** the entry shows "62%↑" (average rate 62 / 72.2 h = 0.86 points per hour, sustainable 38 / 95.8 h = 0.40, ratio 2.2).
2. **Given** a 7-day window at 55% with 45% of the window elapsed, **When** the bar is displayed, **Then** the entry shows "55%↗": it is 10% ahead, but its average rate (55 / 75.6 h = 0.73 points per hour) is below twice the sustainable rate (45 / 92.4 h = 0.49, doubled 0.97).
3. **Given** an entry that would show "↑" reaches its warning threshold, **When** the bar is displayed, **Then** the entry shows "⚠" and its value, without "↑" or "↗".

---

### User Story 3 - Understand why the arrow points up (Priority: P2)

A user sees "↑" in the bar and opens the dropdown. The pace meter of that window or budget reads, as its tooltip and accessibility label, "8% behind · burning fast · runs out 18:40": it tells them the entry burns fast and when it runs out at that rate. VoiceOver reads the bar entry as burning fast.

**Why this priority**: The bar arrow is a glance signal; the explanation belongs in the dropdown, which already holds the pace text.

**Independent Test**: With an entry that qualifies through the recent rate and one that qualifies through the average rate, open the dropdown and check each pace meter's text and color; read the status item with VoiceOver.

**Acceptance Scenarios**:

1. **Given** a window that qualifies through its recent rate while 8% behind even use, **When** the user hovers its pace meter, **Then** the tooltip reads "8% behind · burning fast · runs out <time at the recent rate>" and the meter uses the orange attention color.
2. **Given** a window that qualifies through its average rate while 19% ahead, **When** the user hovers its pace meter, **Then** the tooltip reads "19% ahead · burning fast · runs out <time>".
3. **Given** a bar entry showing "↑", **When** VoiceOver reads the status item, **Then** the entry's description says it is burning fast and projected to run out well before its reset.
4. **Given** the marker toggle is off, **When** the user opens the dropdown, **Then** the pace meters still say "burning fast" where it applies (the toggle affects only the bar).

---

### Edge Cases

- **Right after launch**: no recent samples exist yet; "↑" can only come from the average rate until two observations span at least 15 minutes. Values restored from the last good store at launch (spec 010) count as an observation when their observation time is within the lookback (FR-003).
- **Same observation repeated**: a refresh that reuses the previous subscription result (same fetch time) or a Codex observation that has not changed adds no new sample.
- **Window reset between samples**: a changed reset time or a lower percent than an earlier sample discards the earlier samples of that window.
- **Budget amount, group membership or prices edited**: the percent of a budget can jump without any new usage; its observations are discarded when its amount, its period, its members or the prices used for its spend change (a price import or a price override edit).
- **Quiet after a burst**: the lookback is anchored at the snapshot time, so a burst older than 60 minutes no longer counts; while Codex writes no new observations its recent rate expires the same way.
- **Single whole-percent step**: a change of less than 2 percentage points within the lookback never qualifies through the recent rate, so one rounding step on a long window cannot turn on "↑".
- **Rate falls**: once the recent rate falls below the threshold and the average rate does not qualify, "↑" returns to "↗" (if spec 011 still projects a run-out before the reset) or to no marker.
- **Early in the window**: the recent rate counts inside spec 011's 10% hold back; the average rate does not (FR-006).
- **No pace**: an entry without a pace under spec 011 FR-007 (window not started, at or above 100%, limit reached, empty group, no data, window already reset) never shows "↑".
- **Stale entry, member share, warning or over-limit glyph, toggle off**: no "↑", exactly like "↗" (spec 011 FR-013, FR-014).
- **Fast run-out already passed**: when the newest observation is older than the snapshot (for example Codex values from logs that stopped an hour ago), a qualifying rate can project a run-out at or before the snapshot time. Such a rate does not qualify (FR-007), and the entry falls back to spec 011's marker rules. A qualifying rate never projects a run-out at or after the reset, because it runs out within half the remaining time.
- **Slow refresh**: with a refresh interval above 60 minutes, at most one observation falls within the 60-minute lookback, so there is no recent rate and "↑" comes only from the average rate.

## Requirements *(mandatory)*

### Functional Requirements

**Rates**

- **FR-001**: For every entry with a pace (spec 011 FR-001, FR-007), the app MUST compute the sustainable rate at the observation time: the remaining percent (100 minus the unrounded used percent) divided by the time from the observation time to the reset, in percentage points per hour.
- **FR-002**: The average rate MUST be the unrounded used percent divided by the time elapsed since the window start at the observation time (the linear model of spec 011 FR-004).
- **FR-003**: The app MUST keep, in memory only, the observations of every window and budget that has a pace: observation time (spec 011 FR-002), unrounded used percent and reset time. An observation is added only when its observation time is later than the newest kept observation of that window. Observations whose time is before the snapshot time minus 60 minutes are dropped; an observation exactly 60 minutes old is kept. A changed reset time (a reset time 60 seconds or more away from the kept one, so second-level differences between sources of the same reset do not count; for a budget, the end of its window, so any move of the budget window counts), a used percent lower than an earlier observation, or a changed budget amount, period, member list or price table (a price import or a price override edit) discards the earlier observations of that window or budget. An entry that has no pace at a refresh (spec 011 FR-007) discards its observations. A stale budget adds no observation (its values are carried over, not observed again) and keeps its earlier ones, which the lookback prunes. Kept observations more than 10 minutes after the snapshot time (the clock was set back) are dropped. Nothing is written to disk and the list starts empty at launch; the first observation after launch may be a value restored from the last good store (spec 010) when its observation time is within the lookback.
- **FR-004**: The recent rate MUST be the change in used percent between the oldest and the newest observation of the same window within the last 60 minutes before the snapshot time, divided by the time between them. It exists only when those two observations are at least 15 minutes apart and the change is at least 2 percentage points.

**Escalation**

- **FR-005**: The escalation factor k MUST be 2: an entry burns fast when a qualifying rate is at least k times its sustainable rate, that is, at that rate it runs out in half the time left until the reset or less.
- **FR-006**: The average rate qualifies only when spec 011 counts a run-out for the entry (ahead beyond the band, run-out after the snapshot time and before the reset, FR-005, and not withheld by the 10% hold back, FR-006). The recent rate qualifies whenever it exists (FR-004), also when the entry is on pace or behind and inside the hold back.
- **FR-007**: The fast run-out MUST be the observation time of the qualifying rate plus the remaining percent at that observation divided by that rate. For the recent rate this is the newest observation within the lookback, which is the entry's current observation (for a stale budget, its last observation before it became stale); for the average rate it is the entry's observation time (spec 011 FR-002). When both rates qualify, the earlier run-out is used. A rate whose run-out is at or before the snapshot time does not qualify; when no rate qualifies, the entry falls back to spec 011's marker rules.

**Menu bar**

- **FR-008**: A bar entry MUST show "↑" instead of "↗" directly after its value when the window or budget its bar value follows (spec 011 FR-012) burns fast (FR-005 to FR-007). An entry shows at most one of the two markers.
- **FR-009**: "↑" MUST follow the suppression rules of "↗" (spec 011 FR-013): not while the warning or over-limit glyph shows, not on a stale entry, not on a group member's share entry.
- **FR-010**: The Menu Bar tab toggle of spec 011 FR-014 MUST cover both markers and read "Show ↗ or ↑ when an entry will run out before it resets". Its stored setting is unchanged, so existing configurations keep their choice. The Menu Bar tab's bar preview shows "↑" by the same rules.
- **FR-011**: The accessibility description of an entry showing "↑" MUST end its value with ", burning fast, projected to run out well before reset" instead of spec 011's ", projected to run out before reset" (the phrase as implemented for spec 011 FR-015).

**Dropdown**

- **FR-012**: When a window or budget row with a pace meter (spec 011 FR-008) burns fast, the meter's pace text MUST be the delta text followed by " · burning fast · runs out <time>", with the fast run-out (FR-007) formatted like spec 011 FR-009; it replaces spec 011's " · runs out <time>", so the text names one run-out only, and the meter MUST use the orange attention color (spec 011 FR-010). The meter's bar position is unchanged. This applies to every row that has a pace meter, whether or not its window is the one shown in the bar, and does not depend on the toggle.

**Scope and constraints**

- **FR-013**: The feature MUST NOT add network requests, credential reads, stored files or notifications, and the README's "Security and privacy" section MUST remain accurate without change.
- **FR-014**: The README's description of the bar markers and of the Menu Bar tab toggle MUST describe "↑" and the new toggle label (FR-010) in the same change.
- **FR-015**: The rate computation, the observation list rules, the escalation decision and the marker choice MUST be part of the tested core; the app layer only renders their results.

### Key Entities *(include if feature involves data)*

- **Observation**: one value of one window or budget: observation time, unrounded used percent, reset time. Kept in memory for at most 60 minutes. Observations belong to one window, identified by the account and window kind for Claude (5-hour, 7-day, or the model name for a model-scoped weekly limit), the account and window length for a Codex plan, and the group or the account with its own budget for budgets.
- **Burn rate**: for one window or budget at one snapshot: sustainable rate, average rate, recent rate if it exists, whether the entry burns fast, and the fast run-out.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: When the recent rate (FR-004) of the window a bar entry follows reaches at least twice its sustainable rate and the entry is not suppressed (FR-009), the bar shows "↑" at that refresh, without the user opening the dropdown.
- **SC-002**: For every entry kind (Claude 5-hour, 7-day, model limit, Codex window, weekly budget, monthly budget), the "↑" decision and the fast run-out match a hand calculation from the observed values to within one minute.
- **SC-003**: A single whole-percent step never turns on "↑" through the recent rate.
- **SC-004**: With the toggle off, the menu bar is identical to the bar before spec 011.
- **SC-005**: The feature adds zero network requests and zero files written, verified by the unchanged security statement and diagnostic log.

## Assumptions

- This feature amends spec 011 FR-005, FR-006 and SC-003 for fast entries only: the fast run-out (FR-007) and "↑" are shown also when the entry is on pace or behind and inside the 10% hold back. Entries that do not burn fast keep spec 011's rules unchanged.
- k = 2 applies to every window kind, including the 5-hour window; a configurable factor is out of scope.
- The lookback is 60 minutes, the minimum span 15 minutes and the minimum change 2 percentage points for every window kind.
- There is no hysteresis: the 60-minute lookback already smooths the recent rate, and the average rate changes slowly between refreshes.
- With adaptive refresh (brainstorm 15), endpoint calls stay at the base interval while an agent is active, which is when bursts happen, so the observations stay dense when they matter; while no agent is active, fewer observations simply mean no recent rate.
- The "↑" glyph renders in the monochrome menu bar like "↗"; colored bar levels (spec 012) leave entries without a level neutral, so "↑" stays neutral like "↗".
- Out of scope: notifications from pace or burn rate, persisted observations, burndown charts, a recent-rate model for the dropdown pace delta.
