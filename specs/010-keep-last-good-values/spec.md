# Feature Specification: Keep Last Good Values

**Feature Branch**: `010-keep-last-good-values`

**Created**: 2026-10-15

**Status**: Draft

**Input**: Brainstorm `brainstorm/09-keep-last-good-values.md` (approach A, a shared last-good layer for all network-bound limit sources).

## Context

AgentTacho already keeps the last good values within one run. When a request to a provider's usage service fails, Claude subscription accounts and Codex subscription accounts keep their previous numbers, the bar marks them with `~`, and the dropdown says when they were last good (spec 001 FR-007, SC-007; spec 007 FR-005, FR-006). Three gaps remain:

1. A single failed request is visible at once. The refresh on wake from sleep often runs before the network is back, and the bar shows `~` until the next scheduled refresh although nothing is really wrong.
2. Failed Claude requests are not classified. A rejected sign-in looks exactly like a network blip, so nothing tells the user to act. Codex accounts already separate a rejected sign-in from being offline (spec 007 FR-006).
3. Last good values live in memory only. After a quit, an update or a relaunch while offline, Claude accounts show no values until a request succeeds.

This feature closes all three gaps with one shared set of rules for both providers.

### Changes to earlier specs

- **Spec 001 FR-007** ("MUST mark values as stale when the last refresh failed"): a transport failure inside a grace period (FR-005) does not mark values stale; the stale marking follows only if the quick retry fails too. Saved values shown while the first refresh after launch runs (FR-015) are not marked stale either.
- **Spec 007 FR-005** ("the last live result is kept in memory only"): the last live Codex result is now saved and restored across launches (FR-017).
- **Spec 007 FR-006** ("values that do not come from a successful live fetch in the current refresh MUST be marked stale"): the same two exceptions as for spec 001 FR-007 apply.
- **Bar for expired Claude credentials** (spec 001 bar rules): an account in the "credentials expired" state that has values (in-run or saved) shows its percent with `~` instead of `--`, so expired credentials keep the last good values visible like every other stale state (FR-015). Without values it still shows `--`.
- **Spec 007 contract** (`specs/007-codex-plan-limits/contracts/codex-usage-endpoint.md`): a Codex HTTP 5xx answer now gives the reason "usage service unavailable (HTTP n)" (was "usage service returned HTTP n") and counts as a transport failure, and an answer from an unexpected location is a service-changed failure with the source error "usage service changed" (was "offline"), following FR-001.
- **Endpoint call policy design** (`docs/superpowers/specs/2026-10-13-endpoint-call-policy-design.md`, "Persistence: None", "Out of scope: Persisting fetch results"): fetch results are now persisted (FR-013). Rate-limit blocks, spacing and retry state stay in memory only. The policy gains the quick retry (FR-004 to FR-009) next to its rate-limit retry.

## Clarifications

### Session 2026-10-15

- Q: How are saved values shown at launch while the first refresh is still running, so a normal launch with network does not flash `~` on every entry? → A: Without stale marking while the first refresh runs; they are marked stale as soon as the first refresh fails for the account. The grace period of FR-005 applies only to values from a successful request in the current run, never to saved values.
- Q: Does a quick retry request every subscription account again, or only the ones whose request failed? → A: Only the failed ones (FR-009), because the Claude usage service rate-limits aggressively and an extra request for a healthy account risks a rate limit.
- Q: Does Claude's "credentials expired" state (token past its expiry before any request is sent) also get the attention style? → A: No. It keeps its current wording and style; only a sign-in the service actually rejected uses the attention style.
- Q: How does the app know at launch that saved values still belong to the same sign-in? → A: The saved entry records the credential directory (Claude) or Codex home (Codex) the values were fetched with; a different directory means the values are not shown.
- Q: What does the attention style look like, compared with the existing stale style? → A: Red text for the rejected-sign-in note; stale notes stay orange and the grace-period note uses the secondary (gray) text color.
- Q: (spec review) When do saved values appear after launch: right away, or with the first refresh result? → A: Right away. The app shows a first result built from the saved values as soon as they are loaded, before the first refresh finishes, because an offline request can take long to time out.
- Q: (spec review) How is "0% after a reset" drawn when the bar marks stale per entry, not per window? → A: A reset window shows 0% without a reset time and is not marked on its own; the entry as a whole follows the stale rules of FR-015 and FR-006.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A network blip does not mark values stale (Priority: P1)

