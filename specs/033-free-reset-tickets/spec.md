# Feature Specification: Free Reset Tickets

**Feature Branch**: `033-free-reset-tickets`

**Created**: 2026-10-21

**Status**: Draft

**Input**: Brainstorm `brainstorm/32-free-reset-tickets.md`: "Check for the subscription models, Claude and Codex, whether there are free limit resets available. For every free limit ticket show an icon like a present box next to the account name in the dropdown, with a tooltip showing how long it is valid. Use a dimmed, monochrome icon from our Font Awesome collection."

## Background

Claude and ChatGPT subscriptions sometimes grant free limit resets: tickets that reset a usage limit early when the user redeems them. Claude's own UI calls this "Reset for free" (Settings > Usage). The tickets expire, and nothing in AgentTacho tells the user they hold one, so a ticket can lapse unused while the user waits for a window to reset.

CodexBar ("Limit Reset Credits") reads them for both providers and only displays them. The sources, as CodexBar reads them:

- **Claude**: the usage request AgentTacho already sends returns a free-reset block when it carries an extra query flag. The block lists grants, each with a count of resets left, an optional start time, an optional end time (none means it never expires) and a paused flag, plus an eligibility flag for the whole account. The flag and the block are undocumented and were observed on personal Pro and Max accounts only.
- **Codex**: one extra read-only request to the ChatGPT usage service, with the same sign-in as the plan-limit request, returns a list of credits, each with a status (available, redeeming, redeemed, expired) and an optional expiry time.

This feature shows the usable tickets in the dropdown and reminds the user before one expires. AgentTacho never redeems a ticket; it only reads (constitution III).

## Clarifications

### Session 2026-10-21

- Q: Should the Codex credit request also be sent when the plan-limit request of the same refresh failed? → A: No; it is sent only after a successful plan-limit request, and a skipped request counts as a failed ticket read (FR-001, FR-003).
- Q: Which result decides the usage figures, errors and credential health when the Claude request with the flag is refused and repeated without it? → A: The plain request's result alone; the refused flagged request leaves no trace beyond the log line. HTTP 401 is a sign-in rejection either way and is not repeated (FR-004).
- Q: When two accounts share one Claude Code directory or Codex home, do both show the tickets and both notify? → A: Yes; tickets and notifications are per account, as credential notifications are (spec 014 FR-011).
- Q: Should the gift glyphs lead somewhere? → A: Yes (maintainer request); a click opens the provider's usage page in the browser, where the reset can be redeemed (FR-010a).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See free reset tickets next to the account (Priority: P1)

A user with a Claude Max account opens the dropdown. Next to the account name sit two small, dimmed gift glyphs. Hovering over the first shows "Free limit reset, expires in 2 days (Thu 14:00)", the second "Free limit reset, no expiry". The user now knows they can reset their 5-hour limit for free instead of waiting.

**Why this priority**: This is the core request. With only this story the user can see and use tickets they would otherwise miss.

**Independent Test**: Give an account tickets (in a test double of the usage service or the demo scenario), open the dropdown, and check the glyphs, their count, order and tooltips.

**Acceptance Scenarios**:

1. **Given** a Claude subscription account whose usage response lists one usable ticket, **When** the user opens the dropdown, **Then** one dimmed gift glyph appears in that account's header next to its name.
2. **Given** a Codex subscription account with live limits on whose credit list holds two available credits, **When** the user opens the dropdown, **Then** two gift glyphs appear in that account's header.
3. **Given** an account with five usable tickets, **When** the user opens the dropdown, **Then** three gift glyphs and a dimmed "+2" appear, the glyphs for the three soonest-expiring tickets.
4. **Given** a ticket that expires in 2 days and 3 hours, **When** the user hovers over its glyph, **Then** the tooltip says it is a free limit reset and when it expires, as a relative time and an absolute time in the formats the window reset texts use.
5. **Given** a ticket without an expiry time, **When** the user hovers over its glyph, **Then** the tooltip says it is a free limit reset with no expiry.
6. **Given** the "+2" marker, **When** the user hovers over it, **Then** its tooltip lists the expiry of each of the two tickets it stands for.
7. **Given** an account without usable tickets, **When** the user opens the dropdown, **Then** its header looks as it does without this feature.
8. **Given** a Claude account with a ticket, **When** the user clicks its gift glyph, **Then** Claude's usage page opens in the default browser and the dropdown closes; for a Codex account the Codex usage page opens.

