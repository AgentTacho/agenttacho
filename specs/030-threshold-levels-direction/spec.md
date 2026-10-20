# Feature Specification: Threshold Levels and Budget Direction

**Feature Branch**: `030-threshold-levels-direction`

**Created**: 2026-10-20

**Status**: Draft

**Input**: User description: "Threshold-driven warning and critical levels for the menu bar and the dropdown, plus a global used or remaining direction switch (from brainstorm/29-threshold-levels-direction.md). The lower notification threshold is the warning level, the upper one the critical level, everywhere a level is shown; in the dropdown only the percent number takes the level color and the bar turns red at the critical threshold. A General setting shows every budget and limit either as used (0% to 100%, today) or as remaining (100% to 0%); arrows flip, thresholds read in the chosen direction while they stay stored as used percent, and budgets above 100% show a negative remaining value."

Each Claude subscription, Codex plan and budget (group or own budget) has notification thresholds, two fields in Settings with 80% and 100% as the defaults (spec 001 FR-027). They only partly decide what the user sees. In the menu bar the lowest threshold sets the **warning** level, but the **critical** level is fixed at 100% (spec 001 FR-003, spec 012). In the dropdown the thresholds have no effect at all: a row's percent turns red only at 100% or more, and its bar is orange for pace attention or red at 100% (spec 025 FR-003). A user who sets the upper threshold to 90% is notified at 90% and sees nothing red until 100%. This spec makes the thresholds the single source of both levels everywhere.

The app also shows every budget and limit as filling up, from 0% to 100% used. Some users think in what is left and want to watch the budget empty as they burn it down. This spec adds one global switch for that.

