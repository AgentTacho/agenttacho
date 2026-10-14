# Feature Specification: Codex Plan Limits

**Feature Branch**: `007-codex-plan-limits`

**Created**: 2026-10-14

**Status**: Draft

**Input**: User description: "Codex plan limits (multi-harness part B). Source brainstorm: brainstorm/06-codex-plan-limits.md. Builds on specs/006-multi-harness-usage."

## Context

Spec 006 (part A) added a Codex subscription account for Codex sessions that run on a ChatGPT plan login. It shows the tokens used through the plan, but no percent, no reset times, no thresholds and no bar entry (spec 006 FR-017). Claude subscription accounts have all of these (spec 001 FR-002 to FR-005, FR-027 to FR-029).

A ChatGPT plan limits Codex usage per time window. The limits are known in two places:

- **Codex session logs.** Every Codex turn records a snapshot of the plan's limits: for each window, the used percent, the window length and the reset time, plus the plan type and whether a limit was reached. A snapshot describes the state after that machine's last turn.
- **The plan's usage service.** Codex itself asks this service for the current limits, signed in with the credentials Codex stores in its home. The answer covers usage from every device and surface, not only this machine.

The developer spends the plan's Codex quota in several places (other machines, cloud tasks, editor extensions). Local snapshots alone therefore lag behind the real utilization. This feature reads the live limits from the usage service and falls back to the newest local snapshot when the service cannot be reached.

It replaces the "no percent, no bar entry, no thresholds, no shown-in-bar setting" part of spec 006 FR-017 and spec 006 User Story 3 scenario 2. Spec 001 FR-002 (bar entries in configuration order with their label) now covers Codex subscription accounts too.

The windows differ per plan. Observed on the developer's machine in October 2026:

| Plan | Windows |
|------|---------|
| Free | one 30-day window |
| Plus | a 5-hour window and a weekly window |

Window lengths therefore come from the data, not from fixed assumptions.

## Clarifications

### Session 2026-10-14

- Q: Should Codex subscription accounts that already exist from spec 006 appear in the bar after the update? → A: Yes. They get the new defaults (shown in bar, live limits on, no thresholds), because the account was created to watch the plan.
- Q: How is a window named in the dropdown and in notifications when its length is not a familiar one? → A: By its length: under one day as "N-hour", exactly 7 days as "weekly", otherwise "N-day" (for example "5-hour", "weekly", "30-day").
- Q: What does the account show when the usage service answers successfully but reports no windows for the main Codex bucket? → A: Treat it like a failed fetch: keep the newest observation that has windows, marked stale with the reason "usage service reported no limits".
- Q: Do threshold notifications also fire for values that come from a snapshot or an older live result? → A: Yes. Thresholds are evaluated on the values shown, whatever their source. Since only newer observations replace older ones, a value never jumps back and fires twice. Changing the live-limits setting starts a new baseline, as after launch.
- Q: (spec review) How old may a fallback snapshot be? → A: Any age; windows whose reset has passed show 0%.
- Q: (spec review) How does the bar look when a window it does not show has reached its limit? → A: It uses the at-or-above-100% style whenever any window reports its limit as reached.
- Q: (spec review) Are snapshot values styled as stale when live limits are off? → A: No, normal styling; the observation time is in the dropdown.
- Q: (code review) No request was due and the last live attempt did not fail, but a local snapshot is newer than the kept live result: which observation is shown? → A: The newest one (the snapshot), without stale marking, since it is fresher and nothing failed; the dropdown shows its observation time. A kept live result that is newer stays live. After a failure, the newest of the last live result and the snapshot stays stale.
- Q: (code review) Is a token the usage service rejected sent again on scheduled refreshes? → A: Not after an HTTP 401: it is sent again only once Codex replaces it, after a manual refresh, after live limits are turned off and on, after a later successful fetch, or after a restart. A 403 is retried on the normal schedule.
- Q: (code review) How long a Retry-After wait is honoured? → A: Up to one hour (3600 s); a longer stated wait counts as one hour.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See live Codex plan utilization (Priority: P1)