---

### User Story 2 - Be reminded before a ticket expires (Priority: P2)

A user holds a Codex ticket that expires on Friday. On Tuesday a notification says that a free limit reset of that account expires in 3 days. On Thursday a second one says it expires within 24 hours. The user redeems it in time.

**Why this priority**: A ticket that lapses is the loss this feature exists to prevent, and the user does not open the dropdown every day. The dropdown alone (story 1) still delivers value without it.

**Independent Test**: Feed a ticket whose expiry moves into the 3-day and then the 24-hour range across refreshes, and check that exactly one notification is delivered at each step, also across a relaunch.

**Acceptance Scenarios**:

1. **Given** a ticket that expires in more than 3 days, **When** a refresh sees it less than 3 days before its expiry, **Then** one notification is delivered naming the account and the expiry.
2. **Given** that ticket, **When** a refresh sees it less than 24 hours before its expiry, **Then** a second notification is delivered.
3. **Given** a ticket first seen 30 hours before its expiry, **When** the refresh sees it, **Then** only the 3-day notification is delivered at once; the 24-hour one follows when its time comes.
4. **Given** a ticket first seen 10 hours before its expiry, **When** the refresh sees it, **Then** only the 24-hour notification is delivered.
5. **Given** a ticket whose 3-day notification was delivered, **When** AgentTacho is quit and relaunched before the 24-hour step, **Then** the 3-day notification is not delivered again.
6. **Given** a ticket without an expiry time, **When** any number of refreshes see it, **Then** no expiry notification is delivered.
7. **Given** two tickets of one account with the same expiry time, **When** they reach the 3-day step, **Then** one notification is delivered that says two free limit resets expire.

---

### User Story 3 - Turn the reminders off (Priority: P3)

A user who checks the dropdown often finds the reminders redundant. In Settings > General they turn off "Notify before a free limit reset expires". The glyphs stay; no expiry notification is delivered any more.

**Why this priority**: A small control that keeps the reminders from becoming a nuisance.

**Independent Test**: Turn the switch off, move a ticket into the 3-day range, and check that nothing is delivered while the glyph still shows.

**Acceptance Scenarios**:

1. **Given** a new configuration, **When** the user opens Settings > General, **Then** the switch "Notify before a free limit reset expires" is on, next to "Notify when a sign-in stops working".
2. **Given** the switch is off, **When** a ticket reaches the 3-day or 24-hour step, **Then** no notification is delivered and the glyph still shows.
3. **Given** the switch is off, **When** threshold or sign-in notifications fall due, **Then** they are delivered as before.

---

### Edge Cases