The user opens the lid of their Mac. AgentTacho refreshes on wake, but Wi-Fi needs a few more seconds to connect, so the request fails. Instead of switching every subscription entry to `~`, AgentTacho keeps the values as they were and tries again shortly after. By then the network is back, the retry succeeds, and the user never sees a stale marker.

**Why this priority**: It happens several times a day for every laptop user and makes the bar look broken when it is not. It is also the most visible of the three gaps.

**Independent Test**: With a subscription account showing live values, make the next request fail with a transport error and the following one succeed. The bar must never show `~`, and the dropdown shows a neutral "retrying" note in between.

**Acceptance Scenarios**:

1. **Given** a Claude subscription account shows live values, **When** a refresh fails because the usage service cannot be reached, **Then** the bar keeps the values without `~`, the dropdown shows a neutral note naming the failure and the retry time, and one retry for that account runs about 30 seconds later.
2. **Given** a retry is pending after a transport failure, **When** the retry succeeds, **Then** the account shows the new values without any stale marking and the note disappears.
3. **Given** a retry is pending after a transport failure, **When** the retry also fails, **Then** the values are marked stale (bar `~`, dropdown "Stale, last good value ..." with the reason, or the rejected-sign-in note of FR-010 when the retry was rejected), and no further quick retry is scheduled until a request succeeds again.
4. **Given** a Codex subscription account with live limits on shows live values, **When** its live request fails with a transport error, **Then** the same rules apply: values unmarked, one retry about 30 seconds later, stale only if the retry fails too.
5. **Given** the usage service answers with a rate limit, **When** the refresh records it, **Then** no quick retry is scheduled and the existing rate-limit wait and single retry apply unchanged.

---

### User Story 2 - A rejected sign-in asks the user to act (Priority: P2)

The user signed in to Claude Code on another machine, which invalidated the token on this Mac. The next refresh gets a rejection. AgentTacho keeps the last values marked `~`, and the dropdown tells the user in an attention color that the sign-in was rejected and how to fix it, instead of a generic stale note that looks like a network problem.

**Why this priority**: Without it the user waits for a "network problem" that never resolves, while the fix (sign in again) takes seconds. It is less frequent than a blip, so it ranks second.

**Independent Test**: Make the Claude usage service answer HTTP 401 for an account with values. The bar shows `~` and the dropdown shows the sign-in note in the attention style, distinct from the stale note of an offline failure.

**Acceptance Scenarios**:

1. **Given** a Claude subscription account shows values, **When** the usage service rejects its sign-in (HTTP 401 or 403), **Then** the bar keeps the values with `~` and the dropdown shows "Sign-in rejected, run claude to sign in again" in the attention style, together with the time of the last good values.
2. **Given** a rejected sign-in, **When** the refresh is recorded, **Then** no quick retry is scheduled; requests continue on the normal schedule.
3. **Given** a Claude account shows the rejected-sign-in note, **When** a later request succeeds (for example after the user ran claude), **Then** the note disappears and fresh values are shown without stale marking.
4. **Given** a Codex subscription account whose sign-in the usage service rejects, **When** the dropdown shows its state, **Then** the rejected sign-in reason uses the same attention style as the Claude note.

---

### User Story 3 - Values survive a relaunch (Priority: P3)

The user installs an update while on a train without connectivity. After the relaunch, AgentTacho shows the last known plan limits right away, and once the first refresh has failed, marks them `~` with the time they were fetched, instead of showing empty entries. When the network returns, the first successful request replaces them.

**Why this priority**: Relaunches are rarer than wakes, and Codex accounts already fall back to the limits Codex records locally. It matters most for Claude accounts.

**Independent Test**: Fetch values successfully, quit the app, block the network, start the app again. Every subscription account that had values shows them right away, and after the first refresh they are marked stale with the original fetch time.

**Acceptance Scenarios**:

1. **Given** a Claude subscription account had values fetched at 09:12, **When** the app starts and the first request fails, **Then** the account shows those values marked `~` with "last good value" 09:12 and the failure reason.
2. **Given** saved values whose 7-day window has reset since they were fetched, **When** the app starts, **Then** that window shows 0% without a reset time, windows that have not reset show their saved values, and the entry as a whole is marked stale once the first refresh fails.
3. **Given** saved values for an account, **When** the first request after launch succeeds, **Then** the fresh values replace the saved ones without stale marking.
4. **Given** a Codex subscription account with live limits on, **When** the app starts offline, **Then** the account shows the newer of the saved live result and the newest locally recorded snapshot, marked stale once the first refresh fails.
5. **Given** saved values for an account that was removed from the configuration, or whose credential directory or Codex home changed, **When** the app starts, **Then** those values are not shown.

