# Feature Specification: Dynamic Claude Plan Windows

**Feature Branch**: `040-dynamic-plan-windows`

**Created**: 2026-11-02

**Status**: Draft

**Input**: User description: "Dynamic Claude plan windows (from brainstorm/40-dynamic-plan-windows.md). Anthropic removed the 5-hour window from Claude plans; the usage endpoint now answers `five_hour: null`. AgentTacho hardcodes Claude windows as a fixed 5-hour and 7-day pair, so the dropdown shows a permanent '5-hour: unavailable' row. Make Claude plan windows a list read from the endpoint's `limits` array, with the old top-level fields as a fallback. Windows that are not sent get no row, no threshold, no pace and no headline option. Codex is unchanged."

A Claude subscription account has two **fixed windows** today, the 5-hour and the 7-day window (spec 001 FR-005, spec 027), plus a list of model limits read from the usage endpoint's `limits` array (spec 025 FR-001). Anthropic no longer reports a 5-hour window: since late October 2026 the endpoint answers `five_hour: null`, and the dropdown shows a "5-hour" row that always reads "unavailable". A Codex plan never had this problem, because its windows come from the data (spec 007 FR-009).

This spec turns the Claude windows into a list read from the answer, the way Codex windows already are. The endpoint's `limits` array already lists every limit with a `kind` (for example `weekly_all`, `weekly_scoped`), a `group` (for example `weekly`), a percent, a reset time, an optional scope (a model, or a surface) and the flags `severity` and `is_active`. Its `group` names the window family and stands in for the window length that Codex reads from `window_minutes`.

In this spec a **Claude window** is one entry of that list as AgentTacho shows it: a **plan window** (no scope, for example the weekly window) or a **model limit** (scoped to a model, for example "Fable"). A window has a **group** (from the answer), a **length** when the group is known, a **display name** and an **identity** that stays the same across refreshes (FR-004). A **known group** is one this spec maps to a length (FR-003); every other group is an **unknown group**.

## Clarifications

### Session 2026-11-02

- Q: How often is the diagnostic line listing the Claude window kinds written? → A: On the first successful fetch after launch and whenever the set of windows (kind, group, scope) changes; not on every refresh (FR-012).
- Q: Where does a model limit's length, and so its pace, come from? → A: From its group, mapped as for plan windows (FR-003): `weekly` gives 7 days as today, an unknown group gives no pace (FR-007).
- Q: Must the last-good file stay readable by the previous AgentTacho version after a downgrade? → A: Yes; besides the window list it keeps writing the legacy `fiveHour` and `sevenDay` fields for the windows with those identities (FR-014).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - No dead 5-hour row (Priority: P1)

A user with a Claude Max subscription opens the dropdown. Anthropic reports a weekly window at 11% and a Fable limit at 15%, and no 5-hour window. The Claude section shows two rows, "7-day" and "Fable", and nothing that reads "unavailable". The menu bar shows the 7-day percent as before.

**Why this priority**: It is the visible bug: a row that never has a value tells the user AgentTacho is broken.

**Independent Test**: Feed the endpoint parser the answer shape seen on 2026-11-02 (`five_hour: null`, `limits` with `weekly_all` and a `weekly_scoped` Fable entry) and check the resulting window list; with the demo build, open the dropdown and check that the Claude section has no 5-hour row.

**Acceptance Scenarios**:

1. **Given** an answer with `five_hour: null` and a `limits` array holding a `weekly_all` entry (group `weekly`) and a `weekly_scoped` entry for the model "Fable", **When** the dropdown opens, **Then** the Claude section shows the rows "7-day" and "Fable" in that order and no 5-hour row.
2. **Given** the same answer, **When** the bar is drawn with the default headline, **Then** the entry shows the 7-day percent without a tag, exactly as today.
3. **Given** the same answer, **When** a threshold is crossed in the weekly window, **Then** the notification names the "7-day" window as today, and no notification ever names a 5-hour window.
4. **Given** the same answer, **When** the Settings account pane is shown, **Then** its threshold help text does not name a 5-hour window.

---

### User Story 2 - A window that comes back or is new (Priority: P1)

Some weeks later Anthropic brings back a short window, or adds a new one. Without an AgentTacho update, the new window shows up as a row with its percent and reset time, can be chosen as the headline and gets threshold notifications. When the window is gone again, its row disappears.

