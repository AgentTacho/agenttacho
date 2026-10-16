# Feature Specification: Fix-Soon Review Batch

**Feature Branch**: `015-fix-soon-batch`

**Created**: 2026-10-16

**Status**: Draft

**Input**: User description: "Fix-soon review batch (from brainstorm/14-fix-soon-batch.md). Seven deep-review findings rated 'worth fixing soon': threshold notifications after a window reset, stale group entries after a period switch, scanning credential directories, defensive opening of the OpenCode database, a total time limit for the Claude usage request, a guard against an unintended signing tier downgrade, and safe replacement of a published release."

This feature amends earlier specs instead of adding a new capability. It changes the baseline rule of `specs/001-agentmeter/spec.md` FR-028 and the reset rule of FR-029 for window resets, the display of carried-over group entries after a period switch (spec 003 FR-014), the scan set for Claude Code session logs (spec 001 FR-013), the hardening of the OpenCode read (spec 006) and of the Claude usage request (spec 001 FR-011a, spec 007), and the release command (spec 005 FR-001, FR-015, FR-016, FR-021). Every rule of those specs not named here stays as it is.

In this spec, a **window reset** happens when a window that already has notification state (a 5-hour or 7-day subscription window, a Codex plan window, or the weekly or monthly window of a budget group or an account with its own budget) is observed in a new window: for subscription and Codex plan windows, a known window end later than the recorded known end by more than 120 seconds (the Codex tolerance of spec 007; Claude reset times are rounded to the minute, so they get the same tolerance); for budget owners, a different window end or window start (spec 003 FR-016). Examples are the 5-hour window rolling over, a new budget week or month starting, or a time zone change moving the month. For subscription and Codex windows, an observation with an earlier known window end than the recorded one is older data and is ignored for notifications (the state is kept), and a window gaining or losing its reset time re-baselines as today (sources can disagree about these, and alternating values must not notify repeatedly). A window without notification state (for example a Codex window that appears for the first time while the app runs, spec 007 FR-015) has nothing to reset and records a baseline as today. A **re-baseline** is any of the other events after which today's rules record a baseline without notifying: the first observation after launch (spec 001 FR-028), a period switch (spec 003 FR-017), a change of a budget's member set (spec 004 FR-015, spec 009 FR-006 and FR-012), a Codex live-limits toggle (spec 007 FR-015), saved values loaded at launch (spec 010 FR-019), and a change of a subscription account's credential directory or Codex home, after which the values may come from another login with other windows.

## Clarifications

### Session 2026-10-16

- Q: Does a Developer ID certificate that macOS reports as not trusted (for example because the G2 intermediate is missing) count as unusable for the tier guard? → A: No. Only expired and revoked certificates are unusable; a not-trusted Developer ID certificate stays accepted as today.
- Q: Does a release with an explicitly forced identity (`SIGN_IDENTITY`) on a lower tier stop when an unusable Developer ID certificate exists? → A: No. The guard applies only to automatic identity selection; an explicitly forced identity is a deliberate choice and is used as today.
- Q: How does a replacement keep a published release from losing its DMG? → A: The release is switched back to a draft before any asset is replaced, the assets are uploaded, and the release is published again only after every upload succeeded; on failure it stays a draft (spec 005 FR-015 behavior) and the output says how to retry.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Correct notifications and labels (Priority: P1)

A user has an 80% threshold on their Claude 5-hour window. They close the laptop at 40%, work on another machine on the same subscription, and open the laptop again after the window has rolled over; the new window is already at 85%. AgentMeter tells them that the 80% threshold is crossed, instead of staying silent for the whole window. The same user switches a budget group from weekly to monthly while the session logs cannot be read and the group's value cannot be recomputed; the group no longer shows last week's number under "per month" wording, it shows the group as waiting for data until the next successful read. And the user who runs a second Claude Code directory for a second subscription account sets that directory once, as the account's credential directory, and its sessions are counted.

