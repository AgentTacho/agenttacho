# Feature Specification: AgentMeter

**Feature Branch**: `001-agentmeter`

**Created**: 2026-10-13

**Status**: Draft

**Input**: User description: "Build the feature described in brainstorm/01-agentmeter.md: a macOS menu bar app showing LLM harness usage across accounts with different pricing models. Single native menu bar app with pluggable usage sources; subscription accounts show Anthropic's real 5-hour and 7-day limits fetched from the Anthropic usage API using locally stored Claude Code OAuth credentials; token-based accounts (Claude Code via Google Vertex) compute USD spend from local session logs with a built-in overridable per-model price table; account attribution auto-detected from session log content; self-set weekly USD budgets belong to budget groups (1..n accounts); week window aligned with the subscription 7-day reset, configurable weekday fallback; menu bar shows short label + percent for user-selected accounts/groups; dropdown shows used vs budget with reset time, per-model breakdown, daily trend; macOS notifications at configurable thresholds; refresh every 5 minutes configurable; config in a local file editable via settings window; version one covers Claude Code only but the model must allow other harnesses; 5 to 10 accounts."

## Clarifications

### Session 2026-10-13

- Q: How does the app handle the harness's locally stored subscription credentials? → A: Read at refresh time only; never copied into the configuration file, the diagnostic log, or notifications.
- Q: Should the app offer to start automatically at login? → A: Yes, as a settings toggle, off by default.
- Q: How does the user diagnose a failed or suspicious refresh? → A: A diagnostic log file records the outcome of every refresh per source; the dropdown offers an "Open log" entry; the log is bounded in size.
- Q: What happens to a budget group when its last account is removed, and must a new token-based account choose a group? → A: Removing the last member deletes the group and its notification state; creating a token-based account requires choosing an existing group or creating a new one with a weekly budget.
- Q: Which window applies to the Unassigned entry and how are percents rounded? → A: Unassigned uses the same weekly window as budget groups and shows tokens only; percents are rounded to the nearest whole number and values above 100% are shown as the actual value.
- Q: How are sessions attributed when content markers cannot distinguish two subscription accounts? → A: Content rules decide first; when a session matches the subscription type and more than one subscription account exists, the harness configuration directory containing the session log (the same directory the account's credentials come from, FR-011) decides.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Glance at subscription limits from the menu bar (Priority: P1)

A developer runs Claude Code on a Claude Max subscription. Anthropic enforces a rolling 5-hour window and a rolling 7-day window. The developer wants to look at the menu bar and immediately know how close they are to either limit, without opening a terminal or running a command. Clicking the menu bar item shows both windows with their utilization and the time at which each resets.

**Why this priority**: This is the single most frequent question the user has during a work day ("can I keep going?"). It needs no configuration beyond having Claude Code logged in, so it delivers value on first launch.

**Independent Test**: Launch the app on a machine where Claude Code is logged in with a subscription. The bar shows a label and a percent for that account within one refresh cycle. Open the dropdown and confirm both windows appear with percent and reset time matching what Claude Code's own usage view reports.

**Acceptance Scenarios**:

1. **Given** Claude Code is logged in with a subscription account, **When** the app starts, **Then** within one refresh interval the bar shows the account's short label and the current utilization percent.
2. **Given** the dropdown is open, **When** the user looks at the subscription account entry, **Then** they see the 5-hour utilization with its reset time and the 7-day utilization with its reset time.
3. **Given** the subscription provider cannot be reached, **When** a refresh runs, **Then** the bar keeps showing the last known values marked as stale, and the dropdown shows when the data was last updated and why the refresh failed.
4. **Given** no subscription credentials are found locally, **When** the app starts, **Then** the subscription account shows a clear "not signed in" state instead of a percent, and the rest of the app keeps working.

---

### User Story 2 - Track token-based spend against a self-set weekly budget (Priority: P2)

The same developer also runs Claude Code through a Google Vertex account that bills per token. There is no provider-imposed limit, so the developer sets their own weekly budget in US dollars. The app reads the local session logs Claude Code writes, recognizes which sessions went through Vertex, prices the tokens with a per-model price table, and shows how much of the weekly budget has been consumed.

**Why this priority**: This is the account with real money at stake and no provider guardrail. It is the second of the two accounts the user runs today.

**Independent Test**: Configure one budget group with a weekly budget and let the app scan a directory containing session logs from a Vertex session. The dropdown shows spend in dollars, the percent of budget used, and the end of the current week. The bar shows the group's label and percent.

**Acceptance Scenarios**:

1. **Given** session logs from Vertex sessions exist and a weekly budget of $60 is configured for the group, **When** a refresh runs, **Then** the dropdown shows the summed cost this week, the budget, the percent used, and the week reset time.
2. **Given** a session log contains a model that is not in the price table, **When** the refresh runs, **Then** that model's tokens are counted but shown as unpriced, the group total is flagged as incomplete, and the model is listed so the user can add a price.
3. **Given** the user edits the price of a model in settings, **When** the next refresh runs, **Then** the recomputed cost reflects the new price for all sessions in the current week.
4. **Given** a session log cannot be attributed to any configured account, **When** the refresh runs, **Then** its usage appears under an "Unassigned" entry in the dropdown rather than being silently dropped.

---

### User Story 3 - Configure accounts, groups, budgets, and display (Priority: P3)

The developer expects to grow from 2 to between 5 and 10 accounts. They open a settings window from the dropdown, add accounts, give each a 1 to 3 character label, assign token-based accounts to budget groups with a weekly budget, choose which accounts or groups appear in the bar, set the refresh interval, and add directories where session logs live.

**Why this priority**: Without configuration the app only works for the default setup. Configuration is what makes it scale to many accounts and to the shared-budget case the user already anticipates.

**Independent Test**: Open settings, add a second token-based account, assign it to the existing group, hide one account from the bar, change the refresh interval to 2 minutes, and save. The bar updates to reflect the selection, and the config file on disk contains the new values.

**Acceptance Scenarios**:

1. **Given** the settings window is open, **When** the user adds an account with a label and a type, **Then** the account appears in the dropdown after save and in the bar if marked as shown.
2. **Given** two token-based accounts are assigned to one budget group, **When** a refresh runs, **Then** the group percent is computed from the combined spend of both accounts against the group's single budget.
3. **Given** the user sets the refresh interval to a value below the allowed minimum, **When** they save, **Then** the settings window rejects the value and explains the minimum.
4. **Given** the config file was edited by hand while the app runs, **When** the next refresh runs, **Then** the app picks up the new configuration or, if the file is invalid, keeps the last valid configuration and shows an error in the dropdown.
5. **Given** the user enters a label longer than 3 characters, **When** they save, **Then** the settings window rejects the label.

---

### User Story 4 - Get notified before hitting a limit (Priority: P4)

The developer is deep in a task and does not look at the bar. When an account or group crosses a configured threshold (for example 80% or 100%), a macOS notification tells them which account crossed which threshold.

**Why this priority**: Useful but secondary. The bar already provides the information; notifications reduce the chance of being surprised.

**Independent Test**: Set a threshold of 50% on a group whose usage is at 45%, then add session logs that push it to 55%. On the next refresh a notification appears naming the group and the threshold. A further refresh at 60% produces no second notification for the same threshold.

**Acceptance Scenarios**:

1. **Given** a threshold of 80% is configured and an account moves from 75% to 82%, **When** the refresh runs, **Then** one notification appears naming the account and the threshold.
2. **Given** the 80% notification was already sent in this window, **When** usage stays above 80% on later refreshes, **Then** no further 80% notification appears until the window resets.
3. **Given** the window resets and usage drops to 10%, **When** usage later crosses 80% again, **Then** a new notification appears.

---

### User Story 5 - Understand where the usage went (Priority: P5)

In the dropdown, the developer expands an account or group to see which models consumed the tokens and cost, and a per-day view of the current week to judge whether they are on pace.

**Why this priority**: Diagnostic detail that helps adjust behavior, but not needed for the core "how much is left" question.

**Independent Test**: With session logs spanning three days and two models, open the dropdown details for the group. Two model rows show tokens and cost; three day entries show the spend per day.

**Acceptance Scenarios**:

1. **Given** sessions used two different models this week, **When** the user opens the details for the group, **Then** each model is listed with its token counts and cost, and the rows sum to the group total.
2. **Given** usage spread over several days, **When** the user views the daily trend, **Then** each day of the current window shows its spend or token count, with days without usage shown as zero.

---

### Edge Cases

- A session log is being written while the app reads it: the partial last record must be ignored without failing the whole file.
- A session started before the week boundary and continued after it: only the records timestamped inside the current window count.
- Several Claude Code configuration directories exist on the machine (default directory plus profile directories): the default directory and every user-configured directory are scanned, and the same session is never counted twice even when a file is reachable through more than one configured path.
- The subscription reset timestamp has never been fetched since launch (first launch, offline since launch, no subscription account configured): budget windows fall back to the configured weekday boundary. When a reset timestamp was fetched earlier in this run and the provider is now unreachable, the last fetched timestamp keeps defining the window.
- Two subscription accounts exist with different reset timestamps: the budget window alignment uses one explicitly chosen subscription account, defaulting to the first configured one.
- A model appears with a provider-specific identifier (for example Vertex-style versioning) that differs from the direct-provider identifier: the price table matches it to the same price entry.
- The machine was asleep past a refresh tick: the next refresh runs immediately on wake.
- The user has more than 10 accounts: the app still works, but the bar text may be truncated by macOS, and the dropdown remains usable.
- The config file is missing on first launch: the app creates a default configuration with a subscription account detected from local credentials, if any.
- Log directories contain thousands of files: a refresh must still finish well within the refresh interval, so only files changed since the last scan are re-read.

## Requirements *(mandatory)*

### Functional Requirements

Display:

- **FR-001**: The app MUST run as a macOS menu bar item without a Dock icon.
- **FR-002**: The menu bar item MUST show, for every subscription account or budget group marked as "shown in bar", its short label followed by its current percent, in the order the entries appear in the configuration. Token-based accounts and the Unassigned entry have no percent and MUST NOT be shown in the bar.
- **FR-003**: The menu bar item MUST visually distinguish entries at or above their warning threshold and entries at or above 100% from those below. The warning threshold of an entry is its lowest configured notification threshold, or 80% when none is configured.
  - *Note*: How levels are shown (color, pill, symbols, or not at all) is defined by spec 012 (colored bar levels).
- **FR-004**: Clicking the menu bar item MUST open a dropdown listing all accounts and groups, each with its usage summary, plus entries for settings, manual refresh, and quit.
- **FR-005**: For a subscription account the dropdown MUST show both the 5-hour and the 7-day utilization as percent, each with its reset time in local time. The percent shown in the bar (and in the dropdown's account header) for a subscription account MUST be the 7-day utilization; when the 7-day window is unavailable, the bar shows the account as unavailable rather than falling back to the 5-hour value.
- **FR-006**: For a budget group the dropdown MUST show spend to date, the weekly budget, the percent used, and the window reset time.
- **FR-007**: The dropdown MUST show when the data was last successfully refreshed and MUST mark values as stale when the last refresh failed.
- **FR-008**: The dropdown MUST offer a per-model breakdown (input, output, cache-write and cache-read tokens, cost) and a per-day trend for the current window for every group and token-based account. For a subscription account the same breakdown and trend MUST be shown from the sessions attributed to it, with token counts only and no cost.
- **FR-009**: Usage from session logs that cannot be attributed to any configured account MUST be shown under an "Unassigned" entry with token counts only, using the same weekly window as budget groups, and MUST NOT count toward any account or group. The Unassigned entry carries no budget, no thresholds, and is never shown in the bar.
- **FR-009a**: All percents MUST be rounded to the nearest whole number. Values above 100% MUST be shown as their actual value (for example 130%), not capped.

Usage sources:

- **FR-010**: The app MUST support two account types in this version: subscription (utilization fetched from the provider) and token-based (usage computed from local session logs).
- **FR-011**: For subscription accounts the app MUST fetch the 5-hour and 7-day utilization and reset times from the provider's usage service using the credentials the Claude Code harness already stores locally. Each subscription account references the harness configuration directory whose stored credentials it uses; the default is the harness's default directory, and two subscription accounts MUST NOT reference the same directory. The app MUST NOT ask the user to enter credentials.
- **FR-011a**: The app MUST read stored credentials only at refresh time and MUST NOT copy them into the configuration file, the diagnostic log, notifications, or any other file.
- **FR-012**: For token-based accounts the app MUST read the Claude Code session logs from the default location and from any additional directories configured by the user.
- **FR-013**: The app MUST attribute each session to an account using markers found in the session's content. Each account type MUST have built-in detection rules, and the user MUST be able to add a custom marker string per account for cases the built-in rules do not cover. When a session's content matches the subscription type and more than one subscription account exists, the harness configuration directory containing the session log (the directory the account's credentials come from, FR-011) decides between them. A session whose content matches the rules of no account, or that still matches more than one account after the directory tie-breaker, MUST be attributed to the Unassigned entry (FR-009).
- **FR-014**: The app MUST compute cost per session from token counts and a price table with per-model entries for input, output, cache-write, and cache-read tokens, in US dollars.
- **FR-015**: The app MUST ship with a built-in price table and MUST allow the user to override any entry and add entries for new models in settings. User entries take precedence over built-in ones.
- **FR-016**: Tokens of a model with no price entry MUST be counted and flagged as unpriced; the containing total MUST be marked incomplete.
- **FR-017**: The account model MUST allow adding further harnesses and source types later without changing the stored configuration format for existing accounts.
- **FR-018**: A refresh MUST re-read only session files that changed since the previous refresh and MUST tolerate a partially written last record.

Budgets and windows:

- **FR-019**: Every token-based account MUST belong to exactly one budget group; a group MUST contain one or more accounts and MUST carry one weekly budget in US dollars. Creating a token-based account MUST require choosing an existing group or creating a new one with a weekly budget. Removing the last member of a group MUST delete the group and its notification state.
- **FR-020**: Subscription accounts MUST NOT carry a self-set budget.
- **FR-021**: The weekly window for budget groups MUST end at the next 7-day reset timestamp reported for the designated subscription account and MUST start 7 days before that timestamp. When the provider reports a new reset timestamp, the window moves accordingly on the same refresh.
- **FR-022**: When no subscription reset timestamp has been fetched since launch, the weekly window MUST start at the most recent occurrence of a configurable weekday and hour in local time (default Monday 00:00) and end 7 days later.
- **FR-023**: Only usage timestamped inside the current window MUST count toward the window's totals.

Refresh:

- **FR-024**: The app MUST refresh all sources on a configurable interval with a default of 5 minutes and a minimum of 1 minute. The first refresh MUST start immediately at launch. If a refresh is still running when the next tick or a manual trigger arrives, the app MUST NOT start a second concurrent refresh.
- **FR-025**: The user MUST be able to trigger a manual refresh from the dropdown.
- **FR-026**: A failure in one source MUST NOT prevent other sources from refreshing.

Notifications:

- **FR-027**: The user MUST be able to configure one or more whole-number percent thresholds greater than 0 per subscription account or budget group. Token-based accounts have no percent of their own and carry no thresholds. For a subscription account the thresholds apply to the 5-hour window and the 7-day window independently.
- **FR-028**: The app MUST send one macOS notification per threshold per window when usage crosses that threshold, naming the account or group, the window, and the threshold. A crossing happens when the previous refresh's value in the same window was below the threshold and the current value is at or above it. When a single refresh crosses several thresholds, one notification per crossed threshold is sent. The first refresh after launch establishes the baseline and MUST NOT send notifications for thresholds already exceeded at that point.
- **FR-029**: Threshold notification state MUST reset when the window resets.

Configuration:

- **FR-030**: All configuration MUST be stored in a single human-readable local file.
- **FR-031**: The app MUST provide a settings window to edit accounts (label, type, detection marker, credential directory for subscription accounts, shown-in-bar and thresholds for subscription accounts), budget groups (members, weekly budget, shown-in-bar, thresholds), price overrides, log directories, refresh interval, the week fallback, and the designated subscription account for window alignment.
- **FR-032**: Account and budget group labels MUST be 1 to 3 characters and unique across all accounts and groups together.
- **FR-033**: When the configuration file is invalid, the app MUST keep the last valid configuration and surface the error in the dropdown.
- **FR-034**: On first launch without a configuration file, the app MUST create a default configuration and, if local subscription credentials are found, a subscription account.
- **FR-035**: The settings window MUST offer a "start at login" toggle, off by default.

Diagnostics:

- **FR-036**: The app MUST write a diagnostic log file recording the outcome of every refresh per source (success, record counts, or the error), bounded to a maximum of 5 MB by rotation or truncation.
- **FR-037**: The dropdown MUST offer an "Open log" entry that opens the diagnostic log.

### Key Entities

- **Account**: One billing identity on one harness. Attributes: label (1 to 3 characters), display name, type (subscription or token-based), harness (Claude Code in this version), detection markers. A subscription account additionally has a credential directory, a shown-in-bar flag, and thresholds. A token-based account belongs to exactly one budget group and has no shown-in-bar flag or thresholds of its own.
- **Budget Group**: A set of one or more token-based accounts sharing one weekly budget in US dollars. Attributes: name, label, budget, shown-in-bar flag, thresholds.
- **Usage Window**: A time range with a start and an end. For subscriptions there are two (5-hour and 7-day) with provider-reported utilization and reset time. For budget groups there is one weekly window derived from the designated subscription reset or the configured weekday fallback.
- **Usage Record**: One priced unit of consumption from a session log: timestamp, account, model, input, output, cache-write and cache-read token counts, computed cost, price status (priced or unpriced).
- **Price Entry**: Per-model prices in US dollars per million tokens for input, output, cache-write and cache-read, with a source (built-in or user override) and the model identifiers it matches.
- **Usage Snapshot**: The result of one refresh: per account and per group, the window totals, per-model breakdown, per-day trend, staleness and error information.
- **Configuration**: Accounts, groups, price overrides, log directories, refresh interval, week fallback, designated alignment account, notification thresholds.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On a machine with a signed-in subscription account, the bar shows a current percent within 60 seconds of first launch with no configuration.
- **SC-002**: The subscription percent shown matches the harness's own usage view within 1 percentage point at the time of refresh.
- **SC-003**: Weekly spend computed for a token-based account matches a manual calculation from the same session logs and price table to within 1 cent.
- **SC-004**: A refresh over 10 configured accounts and 5,000 session log files completes in under 10 seconds on an Apple Silicon Mac, and an incremental refresh with no changed files completes in under 1 second.
- **SC-005**: The user can add an account, assign it to a group, and see it in the bar in under 2 minutes using only the settings window.
- **SC-006**: Threshold notifications fire exactly once per threshold per window in a test that crosses each threshold multiple times.
- **SC-007**: With the provider unreachable for an hour, the app keeps showing last known values marked stale and recovers automatically on the first successful refresh.
- **SC-008**: Between refreshes the app uses less than 1% CPU on average and less than 100 MB of resident memory, measured over one hour with 10 accounts configured.

## Assumptions

- The user already runs Claude Code and it stores subscription credentials and session logs locally. The app reads those but never modifies them.
- Session logs from Vertex sessions carry a recognizable marker (such as the provider-specific model identifier format) that distinguishes them from direct-provider sessions. The planning phase verifies this against real logs; if no reliable marker exists, the detection marker on an account can be a configured string the user supplies.
- The provider's usage service accepts the locally stored credentials and reports both windows with reset times. If a window is not reported, the app shows it as unavailable.
- Prices are per million tokens in US dollars and do not vary by region. Vertex and direct-provider prices for the same model are treated as identical unless the user overrides them.
- The bar shows the 7-day subscription window, the budget that matters over the week; the 5-hour window stays visible in the dropdown. (Earlier versions showed the higher of the two windows.)
- Default log locations are the standard Claude Code directory plus any profile directories the user adds. Discovery of additional profile directories is manual in this version.
- Only the current window is kept; historical weeks are out of scope.
- Harnesses other than Claude Code, per-account sub-budgets within a group, export of usage data, and statusline integration are out of scope for this version.
- The app runs on a current macOS version and does not need to support Intel-only machines or versions older than the previous major release.
- Usage from other harnesses that go through the same Vertex account is counted only once such harnesses are supported as sources.
