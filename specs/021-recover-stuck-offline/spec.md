# Feature Specification: Recover From a Stuck Offline State

**Feature Branch**: `021-recover-stuck-offline`

**Created**: 2026-10-16

**Status**: Draft

**Input**: User description: "Recover from a stuck offline state (from brainstorm/21-recover-stuck-offline.md, for 0.4.2). The running app failed every Claude and Codex usage request for over six hours with 'The Internet connection appears to be offline' while the network worked; only a restart fixed it. 'Refresh now' did not help because a manual refresh within 60 s of the last attempt reuses the last result. Use a fresh connection per request, let 'Refresh now' retry after a no-answer failure, and log the underlying error."

On 2026-10-16 the running 0.4.1 app failed every request to the Claude and the Codex usage services from 12:26 UTC on, for more than six hours, with "The Internet connection appears to be offline", through sleep and wake. The network worked (other programs reached both services), and a restart of AgentMeter fixed it at once. The likely cause is a network change (for example a VPN going up or down) after which the app's long-lived connection state stayed broken; the system kept no detail, so the cause is not proven.

In this spec, a **no-answer failure** is every failed usage request that spec 010 FR-001 classifies as "transport" except an HTTP 5xx answer, for example offline, name resolution failed, connection lost or refused, secure connection failed, cancellation, or a timeout including the 45-second total limit. A timed-out request may have reached the server; the manual bypass (FR-003) accepts that, because only the user's own clicks trigger it. A **usage request** is one request to the Claude usage service or the Codex live limits service (spec 001, spec 007).

## Clarifications

### Session 2026-10-16

- Q: Does the manual-retry exception apply to both services? → A: Yes, to the Claude usage service and the Codex live limits service. Each Codex home is judged by its own last request (its spacing and rate-limit wait are kept per home today).
- Q: With several Claude subscription accounts, one failed with no answer and another answered recently: which accounts does "Refresh now" ask within the 60 seconds? → A: Only the accounts whose last request was a no-answer failure, like spec 010's quick retry (spec 010 FR-009); accounts that answered keep their spacing.
- Q: Which underlying error is logged? → A: The URL error's domain and code, the underlying error's domain and code when the URL error carries one, and the stream error code when present; no other user info.
- Q: Does the exception apply to failures before a request (expired, missing or unreadable credentials, spec 010 FR-002)? → A: No; those are not request failures and keep today's behavior.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The app recovers by itself after a network change (Priority: P1)

A user switches networks or toggles a VPN. A usage request made during the change fails, but once the network works again, the next request succeeds, without restarting AgentMeter.

**Why this priority**: Six hours of stale plan limits until a restart is the failure this feature exists to prevent.

**Independent Test**: Make one usage request fail with a no-answer error, then let the network work again; the next request (scheduled, wake or manual) succeeds and the values are fresh.

**Acceptance Scenarios**:

1. **Given** a usage request failed with a no-answer failure, **When** the network works again and the next request is sent, **Then** that request is made on a new connection setup that does not reuse anything from the failed one, and it succeeds.
2. **Given** the app has been running for days across network changes, **When** a usage request is sent, **Then** it never depends on network state from an earlier request.
3. **Given** a usage request, **When** it is sent, **Then** it keeps every current privacy rule: no cache, no cookies, redirects refused, the request and total time limits (spec 001 FR-011a, spec 007, spec 015 FR-010).

---

### User Story 2 - "Refresh now" really retries after a failure (Priority: P2)

The dropdown says the Claude limits are stale because the service was unreachable. The user clicks "Refresh now" a few seconds later; AgentMeter sends a real request instead of showing the old failure again.

**Why this priority**: The manual refresh is the user's only lever; it must not silently reuse a failure that no server saw.

**Independent Test**: Let a request fail with a no-answer failure, then click "Refresh now" within 60 seconds; a request is sent. Repeat with an HTTP 5xx answer instead; no request is sent within the 60 seconds.

**Acceptance Scenarios**:

1. **Given** the last request to a service ended in a no-answer failure less than 60 seconds ago, **When** the user clicks "Refresh now", **Then** a new request is sent to that service.
2. **Given** the last request to a service got any HTTP answer (including 5xx, 429, 401 or 403) less than 60 seconds ago, **When** the user clicks "Refresh now", **Then** the spacing of spec 010 and spec 016 applies as today and the last result is reused (a rate-limit wait stays respected).
3. **Given** the last request ended in a no-answer failure, **When** the refresh is triggered by wake, opening the dropdown, a Settings change or the return from idle, **Then** today's spacing applies unchanged.
4. **Given** the user clicks "Refresh now" several times quickly after a no-answer failure, **When** the clicks fall into one refresh or one refresh is already running, **Then** at most one request per service is sent per refresh (no burst).

---

### User Story 3 - The log shows why a request failed (Priority: P3)

Next time requests keep failing, the diagnostic log line names the technical error behind "The Internet connection appears to be offline", so the cause can be found.

**Why this priority**: The 2026-10-16 incident left no evidence; this makes the next one diagnosable.

**Independent Test**: Make a usage request fail with a no-answer failure and read the log line.