**Why this priority**: These are the user-visible defects: a missed notification is the exact thing the threshold feature promises not to do, a number with the wrong period wording is wrong information, and the doubled directory setting makes a supported setup fail silently.

**Independent Test**: Feed the threshold logic an observation below a threshold, then an observation of the next window above it, and check that a notification is produced; switch a group's period while its source fails and check the shown entry; configure a second Claude Code directory only as a credential directory and check that its sessions are counted and attributed to that account.

**Acceptance Scenarios**:

1. **Given** the app is running and has notification state for a window with thresholds 80 and 95, **When** the next observation belongs to a new window (different window end) and is at 85%, **Then** exactly one notification is sent, for 80%.
2. **Given** the same state, **When** the first observation of the new window is at 97%, **Then** two notifications are sent, one for 80% and one for 95%, as for any refresh that crosses several thresholds (spec 001 FR-028).
3. **Given** the same state, **When** the first observation of the new window is at 30%, **Then** no notification is sent, and a later observation at 82% in the same window sends the 80% notification.
4. **Given** the app has just launched, **When** the first observation of a window is at 85%, **Then** no notification is sent (launch baseline unchanged).
5. **Given** a budget group whose period was just switched from weekly to monthly, or whose member set just changed, **When** the first observation for the new period or member set is above a threshold, **Then** no notification is sent (re-baseline unchanged).
6. **Given** a weekly budget group whose source keeps failing, so its entry is carried over as stale, **When** the user switches the group to monthly, **Then** the bar and dropdown show the group as before its first value (no amount, percent or period line; the bar shows the waiting placeholder), and no notification is sent for it.
7. **Given** the situation of scenario 6, **When** the source recovers, **Then** the group shows its monthly value as usual.
8. **Given** a Claude subscription account whose credential directory is `~/.claude-work` and no extra Claude Code directory configured, **When** a refresh runs, **Then** session logs under `~/.claude-work` are read and their sessions are attributed using that directory as tie-breaker (spec 001 FR-013).
9. **Given** the same directory is listed both as credential directory and as extra Claude Code directory, **When** a refresh runs, **Then** each session in it is counted once.

---

### User Story 2 - Safer reads and requests (Priority: P2)

A user points AgentMeter at an extra OpenCode data directory they got from somewhere else. Even if that `opencode.db` was crafted to run unusual database code while being read, AgentMeter reads only the plain data it needs and the crafted parts are not executed. Separately, when Anthropic's usage service accepts the connection but answers extremely slowly, the Claude request gives up after a bounded total time like the Codex request does, so the Claude token is not held in an open request indefinitely.

**Why this priority**: Defence in depth for a program that holds sign-in tokens; no visible behavior changes in normal use, so it ranks after the user-visible defects.

**Independent Test**: Open a database whose schema contains a view or generated column that would call a function with side effects (registered by the test) and check that the read either returns only plain records or fails cleanly, without executing it; point the Claude usage request at a server that trickles its response and check that it ends with a transport error within the total limit.

**Acceptance Scenarios**:

1. **Given** an OpenCode database whose schema uses functions or constructs that a hardened reader refuses, **When** AgentMeter reads it, **Then** either the read returns only the plain records, or it fails as a source error with the existing stale handling (spec 006); in both cases the rest of the snapshot is unaffected and no schema-defined code runs.
2. **Given** a normal OpenCode database, **When** AgentMeter reads it, **Then** the results are identical to today's.
3. **Given** the Claude usage service sends response bytes slowly enough that no single wait exceeds the per-request timeout, **When** the total time exceeds 45 seconds, **Then** the request ends as a transport error and is handled like any other transport error (spec 010 retry and last-good rules).

---

### User Story 3 - Releases cannot silently downgrade or lose their DMG (Priority: P2)

The maintainer runs a release on a Mac where the Developer ID certificate has expired. Instead of quietly signing with the self-signed certificate (which would make macOS treat the update as a different app for every user and drop their notification permission), the release stops in preflight and says why; the maintainer renews the certificate, or explicitly allows the downgrade. Later the maintainer re-uploads the assets of an already published release; the network drops halfway, and the public release still has a downloadable DMG.