**Why this priority**: It is why the list is generic rather than the 5-hour row simply hidden: the next plan change must not need a release.

**Independent Test**: Unit tests feed answers with a `limits` entry of a known short group (`five_hour` or `session`) and one of an unknown group (for example `daily`), then an answer without them; check rows, names, pace, thresholds and headline fallback.

**Acceptance Scenarios**:

1. **Given** an answer whose `limits` holds an unscoped entry with group `five_hour` (or `session`), **When** the dropdown opens, **Then** a "5-hour" row is shown before the "7-day" row, with pace and the `↗` / `↑` markers as the 5-hour window had before this spec.
2. **Given** an answer whose `limits` holds an unscoped entry with an unknown group `daily` (kind `daily_all`), **When** the dropdown opens, **Then** a row named "daily" is shown after the known plan windows and before the model limits, with its percent, bar and reset text, and without a pace line or pace markers.
3. **Given** that unknown-group window, **When** its percent crosses a threshold, **Then** a threshold notification is sent naming the window "daily".
4. **Given** that unknown-group window was chosen as the headline, **When** the bar is drawn, **Then** the entry shows the tag "daily" before the value, without pace markers.
5. **Given** a window that was shown, **When** a later successful answer no longer contains it, **Then** its row disappears, a headline choice of it falls back to the default window (stored choice kept), and its threshold state is dropped without a notification.

---

### User Story 3 - Existing settings keep working (Priority: P2)

A user had chosen the 5-hour window as the headline under spec 027. After the update, AgentTacho starts without a configuration error, the bar shows the 7-day value without a tag, and the stored choice is kept, so the bar would follow a 5-hour window again if Anthropic brings it back. A user who chose the Fable limit (`model:Fable`) keeps that choice.

**Why this priority**: An update must not break a working configuration or lose saved values.

**Independent Test**: Load a configuration with `headlineWindow: "fiveHour"`, one with `"sevenDay"`, one with `"model:Fable"`, and a last-good store written by the previous version; check the resolved headline, the shown windows and that nothing is reported as invalid.

**Acceptance Scenarios**:

1. **Given** a configuration with `headlineWindow: "fiveHour"` and an answer without a 5-hour window, **When** the bar is drawn, **Then** it shows the default window without a tag, the ● sits on the default row, and the configuration value is not changed.
2. **Given** that configuration, **When** a later answer contains a window of a 5-hour group, **Then** the bar follows it again with the tag "5h", without any action by the user.
3. **Given** a configuration with `headlineWindow: "sevenDay"`, **When** the bar is drawn, **Then** it shows the 7-day window as the default, as today.
4. **Given** a last-good store written by the previous version (fixed 5-hour and 7-day fields plus model limits), **When** AgentTacho starts offline, **Then** the saved values are shown as the window list, marked stale as today (spec 010), and a saved 5-hour value with a reset time in the past is shown as 0% without a reset time (spec 010 FR-016) until the next successful answer replaces the list.

---

### User Story 4 - Older answer shape (Priority: P3)

If the endpoint answers without a `limits` array, or with an empty one, AgentTacho reads the top-level `five_hour` and `seven_day` objects as before, so an account whose answer still uses the old shape keeps working.

**Why this priority**: A fallback for an older or partial answer; today's answers all carry `limits`.

**Independent Test**: Unit tests with an answer that has `five_hour` and `seven_day` objects but no `limits`, and one with `limits: []`.

**Acceptance Scenarios**:

1. **Given** an answer without `limits` and with `five_hour` and `seven_day` objects, **When** it is parsed, **Then** the window list holds a 5-hour and a 7-day window with the reported percent and reset times.
2. **Given** an answer with a non-empty `limits` array and a non-null `five_hour` object, **When** it is parsed, **Then** the window list comes from `limits` alone.

---

### Edge Cases

