# Feature Specification: Credential Notifications

**Feature Branch**: `014-credential-notifications`

**Created**: 2026-10-16

**Status**: Draft

**Input**: Brainstorm `brainstorm/11-credential-notifications.md` (approach A, a separate credential alert tracker that reads the failure classification of spec 010 and sends through the existing notification presenter).

## Context

When a sign-in stops working, AgentMeter fails silently. The bar shows `--` or a stale `~` value, and the dropdown shows a colored note (spec 001, spec 007, spec 010 FR-010 and FR-012), but nothing reaches a user who is not looking at the menu bar. A sign-in the usage service rejects, a credential that disappears, or a token that stays expired all need the user to act, usually by running the agent to sign in again. Today the only notifications AgentMeter sends are threshold crossings (spec 001 FR-028 and following, spec 007 FR-015).

Spec 010 made the failures distinguishable: every failed request is classified as transport, sign-in rejected, rate limited or service changed (spec 010 FR-001), and failures before a request (missing, expired or unreadable credentials, a Codex token already rejected) keep their own states (spec 010 FR-002). This feature turns the change from a working sign-in to a failing one into a single notification.

### Changes to earlier specs

- **Spec 010 Assumptions** ("Notifications about rejected sign-ins or resets ... are out of scope"): notifications about failing sign-ins are now in scope. The inbox item `reset-and-credential-notifications` named there was split: its credential part is this feature, and reset notifications stay out of scope as inbox item `reset-notifications`.
- **Notification presenter** (spec 001 threshold notifications): the presenter now also delivers and withdraws credential notifications, and clicking any AgentMeter notification opens the dropdown (FR-013). Threshold notifications now also appear while the dropdown is open (AgentMeter counts as the active app then; before, macOS did not show them in that case). Threshold notification text and rules are unchanged.

## Clarifications

### Session 2026-10-16

- Q: Does a Codex sign-in that moved to keychain storage (which AgentMeter cannot read) notify, and with which text? → A: Yes, as "not signed in", but with its own wording: title "<account>: sign-in not readable", body "Codex keeps its sign-in in the keychain, which AgentMeter cannot read." Running codex to sign in would not fix it, so the generic text would mislead (FR-009).
- Q: When the first refreshes after launch fail with a transport error, rate limit or service change, which health becomes the baseline? → A: The first health other than unchanged. Unchanged results leave the baseline unset, so a launch while offline followed by a rejection stays silent (FR-004).
- Q: Do accounts hidden from the bar ("Show in bar" off) get credential notifications? → A: Yes. Bar visibility does not affect notifications, as for threshold notifications; only the global switch does (FR-002).
- Q: (verification) Do withdrawn and dropped log lines also carry the health? → A: No. A withdraw follows a recovery, a removal or the switch, so there is no failing health to report; those lines carry the account id only, as the notification contract specifies (FR-010).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A rejected or removed sign-in notifies once (Priority: P1)

The user signs in to Claude Code on another machine, which invalidates the token on this Mac. AgentMeter's next refresh is rejected. A macOS notification appears: "Claude (Work): sign-in rejected" with "Run claude to sign in again." The user runs claude, the next refresh succeeds, and the notification disappears from Notification Center. No further notification follows while the sign-in keeps failing on later refreshes.

**Why this priority**: A rejected sign-in never fixes itself, and the user usually only notices when they look at the bar hours later. It is the core of the feature.

**Independent Test**: With a Claude subscription account that has a successful refresh, make the usage service answer HTTP 401 on the next refresh. Exactly one notification is delivered, later rejected refreshes deliver nothing, and a successful refresh removes the delivered notification.

**Acceptance Scenarios**:

1. **Given** a Claude subscription account whose last request succeeded, **When** a refresh is rejected (HTTP 401 or 403), **Then** one notification is delivered naming the account and telling the user to run claude to sign in again.
2. **Given** a rejected sign-in has notified, **When** later refreshes are rejected too, **Then** no further notification is delivered.
3. **Given** a rejected sign-in has notified, **When** a request for the account succeeds, **Then** the delivered notification is removed from Notification Center and no new notification is delivered.
4. **Given** the account recovered, **When** its sign-in is rejected again later, **Then** a new notification is delivered.
5. **Given** a Claude subscription account whose last request succeeded, **When** its credentials disappear (the account becomes "not signed in"), **Then** one notification is delivered telling the user that no sign-in was found and to run claude to sign in.
6. **Given** a Codex subscription account with live limits on whose last live request succeeded, **When** its sign-in is rejected or its sign-in disappears from the Codex home, **Then** the same rules apply, with the fix naming codex.