**Why this priority**: Rare, but each failure affects every installed user at once, and since v0.2.1 the releases are on the Developer ID tier.

**Independent Test**: Run the release preflight with a stubbed keychain that lists an expired Developer ID certificate and a self-signed one, with and without the downgrade opt-out; run a replacement of a published release with a stubbed upload that fails, and check what users can download.

**Acceptance Scenarios**:

1. **Given** the keychain holds an expired or revoked Developer ID Application certificate and a valid self-signed certificate, **When** a release runs without the downgrade opt-out, **Then** preflight stops before building, names the unusable certificate and its problem, and explains how to renew it or how to allow the downgrade explicitly; nothing changes on GitHub or in the tap.
2. **Given** the same keychain, **When** a release runs with the downgrade opt-out, **Then** it signs with the self-signed certificate as today and the output states that the release is a deliberate tier downgrade.
3. **Given** the keychain holds no Developer ID certificate at all, **When** a release runs, **Then** it uses the self-signed certificate exactly as today, without the opt-out.
4. **Given** the same keychain as scenario 1, **When** a development build (`make app`) or a dry run runs, **Then** it falls back to the next tier as today and only prints a warning naming the unusable Developer ID certificate.
5. **Given** a published release and a replacement of its assets, **When** every upload succeeds, **Then** the release is published with the new assets.
6. **Given** a published release and a replacement of its assets, **When** an upload fails, **Then** the release is a draft (not visible to users), and the output says how to retry or delete it.
7. **Given** the keychain holds a Developer ID certificate that macOS reports only as not trusted, **When** a release runs, **Then** it signs with that certificate as today.
8. **Given** the keychain holds an expired Developer ID certificate, **When** a release runs with an explicitly forced self-signed `SIGN_IDENTITY`, **Then** it signs with the forced identity as today.

---

### Edge Cases

- A window resets while its entry is stale or unavailable (for example the Mac slept across the reset, or the service was down): the first good observation of the new window is compared against 0, so thresholds already exceeded notify once.
- A window resets and, in the same refresh, its thresholds were edited: the edited thresholds apply, as for any refresh after a threshold edit.
- A Codex window's live and snapshot reset times differ within the existing tolerance (spec 007): this is not a window reset and nothing changes. Live and snapshot values alternating between two known ends further apart notify at most once for the later window (the earlier end is ignored); alternating between a known and an unknown reset time re-baselines without notifying, as today.
- A budget owner's window moves because of a time zone change (spec 003 FR-016): this counts as a window reset; if the recomputed spend is already above a threshold, it notifies.
- A window reset coincides with a re-baseline event (for example a period switch, or the first refresh after launch): the re-baseline wins and no notification is sent.
- A period-mismatched group entry that is also over a threshold: it shows no amount, so it shows no warning or over-limit level either, and the group's threshold state is the new period's (still without baseline).
- An account with its own budget switches period while its source fails: it is shown like a group in the same situation.
- A credential directory that does not exist or has no `projects` folder: it is skipped like a missing extra Claude Code directory, without an error in the dropdown.
- A Claude subscription account uses the default `~/.claude` as its credential directory: the directory is scanned once, together with the default directory.
- A credential directory is reached through a symlink or a path with `..` that resolves to a directory already scanned: it is scanned once.
- A carried-over group entry was computed for an earlier member set (an account moved while the source fails, spec 004 FR-015, spec 009 FR-006): out of scope; it keeps today's stale presentation, because its period wording is still correct and the stale marker says the value is old.
- An expired Developer ID certificate exists next to a valid Developer ID certificate (of any team): the valid one is used and no stop occurs.
- No self-signed certificate exists and the Developer ID certificate is expired: with `ALLOW_TIER_DOWNGRADE=1` alone the release still stops, because ad-hoc additionally needs `ALLOW_ADHOC` (spec 005 FR-016).
- The downgrade opt-out is set but a valid Developer ID certificate exists: the Developer ID certificate is used; the opt-out only permits a fallback, it never forces one.
- A replacement run on a release that is still a draft: behavior is unchanged (a draft is not visible to users).