- `limits` holds only model-scoped entries and no unscoped entry: the top-level `seven_day` (and `five_hour`) objects supply the plan windows; model limits come from `limits`.
- An entry without `percent`, with an unreadable `resets_at`, or with an unknown shape is skipped, as model-limit entries are skipped today; a skipped entry never drops the other entries or the answer.
- An entry whose `resets_at` is null: the row reads "not started" as the 7-day window does today (spec 025 FR-008), the window has no pace and gets no threshold check until a reset time arrives. This now also applies to model limits, which were skipped before.
- Two unscoped entries with the same group (for example two `weekly` kinds): both are shown; the one with the identity `sevenDay` (FR-004: `weekly_all`, or else the first in response order) is named "7-day", the other is named from its kind by FR-005.
- An entry scoped to a surface and not to a model (`scope.surface`, not seen yet): it is not shown, and its kind is listed in the diagnostic log line (FR-012).
- An unknown group name with underscores or in upper case (`Rolling_Day`): the display name is lowercased with spaces ("rolling day").
- Two limits for the same model (for example a weekly and a daily Fable entry): the weekly one keeps `model:Fable` and the name "Fable"; the other gets `model:Fable:<kind>` and the name "Fable daily" (FR-004).
- A model limit and a plan window with the same display name: the model limit keeps its model name; identities differ (FR-004), so the headline choice stays unambiguous.
- The endpoint answers with no window at all (empty `limits`, null top-level fields): the section shows no window rows and the state line "No limits reported", the bar shows "--", and the stored headline choice is kept.
- A failed fetch: last-good values are shown, stale, as today (spec 010); the window list is the saved one, not an empty one.
- Two Claude accounts with different window lists (one plan still has a short window, the other not): each section shows its own rows.
- The window whose `is_active` is true, and the `severity` field: neither changes rows, levels or headline in this spec (FR-013).

## Requirements *(mandatory)*

### Functional Requirements

**Reading the windows**

- **FR-001**: A Claude subscription's windows MUST be read as a list from the usage endpoint's `limits` array: every entry with a percent, a readable (or null) reset time and a kind or a group becomes a window; an entry with neither kind nor group is skipped. An entry scoped to a model becomes a model limit, with its `weekly_scoped_shares` allowance as today (spec 025 FR-001); an entry without a scope becomes a plan window; an entry scoped only to a surface is not shown.
- **FR-002**: When the answer has no `limits` array or no readable unscoped entry in it (FR-001), the plan windows MUST come from the top-level `five_hour` and `seven_day` objects (each only when not null), as a 5-hour and a 7-day window with the kinds `five_hour` and `seven_day`. When `limits` has at least one unscoped entry, the top-level objects MUST be ignored. Model limits always come from `limits`. The top-level objects MUST be decoded leniently: when `limits` supplies the plan windows, an unreadable top-level object is ignored; when the fallback is used, an unreadable object is skipped like a bad `limits` entry and never drops the other window or the answer.
- **FR-003**: A plan window's group MUST map to its length and display name: `weekly` to 7 days, named "7-day"; `five_hour`, `session` and `5h` to 5 hours, named "5-hour". The top-level fallback windows have the groups `five_hour` and `weekly`. Any other group is an unknown group: the window has no length.
- **FR-004**: Each window MUST have an identity that stays the same across refreshes and is what the configuration and the threshold state store: `fiveHour` for the first plan window of a 5-hour group; `sevenDay` for the unscoped `weekly_all` entry when present, otherwise the first plan window of the `weekly` group; `model:<model name>` for a model limit (as today, spec 027 FR-006, matched exactly); and `limit:<kind>` for every other plan window, `<kind>` being the entry's `kind` as reported (its group when it has no kind). When one model has several limits, the first in the `weekly` group (otherwise the first in response order) has `model:<model name>`, and each further one has `model:<model name>:<kind>` and is named "<model name> " followed by its group lowercased with underscores as spaces, or by its kind the same way when its group is `weekly` or missing. These values keep the configuration written by spec 027 valid.
- **FR-005**: A plan window of an unknown group MUST be named from its group (its kind when the group is missing), lowercased, with underscores replaced by spaces. A plan window of a known group that does not have that group's identity (`fiveHour` or `sevenDay`, FR-004) MUST be named from its kind the same way. When two windows would get the same identity, only the first in response order MUST be shown; the other is skipped and listed in the FR-012 log line.

**Showing the windows**