The developer has a Codex subscription account. The menu bar shows its utilization next to the Claude entries. The dropdown lists every window of the plan with its percent and reset time. Usage spent on another machine shows up at the next refresh.

**Why this priority**: This is the reason for the feature. Without it, the developer runs into the plan limit without warning.

**Independent Test**: With a valid Codex sign-in in the account's Codex home, refresh and compare the account's windows with what Codex itself reports for the plan at the same time.

**Acceptance Scenarios**:

1. **Given** a Codex subscription account on a Plus plan and a reachable usage service, **When** the refresh runs, **Then** the dropdown shows the 5-hour and the weekly window, each with its percent and its reset time in local time, and the bar shows the weekly percent.
2. **Given** a Codex subscription account on a Free plan, **When** the refresh runs, **Then** the dropdown shows the one 30-day window and the bar shows its percent.
3. **Given** usage was spent on another machine since the last refresh, **When** the next refresh runs, **Then** the shown percent includes that usage.
4. **Given** the account's shown-in-bar setting is off, **When** the bar is drawn, **Then** the account is not in the bar, but the dropdown still shows its windows.
5. **Given** the account, **When** the user opens its breakdown, **Then** the token breakdown from spec 006 is unchanged.

---

### User Story 2 - Keep a plausible value when the service is unavailable (Priority: P1)

The developer is offline, or Codex has not run for a while and its stored sign-in has expired. The account keeps showing the limits from the newest local snapshot. The dropdown says how old the values are and why the live values are missing.

**Why this priority**: The service is not always reachable, and its sign-in is only renewed while Codex runs. Without a fallback, the account would show nothing exactly when Codex has been idle.

**Independent Test**: With local Codex sessions that carry plan limits, make the usage service unreachable and refresh. The account shows the snapshot's windows, marked stale with their observation time.

**Acceptance Scenarios**:

1. **Given** the usage service is unreachable and a local snapshot exists, **When** the refresh runs, **Then** the account shows the snapshot's windows, marked stale, with the time the snapshot was taken and the reason the service was not used.
2. **Given** the stored Codex sign-in has expired, **When** the refresh runs, **Then** the app does not contact the usage service, shows the newest snapshot marked stale, and tells the user to run Codex to renew the sign-in.
3. **Given** a window's reset time has passed since the shown observation, **When** the refresh runs, **Then** that window shows 0% and no reset time until a newer observation arrives.
4. **Given** neither the service nor any snapshot is available, **When** the refresh runs, **Then** the account shows its windows as unavailable, and the bar shows it as unavailable.
5. **Given** an earlier live result and a newer local snapshot (Codex ran on this machine after the service failed), **When** the refresh runs, **Then** the account shows the newer of the two.

---

### User Story 3 - Threshold notifications for Codex windows (Priority: P2)

The developer sets thresholds (for example 80 and 95) on the Codex subscription account. When a window crosses a threshold, a macOS notification names the account, the window and the threshold. The bar entry turns to the warning style at the lowest threshold.

**Why this priority**: Notifications turn the visible percent into a warning that reaches the developer while they work. It depends on User Story 1 or 2 providing values.

**Independent Test**: Configure a threshold below the current weekly percent of a test account, starting from a value below it, and confirm one notification after the refresh that observes the crossing.

**Acceptance Scenarios**:

1. **Given** thresholds 80 and 95 and a weekly window at 70%, **When** a refresh observes 85%, **Then** one notification for 80% is sent for the weekly window.
2. **Given** a 5-hour and a weekly window, **When** both cross 80% in the same refresh, **Then** one notification is sent per window.
3. **Given** a window that reset, **When** it later crosses a threshold again, **Then** a new notification is sent.
4. **Given** the app has just started and the first observed value is already above a threshold, **When** the first refresh runs, **Then** no notification is sent for that threshold (spec 001 FR-028 baseline).