---

### User Story 2 - A long expiry notifies after a delay (Priority: P2)

The user has not used Claude Code for two days. AgentMeter only reads the token and never refreshes it, so the token expired a day and a half ago. An expired token is normally harmless (running the agent renews it), so AgentMeter waits. Once the token has been expired for 24 hours, AgentMeter notifies: "Claude (Work): sign-in expired" with "Run claude to refresh it."

**Why this priority**: Expiry is common and usually fixes itself, so notifying at once would be noise. After a day it is likely the user wants to know their usage is no longer tracked. It is less urgent than a rejection.

**Independent Test**: With a working account, let its token's expiry time pass. No notification is delivered before 24 hours after the expiry time; the first refresh after that delivers one.

**Acceptance Scenarios**:

1. **Given** an account whose last request succeeded, **When** its token expires, **Then** no notification is delivered while less than 24 hours have passed since the token's expiry time.
2. **Given** a token has been expired for 24 hours or more and the account was working before the expiry, **When** a refresh sees the expired state, **Then** one notification is delivered.
3. **Given** the token was renewed before the delay passed, **When** the next request succeeds, **Then** nothing is delivered.
4. **Given** the app was quit while a token was expired and restarted 30 hours after the expiry time, **When** the first refresh sees the expired state, **Then** no notification is delivered, because the first state after launch is the baseline (FR-004).

---

### User Story 3 - The user can turn credential notifications off (Priority: P3)

A user who checks the dropdown often finds the notifications redundant. They open Settings, General, and turn off "Notify when a sign-in stops working". From then on no credential notification is delivered; threshold notifications keep working.

**Why this priority**: It is a small control that keeps the feature from becoming a nuisance, but the feature delivers value without it.

**Independent Test**: Turn the switch off, cause a rejected sign-in on a working account, and observe that nothing is delivered; turn it on again and observe that the next new failure notifies.

**Acceptance Scenarios**:

1. **Given** a new configuration, **When** the user opens Settings, General, **Then** the switch "Notify when a sign-in stops working" is on.
2. **Given** the switch is off, **When** a working account's sign-in is rejected, **Then** no notification is delivered.
3. **Given** the switch is off, **When** threshold crossings happen, **Then** threshold notifications are delivered as before.
4. **Given** a credential notification is delivered, **When** the user turns the switch off, **Then** that notification is removed from Notification Center.

---

### Edge Cases

- **Already failing at launch**: an account that is rejected, not signed in or expired on the first refresh after launch stays silent; that state is its baseline. It notifies only after it has worked once and failed again. A credential notification left in Notification Center from before the launch is removed at launch and does not come back while the account stays failing.
- **Offline at launch**: while refreshes after launch fail with transport errors, the account has no baseline yet; the first rejected, not signed in, expired or working result becomes the baseline, so a rejection seen after the network returns stays silent.
- **New account or changed directory**: an account added to the configuration, or whose credential directory (Claude) or Codex home (Codex) changes, starts without a baseline, as at launch. A notification delivered for its previous directory is removed.
- **Account removed**: an account removed from the configuration has its delivered credential notification removed and its state dropped.
- **Transport errors, rate limits and service changes**: they never notify and never end an episode. An account that was working stays working through them, so a rejection after a stretch of transport failures still notifies.
- **Kind changes within an episode**: an episode is the span from the first credential failure after a working state to the next successful request. At most one notification is delivered per episode. If an expired token has not notified yet and the account becomes rejected or not signed in, that notification is delivered at once. Once an episode has notified, a change of kind (for example expired to rejected) delivers nothing new.
- **Codex token already rejected**: spec 007 FR-003 keeps a rejected Codex token from being sent again; that state counts as the same rejected episode and does not notify again.
- **Codex live limits off**: a Codex account with live limits off sends no request and uses no sign-in; it never notifies. Turning live limits off ends its episode and removes a delivered notification.
- **Unreadable credentials**: a Claude credential file or keychain entry that exists but cannot be read is not a sign-in failure the user can fix by signing in; it does not notify and does not end an episode.
- **Notification permission not decided or denied**: credential notifications queue like threshold notifications. A queued credential notification whose account recovers, is removed, or whose switch is turned off before permission is granted is dropped.
- **Running without an app bundle** (for example during development): credential notifications are only written to the diagnostic log, as threshold notifications are today.
- **Expiry time unknown**: a credential without a known expiry time is never classified as expired (its health comes from the request result), so FR-005 never applies to it.
- **Clock moved backwards**: an expiry time in the future is not expired; the delay is measured against the current clock.