- **FR-006**: The Claude section MUST show one row per window in this order: plan windows of known groups from shortest to longest (equal lengths in response order), then plan windows of unknown groups in response order, then model limits in response order (spec 025 FR-001). A window that the latest values do not contain MUST NOT get a row; in particular the "5-hour" row MUST NOT be shown when no 5-hour window is reported. Each row keeps today's layout, percent, bar, reset text, note, tooltips, click and marker (spec 025, spec 027).
- **FR-007**: Pace (spec 011) and burn rate markers (spec 017) MUST apply to every window with a length, as they apply to the 5-hour and 7-day windows and model limits today; a window without a length MUST show no pace line, no pace note and no `↗` / `↑` marker. A model limit's length MUST come from its group like a plan window's (FR-003), so a weekly model limit keeps its weekly pace as today.
- **FR-008**: Threshold notifications MUST be checked for every plan window separately, named by the window's display name ("7-day", "5-hour", "daily"); model limits keep getting no threshold notifications, as today. Threshold state for a window that a successful answer no longer contains MUST be dropped without a notification; when the window returns, it starts with a new baseline (spec 015 FR-001).

**Headline**

- **FR-009**: The default headline window MUST be the `sevenDay` window when present, otherwise the longest plan window with a length (the first in FR-006 order among equal lengths), otherwise the first plan window in FR-006 order; with no plan window there is no headline and the bar shows "--" as today. This replaces the fixed 7-day default of spec 027 FR-005 for Claude.
- **FR-010**: A chosen headline MUST apply only when the latest values contain a window with that identity; otherwise the default window is the headline, the ● sits on the default row, and the stored choice MUST NOT change (spec 027 FR-006, now for every Claude window, including the 5-hour window). This replaces spec 027 US3 scenario 4 ("5h --" for a missing 5-hour window).
- **FR-011**: The menu bar tag of a non-default headline MUST be "5h" for the `fiveHour` window, "7d" for the `sevenDay` window, and for any other window its display name cut like a model name (first 7 characters plus "…" when longer than 8, spec 027 FR-008). A Claude entry MUST use the at-or-above-100% style when the headline window or the default window is at or above 100% (spec 027 FR-007). With a tag, the entry's accessibility text MUST name the window as "<display name> window" for a plan window and "<model name> weekly limit" (as today) or "<display name> limit" for a further model limit.

**Diagnostics, compatibility and wording**

- **FR-012**: The first successful Claude fetch after launch, and every later successful fetch whose set of windows (kind, group, scope) differs from the previous one for that account, MUST write one diagnostic log line listing the windows read, as kind, group and scope per window (scope written as `model:<display name>`, `surface` or `none`), without percents, reset times or account details other than the configured account id, and MUST say whether the top-level fallback (FR-002) was used, for example `[subscription] <account id>: windows weekly_all/weekly/none, weekly_scoped/weekly/model:Fable (limits)`. The existing "ok(5h ..., 7d ...)" summary line MUST list the shown windows by display name instead of the fixed pair, for example `ok(7-day 11%, Fable 15%)`.
- **FR-013**: The entries' `severity` and `is_active` fields MUST be read leniently and MUST NOT change rows, levels, notifications or the headline in this spec.
- **FR-014**: The last-good store MUST save the window list and MUST read a file written by the previous version (fixed `fiveHour` and `sevenDay` fields plus model limits) as the equivalent list, without reporting a problem. It MUST also keep writing the legacy `fiveHour`, `sevenDay` and `modelLimits` fields for the windows with those identities and the model limits, so the previous version still reads its saved values after a downgrade; the file keeps `"version": 1` and the window list is an added key.
- **FR-015**: A stored `headlineWindow` value of the previous version (`fiveHour`, `sevenDay`, `model:<name>`) MUST load unchanged and keep meaning the same window (FR-004). `limit:<kind>` and `model:<name>:<kind>` values are valid Claude choices.
- **FR-016**: User-facing wording MUST stop naming specific Claude windows where it describes the plan in general: the Settings threshold help text ("the 5-hour or the 7-day limit"), the Settings plan description, `docs/usage.md`, `docs/accounts-and-budgets.md`, `docs/configuration.md` (the identities of FR-004) and the README's feature list and dropdown image alt text. The README's "Security and privacy" section MUST stay true; the request and the data read do not change.

**Unchanged behavior**

