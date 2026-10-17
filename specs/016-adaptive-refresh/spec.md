# Feature Specification: Adaptive Refresh

**Feature Branch**: `016-adaptive-refresh`

**Created**: 2026-10-16

**Status**: Draft

**Input**: User description: "Adaptive refresh (from brainstorm/15-adaptive-refresh.md). Approach B, split cadence: an 'Adapt refresh' toggle, on by default; the local scan keeps the configured interval; usage endpoint calls stretch up to 30 minutes while the scans find no new agent records; Low Power Mode, serious or critical thermal pressure and user idle stretch the whole timer up to 30 minutes; opening the dropdown and returning from idle refresh when the values are older than about a minute, within the existing endpoint spacing; retries and backoff unchanged; one dropdown pace line plus log lines; README refresh and security statement updated; the pace logic lives in the tested core."

AgentTacho refreshes on one fixed timer (spec 001 FR-024: default 5 minutes, minimum 1 minute). Every scheduled refresh scans the local agent logs and, for subscription accounts, calls the undocumented and rate-limited usage endpoints of Anthropic and ChatGPT. Opening the dropdown does not refresh, so the numbers a user looks at can be one full interval old, while the endpoints are called every few minutes even when nobody looks, no agent runs and the Mac is saving power. This feature makes the refresh pace follow what is happening: a refresh when the user opens the dropdown, fewer endpoint calls while no agent is working, and a slower timer while the user is away or the Mac is saving power. The configured interval stays the fastest regular pace, and one toggle restores today's fixed behavior.

## Clarifications

### Session 2026-10-16

- Q: When does a local record count as new activity for an endpoint, given that the scan re-reads all records after launch, a price change or a window move? → A: When it comes from a harness that counts for that endpoint and its timestamp is later than the endpoint's last call; re-reading older records is never activity (FR-004).
- Q: Does the refresh on returning from idle call the endpoints even when their activity pace is stretched? → A: Yes, like the wake refresh; only the 60-second spacing and rate-limit blocks hold it back (FR-011).
- Q: Is the dropdown-open check of "at least 60 seconds old" made for each endpoint separately? → A: Yes; the refresh starts when any endpoint's last call is at least 60 seconds old, and only those endpoints are called (FR-012).
- Q: Do endpoint calls outside the schedule (launch, wake, manual, settings, dropdown open, return from idle, retries) change an endpoint's interval? → A: They count as the endpoint's last call and never double its interval; they return it to the base when they saw new activity, so activity is never lost (FR-013, changed in spec review).
- Q: Which reason and which time does the pace line show when several reasons apply or the two endpoints have different next checks? → A: One line; a timer reason (idle, then Low Power Mode, then high temperature) wins over "no agent activity"; the time follows the reason (FR-016).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Current numbers when I look (Priority: P1)

A user works with Claude Code and opens the dropdown four minutes after the last refresh. Today they see four-minute-old percentages and have to press "Refresh now". After this feature, opening the dropdown starts a refresh right away, and the rows update to current values while the dropdown is open.

**Why this priority**: The moment the user looks is the moment freshness matters; it is also what makes slower background refreshes acceptable.

**Independent Test**: With adaptive refresh on, wait more than a minute after a refresh, open the dropdown, and check in the diagnostic log that a refresh started on opening; open it again within a minute and check that no endpoint call was made.

**Acceptance Scenarios**:

1. **Given** the last usage endpoint call was 4 minutes ago, **When** the user opens the dropdown, **Then** a refresh starts at once and calls the usage endpoints.
2. **Given** the last usage endpoint call was 30 seconds ago, **When** the user opens the dropdown, **Then** no endpoint call is made.
3. **Given** a rate-limit block is active until 14:20, **When** the user opens the dropdown at 14:10, **Then** no endpoint call is made and the existing rate-limit display stays.
4. **Given** adaptive refresh is off, **When** the user opens the dropdown, **Then** no refresh starts (today's behavior).

---

### User Story 2 - Fewer endpoint calls while no agent works (Priority: P1)

A user with a Claude Max subscription stops working in the evening but leaves the Mac on. Today AgentTacho keeps calling Anthropic's usage endpoint every 5 minutes all night. After this feature, the local scans keep running every 5 minutes (they need no network), but because they find no new Claude Code records, the time between endpoint calls grows to 10, 20 and then 30 minutes. When the user starts Claude Code again the next morning, the first refresh that finds new records calls the endpoint again and the pace returns to every 5 minutes.

**Why this priority**: Fewer calls to rate-limited, undocumented endpoints is the main protection against being rate limited or blocked, and it saves battery and network.

**Independent Test**: Run with a Claude subscription account and no agent activity for two hours and count the endpoint calls in the diagnostic log; then write a new Claude Code session record and check that the next refresh calls the endpoint.

**Acceptance Scenarios**:

1. **Given** a base interval of 5 minutes and no new Claude Code or OpenCode records since the last Claude endpoint call, **When** the following scheduled refreshes run, **Then** the Claude endpoint is called after 5, then 10, then 20, then every 30 minutes, while the local scan runs every 5 minutes.
2. **Given** the Claude endpoint pace has grown to 30 minutes, **When** a scheduled refresh finds a new Claude Code record and at least the base interval has passed since the last Claude endpoint call, **Then** that refresh calls the Claude endpoint and the pace returns to the base interval.
3. **Given** new Codex records but no new Claude Code or OpenCode records, **When** refreshes run, **Then** the Codex endpoint stays at the base pace and the Claude endpoint pace keeps growing.
4. **Given** a slowed Claude endpoint pace, **When** a new local record is attributed to a token-based account (for example Vertex), **Then** local spend, budgets and threshold notifications for that account update at the base pace as before.

---

### User Story 3 - A slower timer while I am away or saving power (Priority: P2)

A user leaves the desk for lunch, or works on battery with Low Power Mode on. Today AgentTacho refreshes every 5 minutes regardless. After this feature, while the user is idle, or while Low Power Mode is on, or while the Mac is under serious thermal pressure, the whole refresh runs less often. When the user comes back, one refresh runs and the base pace returns.

**Why this priority**: Saves battery and requests in the situations where nobody benefits from frequent refreshes, but matters less than the two P1 stories.

**Independent Test**: Simulate idle, Low Power Mode and a serious thermal state, and check the scheduled refresh times in the diagnostic log; then end the condition and check that a refresh runs and the base pace returns.

**Acceptance Scenarios**:

1. **Given** a base interval of 5 minutes, **When** the user has had no keyboard or mouse input for 10 minutes, or the screen is locked, **Then** the next scheduled refresh runs 30 minutes after the previous one.
2. **Given** the user was idle, **When** they return (input or unlock), **Then** a refresh starts within 60 seconds, subject to the 60-second endpoint spacing, and scheduled refreshes return to the base interval.
3. **Given** a base interval of 5 minutes, **When** Low Power Mode is on or the thermal state is serious or critical, **Then** scheduled refreshes run every 10 minutes (twice the base).
4. **Given** a base interval of 40 minutes, **When** the user is idle or Low Power Mode is on, **Then** scheduled refreshes keep running every 40 minutes (never faster than the base).

---

### User Story 4 - Know what the refresh is doing, and turn it off (Priority: P3)

A user notices that the Claude percentages were last fetched 20 minutes ago and wonders why. The dropdown says that plan limits are checked less often because no agent is running, and when the next check is due. A user who prefers the old fixed timer turns off "Adapt refresh" in the General tab.

**Why this priority**: Transparency and control; the feature works without it, but silent behavior changes erode trust.

**Independent Test**: With a slowed pace, open the dropdown and read the pace line; turn the toggle off and check that refreshes and endpoint calls follow the fixed interval again and the line disappears.

**Acceptance Scenarios**:

1. **Given** the Claude endpoint pace is stretched because no agent is active, **When** the user opens the dropdown, **Then** a line under "Last refreshed" names the reason and the time of the next plan-limit check.
2. **Given** every pace equals the base interval, **When** the user opens the dropdown, **Then** no pace line is shown.
3. **Given** the user turns "Adapt refresh" off, **When** refreshes run, **Then** every scheduled refresh calls the endpoints at the configured interval, as before this feature.
4. **Given** a configuration file without the toggle, **When** AgentTacho loads it, **Then** adaptive refresh is on.

---

### Edge Cases

- **Launch**: the first refresh at launch calls the endpoints as today; all paces start at the base interval.
- **Wake from sleep, manual refresh, settings edits**: keep their current behavior (spec 001, spec 010); they are not stretched, and their endpoint calls count as the endpoint's last call; they never double its interval and return it to the base when they saw new activity (FR-013).
- **Rate-limit block longer than the adaptive pace**: the block wins; adaptation never shortens a backoff or calls an endpoint during a block.
- **Quick retry and rate-limit retry** (spec 010 FR-004, FR-008): keep their timing; adaptation never delays or cancels them.
- **Several conditions at once** (idle and Low Power Mode, or idle and no agent activity): the slowest applicable pace applies, never slower than 30 minutes (or the base, when the base is longer).
- **Base interval of 30 minutes or more**: no stretching happens; the endpoints follow the base like today.
- **Base interval of 1 minute**: the endpoint pace grows 1, 2, 4, 8, 16, 30 minutes while no agent is active.
- **Usage elsewhere** (claude.ai chat, another Mac, Codex cloud tasks): not visible in local logs; it shows up at the latest after 30 minutes, or at once when the user opens the dropdown.
- **No subscription accounts, or Codex live limits off**: there is no endpoint pace to stretch; only the timer conditions apply.
- **OpenCode records**: count as activity for both the Claude and the Codex endpoint, because OpenCode can use either subscription.
- **Unassigned records**: count as activity for their harness like any other record.
- **Refresh already running when the dropdown opens**: no second refresh starts (spec 001 FR-024).
- **Dropdown kept open for a long time**: opening counts once; no repeated refreshes while it stays open beyond the normal schedule.
- **Clock moved backwards or large jumps**: paces are recomputed from the new time and never block a refresh longer than 30 minutes past its due time.
- **Toggle switched while slowed**: switching off returns to the fixed interval at once; switching on starts all paces at the base interval.

## Requirements *(mandatory)*

### Functional Requirements

**Setting**

- **FR-001**: The General tab MUST have a toggle "Adapt refresh", next to the refresh interval, on by default. It is stored in the configuration; a configuration without it behaves as on. Unlike other booleans (spec 012 FR-002), a value that is not a boolean does not make the configuration invalid: it behaves as on, and the diagnostic log notes the ignored value when the configuration loads.
- **FR-002**: With the toggle off, refreshing MUST behave exactly as before this feature: a scheduled refresh at the configured interval that calls the usage endpoints (subject to the existing endpoint policy), and no refresh on opening the dropdown.
- **FR-003**: The configured refresh interval MUST remain the fastest regular pace (the base). An adaptive pace MUST NOT be slower than 30 minutes, except that a base longer than 30 minutes is used unchanged. Adaptation never makes scheduled refreshes more frequent than the base.
- **FR-003a**: A usage endpoint is in use when it would be called at a refresh: the Claude usage endpoint when at least one Claude subscription account is configured, the Codex usage endpoint when at least one Codex subscription account has live limits on. There is one Codex endpoint pace for all Codex homes; its last call is the latest call to any of them. The last refresh is the last completed refresh of any trigger.

**Endpoint pace (agent activity)**

- **FR-004**: The app MUST track, per usage endpoint (the Claude usage endpoint and the Codex usage endpoint), whether new local usage records appeared since that endpoint's last call. Records from Claude Code count for the Claude endpoint, records from Codex count for the Codex endpoint, and records from OpenCode count for both. A record is new activity for an endpoint when its timestamp is later than that endpoint's last call, whichever account it belongs to, including Unassigned. Re-reading older records (after launch, a price change or a window move) is never activity.
- **FR-005**: When a scheduled refresh calls an endpoint and no new records counted for that endpoint since its previous call, the endpoint's interval MUST double, starting from the base and capped at 30 minutes (for a 5-minute base: 5, 10, 20, 30 minutes). When new records counted for that endpoint, its interval MUST return to the base, whatever triggered the call. Only calls that reach the service (an answer other than a transport failure as classified by spec 010 FR-001, which counts HTTP 5xx as transport) change the interval; refreshes that make no request (expired or rejected sign-in, rate-limit block) or end in a transport failure leave it unchanged.
- **FR-006**: A scheduled refresh MUST call an endpoint only when its due time (FR-010a) has passed, or when new records counted for it and at least the timer interval (FR-008 to FR-010, the base when no condition holds) has passed since its last call. Otherwise the refresh reuses the last endpoint result for that endpoint, as it does today for other reuse reasons, and the local scan still runs. In a scheduled refresh the local scan completes before the fetch-or-reuse decision for each endpoint, so records found by that scan count. A tick that fires up to 5 seconds before an endpoint's due time, or before the end of the timer interval required with new records, counts as due.
- **FR-007**: Reusing an endpoint result because of the endpoint pace MUST NOT mark the values as stale and MUST NOT change the stale, grace or rejected-sign-in behavior of spec 010.

**Timer pace (power and idle)**

- **FR-008**: While the user is idle (no keyboard or mouse input for 10 minutes, the screen is locked, or the displays are asleep), the time between scheduled refreshes MUST be 30 minutes, or the base when the base is longer.
- **FR-009**: While Low Power Mode is on, or the system thermal state is serious or critical, the time between scheduled refreshes MUST be twice the base, capped at 30 minutes.
- **FR-010**: When several timer conditions hold, the longest applicable interval MUST apply. When all conditions end, scheduled refreshes MUST return to the base interval, counted from the last refresh, or at once when that time has already passed.
- **FR-010a**: An endpoint's due time MUST be its last call plus the longer of its own interval (FR-005) and the timer interval (FR-008 to FR-010). The next scheduled refresh runs at the earlier of the last refresh plus the timer interval and the earliest due time of an endpoint in use, so the timer never holds back a due endpoint call and the timer conditions also slow the endpoint calls. A due time that a scheduled refresh already handled or tried does not pull the timer forward again, so an endpoint whose calls keep failing never makes the timer fire repeatedly.
- **FR-011**: When the user returns from idle (first input after idle, or unlock), a refresh MUST start within 60 seconds. Like the wake refresh, it calls the endpoints regardless of the endpoint pace (FR-005), but only when at least 60 seconds have passed since the endpoint's last call, and never during a rate-limit block. The wake refresh always runs; a return from idle within 60 seconds after a wake refresh starts no further refresh, and a wake within 60 seconds after a return-from-idle refresh still runs its wake refresh, whose endpoint calls are spaced as usual.

**Dropdown open**

- **FR-012**: Opening the dropdown MUST start a refresh when the last call or attempt (including a transport failure or a refresh that could make no request) of any usage endpoint in use is at least 60 seconds old, or, without any endpoint in use, when the last refresh is at least 60 seconds old. This refresh calls each endpoint whose last call is at least 60 seconds old, regardless of the endpoint pace (FR-005), and never during a rate-limit block; endpoints called less than 60 seconds ago reuse their last result.
- **FR-013**: Only calls that reach the service count as an endpoint's last call (for FR-004, FR-006 and FR-010a); activity seen before a call that made no request or ended in a transport error carries over to the next call. An endpoint call outside the scheduled refreshes (launch, wake, manual refresh, settings edit, dropdown open, return from idle, quick retry, rate-limit retry) MUST count as that endpoint's last call for FR-004 and FR-006. It never doubles the interval; it returns the interval to the base when new records counted for that endpoint since its previous call (FR-005).

**Unchanged behavior**

- **FR-014**: The launch refresh, the wake refresh, the manual refresh, refreshes after settings edits, the rate-limit backoff with `Retry-After`, the single rate-limit retry and the quick retry (spec 010) MUST keep their current timing and endpoint behavior; adaptation never delays or cancels them. The only refreshes the feature adds are those of FR-011 and FR-012.
- **FR-015**: Threshold notifications MUST follow the refreshes that run; the feature adds no refreshes for them.

**Visibility**

- **FR-016**: When any pace is slower than the base, the dropdown MUST show one line under "Last refreshed" that names one reason and a time. Reasons rank idle, then Low Power Mode, then high temperature, then "no agent activity". For "no agent activity" the time is the earliest next scheduled call of the stretched endpoints; for a timer reason it is the earliest next scheduled call of any endpoint in use, or the next scheduled refresh when no endpoint is in use. When every pace equals the base, the line MUST NOT be shown. "Last refreshed" keeps its current meaning. The menu bar shows no indicator. (Wording changed by spec 019: the "no agent activity" line names the slowed plan or plans, see `specs/019-pace-line-names-plan/spec.md`.)
- **FR-017**: The diagnostic log MUST record each change of the timer interval and of each endpoint interval with its reason, and each scheduled refresh that reuses an endpoint result because of the endpoint pace, with the time of the next endpoint call.

**Docs and structure**

- **FR-018**: The README's Configuration section MUST describe the toggle and the adaptive behavior, and its "Security and privacy" section MUST describe the request frequency accurately (at most one request per account per refresh, at the configured interval, less often while no agent is active, the user is away or the Mac is saving power, plus a refresh when the dropdown opens or the user returns, plus the existing retries), in the same pull request.
- **FR-019**: The pace decisions (endpoint intervals and fetch-or-reuse, timer interval from the conditions, the dropdown-open decision and the pace line content) MUST be part of the tested core as plain values with no clock of their own; the app layer only reads the system conditions, runs the timer and renders the line.
- **FR-020**: The feature MUST NOT add network requests to new hosts, credential reads, stored files or permission prompts.

### Key Entities *(include if feature involves data)*

- **Refresh pace**: the current timer interval and its reason, and per usage endpoint the current interval, the time of its last call and whether new activity was seen since then.
- **System conditions**: user idle, Low Power Mode, thermal state, as read by the app at each scheduling decision.
- **Adapt refresh setting**: one on or off value in the configuration, default on.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With a 5-minute base, a Claude subscription and no agent activity for 2 hours, the Claude usage endpoint is called at most 7 times, down from 24 with the fixed timer.
- **SC-002**: After a period without activity, the first refresh that finds new records for an endpoint calls that endpoint, so agent use is reflected within one base interval of the record being written.
- **SC-003**: Opening the dropdown when the last endpoint call is a minute or more old shows values fetched after the opening, or, when that request fails, the failure state of spec 010, in every case where no rate-limit block is active.
- **SC-004**: With the toggle off, the sequence of scheduled refreshes and endpoint calls over one hour is identical to the behavior before this feature.
- **SC-005**: No usage endpoint in use is ever called more than 30 minutes (or one base interval, when the base is longer) after its previous call while AgentTacho runs and the Mac is awake, outside rate-limit blocks.
- **SC-006**: The feature adds zero new hosts, zero credential reads and zero files written, verified by the security statement and the diagnostic log.

## Assumptions

- Idle means 10 minutes without keyboard or mouse input, a locked screen, or sleeping displays; this can be detected without new permissions.
- Low Power Mode and thermal pressure use the system's own state; being on battery without Low Power Mode is not a condition.
- Doubling the endpoint interval per quiet call is gradual enough that a short break (under 10 minutes) costs at most one slower check.
- Claude Code and Codex records are a good enough signal for their own subscription's activity; usage on other devices is covered by the 30-minute bound and the dropdown-open refresh.
- The pace line's exact wording and placement are settled in the plan within FR-016.
- Older AgentTacho versions ignore the new configuration key; writing the configuration from an older version drops it, which turns adaptive refresh back on by default.