---

### User Story 4 - Use local snapshots only (Priority: P3)

The developer does not want AgentMeter to use their Codex sign-in or contact the usage service. In settings they turn off live limits for the account. From then on the account shows only the newest local snapshot.

**Why this priority**: The default covers most needs. This gives control over credential use and network calls.

**Independent Test**: Turn off live limits for the account, refresh, and confirm that no request reaches the usage service while the account shows the snapshot's windows.

**Acceptance Scenarios**:

1. **Given** live limits are off for the account, **When** the refresh runs, **Then** the app neither reads the Codex sign-in nor contacts the usage service, and shows the newest snapshot with its observation time.
2. **Given** live limits are off, **When** the dropdown is opened, **Then** the values are labelled as local data with their observation time, not as a refresh failure.

---

### Edge Cases

- **Several Codex subscription accounts:** each uses the sign-in and the session logs of its own Codex home (spec 006 FR-015). One account's data never shows on another.
- **Codex signed in with an API key:** the Codex home holds no plan sign-in. The usage service is not used, and only snapshots apply. API-key sessions carry no plan limits, so typically the account shows unavailable.
- **Usage service rate-limits the app:** the app waits as long as the service asks before the next attempt and uses the fallback meanwhile.
- **Usage service answer changed or unreadable:** the answer cannot be understood. The app falls back to snapshots and reports the problem as a source error. Nothing else fails.
- **Limit buckets other than the main Codex bucket:** some snapshots describe a separate bucket (observed as "premium") with no windows. Only the main Codex bucket counts. Other buckets are ignored.
- **Empty snapshots:** a snapshot with no windows, or a turn without a snapshot, never replaces an observation that has windows.
- **Plan change:** the developer upgrades from Free to Plus. The windows follow the newest observation, so the 30-day window disappears and the 5-hour and weekly windows appear. Threshold state for the old window is dropped.
- **Limit reached:** the source reports that a limit was reached. The dropdown says so for the affected window, and the entry uses the at-or-above-100% style.
- **Session file mid-write:** a partially written last line is ignored, as in spec 006.
- **Clock skew:** a snapshot timestamp lies in the future. It still counts as the newest observation, and reset handling uses the reset time from the data.

## Requirements *(mandatory)*

### Functional Requirements

Sources and fallback:

- **FR-001**: For every Codex subscription account, the app MUST determine the plan's limit windows on each refresh. For each window it MUST know the used percent, the window length, the reset time, and whether the limit was reached, together with the plan type and the time of the observation.
- **FR-002**: When live limits are on (the default), the app MUST fetch the limits from the plan's usage service, signed in with the credentials stored in the account's Codex home. It MUST read those credentials only at refresh time.
- **FR-003**: The app MUST NOT renew, refresh, or write the stored Codex credentials, and MUST NOT write anything to the Codex home. When the stored sign-in has expired or is missing, the app MUST NOT contact the usage service and MUST use the fallback (FR-005). After the usage service rejects a sign-in with HTTP 401, the app MUST NOT send the same token again until Codex replaces it, the user refreshes manually, live limits are turned off and on again, a later fetch for that Codex home succeeds, or the app restarts (the rejection is kept in memory only); until then the account shows the fallback with the rejected sign-in as reason and source error (FR-006). A rejection with HTTP 403 is not remembered: the token is sent again on the normal schedule.
- **FR-004**: The app MUST read limit snapshots from the session logs of the account's Codex home, as part of the reading spec 006 already does. Snapshots without a plan type (API-key sessions) and snapshots without any window MUST be ignored. The newest plan snapshot in the account's Codex home MUST count regardless of its age or of the token window; FR-010 handles windows that have reset since.
- **FR-005**: When the usage service is not used (live limits off, or no request due in this refresh) or fails (unreachable, rejected sign-in, rate limit, unreadable answer, or an answer without windows for the main Codex bucket), the account MUST show the newest available observation: the last successful live result or the newest snapshot, whichever was observed later. When the usage service succeeds, its result MUST be shown. When live limits are off, only snapshots are considered, and live results kept from earlier refreshes are discarded. For this comparison, a snapshot time in the future counts as the current time. The last live result is kept in memory only, so after launch only snapshots apply until the first successful fetch.
- **FR-006**: Values that do not come from a successful live fetch in the current refresh MUST be marked stale when live limits are on, except when the refresh only skipped the request because none was due (a cost recompute after a price change, or a manual refresh within the spacing of spec 001) and the last live attempt did not fail; then the newest of the last live result and the newest snapshot is shown without stale marking, a snapshot with its observation time. Stale values MUST carry the observation time and the reason (for example "offline", "Codex sign-in expired, run Codex to renew it", "no Codex plan sign-in found in this Codex home", "usage service changed"). When live limits are off, snapshot values MUST be shown with their observation time and MUST NOT be marked as a failure. An unreadable or changed answer and a rejected sign-in MUST also be reported as source errors (spec 006 FR-006); being offline, an expired or missing sign-in, and rate limiting only produce the stale reason.
- **FR-007**: When the usage service asks the app to wait (rate limit), the app MUST NOT contact it again before that time has passed, honouring a stated wait of up to one hour; a longer stated wait counts as one hour. Without a stated wait, the app MUST skip the service for one refresh interval from the rate-limit response. Manual refreshes (spec 001 FR-025) respect the wait too. The wait applies per Codex sign-in.
- **FR-008**: Limit buckets other than the main Codex bucket MUST be ignored.

Windows and display:

- **FR-009**: The windows shown MUST be those of the newest observation, named by their length: under one day as "N-hour", exactly 7 days as "weekly", otherwise "N-day" (for example "5-hour", "weekly", "30-day"), with N rounded to the nearest whole unit; any length that rounds to 7 days is named "weekly". Windows are matched on this rounded name. Plans with one window and plans with two windows MUST both work. A window is identified by its length (its rounded name), not by its position in the source data.
- **FR-010**: When a window's reset time has passed since its observation, the window MUST show 0%, no reset time, and no limit-reached note until a newer observation arrives.
- **FR-011**: The dropdown MUST show, for a Codex subscription account, every window with its percent (rounded as in spec 001 FR-009a) and its reset time in local time, the plan type as a capitalized name (for example "Plus"), the observation time when the values are not live, and a "limit reached" note for a window whose limit the source reports as reached.
- **FR-012**: A Codex subscription account MUST appear in the bar when its shown-in-bar setting is on. The bar MUST show the percent of the longest window. When no window is available, the bar MUST show the account as unavailable. Bar styling MUST follow spec 001 FR-003 (warning threshold, at or above 100%) and stale styling as for Claude subscription accounts. When any shown window carries the limit-reached note (FR-011, after FR-010 is applied), the bar entry MUST use the at-or-above-100% style, whatever percent it shows. With live limits off, snapshot values MUST use normal (not stale) styling; their observation time appears only in the dropdown.
- **FR-013**: The account's token breakdown (per model, per day, per project, per harness) MUST stay as in spec 006.

Thresholds and notifications:

- **FR-014**: The user MUST be able to configure whole-number percent thresholds greater than 0 for a Codex subscription account. They MUST apply to every window of the plan independently.
- **FR-015**: Notifications MUST follow spec 001 FR-028 and FR-029: one notification per threshold per window when a refresh observes a crossing, naming the account, the window by its length, and the threshold; a baseline instead of a notification on the first observation after launch; state reset when the window resets. When a window disappears (plan change), its threshold state MUST be dropped. The first observation of a window that newly appears during a run establishes its baseline, as after launch. Thresholds MUST be evaluated on the values shown (FR-005), whether they come from a live result or a snapshot. Changing the live-limits setting MUST start a new baseline for the account, as after launch.