## Requirements *(mandatory)*

### Functional Requirements

**App correctness (User Story 1)**

- **FR-001**: On a window reset (as defined above) of a window that already has notification state, the app MUST treat the previous value as 0%: every threshold at or below the first observed value of the new window counts as crossed and is notified once, one notification per crossed threshold, with the usual text. This amends spec 001 FR-028, whose baseline rule then applies only to the re-baseline events defined above.
- **FR-002**: Every re-baseline event (first observation after launch, period switch, member set change, Codex live-limits toggle, saved values at launch, changed credential directory or Codex home) MUST keep today's behavior: record a baseline and send no notification. When a re-baseline event and a window reset coincide for the same window, the re-baseline rule MUST win.
- **FR-003**: A window reset MUST be recognized even when one or more refreshes between the last observation of the old window and the first observation of the new window had no usable value (stale, unavailable or failed).
- **FR-004**: When a group or an account with its own budget is shown from a carried-over entry whose budget period differs from the configured period, the bar and the dropdown MUST NOT show the carried-over amount or percent. They MUST show the owner with the same waiting-for-data presentation it has before its first value (no amount, percent or period line), until a value for the configured period is available; that presentation names no period, so no text can contradict spec 003 FR-014.
- **FR-005**: A period-mismatched entry under FR-004 MUST NOT show a warning or over-limit level, MUST NOT trigger threshold notifications and MUST NOT set a baseline.
- **FR-006**: The credential directory of every Claude subscription account MUST be read for Claude Code session logs, in addition to the default directory and the configured extra Claude Code directories, without the user listing it again. Each distinct directory MUST be read once per refresh, however many settings name it; directories are compared after expanding `~`, standardizing the path and resolving symlinks.
- **FR-007**: A credential directory that is missing or contains no session logs MUST be skipped silently, as an extra Claude Code directory is today.

**Safer reads and requests (User Story 2)**

- **FR-008**: The OpenCode database MUST be opened read-only (as today) in a hardened mode in which the database file cannot make the reader run schema-defined code with side effects or use functions not meant for untrusted schemas. A database the hardened reader refuses MUST be handled as a failed OpenCode read under the existing rules (stale values, diagnostic log line), without affecting other sources.
- **FR-009**: For a normal OpenCode database, the hardened read MUST produce the same records as today.
- **FR-010**: The Claude usage request MUST have a total time limit of 45 seconds, equal to the Codex usage request, in addition to its existing 30-second request timeout, measured from sending the request until its response is complete (the credential read before it is not included). Exceeding it MUST be handled as a transport error under the existing rules (spec 010).
- **FR-011**: The README's "Security and privacy" section MUST state the hardened OpenCode read, the total time limit of both usage requests, and that session logs are also read from each Claude subscription account's Claude Code directory (FR-006).

**Release safety (User Story 3)**