---

### Edge Cases

- **Retry and timer collide**: a scheduled refresh that runs while a quick retry is pending takes the retry's place: the pending retry is dropped, and the scheduled refresh ends the grace period exactly as the retry would (success clears it, failure marks the account stale), so no extra request is made.
- **Manual refresh during the grace period**: the grace period (30 s) usually lies inside the 60-second spacing of manual refreshes, so a manual refresh is reused without a request; the quick retry runs at its time. After a slow failure (a request that ran into its timeout), the retry time can lie beyond the spacing; a manual refresh that then sends a request takes the retry's place like a scheduled or wake refresh (FR-008).
- **Retry while asleep**: if the Mac sleeps with a retry pending, the refresh on wake takes the retry's place when it sends a request for the account (FR-008), like a scheduled refresh: it ends the grace period, and a failure marks the account stale. It does not start a second grace period in the same failure episode. The app also restarts the refresh timer on wake, so the scheduled cadence counts from the wake time and a tick that came due during sleep does not take the quick retry's place.
- **Retry blocked by a rate limit**: when a rate-limit wait is active at the time of a quick retry (for example another Claude account was rate limited in the same refresh), the retry is not sent; the account is marked stale at the retry time with its transport reason, and the episode's quick retry counts as used.
- **Mixed outcomes**: one account fails with a transport error while another succeeds in the same refresh; only the failed account is in its grace period, and the retry requests only what failed.
- **No values yet**: if the first request after launch fails with a transport error and no saved values exist, the account shows its "no data yet" state with the reason (as today) and the quick retry still runs.
- **Already stale**: if the values are stale already (an earlier retry failed, or they came from the saved file), a further transport failure keeps them stale; a quick retry runs only once per failure episode, which starts with the first failed request after a success or after launch.
- **Unreadable saved file**: a missing, unreadable, corrupt or unknown-format file is ignored, the diagnostic log records it once, and the next successful request writes a fresh file.
- **Clock moved backwards**: saved values with a fetch time in the future are shown with the current time as their fetch time; reset times are compared against the current clock.
- **Live limits turned off for a Codex account**: its saved live result is discarded, as spec 007 FR-005 discards in-memory live results today.
- **Threshold notifications (Claude)**: stale and saved values never trigger notifications or set baselines; values in the grace period are the unchanged last good values and trigger nothing new. Codex accounts keep spec 007 FR-015 (FR-019).

## Requirements *(mandatory)*

### Functional Requirements

#### Failure classification

- **FR-001**: Every failed request to a provider usage service (the Claude usage service and the Codex live limits service) MUST be classified into exactly one category, with the same rules for both providers:
  - **transport**: no answer arrived (offline, name resolution failed, connection lost, timeout), or the service answered with an HTTP 5xx status;
  - **sign-in rejected**: HTTP 401 or 403;
  - **rate limited**: HTTP 429;
  - **service changed**: the answer could not be read, a redirect was refused, any other unexpected HTTP status, or a Codex answer without windows for the main Codex bucket (spec 007).
- **FR-002**: Failures that happen before a request is sent (missing, expired or unreadable credentials, or a Codex token already rejected under spec 007 FR-003) MUST keep their existing states and wording (spec 001, spec 007 FR-003, FR-006). They are not classified by FR-001 and get no quick retry.
- **FR-003**: The diagnostic log MUST record, per account and failed request, the category and the existing failure detail, and when a quick retry is scheduled, sent, dropped or suppressed. It MUST never contain a token (spec 001 FR-011a, spec 007 FR-018).

#### Quick retry on transport failures