- **Paused, not yet started, expired, redeeming or redeemed tickets**: never shown and never notified. A Claude grant counts only when the account is eligible, the grant is not paused, its start time (if any) has passed and its end time (if any) lies in the future. A Codex credit counts only when its status is available and its expiry time (if any) lies in the future.
- **A ticket expires while the dropdown is open or between refreshes**: its glyph disappears no later than the next time the dropdown renders its times (the same tick that updates the reset texts); it is not shown with a past expiry.
- **A ticket disappears** (redeemed elsewhere, or the service stops listing it): its glyph goes at the next successful ticket read; a notification already delivered stays in Notification Center, nothing further is delivered for it.
- **The free-reset block is missing** (Claude Team or Enterprise organizations, an account not eligible, a service that changed): the account shows no glyphs, and its usage figures, error state and credential health are as without this feature.
- **The service rejects the Claude query flag** (a client error other than 401 and 429): AgentTacho repeats the request once without the flag (FR-004). If the repeat succeeds, the usage shows as usual, the account shows no glyphs, and the flag stays off for that account until relaunch. If the repeat fails too, the account shows the error it would show without this feature and keeps its tickets as after a temporary failure.
- **The Codex credit request fails**: after a transport error, timeout or HTTP error the account keeps the tickets from its last successful read in this run, minus expired ones; after a malformed or implausible successful response it shows no glyphs (FR-003). The plan limits, their error lines and the credential health are unaffected.
- **Claude account without a request** (no sign-in found clears its tickets; an expired or unreadable credential keeps them as after a temporary failure, since the user can still redeem in the browser).
- **Codex refresh that sends no request** (not due under adaptive refresh, blocked, no sign-in): the account keeps the tickets of its last successful read, minus expired ones.
- **Codex live limits off**: no credit request is sent, the Codex sign-in is not read for it, and the account shows no glyphs.
- **Implausible data**: more than 50 usable tickets for one account, a negative or non-integer count, or an unparsable time make the ticket read a failure that clears the tickets (FR-003); no glyph and no notification come from it.
- **Long account name**: the account name truncates before the glyphs, the "+N" marker or the headline figure do; the header stays one line at the dropdown's width.
- **Notification permission not decided or denied, or no app bundle**: expiry notifications queue or go to the diagnostic log exactly as threshold notifications do.
- **Clock moved backwards**: an expiry in the future is not expired; the steps are measured against the current clock.
- **Account removed from the configuration**: its tickets and its notification record are dropped.
- **Account renamed**: its tickets and notification record stay (the account id does not change); its next notification uses the new display name.
- **A late ticket**: a ticket that appears with an expiry time whose step was already delivered for that account gets no notification of its own for that step; the next step's notification counts it with the others.
- **Groups and budgets**: show no glyphs; tickets belong to the subscription account.
- **Two accounts on one login** (same Claude Code directory or Codex home): each shows the tickets and each notifies on its own, as credential notifications do (spec 014 FR-011).
- **Demo build**: shows the demo scenario's tickets and delivers no expiry notifications, as it delivers no credential notifications (spec 024 FR-008).

## Requirements *(mandatory)*

### Functional Requirements

**Reading tickets**

- **FR-001**: For every Claude subscription account, AgentTacho MUST ask for the free-reset information on the usage request it already sends (with the query flag), so no extra request is made. For every Codex subscription account with live limits on, AgentTacho MUST send one extra read-only request for the credit list with the same sign-in, after each successful plan-limit request. When the plan-limit request failed or was not sent, no credit request is sent and the ticket read counts as failed (FR-003). Token-based accounts, groups and budgets read no tickets.
- **FR-002**: A ticket MUST count as usable only under the rules of the first edge case. Each Claude grant contributes as many tickets as it has resets left, all with the grant's end time. Each available Codex credit is one ticket with its expiry time.
- **FR-003**: Reading tickets MUST be best effort. A failure of any kind MUST NOT change the account's usage figures, its error lines, its credential health (spec 014) or its refresh timing (spec 016). A response without the free-reset block (Claude) or without a credit list (Codex), or with the account marked not eligible, is a successful read with zero tickets. A failed request (transport error, timeout or any HTTP error, including a failed Claude usage request and a Codex credit request skipped after a failed plan-limit request) is a temporary failure: the account keeps the tickets of its last successful read in this run, minus expired ones. A successful response with a malformed or implausible block or list, and a dropped flag (FR-004), clear the account's tickets until the next successful read.
- **FR-004**: When the Claude usage request with the flag fails with an HTTP client error other than 401 and 429 (for example 400, 403 or 422), AgentTacho MUST repeat it once without the flag in the same refresh. If that plain request succeeds, AgentTacho MUST NOT send the flag for that account again until relaunch and clears its tickets. If it fails too, the following refreshes send the request without the flag, and the flag returns on the refresh after the first successful plain request, so each refusal costs at most one extra request. A plain request sent while the flag is suspended after a failed repeat is not a ticket read; the account keeps its tickets as after a temporary failure. The plain request's result alone decides the usage figures, error lines and credential health. HTTP 401 (a sign-in rejection) and 429 (rate limited) mean the same with or without the flag and are not repeated.
- **FR-005**: The Codex credit request MUST follow the same rules as the plan-limit request: read-only, no redirects, no cache or cookies, and only to the ChatGPT usage service host. It MUST use a 10-second total timeout, shorter than the plan-limit request's, so it adds at most 10 seconds to a refresh and never makes the refresh fail (code review 2026-10-21, N1).
- **FR-006**: Tickets MUST stay in memory only. They MUST NOT be written to `last-good.json`, the configuration or the log. Ticket and grant identifiers from the services MUST NOT be stored, logged or shown.
- **FR-007**: AgentTacho MUST NOT redeem, reserve or change a ticket. It sends no request other than the two reads of FR-001.