Settings and configuration:

- **FR-016**: Settings MUST offer, for a Codex subscription account, a shown-in-bar setting (default on), thresholds (default none), and a live-limits setting (default on). The Codex home setting from spec 006 stays, and two Codex subscription accounts MUST NOT reference the same Codex home. Neither the default nor a configured designated subscription for budget group window alignment may be a Codex subscription account; the default is the first Claude subscription account, and settings MUST NOT offer a Codex account for it. (Spec 006 configuration validation already rejects two Codex subscription accounts with the same Codex home, so no such file exists to migrate.)
- **FR-017**: Configuration files from the previous version MUST load unchanged. A Codex subscription account without the new settings MUST get the defaults from FR-016, so an existing account appears in the bar after the update.

Privacy and diagnostics:

- **FR-018**: The Codex credentials MUST NOT appear in the configuration file, the diagnostic log, error messages, notifications, or any file the app writes (as spec 001 FR-011a for Claude credentials).
- **FR-019**: The app MUST contact no service other than the plan's usage service for this feature, and MUST NOT contact it or read the Codex credentials for an account with live limits off.
- **FR-020**: The diagnostic log MUST record, per refresh and account, which source supplied the shown values (live or snapshot), the observation time, and the reason a live fetch was skipped or failed.
- **FR-021**: A failure in the Codex limits of one account MUST NOT prevent any other source or account from refreshing (spec 001 FR-026).

### Key Entities

- **Codex subscription account**: A ChatGPT-plan billing source tied to one Codex home. It now has plan limits, a shown-in-bar setting, thresholds, and a live-limits setting, in addition to the token breakdown from spec 006.
- **Limit observation**: The plan's limits at one moment: plan type, observation time, source (live or snapshot), and one or more windows. The observation time is the fetch time for a live result and the event timestamp for a snapshot.
- **Limit window**: One limit of the plan: length, used percent, reset time, and whether the limit was reached.
- **Codex sign-in**: The credentials Codex stores as a file in its home. The app reads them, never changes them, and never stores them elsewhere. A sign-in that Codex keeps only in the macOS keychain counts as missing, so snapshots apply.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With the usage service reachable, every window's percent shown after a refresh is within 1 percentage point of what Codex itself reports for the plan at the same time.
- **SC-002**: While the usage service is reachable and not rate-limiting the app, usage spent on another device appears in the account's percent within one refresh interval.
- **SC-003**: With the usage service unreachable or the sign-in expired, 100% of refreshes still show the newest available observation (or "unavailable" when none exists), and no refresh fails.
- **SC-004**: Over a week of refreshes with live limits on, no file in the Codex home is created, changed, or deleted by the app (contents and modification times unchanged by it), and Codex remains signed in.
- **SC-005**: A search of every file the app writes (configuration, diagnostic log) and of all notifications finds no part of the Codex credentials.
- **SC-006**: A threshold crossing produces exactly one notification per threshold per window, at the first refresh that observes it.
- **SC-007**: 100% of configuration files from the previous version load unchanged, and the Codex token breakdown shows the same totals as before.

## Assumptions

- The plan's usage service is the one Codex itself uses to show plan limits. It is not publicly documented and may change. The fallback (FR-005) and the error reporting (FR-006, FR-020) limit the damage when it does.
- The live result and the snapshots describe the same limits in the same units (used percent per window, reset time).
- The usage service is asked at most once per refresh per account, on the existing refresh interval (spec 001 FR-024). Recomputing costs after a price change does not trigger a new request.
- Credits, credit balance and spend controls reported by the source are out of scope.
- OpenAI API-key (token-based) accounts have no plan limits and are unchanged.
- The token breakdown keeps the weekly window from spec 006, independent of the plan's windows.
- The plan settles the naming of the per-account plan data in the snapshot (part A review finding M-11), since it now carries limits as well as tokens.