## Requirements *(mandatory)*

### Functional Requirements

#### Credential health

- **FR-001**: For every Claude subscription account and every Codex subscription account with live limits on, the app MUST derive a credential health from each refresh result: **working**, **rejected**, **not signed in**, **expired**, or **unchanged**:
  - **working**: a request for the account succeeded (for Codex, a live fetch that yields windows for the main bucket), or a refresh without a request reused the result of an earlier successful request in this run;
  - **rejected**: the request failed with the "sign-in rejected" category of spec 010 FR-001, or a Codex token is kept from being sent because it was rejected before (spec 007 FR-003);
  - **not signed in**: no credential was found for the account (Claude "not signed in"; Codex "no sign-in found" or "sign-in kept in the keychain"). The keychain case is tracked and logged as its own variant, **not readable**, because its notification text differs (FR-009);
  - **expired**: the credential's expiry time has passed, so no request was sent (spec 010 FR-002);
  - **unchanged**: anything else (transport, rate limited, service changed, unreadable credentials, a refresh without a request for the account). The account keeps its previous health.
- **FR-002**: Token-based accounts (Vertex, Anthropic API, OpenAI API), budget groups and Codex accounts with live limits off MUST never produce credential notifications. Whether an account is shown in the bar MUST NOT affect its credential notifications.

#### When to notify

- **FR-003**: The app MUST deliver a credential notification for an account when its health changes from working to rejected or not signed in, on the first refresh that sees the change.
- **FR-004**: The first health other than unchanged that an account gets after launch, after it is added to the configuration, after its credential directory or Codex home changes, or (Codex) after live limits are turned on, is its baseline and MUST NOT notify, whatever it is. Unchanged results before it leave the baseline unset. Only a later change from working to a failing health notifies.
- **FR-005**: When an account's health changes from working to expired, the app MUST deliver a credential notification on the first refresh at which 24 hours or more have passed since the credential's expiry time, as long as the account is still expired and its episode has not notified. The delay is measured from the expiry time recorded in the credential, not from when the app first saw the expiry.
- **FR-006**: An episode starts with the change from working to rejected, not signed in or expired, and ends with the next working health. Each episode MUST deliver at most one credential notification. If an episode has not notified yet (an expiry inside its delay) and the health becomes rejected or not signed in, the notification MUST be delivered at that refresh.
- **FR-007**: When an episode ends (working again), the app MUST remove that account's delivered credential notification from Notification Center and MUST NOT deliver a new notification. The next episode can notify again.
- **FR-008**: When an account is removed from the configuration, its credential directory or Codex home changes, or a Codex account's live limits are turned off, the app MUST remove that account's delivered credential notification and drop its health state.

#### Content

- **FR-009**: A credential notification MUST name the account (its display name, as threshold notifications do) and the kind of failure in its title, and the fix in its body. The texts below are the notification texts; the dropdown wording stays unchanged:
  - rejected: title "<account>: sign-in rejected", body "Run claude to sign in again." (Claude) or "Run codex to sign in again." (Codex);
  - not signed in: title "<account>: no sign-in found", body "Run claude to sign in." or "Run codex to sign in.";
  - expired: title "<account>: sign-in expired", body "Run claude to refresh it." or "Run codex to refresh it.";
  - Codex sign-in kept in the keychain: title "<account>: sign-in not readable", body "Codex keeps its sign-in in the keychain, which AgentMeter cannot read.".
  For a Claude account whose credential directory is not the default one, the command names the directory as spec 010 FR-010 does (for example "Run CLAUDE_CONFIG_DIR=~/.claude-work claude to sign in again."). For a Codex account whose Codex home is not the default one (`~/.codex`), the command names the home the same way (for example "Run CODEX_HOME=~/.codex-work codex to sign in again.").