**Dropdown**

- **FR-008**: An account with usable tickets MUST show, in its dropdown header right after its display name, one gift glyph per ticket, at most three, ordered soonest expiry first with tickets without expiry last. With more than three, a "+N" marker MUST follow the three glyphs, N being the remaining count.
- **FR-009**: The glyph MUST be the gift icon of the bundled Font Awesome Free font (`solid:gift`, the only style the bundled catalog has), monochrome in the dropdown's secondary text color in both dropdown themes (spec 032), at the system's small font size, a little smaller than the account icon (walkthrough 2026-10-21). The "+N" marker MUST use the same color and size. No colored image or emoji is used.
- **FR-010**: Each glyph MUST have a tooltip: "Free limit reset, expires in <relative> (<absolute>)" for a ticket with expiry, using the relative and absolute time formats of the window reset texts, and "Free limit reset, no expiry" for one without. The "+N" marker's tooltip MUST list one such line per ticket it stands for, in the same order.
- **FR-010a**: A click on any glyph or on the "+N" marker MUST open the provider's usage page in the default browser and close the dropdown: `https://claude.ai/settings/usage` for Claude accounts (where Claude offers "Reset for free") and `https://chatgpt.com/settings/usage?tab=overview` for Codex accounts. Every tooltip of FR-010 MUST end with a line "Click to open the usage page". AgentTacho itself sends nothing to these pages; the browser opens them with the user's own session.
- **FR-011**: VoiceOver MUST read the glyphs and the marker as one element, for example "2 free limit resets, the next expires in 2 days", or "1 free limit reset, no expiry", with an action that opens the usage page (FR-010a).
- **FR-012**: A ticket whose expiry passes MUST disappear from the header no later than the next update of the dropdown's reset texts, without waiting for a refresh.
- **FR-013**: The menu bar item MUST NOT change. Groups and budgets show no glyphs.

**Expiry notifications**

- **FR-014**: For each account, AgentTacho MUST deliver an expiry notification at the first refresh that sees a group of tickets with the same expiry time inside the 3-day range (less than 3 days before that time), and another at the first refresh that sees it inside the 24-hour range. A group whose first sighting is already inside the 24-hour range gets only the 24-hour notification. Tickets without expiry never notify.
- **FR-015**: An expiry notification MUST name the account (its display name) and say how many free limit resets expire and when, for example title "<account>: free limit reset expires within 3 days", body "1 free limit reset expires Fri 14:00." or title "<account>: free limit resets expire within 24 hours", body "2 free limit resets expire 09:30.", with the absolute time form of the window reset texts. It MUST NOT contain a token, an identifier from the service or any credential data.
- **FR-016**: Each step (3 days, 24 hours) MUST be delivered at most once per account and expiry time, also across relaunches. AgentTacho MUST keep a record of the delivered steps (account id, expiry time, step) in its own preferences, and MUST drop an entry once its expiry time has passed or its account is removed.
- **FR-017**: The configuration MUST hold one global switch for expiry notifications, on by default; a configuration without the key MUST behave as on. Settings > General MUST show it as "Notify before a free limit reset expires", next to "Notify when a sign-in stops working". Turning it off MUST stop expiry notifications and MUST NOT affect threshold or sign-in notifications or the glyphs. A step that falls due while the switch is off counts as delivered.
- **FR-018**: Expiry notifications MUST queue while permission is not decided and go to the diagnostic log without an app bundle, as threshold notifications do. The demo build MUST NOT deliver them.

**Diagnostics**

- **FR-019**: The diagnostic log MUST record, per account, a failed ticket read (once per failure kind per run), a dropped Claude flag (FR-004), and each delivered or suppressed expiry notification with the account id, the step and the expiry time. A notification is suppressed when its step falls due while the switch is off (FR-017); queued and log-only notifications are logged as threshold notifications are. It MUST NOT record ticket counts per grant, identifiers from the service or any credential data.