**Acceptance Scenarios**:

1. **Given** a usage request ends in a no-answer failure, **When** the failure is logged, **Then** the log line names the error domain and code, the underlying network error's domain and code when present, and the stream error code when present, in addition to today's readable text; the dropdown text stays as today.
2. **Given** any failure is logged, **When** the line is written, **Then** it contains no token, header value, account ID or email address.

---

### Edge Cases

- A no-answer failure inside the spec 010 grace period: the quick retry 30 seconds later also uses a new connection setup; a manual click before it sends one request that takes the quick retry's place (as a request takes its place today, spec 010 FR-008), not an extra one.
- A rate-limit wait is active for a service and the last request then failed with a no-answer failure: "Refresh now" still respects the rate-limit wait.
- Both services fail with no-answer failures: one click retries both; a service whose last request got an answer keeps its spacing.
- The dropdown's existing note about the failure stays as it is until the new request finishes; this feature adds no new note text.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Each usage request MUST use its own connection setup, created for that request and invalidated after it, so that no network state carries over from an earlier request and none build up over days of running.
- **FR-002**: Each usage request MUST keep today's privacy rules: no persistent cache, no cookies, redirects refused, a 30-second request timeout and a 45-second total time limit.
- **FR-003**: When the last request to a service (for Codex: to a Codex home) ended in a no-answer failure, a manual refresh ("Refresh now") MUST send a new request to it even within the 60-second spacing. This amends, for this case only, the manual spacing of `docs/superpowers/specs/2026-10-13-endpoint-call-policy-design.md` (Claude) and the per-home Codex spacing of spec 007, spec 010 FR-008 and spec 016 FR-014 (the manual refresh keeps its current timing). An active rate-limit wait MUST still be respected.
- **FR-003c**: For Claude, the bypass of FR-003 MUST apply per subscription account: a manual refresh within the 60-second spacing asks only the accounts whose last request was a no-answer failure; accounts whose last request got an answer keep the spacing and their last result.
- **FR-003a**: A manual click merged into a pending refresh with another trigger (for example a scheduled refresh or the quick retry, spec 016 FR-014) MUST still get the bypass of FR-003 for each service or Codex home whose last request was a no-answer failure.
- **FR-003b**: A request sent under FR-003 MUST count as the last attempt for the 60-second spacing, for the adaptive pace's last try and for the dropdown-open spacing; a rate limit it receives MUST set the wait as usual.
- **FR-004**: After any HTTP answer (2xx, 3xx, 4xx including 401, 403 and 429, or 5xx), manual refreshes MUST keep today's spacing and backoff.
- **FR-005**: Refreshes not triggered by "Refresh now" MUST keep today's spacing rules.
- **FR-006**: A manual refresh MUST send at most one request per service (per Codex home), also when the user clicks repeatedly: clicks during a running refresh collapse into one follow-up refresh (today's pending trigger), which bypasses the spacing only if the running refresh ended in a no-answer failure.
- **FR-007**: The diagnostic log line of a no-answer failure MUST include the error domain and code, the underlying error's domain and code when present, and the stream error code when present, besides today's readable description. The technical detail MUST appear only in the diagnostic log: the dropdown's error text, the source errors and notifications keep today's wording.
- **FR-008**: No log line, error text or notification MUST contain a token, header value, ChatGPT account ID or email address (spec 001 FR-011a).
- **FR-009**: The decision which failures are no-answer failures, when a manual refresh skips the spacing, and the log text MUST be made by testable logic outside the user interface.
- **FR-010**: The README's "Security and privacy" section MUST name the extra request of FR-003 in its list of extra requests.

### Key Entities

- **Last request outcome per service**: today's outcome (success, rate limited, other error), extended so that a no-answer failure is distinguishable from a failure with an HTTP answer.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In tests, a usage request after a no-answer failure is made with a new connection setup in 100% of cases, and no connection setup is shared between two requests.
- **SC-002**: In tests, "Refresh now" within 60 seconds after a no-answer failure sends exactly one request per affected service; after an HTTP answer it sends none.
- **SC-003**: A logged no-answer failure contains the error domain and code (and the underlying and stream codes when present) in 100% of tested cases, never a token or header value, and the dropdown text is unchanged.
- **SC-004**: Smoke test: after a network change that broke requests (for example toggling the VPN or Wi-Fi), AgentMeter shows fresh values again at the next request once the network works, without a restart. Because the original cause is unproven, the evidence if it happens again is the log line of User Story 3.

## Out of Scope

- Recreating the connection setup only after repeated failures, or on network path changes.
- A "Retrying…" note in the dropdown.
- Changing spec 010's grace period and quick retry.

## Assumptions

- A new connection setup per request costs one extra TLS handshake every few minutes, which is negligible.
- The README "Security and privacy" statements (refused redirects, no cache or cookies, 45 seconds total) stay true. The "tokens are powerful" bullet, which lists every extra request, gains one item: "Refresh now" after a failed connection asks again at once (FR-010).
- Spec 010's quick retry and grace period stay as they are; only the manual refresh rule and the connection setup change.
- Ships as 0.4.2 together with spec 019.
