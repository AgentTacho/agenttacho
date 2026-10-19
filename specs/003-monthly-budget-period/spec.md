# Feature Specification: Monthly Budget Period

**Feature Branch**: `003-monthly-budget-period`

**Created**: 2026-10-14

**Status**: Draft

**Input**: User description: "Build the feature described in brainstorm/02-monthly-budget-period.md: Monthly budget period for budget groups. Each budget group has a period (weekly or monthly, either/or) and a single budget amount applying to that period. Monthly windows start at local midnight on the 1st and end at local midnight on the 1st of the next month."

## Context

This feature extends the budget groups defined in `specs/001-agenttacho/spec.md` (FR-006, FR-019, FR-021, FR-022, FR-027 to FR-029, FR-031). Today every budget group carries one weekly budget, and its window follows the designated subscription account's 7-day reset, falling back to a configured weekday and hour. Some token-based spend is governed by a company spending limit granted per calendar month. Tracking it against a weekly window forces the user to split the monthly amount over an uneven number of weeks, and the reset dates never match the company's month.

## Clarifications

### Session 2026-10-14

- Q: How should a hand-edited configuration be treated when a group has both the new budget amount and the legacy weekly amount, no amount at all, or an unrecognised period value? → A: When both amounts are present the new budget amount wins and the legacy one is ignored; a group with no amount or an unrecognised period value makes the configuration invalid, and the app keeps the last valid configuration (spec 001 FR-033).
- Q: Should the week fallback and the designated alignment subscription remain visible in settings when every group is monthly? → A: Yes, they stay visible and editable, with a note that they apply to weekly groups and the Unassigned entry only.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Track a group against a monthly budget (Priority: P1)

A developer's company grants a fixed monthly amount for the Vertex account. They switch that account's budget group to a monthly period with a budget of $400. From then on, the group's spend, percent, and reset date in the dropdown and the bar refer to the current calendar month, from the 1st at midnight local time to the end of the month.

**Why this priority**: This is the core value: the app mirrors the company's monthly limit without manual arithmetic.

**Independent Test**: Configure one budget group with a monthly period and a budget, let sessions run on several days of the month (including days before the start of the current week), and confirm the dropdown and bar show the month-to-date spend against the monthly budget with the reset date set to the 1st of the next month.

**Acceptance Scenarios**:

1. **Given** a budget group with a monthly period and a $400 budget, and $100 of attributed usage between the 1st of the current month and now, **When** the refresh runs, **Then** the dropdown shows $100 of $400, 25%, and a reset at 00:00 local time on the 1st of the next month.
2. **Given** the same group, and usage timestamped on the last day of the previous month, **When** the refresh runs, **Then** that usage does not count toward the current month.
3. **Given** the same group marked as shown in bar, **When** the refresh runs, **Then** the bar shows the group's label with its monthly percent, using the existing rounding and over-100% display.
4. **Given** a monthly group and a designated subscription account whose 7-day reset is mid-month, **When** the subscription reports a new reset timestamp, **Then** the monthly group's window does not move.
5. **Given** a monthly group with one token-based member account, **When** the user expands the account or the group, **Then** the per-model breakdown and the per-day trend cover the days of the current month up to today, and the rows sum to the group total.

---

### User Story 2 - Choose the period in settings (Priority: P1)

The developer opens settings and, next to the budget amount of a group, picks "Weekly" or "Monthly". The same choice is offered when a new group is created while adding a token-based account. Labels in settings and in the dropdown follow the chosen period ("Monthly budget", "per month").

**Why this priority**: Without a way to set the period, User Story 1 is reachable only by hand-editing the configuration file.

**Independent Test**: In settings, switch an existing weekly group to monthly, save, and confirm the group summary reads "per month" and the dropdown shows month-to-date values after the next refresh; then create a new group with a monthly period while adding an account.

**Acceptance Scenarios**:

1. **Given** an existing weekly group, **When** the user selects "Monthly" and saves, **Then** the next refresh shows the group's spend over the current month against the same amount, now labelled as a monthly budget.
2. **Given** the user adds a token-based account and creates a new group, **When** they choose "Monthly" and enter a budget, **Then** the group is created with a monthly period.
3. **Given** a group switched from weekly to monthly, **When** the user reopens settings, **Then** the period picker shows "Monthly" and the amount field is labelled "Monthly budget".

---

### User Story 3 - Threshold notifications for a monthly group (Priority: P2)