- **FR-004**: When a request for an account fails with a transport error, and this is the first failed request for that account since its last successful request or since launch (the start of a failure episode), the app MUST schedule one quick retry for that account 30 seconds later.
- **FR-005**: Until the quick retry has run (or a refresh has taken its place, FR-008), the values that were shown without stale marking before the failure MUST stay unmarked (for Claude, the values of a successful request in the current run; for Codex, the observation shown unmarked under spec 007 FR-005 and FR-006, which is the newer of the last live result and the newest snapshot): no `~` in the bar and no stale styling in the dropdown. Saved values loaded at launch (FR-015) never get this grace period. The dropdown MUST show a neutral note in the secondary text color (not the stale style) naming the failure and the retry time, for example "Couldn't reach the usage service, retrying at 09:42". The time of the last successful refresh stays the time of the last good values.
- **FR-006**: When the quick retry succeeds, the new values MUST be shown without stale marking. When it fails, in any category, the account MUST be marked stale with that failure's reason as before this feature (with the FR-010 and FR-012 styling for a rejected sign-in), and no further quick retry MUST be scheduled for that account until a request succeeds again. Refreshes on the normal schedule continue throughout.
- **FR-007**: A quick retry MUST NOT be scheduled for sign-in rejected, rate limited or service changed failures. A rate limit keeps the existing wait and single retry (endpoint call policy, spec 007 FR-007). When a rate-limit wait applies to an account at the time of its quick retry, the retry MUST NOT be sent; the account MUST then be marked stale with its transport reason, and the episode's quick retry counts as used.
- **FR-008**: The quick retry is distinct from the rate-limit retry. It MUST fetch even though the last outcome was not a rate limit (the "already fresh" reuse of the endpoint call policy does not apply to it), and it MUST NOT be suppressed by the 60-second spacing that applies to manual, wake and settings refreshes, nor by the per-Codex-home spacing of spec 007. A scheduled refresh, the refresh on wake or a manual refresh past the spacing (possible when a slow failure put the retry time beyond it) that runs while a quick retry is pending and actually sends a request for the account MUST take the retry's place: the pending retry is dropped, and that request's outcome ends the grace period exactly as the retry's would. A refresh that is reused without a request for the account (spacing, or a rate-limit wait) leaves the pending retry in place; a rate-limit wait at the retry time is handled by FR-007.
- **FR-009**: The quick retry MUST request only the accounts whose transport failure scheduled it; accounts that succeeded in the same refresh keep their values and are not requested again early. The quick retry counts as a request for the shared policy rules: its time becomes the last attempt for the 60-second spacing, and a rate limit it receives sets the shared rate-limit wait as today. A successful quick retry ends only the retried accounts' failure episodes.

#### Sign-in rejected state

- **FR-010**: When the Claude usage service rejects an account's sign-in (FR-001), the account MUST keep its last good values (if any) marked stale in the bar (`~`), and the dropdown MUST show "Sign-in rejected, run claude to sign in again" in an attention style (red text) that is visually distinct from the stale style (orange text). With last good values, the note also gives their time; without them, the entry shows no values and only the note. For an account whose credential directory is not the default one, the note names the directory (for example "run CLAUDE_CONFIG_DIR=~/.claude-work claude to sign in again"). The "credentials expired" state (FR-002) keeps its current wording and style.
- **FR-011**: The rejected-sign-in note MUST disappear as soon as a request for that account succeeds. Requests for a rejected sign-in continue on the normal schedule (stopping them is out of scope).
- **FR-012**: The rejected-sign-in reason of Codex subscription accounts (spec 007 FR-006) MUST use the same attention style. Its wording and the existing spec 007 FR-003 rule about not resending a rejected token stay unchanged.

#### Last good values across launches

- **FR-013**: After every successful request for an account (for Codex, a live fetch that yields windows for the main bucket), the app MUST save that account's last good values: the account id, the credential directory (Claude) or Codex home (Codex) the request used, the fetch time, and each limit window with its percent and reset time. For Claude this includes the model-specific weekly limits with their model names. For Codex it includes every plan window with its length, the limit-reached flag and the plan type (spec 007 FR-001, FR-009, FR-011).
- **FR-014**: The saved values MUST NOT contain a token or any other credential data. The app MUST write them only to a file in its own application support directory (`~/Library/Application Support/agenttacho/`), readable and writable only by the user, and never to the agents' files or the configuration file. A write MUST replace the file as a whole, so an interrupted write never leaves a partial file.
- **FR-015**: At launch, the app MUST load the saved values and, as soon as they are loaded and before the first refresh finishes, show them for each subscription account that is still configured with the same credential directory (Claude) or Codex home (Codex) as recorded in the saved entry. Directories are compared after expanding `~` and resolving them to canonical paths. In this early result, all other entries (token-based accounts, groups, the Unassigned entry, and subscription accounts without saved values) show their placeholder state (`…` in the bar, "Refreshing…" in the dropdown) until the first refresh finishes. While the first refresh runs, saved values are shown without stale marking. When the first refresh does not produce a successful request for the account, they MUST be marked stale with their original fetch time and the reason, until a request for that account succeeds:
  - a failed request (FR-001): marked stale with the failure's reason (FR-010 styling for a rejected sign-in);
  - Claude credentials expired or unreadable: marked stale with the existing wording;
  - Claude not signed in: saved values are not shown;
  - Codex failures before a request (expired, missing or already rejected sign-in): the newer of the saved live result and the newest snapshot, marked stale per spec 007 FR-006.
  Saved values of accounts that are not shown MUST be dropped at the next save.