- **FR-017**: Codex plan windows, their names, thresholds, pace and headline (spec 007, spec 027) MUST stay as they are. Budgets, member shares, token counting and the free-reset tickets (spec 033) MUST stay as they are; budget windows aligned to the Claude weekly reset follow the window with the identity `sevenDay`, and without one behave as today without a 7-day window.

**Core logic and tests**

- **FR-018**: Parsing (FR-001 to FR-005), ordering (FR-006), pace eligibility (FR-007), threshold keys (FR-008), burn rate observation keys (by window identity, FR-004), headline resolution and tags (FR-009 to FR-011), the log line (FR-012) and the last-good and configuration compatibility (FR-014, FR-015) MUST be decided by tested UsageCore logic; the SwiftUI layer only renders the list (constitution II).

**Specs, demo and screenshots**

- **FR-019**: Earlier specs MUST be amended where they describe the fixed 5-hour and 7-day pair: spec 001 FR-005, spec 025's dropdown contract (FR-001 row list), spec 027 FR-005, FR-006, FR-008 and US3 scenario 4, spec 010's `contracts/last-good-file.md` (the saved window list; kind and group strings from the answer are allowed in the file), spec 027's `contracts/config-file.md` (the new `headlineWindow` values) and spec 027's `contracts/bar-and-dropdown.md` (the `✳ 5h --` row that FR-010 replaces).
- **FR-020**: The demo scenarios MUST describe Claude windows as a list, so a scenario can hold any set of plan windows and model limits. The `default` scenario's Claude accounts MUST have no 5-hour window; the Claude Max account's chosen headline MUST move to its model limit, so the dropdown still shows a non-default ● and the bar a tag. The demo coverage test MUST check that a Claude account without a 5-hour window shows no 5-hour row, and its existing checks (all three levels, both markers, the pace states, the 7-day attention row, the bar tag) MUST keep passing; values MAY be tuned for that.
- **FR-021**: The shots that show a Claude section or the Claude bar entry MUST be recaptured from the demo build, and the website copy that names the 5-hour window for Claude MUST be updated, in a site pull request linked from the app pull request (constitution V, AGENTS.md steps 4 to 7).

### Key Entities

- **Claude window**: one limit of a Claude subscription: kind, group, optional length, display name, identity, percent, reset time, and for a model limit its model name and weekly allowance.
- **Window identity**: the stable name of a Claude window stored in the configuration (headline choice) and in the threshold state: `fiveHour`, `sevenDay`, `model:<name>`, `model:<name>:<kind>` or `limit:<kind>`.
- **Group mapping**: the table of known groups with their length and display name (FR-003).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With today's endpoint answer, the Claude section shows no row that reads "unavailable" while the fetch succeeds.
- **SC-002**: A new or returning Claude window kind appears in the dropdown, in threshold notifications and as a headline choice without a new AgentTacho release (shown by unit tests with an unknown group).
- **SC-003**: Every configuration and last-good file written by the previous version loads without a reported problem, and the bar shows the same value it showed before the update whenever the chosen window still exists.
- **SC-004**: Codex sections, budgets and token counts are unchanged (all existing tests pass).
- **SC-005**: The diagnostic log shows, after one successful fetch, which window kinds Anthropic reported, so the next change to the answer can be diagnosed from the log alone.

## Assumptions

- The `limits` array is the endpoint's current, general description of a plan's limits; the top-level fields are a legacy view of the same data. The shape was observed on 2026-11-02 with one read-only request.
- A returning short window will use a group named `five_hour`, `session` or `5h`; any other name still works as an unknown group, only without pace until the mapping is extended.
- Unknown groups get no pace, because pace needs the window length and the answer does not carry it.
- Model limits stay without threshold notifications, as today; adding them is a separate decision.
- The window names "7-day" and "5-hour" stay as they are; aligning Claude's "7-day" with Codex's "weekly" is out of scope.
- After a downgrade, a stored `limit:<kind>` or `model:<name>:<kind>` choice is ignored and dropped by the previous version; this is accepted.
- No new Settings control is added: the headline is still chosen by clicking a row (spec 027).
- Out of scope: Codex changes, one shared window model for Claude and Codex, the per-surface `seven_day_breakdown`, `spend`, `extra_usage`, the dollar fields of `seven_day`, and the codenamed top-level keys.