**Privacy, demo and website**

- **FR-020**: The README's "Security and privacy" section MUST name the Claude query flag and the Codex credit request (where the tokens go), and state that tickets are kept in memory only and never redeemed. The website's privacy section MUST mirror it in the same release (constitution III).
- **FR-021**: The demo scenario MUST give the first Claude account two tickets, one expiring within 3 days and one without expiry, so the `glance` shot shows two glyphs. The coverage test MUST check that the default scenario shows at least one ticket with expiry and one without.
- **FR-022**: The existing shots MUST be recaptured with the capture script. No new stem and no new landing page card are added by this feature: its entry in the site's card candidates list (`docs/card-candidates.md`) MUST be updated with the spec and pull request and set to ready once merged (constitution 2.1.0, V). Website copy: the privacy section changes (FR-020); the feature strip and the existing cards stay as they are.
- **FR-023**: This feature depends on constitution 2.1.0 ([AgentTacho/agenttacho#8](https://github.com/AgentTacho/agenttacho/pull/8)) and the site's candidates list ([AgentTacho/agenttacho.github.io#17](https://github.com/AgentTacho/agenttacho.github.io/pull/17)) being merged before this feature's pull request merges. If either is rejected, the constitution 2.0.0 rule applies instead and the feature gets its own card and stem.

### Key Entities

- **Free reset ticket**: one usable free limit reset of a subscription account: the account it belongs to, and an optional expiry time. It has no other identity in AgentTacho.
- **Ticket read**: the result of one attempt to read an account's tickets: a list of tickets (possibly empty), a temporary failure, or a failure that clears. The last successful read per account is kept in memory for the run.
- **Expiry step**: one of two lead times before a ticket's expiry (3 days, 24 hours) at which a notification falls due.
- **Notification record**: per account, the expiry times and steps already notified, kept in AgentTacho's preferences until the expiry time passes.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For an account with usable tickets, the dropdown shows the matching number of glyphs (up to three plus "+N") on 100% of openings after a successful ticket read.
- **SC-002**: Every glyph's tooltip states its ticket's expiry as FR-010 defines, so one hover tells the user how long the ticket stays valid, verified by tests of the tooltip texts.
- **SC-003**: Every account and expiry time produces at most one notification per step it passes through while AgentTacho runs, and none twice across relaunches; it produces exactly one unless the step was already delivered (late ticket), the switch is off (FR-017) or the build is the demo (FR-018). Verified by tests that feed tickets across both steps and a simulated relaunch.
- **SC-004**: With the ticket read failing in every way FR-003 and FR-004 name, the usage figures, error lines and credential notifications are identical to a run without this feature, verified by tests.
- **SC-005**: Tickets add no request for Claude accounts, apart from the single repeat of FR-004 when the flag is refused, and at most one request per refresh for Codex accounts with live limits on.
- **SC-006**: The recaptured `glance` shots show two gift glyphs in both appearances, readable, with no real account name and no non-US format.

## Assumptions

- The query flag, the free-reset block and the credit list are undocumented and may change or vanish. AgentTacho treats them as optional: their absence is "no tickets", never an error the user sees.
- A Claude grant's tickets share its end time; telling them apart is not needed, since a user redeems any of them the same way.
- Grouping tickets by expiry time for notifications keeps two tickets with the same expiry from posting two identical notifications; "two per ticket" from the brainstorm is read as two steps per expiry time.
- The relative and absolute time formats are the ones the dropdown uses for window resets (spec 025), so the tooltips need no new formatting rules.
- The Codex credit request reuses the plan-limit request's headers and sign-in; it adds no new credential read.
- The notification record lives in AgentTacho's macOS defaults, where its UI preferences already are; no new file is created.
- The demo build delivers threshold notifications (the `alert` shot) but no credential notifications (spec 024 FR-008); expiry notifications are excluded the same way, so the demo's single alert stays the only one.
- The usage page addresses are the ones CodexBar uses and tests for subscription accounts (research R6). Opening a page in the browser is not a request by AgentTacho, so the privacy section needs no line for it.