- **FR-016**: A stale or saved window whose reset time has passed MUST be shown as 0% without a reset time and without a limit-reached note (as spec 007 FR-010 does for snapshots). Windows whose reset time has not passed show their percent and reset time. Stale marking applies to the whole entry, never to a single window.
- **FR-017**: For Codex subscription accounts with live limits on, the saved live result MUST take the place of the in-memory last live result in the comparison of spec 007 FR-005: the account shows the newer of the saved live result and the newest local snapshot. When live limits are off, the saved live result MUST be discarded.
- **FR-018**: A missing, unreadable, corrupt or unknown-format file MUST be ignored without user-visible error; the diagnostic log MUST record the problem once per launch, and the next successful request MUST write a new file.
- **FR-019**: For Claude subscription accounts, saved values loaded at launch MUST NOT trigger threshold notifications and MUST NOT establish the notification baseline; the first successful request after launch establishes it, as today (spec 001 FR-028). For Codex subscription accounts, spec 007 FR-015 still holds: thresholds are evaluated on the values shown, and a saved live result counts like any other observation, so as the first observation after launch it establishes the baseline without notifying.
- **FR-020**: Before the first successful request after launch, the saved 7-day reset time of the alignment account MUST drive budget window alignment (spec 001, spec 003) while it is still in the future; once it has passed, alignment behaves as without a reset time, as today.

#### Documentation

- **FR-021**: The README "Security and privacy" section MUST describe the new file: what it holds, where it lives, that it holds no token, and that it is AgentTacho's own file. It MUST be updated in the same change.

### Key Entities

- **Failure category**: the classification of a failed request (transport, sign-in rejected, rate limited, service changed); decides retry, stale marking and wording.
- **Last good values**: per account, the credential directory or Codex home used, the limit windows (percent, reset time, model name for model-specific limits; for Codex also window length, limit-reached flag and plan type) and the fetch time of the last successful request. Kept in memory and saved to disk; never holds credentials.
- **Failure episode**: the span from the first failed request after a success (or after launch) to the next successful request for an account; at most one quick retry per episode. An episode also ends, like with a success, when the account's last good values are dropped: for Claude when the account is not signed in or its credential directory changed, for Codex when its Codex home changed or live limits were turned off.
- **Grace period**: the time between a transport failure that scheduled a quick retry and that retry (or the refresh that takes its place); values stay unmarked during it.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: When the network comes back within 30 seconds of a failed refresh (for example after wake), no stale marker appears in the bar at any point.
- **SC-002**: After a relaunch without network, every subscription account that had values before the quit shows them before the first refresh finishes, and marked stale with the original fetch time after it; none shows an empty or placeholder value.
- **SC-003**: Within one refresh after the Claude usage service starts rejecting a sign-in, the dropdown shows the sign-in note, and a user can tell it apart from an offline failure without reading the diagnostic log.
- **SC-004**: The saved file never contains a token: a test that searches it for the token strings used in a refresh finds none.
- **SC-005**: With the provider unreachable for an hour, the app makes at most one extra request per account per failure episode compared with before this feature, and it recovers automatically on the first successful refresh (spec 001 SC-007 still holds).

## Assumptions

- The retry delay of 30 seconds is long enough for a typical Wi-Fi reconnect after wake and short enough that the grace period is not noticeable. It is a fixed value, not a setting.
- HTTP 5xx answers are transient server problems and count as transport failures; a refused redirect or an unexpected 4xx status means the service changed.
- No maximum age is needed for saved values: every limit window has a reset time or reports 0%, so FR-016 already prevents showing a value from an expired window.
- The plan type shown for Claude accounts comes from the stored credentials at refresh time and is not saved; the Codex plan type comes from the usage answer and is saved (FR-013).
- Notifications about rejected sign-ins or resets, adaptive refresh intervals and stopping requests after a rejection are out of scope (inbox item `reset-and-credential-notifications`).
- Token-based accounts (Vertex, OpenAI API) compute their values from local session data and are not affected.