The developer sets thresholds of 50% and 90% on the monthly group. They get one notification when month-to-date spend crosses 50% and one when it crosses 90%. On the 1st of the next month the thresholds re-arm.

**Why this priority**: Notifications are how the user learns about an approaching company limit without opening the dropdown, but the dropdown and bar already deliver the core value.

**Independent Test**: Configure a monthly group with a threshold, drive spend across it, confirm a single notification naming the group and the monthly window, then simulate the month rollover and confirm the threshold re-arms.

**Acceptance Scenarios**:

1. **Given** a monthly group with a 50% threshold at 45% after the previous refresh, **When** the next refresh reports 55%, **Then** one notification names the group, the monthly window, and the 50% threshold.
2. **Given** that notification was sent this month, **When** later refreshes in the same month stay above 50%, **Then** no further notification is sent for 50%.
3. **Given** the month rolls over, **When** spend in the new month crosses 50% again, **Then** a new notification is sent.

---

### User Story 4 - Existing configurations keep working (Priority: P1)

The developer updates the app. Their configuration file still has the old weekly budget form. The app loads it unchanged, and every group behaves as a weekly group, exactly as before.

**Why this priority**: An update that breaks or silently changes an existing budget would cost trust immediately.

**Independent Test**: Load a configuration file written by the previous version and confirm every group appears as a weekly group with the same amount, window, and thresholds.

**Acceptance Scenarios**:

1. **Given** a configuration file written by the previous version, **When** the app starts, **Then** every group loads as weekly with its previous budget amount and the same window as before.
2. **Given** that file, **When** the user saves any change in settings, **Then** the file is written in the new form, and loading it again yields the same groups, periods, and amounts.

---

### Edge Cases

- The month has 28, 29, 30, or 31 days: the window always ends at 00:00 local time on the 1st of the next month, and the reset date shown is that day.
- A daylight saving time change falls inside the month: the window still starts and ends at local midnight on the 1st; the window is not a fixed number of hours.
- The Mac's time zone changes while the app runs: the monthly window is recomputed at the next refresh from local midnight in the new time zone.
- A group is switched from weekly to monthly (or back) in the middle of a window: the next refresh computes the new window, and threshold state for the group is reset as for a window reset, with that refresh establishing the baseline, so thresholds already exceeded in the new window do not notify.
- The app launches mid-month for the first time: the monthly window still starts on the 1st, and all usage since then that is still present in the session logs counts.
- Session logs older than the harness's own log retention have been deleted (Claude Code removes old session logs by default after a period of about 30 days): usage in those deleted logs cannot be counted; the group shows what the remaining logs contain.
- Weekly and monthly groups exist at the same time: each group uses its own window; a weekly group still follows the designated subscription's reset or the week fallback.
- A monthly group has no usage this month: it shows $0 of its budget and 0%.
- A hand-edited configuration gives a group an unknown period value or no budget amount: the configuration is rejected as invalid and the last valid configuration stays in effect.
- The Unassigned entry exists alongside monthly groups: it keeps the weekly window.

## Requirements *(mandatory)*

### Functional Requirements

Period and budget:

- **FR-001**: Every budget group MUST have exactly one period, either weekly or monthly, and exactly one budget amount in US dollars that applies to that period. The budget amount MUST be greater than 0.
- **FR-002**: A budget group without an explicit period, including every group in a configuration written by the previous version, MUST be treated as weekly. Newly created groups MUST default to weekly in settings.
- **FR-003**: A configuration file written by the previous version (weekly budget form) MUST load without error, and each group MUST keep its budget amount, window, thresholds, and shown-in-bar setting.
- **FR-004**: When the app saves the configuration, it MUST write each group's period and budget amount in the new form. The app MUST NOT rewrite the configuration file solely because it was loaded in the old form.
- **FR-004a**: When a group in the configuration file carries both the new budget amount and the legacy weekly amount, the new budget amount MUST be used and the legacy one ignored. The legacy weekly amount alone MUST be accepted only when the group's period is weekly or absent; a monthly group carrying only the legacy weekly amount MUST make the configuration invalid. A group with neither amount, or with a period value other than weekly or monthly, MUST make the configuration invalid, handled as in spec 001 FR-033 (keep the last valid configuration and surface the error).

Windows:

- **FR-005**: The window of a monthly group MUST start at 00:00 local time on the 1st of the current calendar month and end at 00:00 local time on the 1st of the following month.
- **FR-006**: The window of a monthly group MUST NOT depend on any subscription reset timestamp or on the week fallback setting.
- **FR-007**: The window of a weekly group MUST be computed as before (spec 001 FR-021, FR-022).
- **FR-008**: Only usage timestamped inside a group's own window MUST count toward that group's totals and toward the totals shown for its member accounts.
- **FR-009**: The Unassigned entry MUST keep the weekly window (spec 001 FR-009). Subscription accounts MUST be unaffected by this feature.
- **FR-010**: A change of a group's period MUST take effect at the next refresh after the configuration is saved or reloaded.

Display:

- **FR-011**: For a monthly group the dropdown MUST show spend to date, the monthly budget, the percent used, and the window reset date and time, with the same rounding and over-100% rules as weekly groups (spec 001 FR-009a).
- **FR-012**: A monthly group marked as shown in bar MUST appear in the bar with its label and monthly percent, following the same ordering and warning/over-limit styling as weekly groups (spec 001 FR-002, FR-003).
- **FR-013**: For a monthly group and its member token-based accounts, the per-model breakdown and the per-day trend MUST cover the group's monthly window, with one entry per day from the 1st up to today and days without usage shown as zero. The day row ends with a Σ column holding the sum of all shown days, after the last day on the last row (spec 026 FR-009).
- **FR-014**: Every label that names the budget's period (amount field label, group summary in settings, dropdown wording, notification text) MUST reflect the group's period: "weekly"/"per week" for weekly groups and "monthly"/"per month" for monthly groups.

Notifications:

- **FR-015**: Thresholds of a monthly group MUST follow the existing crossing rules (spec 001 FR-027, FR-028), evaluated against the monthly percent, and notifications MUST name the window as "monthly" (weekly groups keep "weekly").
- **FR-016**: Threshold state of a monthly group MUST reset when the month rolls over (spec 001 FR-029). Any change of a monthly group's computed window start, including one caused by a time zone change that moves the current time into a different month, MUST count as a window reset.
- **FR-017**: When a group's period changes, its threshold state MUST reset, and the first refresh after the change MUST establish the baseline without notifying for thresholds already exceeded.

Settings:

- **FR-018**: The settings window MUST let the user choose a group's period (weekly or monthly) next to its budget amount, both when editing an existing group and when creating a new group while adding a token-based account.
- **FR-019**: Settings MUST reject a budget amount of 0 or less for either period, with the error message naming the period.
- **FR-020**: The week fallback and the designated subscription account for window alignment MUST remain visible and editable in settings regardless of group periods, with a note stating that they apply to weekly groups and the Unassigned entry only.

### Key Entities

- **Budget group**: A named set of one or more token-based accounts sharing one budget. Attributes: label, icon, members, period (weekly or monthly), budget amount in US dollars, shown-in-bar flag, thresholds. Replaces the single weekly budget attribute of spec 001.
- **Budget period**: Weekly or monthly. Determines how the group's window is computed and how its budget is labelled.
- **Budget window**: The time range a group's spend is measured over. Weekly: aligned to the designated subscription's 7-day reset or the week fallback. Monthly: the current calendar month in local time.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can switch an existing group from weekly to monthly in settings in under 30 seconds, without editing the configuration file.
- **SC-002**: For a monthly group, the spend shown matches the sum of all attributed usage recorded since 00:00 local time on the 1st of the month (within the session logs still present) to the cent.
- **SC-003**: 100% of configuration files written by the previous version load with unchanged groups, amounts, windows, and thresholds.
- **SC-004**: On the first refresh after local midnight on the 1st, every monthly group shows only usage from the new month, and its thresholds are re-armed.
- **SC-005**: Each threshold of a monthly group produces at most one notification per calendar month.
- **SC-006**: With monthly groups configured, refresh durations still meet spec 001 SC-004 (full refresh under 10 seconds, incremental refresh with no changed files under 1 second), and the per-day trend for a 31-day window remains readable in the dropdown without horizontal scrolling. The trend's visual layout is left to planning.

## Assumptions

- Month boundaries use the Mac's current local time zone; a configurable time zone is out of scope.
- The monthly window always starts on the 1st; a custom start day is out of scope.
- A group has either a weekly or a monthly budget, never both at once.
- No pacing indicator (expected spend to date) and no pace-based notifications are added; monthly groups show a plain percent like weekly groups.
- The reset date and time of a monthly group is shown in the same format the dropdown already uses for window resets.
- The app does not keep its own copy of usage beyond the session logs; usage from logs deleted by the harness's retention cannot be counted.
- The configurable week fallback and the designated subscription account for window alignment remain global settings that affect weekly groups only.