- **FR-010**: A credential notification MUST NOT contain a token, an account identifier from the credential, or any other credential data (spec 001 FR-011a, spec 007 FR-018). The diagnostic log MUST record each delivered and suppressed credential notification with the account id and the health, and each withdrawn and dropped one with the account id, and nothing more from the credential. Other lines this feature writes (leftovers removed at launch, a failed post with the system's error text, notification clicks) carry no credential data either.
- **FR-011**: The app MUST keep at most one delivered credential notification per account in Notification Center. Notifications are per account: two accounts that share a credential directory or Codex home each notify on their own.

#### Setting

- **FR-012**: The configuration MUST hold one global switch for credential notifications, on by default. A configuration file without the key MUST behave as on. The Settings General tab MUST show it as "Notify when a sign-in stops working". Turning it off MUST stop all credential notifications, remove delivered ones and drop queued ones; it MUST NOT affect threshold notifications. While it is off, health and episodes are still tracked. A notification is delivered only if the switch is on at the refresh where it falls due (FR-003, FR-005, FR-006); an episode whose notification fell due while the switch was off counts as notified and delivers nothing later, also not on a change of kind. An expired episode still inside its delay when the switch is turned on notifies when the delay passes.

#### Delivery

- **FR-013**: Clicking a credential notification or a threshold notification MUST open the dropdown. The plan decides whether opening the dropdown from a notification click is feasible and records the outcome; if it is not, clicking MUST bring AgentMeter to the front and do nothing else. The acceptance test checks the behavior the plan recorded.
- **FR-014**: Credential notifications MUST use the existing permission handling and queueing of threshold notifications. A queued credential notification MUST be dropped when its episode ends, its account is removed or changes directory, or the switch is turned off before permission is granted.

#### Constraints

- **FR-015**: This feature MUST NOT add network requests, MUST NOT write to the agents' files, and MUST NOT read credential data beyond what the refresh already reads. The README "Security and privacy" section MUST stay true; it MUST be updated in the same change if its description of notifications needs to mention credential notifications.

### Key Entities

- **Credential health**: per account, the result of the latest refresh with respect to its sign-in: working, rejected, not signed in or expired (unchanged results keep the previous value). Derived from spec 010's failure categories and the pre-request credential states.
- **Credential episode**: the span from the first failing health after a working one to the next working health; holds the failure kind, the expiry time for an expired credential, and whether a notification was delivered.
- **Credential notification**: one per account at most, delivered once per episode, withdrawn when the episode ends or the account goes away.
- **Credential notification switch**: one global configuration value, on by default.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Within one refresh after a working sign-in is rejected or removed, the user receives exactly one notification naming the account and the fix, without opening the dropdown.
- **SC-002**: A sign-in that keeps failing for a whole day produces exactly one notification, regardless of the number of refreshes.
- **SC-003**: An expired token that is renewed within 24 hours of its expiry produces no notification.
- **SC-004**: Launching the app with an account that is already failing produces no credential notification.
- **SC-005**: Within one refresh after a failing sign-in works again, Notification Center holds no credential notification for that account.
- **SC-006**: No delivered notification text and no diagnostic log line produced by this feature contains a token: a test that searches them for the token strings used in a refresh finds none.

## Assumptions

- The expiry delay of 24 hours is a fixed value, not a setting. Claude Code and Codex renew their tokens whenever they run, so a token expired for a full day means the agent was not used for a day or its renewal is failing.
- The account's display name in the configuration is safe to show in a notification; it is the name threshold notifications already use.
- No recovery notification is wanted; withdrawing the failure notification is enough.
- Per-account control is not needed; a handful of accounts share one switch.
- Persisting episode state across launches is not needed: the first state after launch is the baseline (FR-004), so a failure that happens while the app is not running does not notify.
- Window reset notifications are out of scope (inbox item `reset-notifications`).