- **FR-012**: When a release selects its signing identity automatically (no explicitly forced `SIGN_IDENTITY`) and the keychain holds a Developer ID Application certificate that macOS reports as expired or revoked, and no usable Developer ID Application certificate, the release preflight MUST stop before building, name the certificate and its problem, and explain both remedies (renewing the certificate, or setting the downgrade opt-out). This amends spec 005 FR-001 and FR-016 for releases. A Developer ID certificate that macOS reports only as not trusted remains usable, as today. A release with an explicitly forced `SIGN_IDENTITY` uses that identity as today.
- **FR-013**: An explicit opt-out variable (`ALLOW_TIER_DOWNGRADE=1`) MUST let the release continue with the next tier in the existing order (spec 005 FR-001); the release output MUST then state that the release was signed on a lower tier than an available Developer ID certificate would give. The opt-out permits only leaving the Developer ID tier; falling back to ad-hoc still also needs `ALLOW_ADHOC` (spec 005 FR-016). The Makefile MUST pass the variable through to the release command like the other release variables, and the README maintainer section MUST describe it.
- **FR-014**: Development builds and dry runs MUST keep today's fallback with an unusable Developer ID certificate, and MUST print a warning naming the unusable certificate; the dry run's warning MUST also say that a real release would stop unless `ALLOW_TIER_DOWNGRADE=1` is set.
- **FR-015**: Releases where the keychain holds no Developer ID Application certificate at all MUST behave as today.
- **FR-016**: When the maintainer replaces the assets of a published release (spec 005 FR-016), the release MUST be switched back to a draft before any asset is replaced, so a failed upload never leaves a published release without a complete, matching set of assets. Whether the release is the latest MUST be decided by version (its tag is the highest release tag among the published releases and itself), so the same answer comes out before the draft switch and on a retry of a draft; every publish (a new release, a replacement or a retry) MUST mark it as latest exactly when that is true, and the cask update of spec 005 FR-021 keeps its own version check. After every upload succeeded, the release MUST be published again. On failure, the release MUST stay a draft and the output MUST say how to retry or delete it, as for a new release.
- **FR-017**: The release tests MUST cover FR-012 to FR-016; the existing tests that expect an expired or revoked Developer ID to fall through to self-signed for a release MUST change to expect the stop.

### Key Entities

- **Notification state of a window**: per account or budget owner and window kind, the recorded window end, the last observed percent, (for budget owners) the member set, and (for subscription and Codex accounts) the credential directory or Codex home the values came from. A window reset changes the recorded window end; a re-baseline replaces the whole state.
- **Carried-over budget entry**: the last computed group or own-budget entry kept while its source fails, including the period it was computed for.
- **Signing tier**: as in spec 005 (Developer ID, self-signed, ad-hoc), plus the state of a Developer ID certificate the keychain lists but cannot use.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In tests covering every window kind (Claude 5-hour and 7-day, Codex plan windows, weekly and monthly budget windows), a first observation of a new window above a threshold produces exactly the expected notifications in 100% of cases, and none of the six re-baseline events produces a notification.
- **SC-002**: After a period switch with a failing source, no bar or dropdown text shows an amount computed for the old period in 100% of tested cases.
- **SC-003**: A second Claude Code directory set only as a credential directory has its sessions counted, with the same totals as when it is also listed as an extra directory (no double counting).
- **SC-004**: In a test that registers a side-effecting function and references it from a view or generated column that AgentMeter's OpenCode queries read, the read causes no side effect, while the same database opened without the hardening does.
- **SC-005**: A Claude usage request against a server that never finishes its response ends within 50 seconds (45 seconds plus scheduling slack).
- **SC-006**: In the release tests, a release with only an unusable Developer ID and a self-signed certificate never produces a self-signed release without the opt-out, and a failing replacement upload never leaves a published release without a downloadable DMG.

## Assumptions

- "Window end" is the identity of a window for all window kinds, as in today's notification state; the Codex reset-time tolerance (spec 007) keeps deciding when two Codex reset times are the same window.
- The notification text for a crossing found on a window reset is the normal crossing text; saying that the threshold was already exceeded at the start of the window is not needed.
- The waiting-for-data presentation of FR-004 reuses what a budget owner shows before its first value; no new note text is introduced.
- Only Claude subscription credential directories need FR-006: Codex subscription accounts' homes are already read for session logs.
- The hardened OpenCode read relies on the database engine's built-in defensive settings; AgentMeter's own queries do not use any construct those settings forbid.
- The README already says that the usage requests refuse redirects and keep no cache; FR-011 adds to that list.
- While a replaced release is a draft, its download URLs are not reachable, so a Homebrew install or a direct download during that time fails; that is acceptable for a maintainer-only, rare operation, and better than a published release whose assets do not match.
- Out of scope: all other review findings in the idea inbox.