In this spec a **level owner** is a Claude subscription account, a Codex subscription account, or a budget (a group budget or an account's own budget). Its **thresholds** are the positive whole numbers configured for it, in used percent. Its **warning threshold** is the lowest of them; its **critical threshold** is the second lowest, or 100 when it has fewer than two (FR-002). A **level value** is a percent that is compared with the thresholds of its owner: a bar entry's value, a subscription window row's percent, a budget's percent. The **direction** is the global display setting, **used** or **remaining**. A **remaining value** is 100 minus the used value, so a budget at 115% used has a remaining value of −15%.

## Clarifications

### Session 2026-10-20

- Q: Does a remaining value carry a word such as "left" in the menu bar and the dropdown percents? → A: No. Menu bar values, section header percents, row percents and budget percents stay a bare number ("30%"), so the bar keeps its width; the direction is a deliberate global setting and the bar fill shows it. In direction remaining the accessibility text adds "left" ("30% left"), and the budget dollar line says "left" or "over" (FR-012).
- Q: Which character is the minus sign of a negative remaining value? → A: The typographic minus U+2212 ("−15%"), which lines up with the digits; the accessibility text reads "15% over budget" instead of the sign.
- Q: Where does the direction setting sit and what control is it? → A: In the General tab, in a new "Display" section after "Refresh": a segmented control "Show usage as" with "Used" and "Remaining", and the caption "Remaining counts down from 100% as you use a limit or budget. Thresholds and notifications follow."
- Q: (review-spec) How do equal thresholds, below-100 critical accessibility words, cross-window rules in dropdown rows, stored thresholds above 100 in the editor, used-mode accessibility text, member lines, the "over" boundary of the dollar line and queued notifications behave? → A: [T, T] gives warning = critical = T; critical below 100% reads "critical", a real limit "over limit"; dropdown rows use only their own value and limit state; a stored 120 shows as "−20 (20% over)"; used mode keeps today's texts; member lines stay uncolored; "over" starts when the rounded used percent is above 100; wording follows the direction at posting time (FR-002, FR-004, FR-005, FR-009, FR-012, FR-015, FR-016).
- Q: What exactly do threshold notifications say in direction remaining? → A: For a stored threshold T of 100 or less, the title reads "<name> has <100 − T>% left" and the body "<window> window at <remaining>% left"; for T above 100, the title reads "<name> is <T − 100>% over" and, while the value is above 100% used, the body "<window> window at <used − 100>% over". Direction used keeps today's "<name> reached T%" and "<window> window at P%".

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Red at my own limit (Priority: P1)

A user on a Claude Max plan wants a hard stop at 90% of the 7-day window, so they set the second notification threshold to 90%. At 91% they get the notification, and the menu bar value turns red at the same moment. In the dropdown the 7-day percent is red and its bar is red too. The 5-hour row at 82% shows its percent in orange, because it passed the first threshold (80%), while its bar stays neutral as long as its pace is fine.

**Why this priority**: The levels and the notifications must agree; it is the smaller and most requested half of the feature.

**Independent Test**: In the demo build or with unit tests, set an owner's thresholds to 80 and 90, feed values of 79, 85 and 91; check the menu bar level, the dropdown percent color and the bar tone for each.

**Acceptance Scenarios**:

1. **Given** a subscription with thresholds 80 and 90, **When** its headline window is at 91%, **Then** the menu bar entry is at the critical level (red in the text and pill styles of spec 012).
2. **Given** the same thresholds, **When** a window row is at 85%, **Then** its percent in the dropdown is orange and its bar keeps its pace tone (neutral or orange attention).
3. **Given** the same thresholds, **When** a window row is at 91%, **Then** its percent and its bar are red.
4. **Given** a budget with thresholds 50 and 75, **When** its spend is at 60% of the budget, **Then** its menu bar entry and its dropdown percent are orange; at 80% both are red and the budget bar is red.
5. **Given** an owner with no thresholds, **When** values are drawn, **Then** the levels are warning at 80% and critical at 100%, as today.
6. **Given** a subscription with thresholds 80 and 120, **When** its 7-day window is at 100%, **Then** the entry is critical: a real limit is always critical.

---

### User Story 2 - Watch the budget empty (Priority: P1)

A user prefers to see what is left. In Settings, General, they switch "Show usage as" from "Used" to "Remaining". The menu bar entry that read "✳ 70%" now reads "✳ 30%", the dropdown's 7-day row reads 30% with a bar that is 30% full, and a budget at $40 of $100 per week reads "$60 left of $100/week" with 60%. An entry that will run out before its reset shows `↘` instead of `↗`, a fast burn `↓` instead of `↑`. Switching back restores today's look at once.

**Why this priority**: It is the second half of the agreed feature and changes every visible number, so it has to be complete and consistent from the start.

**Independent Test**: In the demo build, switch the setting and compare the menu bar, the dropdown sections, a budget and the Settings preview with the used view: every level value is 100 minus its used value, and the arrows are flipped.

**Acceptance Scenarios**:

1. **Given** direction remaining, **When** a subscription window is at 70% used, **Then** its menu bar value and its dropdown percent read 30% and its bar is 30% filled.
2. **Given** direction remaining, **When** an entry runs out before its reset at the current pace, **Then** its marker is `↘`; when it burns fast, `↓`.
3. **Given** direction remaining, **When** a budget has spent $40 of $100 per week, **Then** its dropdown line reads "$60 left of $100/week" and its percent 60%.
4. **Given** direction remaining, **When** the user switches back to used, **Then** every value, bar, marker and wording returns to today's look without a refresh.
5. **Given** direction remaining, **When** levels are computed, **Then** they are the same as in direction used: the colors of an entry do not change when the direction changes.
6. **Given** direction remaining, **When** the Menu Bar tab's preview is drawn, **Then** it shows remaining values and flipped markers exactly as the bar does.

---

### User Story 3 - Over budget in remaining mode (Priority: P2)

A user tracks a Vertex AI budget of $100 per week in remaining mode. They spend $115. The menu bar entry reads "−15%" in red, the budget bar in the dropdown is empty and red, and the budget line reads "$15 over $100/week".

**Why this priority**: Only token-priced budgets can pass 100%; they need an honest value, but the case is rarer than the main flows.

**Independent Test**: Unit tests and a demo scenario with a budget above 100% in remaining mode; check the value, the sign, the bar fill, the color and the dollar text.

**Acceptance Scenarios**:

1. **Given** direction remaining and a budget at 115% used, **When** the bar and the dropdown are drawn, **Then** the value reads "−15%" at the critical level and the budget bar is empty.
2. **Given** the same budget, **When** the dropdown line is drawn, **Then** it reads "$15 over $100/week".
3. **Given** direction used and the same budget, **When** values are drawn, **Then** they read 115% and "$115 of $100/week" as today.

---

### User Story 4 - Thresholds in the chosen direction (Priority: P2)

A user in remaining mode opens a budget's thresholds in Settings. The fields read "First notification at 20% left" and "Second notification at 0% left". They change the first one to 30% left. The configuration file stores 70, and the notification later reads "Max has 30% left". Switching the direction back to used shows 70% and 100% in the fields; nothing about when notifications fire changed.

**Why this priority**: Without it the menu bar says 30% while Settings says 70%, which breaks the one language of the UI; it depends on the switch of story 2.

**Independent Test**: Unit tests for the conversion and the notification text in both directions; in the app, enter a value in remaining mode and check the stored configuration value and the field after switching back.

**Acceptance Scenarios**:

1. **Given** direction remaining and stored thresholds 80 and 100, **When** the thresholds editor is shown, **Then** the fields show 20 and 0, labeled as percent left.
2. **Given** direction remaining, **When** the user enters 30 in the first field, **Then** the configuration stores 70.
3. **Given** direction remaining and a threshold stored as 80, **When** usage rises past 80% used, **Then** the notification says the owner has 20% left, and it fires at the same moment it would in direction used.
4. **Given** either direction, **When** the user switches the direction, **Then** stored thresholds and notification timing do not change.

---

### Edge Cases

- Thresholds where the second field is lower than the first: the lower value is still the warning threshold and the higher one the critical threshold, as the notification order already treats them (FR-002).
- Both fields with the same value (90 and 90): warning and critical are both 90; the entry is critical there (critical wins) and never orange (FR-002).
- Stored threshold above 100 in direction remaining (120): the editor field shows -20 with "(20% over)" (FR-015).
- Direction changed while a notification is pending: the posted text uses the direction at posting time (FR-016).
- One field empty: the other value is the warning threshold and the critical threshold is 100. When that value is 100 or more, nothing is orange: below 100% the entry is normal, and at 100% it is critical (FR-003).
- More than two thresholds in the configuration file: the lowest is warning, the second lowest critical; the others only notify.
- Critical threshold above 100 (for example 120 on a budget): a budget between 100% and 120% is critical anyway, because 100% is a real limit for every owner (FR-003).
- Codex limit reached and the Claude 7-day window at 100% (spec 007 FR-012, spec 027 FR-007): critical in both directions, unchanged.
- Remaining mode and rounding: the remaining value is 100 minus the rounded used percent, so a row that shows 100% used shows 0% left and both are red; a row at 99.6% used shows 0% left and is red in both directions.
- Remaining mode and "…" or "--": unchanged, there is nothing to flip.
- Remaining mode and the stale marker: kept before the value ("✳ ~30%").
- Remaining mode and a budget without a positive amount, or unpriced spend: as today, with "left" wording only where a level value is shown.
- Remaining mode and the pace tick: the tick sits at the expected remaining share (100 minus the expected used share), so the bar and the tick keep their relation.
- Remaining mode and pace notes: the wording stays ("15% ahead · runs out in 2d 13h"), since it describes the burn rate.
- Remaining mode and member entries of a group: a member's value is its share of the group's spend, not a level of its own, so it is not flipped (FR-013).
- Remaining mode and the per-model breakdown, the per-day trend and Σ totals: spend figures, not flipped.
- A configuration file written by an earlier version: direction used, thresholds unchanged.
- Settings open while the direction changes: the thresholds editor redraws in the new direction at once.

## Requirements *(mandatory)*

### Functional Requirements

**Levels from thresholds**

- **FR-001**: Every level shown in the menu bar and in the dropdown MUST come from one level rule applied to the level value and the thresholds of its owner. The levels are normal, warning and critical, as in spec 001 FR-003 and spec 012.
- **FR-002**: The warning threshold MUST be the lowest positive threshold of the owner, or 80 when it has none. The critical threshold MUST be the second lowest positive threshold, or 100 when the owner has fewer than two; duplicates count separately, so thresholds 90 and 90 give warning 90 and critical 90 (critical wins). A value at or above the critical threshold MUST be critical; otherwise a value at or above the warning threshold MUST be warning; otherwise normal.
- **FR-003**: A real limit MUST always be critical, whatever the thresholds: a used value at or above 100%, a Codex window that reached its limit (spec 007 FR-012), and the Claude 7-day window at or above 100% while another headline window is chosen (spec 027 FR-007).
- **FR-004**: The menu bar entry's level (spec 012 text color, pill, symbols and accessibility text) MUST follow FR-001 to FR-003. Member entries of a group keep their level from the group's thresholds, with the same rule. The accessibility text MUST name a critical level below 100% used "critical" and keep "over limit" for a real limit (FR-003).
- **FR-005**: In the dropdown, each Claude and Codex window row's percent and each budget's percent MUST be drawn in orange at the warning level and in red at the critical level, with the thresholds of the account or budget; normal stays the primary color. Each row uses only its own value and its own limit-reached state; the cross-window rules of FR-003 (the Claude 7-day window while another headline is chosen, any Codex limit reached) apply only to the menu bar entry and to the section header's bold percent, which otherwise follows the same rule. Member percent lines of a group are shares, not level values, and stay uncolored.
- **FR-006**: The dropdown bar fill MUST be red when its value is critical (FR-002, FR-003). The warning level MUST NOT color the bar: orange on the bar stays the pace attention of spec 025 FR-003, and the orange pace note keeps its meaning.
- **FR-007**: The threshold editor's explanation MUST describe both levels: the first value marks a warning, the second marks the entry as critical, and a real limit at 100% is always critical. It MUST still say how empty fields behave.

**Direction switch**

- **FR-008**: The General tab MUST offer a global setting "Show usage as", a segmented control with the choices **Used** (default) and **Remaining**, in a "Display" section after "Refresh", with the caption "Remaining counts down from 100% as you use a limit or budget. Thresholds and notifications follow." It MUST be stored in the configuration file; a missing value MUST mean Used, and an older configuration file MUST load unchanged.
- **FR-009**: In direction remaining, every level value MUST be shown as its remaining value: menu bar entries, the dropdown section header percent, window row percents, budget percents, the Menu Bar tab's preview and accessibility text. The remaining value MUST be 100 minus the rounded used percent that direction used would show. The visible percent MUST stay a bare number without a "left" suffix; in direction remaining the accessibility text MUST add "left" to a percent ("30% left"), and in direction used it stays as today. Changing the direction MUST redraw at once, without a refresh.
- **FR-010**: In direction remaining, each bar MUST be filled to the remaining share, from the leading edge, clamped to empty and full; the pace tick MUST sit at the expected remaining share.
- **FR-011**: In direction remaining, the run-out marker `↗` MUST be shown as `↘` and the fast-burn marker `↑` as `↓`, in the bar, its preview and the Menu Bar tab's checkbox label. Their meaning and when they show stay as in spec 011 FR-012 and spec 017 FR-008.
- **FR-012**: In direction remaining, a budget's dollar line MUST read "$X left of $Y/period" while the rounded used percent is at most 100 and "$X over $Y/period" once it is above 100, so the dollar line, the percent and the bar never disagree (a rounded 100% reads "$0 left"), with the same amount and period formats as today. Any level value above 100% used (a token-priced budget, or a subscription window the provider reports above 100%) MUST show a negative remaining percent with the typographic minus U+2212 ("−15%") and an empty bar; its accessibility text MUST read "15% over budget" for a budget and "15% over the limit" for a window instead of the sign.
- **FR-013**: Values that are not level values MUST NOT flip: member shares of a group, the per-model breakdown, the per-day trend, Σ totals, token counts, costs and the pace note wording.
- **FR-014**: The levels MUST be the same in both directions (FR-001 to FR-003 work on the used value); only the presentation changes.

**Thresholds in the chosen direction**

- **FR-015**: Thresholds MUST stay stored in used percent in both directions. In direction remaining, the thresholds editor MUST label its fields "First notification at [field] % left" and "Second notification at [field] % left", show each stored threshold T as 100 − T, convert entered values back (an entered L is stored as 100 − L), and its validation MUST accept whole numbers below 100, negatives included, so every positive stored threshold can be entered; a stored threshold above 100 (for example 120) shows as the negative number -20 (typed and shown with the field's plain minus) with the caption "(20% over)". Its placeholders MUST read 20 and 0. The note about further thresholds from the configuration file MUST use the same direction.
- **FR-016**: Threshold notifications MUST fire at the same moments in both directions (spec 001 FR-028, spec 015). In direction remaining, for a stored threshold T of 100 or less, the title MUST read "<name> has <100 − T>% left", and for T above 100 "<name> is <T − 100>% over". The body MUST depend only on the current value: "<window> window at <remaining>% left" while the used value is at most 100, otherwise "<window> window at <used − 100>% over" ("Max has 20% left", "7-day window at 17% left"; a jump from 70% to 115% gives "weekly window at 15% over"). In direction used they stay as today ("<name> reached T%", "<window> window at P%"). The wording MUST follow the direction at the moment the notification is posted.
- **FR-017**: The diagnostic log MUST keep logging threshold crossings in used percent, so logs are comparable whatever the direction.

**Core logic and tests**

- **FR-018**: The level rule (FR-001 to FR-003), the dropdown percent and bar tones (FR-005, FR-006), the remaining value and its text (FR-009, FR-012), the bar fill and tick position (FR-010), the markers (FR-011), the threshold conversion (FR-015), the notification texts (FR-016) and the setting's encoding and decoding (FR-008) MUST be decided by tested UsageCore logic; the SwiftUI and AppKit layers only render them (constitution II).

**Specs, docs, demo and screenshots**

- **FR-019**: Earlier specs MUST be amended where they fix critical at 100% or describe values as used only: spec 001 FR-003, spec 001 FR-027 (threshold editor text), spec 001 FR-028 (notification wording), spec 012 (levels and the level words of the accessibility text, "critical" below 100% and "over limit" at a real limit), spec 025 FR-002 (fill and tick show the used percent), spec 025 FR-003 and FR-007 (bar and percent colors), spec 011 FR-012 and spec 017 FR-008 (markers). `docs/usage.md` MUST describe both levels and the direction setting, `docs/configuration.md` the stored field and that thresholds stay in used percent.
- **FR-020**: The demo `default` scenario MUST include an owner whose critical threshold is below 100 with a value between it and 100, so the dropdown and the menu bar show a threshold-driven red; the demo coverage test MUST check that state and keep its existing checks passing. A budget above 100% MUST stay available in a demo scenario for the remaining-mode check, covered by UsageCore tests for the value, sign and text.
- **FR-021**: The plan MUST list the shots that change (at least `menubar`, `dropdown`, `plan-limits`, `budget`, `pace`, `groups`, and `menubar-settings` if the preview changes) and the website copy that mentions the levels or the direction, following AGENTS.md. Whether remaining mode gets its own shot is decided in the plan.

### Key Entities

- **Level owner**: a Claude subscription account, a Codex subscription account, or a budget; holds thresholds in used percent.
- **Level thresholds**: the warning and critical thresholds derived from an owner's thresholds (FR-002).
- **Level**: normal, warning or critical for one level value (FR-001 to FR-003).
- **Display direction**: the global setting, used or remaining, stored in the configuration file.
- **Displayed level value**: a level value in the chosen direction with its text, sign, bar fill, tick position and marker glyphs.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For every owner with two distinct thresholds whose upper one is at most 100, a window's or budget's value turns red in the dropdown (and in the menu bar when it is the headline) at the same value at which the second notification fires for it; for every threshold combination the level matches FR-002 and FR-003 (checked by unit tests).
- **SC-002**: With default thresholds and direction used, the bar and the dropdown colors are the same as before this feature except that dropdown row percents and section header percents now take the level colors (orange at the warning threshold, red at the critical one).
- **SC-003**: A user switches between used and remaining with one control in Settings, and every level value on screen changes consistently at once (checked by the walkthrough and the coverage test).
- **SC-004**: Switching the direction never changes when a notification fires or what is stored for thresholds (checked by unit tests).
- **SC-005**: Level rule, remaining values, texts, markers, threshold conversion and the stored setting are covered by automated tests; all existing tests pass.

## Assumptions

- The setting is global, not per owner: the user's preference is a way of reading numbers, not a property of one account.
- Member shares of a group stay as used shares in both directions: "remaining" belongs to the group budget, and a member's share of what is left has no clear meaning.
- The pace note keeps its words in both directions (brainstorm 29 decision); only arrows and numbers flip.
- An earlier AgentTacho version reading a file with the new field ignores it, as it ignores other unknown global fields.
- The orange used for warning percents in the dropdown is the same system orange as the pace attention and the menu bar's warning, and red the same system red; no yellow is introduced.
- Notifications keep their existing grouping, timing and identifiers; only their wording follows the direction.
