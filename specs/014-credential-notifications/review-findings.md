# Deep Review Findings

**Date:** 2026-10-16
**Branch:** 014-credential-notifications
**Rounds:** 3 (fix rounds, each re-reviewed by CodeRabbit and Codex)
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 2 | 2 | 0 |
| Minor | 14 | 9 | 5 |
| Notable | 5 | - | 5 |
| **Total** | **21** | **11** | **10** |

**Agents completed:** 5/6 (Goal Alignment skipped: no PR found) + 2 external tools (CodeRabbit, Codex; Copilot disabled in config)
**Agents failed:** none

The first pass (5 agents, CodeRabbit, Codex) found no Critical or Important issues. Minor findings were fixed by choice. Both Important findings came from CodeRabbit re-reviewing those fixes (a race introduced in round 1 and a project-convention issue in round 2); both were fixed. Fix commit: a72bf5d.

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/AgentMeter/NotificationPresenter.swift (post completion)
- **Category:** external
- **Source:** coderabbit (round 2 re-review); also reported by codex (round 1 re-review, P2)
- **Round found:** 2
- **Resolution:** fixed (round 2)

**What is wrong:** After round 1 moved the "posted" bookkeeping into the `add` completion, a withdrawal that ran before the completion (and before the system processed the `add`) could leave the notification in Notification Center, and the late completion would record a withdrawn notification as posted.

**Why this matters:** FR-007 requires the notification to disappear when the episode ends; a stale "sign-in rejected" notification would stay after recovery. The log would also claim a later withdrawal for a notification that is gone.

**How it was resolved:** Each post gets a generation; a completion whose generation was withdrawn removes the delivered notification again and logs `credential withdrawn`, and a superseded completion does nothing.

### FINDING-2
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/AgentMeter/NotificationPresenter.swift
- **Category:** external
- **Source:** coderabbit (round 3 re-review)
- **Round found:** 3
- **Resolution:** fixed (round 3)

**What is wrong:** The generation bookkeeping from FINDING-1 was logic living in the app layer, untested, against the project rule that logic belongs in UsageCore with tests.

**Why this matters:** The ordering rules (withdrawn, superseded, current) are exactly the kind of state that regresses silently without tests.

**How it was resolved:** New `CredentialPostLedger` in `Sources/UsageCore/Notifications/CredentialPostLedger.swift` with `CredentialPostLedgerTests` (6 tests: completion, withdraw before completion, superseded, withdraw and repost, failed post, independent identifiers). The presenter only calls it and performs the Notification Center calls.

### FINDING-3
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/AgentMeter/NotificationPresenter.swift:187-203
- **Category:** architecture
- **Source:** architecture-agent (also reported by: production-readiness-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1, refined in rounds 2 and 3)

**What is wrong:** `postedCredentials.insert` ran before `add` completed, so a failed post later logged `credential withdrawn` for a notification that never appeared; the `credential failed` line was not in the contract.

**Why this matters:** FR-010 log lines must reflect what reached Notification Center.

**How it was resolved:** A post counts only after a successful, current completion (see FINDING-1, FINDING-2). The contract lists `credential failed: ...` and says "posted successfully".

### FINDING-4
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/AgentMeter/MenuBarOpener.swift:17-22, 44-48
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** A click while the dropdown was open logged "opened dropdown" although nothing was clicked; the decision rests on SwiftUI's private window class name.

**Why this matters:** If SwiftUI renames the class, the log would hide why a notification click closes the dropdown.

**How it was resolved:** A separate line `notification click: dropdown already open (<window class>)`; the contract lists it.

### FINDING-5
- **Severity:** Minor
- **Confidence:** 78
- **File:** Tests/UsageCoreTests/CredentialNoTokenTests.swift:63-67, 107-112
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The only end-to-end tests (real sources into the tracker) checked only that some deliver and some withdraw occurred.

**Why this matters:** A source regression (a 401 no longer classified as rejected, a Codex expiry without `credentialProblem`) would still pass.

**How it was resolved:** Both tests assert the exact event sequence (`deliver rejected`, `withdraw`, `deliver notSignedIn`, `withdraw`, `deliver expired`).

### FINDING-6
- **Severity:** Minor
- **Confidence:** 72
- **File:** Tests/UsageCoreTests/CredentialAlertTrackerTests.swift:358-368
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** FR-006 "an expiry inside its delay that becomes rejected or not signed in delivers at once" was tested only for rejected.

**How it was resolved:** Added `missingSignInInsideTheDelayDeliversAtOnce` and `codexKeychainInsideTheDelayDeliversAtOnce`.

### FINDING-7
- **Severity:** Minor
- **Confidence:** 70
- **File:** Tests/UsageCoreTests/CredentialAlertTrackerTests.swift:309-397
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** No tracker test for an expiry time that changes inside an episode, or for the "clock moved backwards" edge case.

**How it was resolved:** Added `expiryTimeChangeInsideAnEpisodeCountsFromTheNewTime` and `clockMovedBackwardsDoesNotNotifyEarly`.

### FINDING-8
- **Severity:** Minor
- **Confidence:** 72
- **File:** Tests/UsageCoreTests/CredentialAlertTrackerTests.swift:430, 446-448, 471
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** `configurationChanged` used its default `now: Date()` (wall clock) against synthetic 2026-10-14 snapshot times; a future change creating state there would make later `.isEmpty` checks pass for the wrong reason.

**How it was resolved:** All calls pass an explicit time between the surrounding snapshots.

### FINDING-9
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/UsageCore/Subscription/CodexLimits.swift:137-139
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, comment)

**What is wrong:** The doc comment claimed no reason string is matched, but `CodexLimitsSource.live` derives `.keychain` by comparing the lookup's reason string.

**How it was resolved:** The comment names the one remaining string match. Making `CodexCredentialLookup.missing` typed is left as a possible follow-up (same finding, optional part).

### FINDING-10
- **Severity:** Minor
- **Confidence:** 72
- **File:** Sources/UsageCore/Notifications/CredentialAlertTracker.swift:27-28
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, comment)

**What is wrong:** `Episode.delivered` was documented as "in Notification Center or queued", but it only means a deliver event was emitted and not withdrawn.

**How it was resolved:** Comment corrected.

### FINDING-11
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/UsageCore/Notifications/CredentialAlert.swift:68-77; CredentialAlertTracker.swift (eligibleAccounts); Sources/UsageCore/Snapshot/FailureCategory.swift:67-69
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** The "default directory or `CLAUDE_CONFIG_DIR=<dir> claude`" rule exists both in `SignInRejectedNote` (spec 010 dropdown) and in the tracker plus `CredentialAlert`.

**Why it remains:** Behavior is identical today and tested on both sides; a shared helper is a refactor touching spec 010 code, better done separately.

### FINDING-12
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/UsageCore/Notifications/CredentialAlertTracker.swift:22-29
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** `Episode.health` always equals `State.health` while an episode exists.

**Why it remains:** Redundant but consistent in every transition and covered by tests; removing it is a cosmetic refactor of a state machine that just passed review.

### FINDING-13
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/AgentMeter/NotificationPresenter.swift; Sources/UsageCore/Notifications/CredentialAlert.swift:90-98
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** Log subjects are formatted three ways (`CredentialAlertEvent.logMessage` on throwaway events, raw `accountId`).

**Why it remains:** Output matches the contract; consolidation (`CredentialAlert.logSubject`) is optional cleanup.

### FINDING-14
- **Severity:** Minor
- **Confidence:** 85
- **File:** Sources/UsageCore/Notifications/CredentialHealth.swift:20-21
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:** `CredentialHealth.isFailing` is public but only used by a test.

**Why it remains:** It documents the data-model definition ("a failing health is any case other than working"); harmless.

### FINDING-15
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/AgentMeter/NotificationPresenter.swift (recordPosted, `.superseded`)
- **Category:** external
- **Source:** codex (round 3 and final re-review, P2)
- **Round found:** 3
- **Resolution:** remaining (triaged from Important to Minor)

**What is wrong:** If two posts for the same account are in flight and the system processes the older `add` last, the older content could replace the newer one.

**Why it remains:** Two posts for one account need two refreshes (at least one minute apart, a recovery in between), while an `add` completes in milliseconds; the system also handles requests of one connection in order. Serializing posts per identifier is out of proportion for this case.

**External tool analysis (Codex):**
> If generation 1 is withdrawn, generation 2 starts, and generation 1's `add` finishes last, this call returns `.superseded` and performs no Notification Center operation. Adding a request with the same identifier at that point can replace generation 2's newer content, or leave the withdrawn generation visible if generation 2 failed to post. Serialize the posts or reassert the latest generation after an older completion so the newest logical alert wins.

### FINDING-16
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/AgentMeter/NotificationPresenter.swift (recordPosted, `.withdrawn`)
- **Category:** external
- **Source:** codex (final re-review, P2)
- **Round found:** 3
- **Resolution:** fixed (round 3)

**What is wrong:** A post withdrawn before its completion was logged as `credential sent` but never as `credential withdrawn`.

**How it was resolved:** The `.withdrawn` branch logs `credential withdrawn: <accountId>` after removing the notification again.

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/Notifications/CredentialHealth.swift:27-53
- **Category:** correctness
- **Source:** correctness-agent
- **Description:** Health is derived from entry state, so entries replayed without a request (reprice reuse, quick-retry kept entries, Codex not-due and blocked paths) count as working or failing rather than "unchanged" as FR-001 says for "a refresh without a request".
- **Rationale:** No wrong notification follows (a replay repeats the health the tracker already saw), but after an FR-004 reset (Codex live limits off and on quickly) a replay can become the baseline. Either document that a replay counts as its request's result, or carry a "request sent" marker.

### NOTABLE-2
- **File:** Sources/UsageCore/Notifications/CredentialAlertTracker.swift:90-128
- **Category:** correctness
- **Source:** correctness-agent
- **Description:** An expired episode can notify on a snapshot that did not read the credential again (a reprice or a Codex not-due replay), up to one refresh interval after the agent renewed the token.
- **Rationale:** Allowed by FR-001 and FR-005; a "credential read this refresh" marker would tighten it.

### NOTABLE-3
- **File:** Sources/AgentMeter/MenuBarOpener.swift:26-48
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** FR-013 relies on SwiftUI internals: an `NSStatusBarButton` found in the window tree and a window class name containing `MenuBarExtra`.
- **Rationale:** A SwiftUI update could break it silently; owning an `NSStatusItem` would remove the dependency. The new log line (FINDING-4) makes a break visible.

### NOTABLE-4
- **File:** Sources/UsageCore/Notifications/CredentialAlertTracker.swift:96-133
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Description:** Silent tracker decisions (failing baseline, episode started inside the expiry delay, result ignored after a directory change) leave no log line.
- **Rationale:** "I never got a notification" is the likely support question; one log line per transition (never per refresh) would answer it from the diagnostic log.

### NOTABLE-5
- **File:** Sources/AgentMeter/NotificationPresenter.swift, Sources/AgentMeter/App.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Description:** Notification Center removal, leftover removal at launch, queue dropping on withdraw, the log prefixes and the click behavior are verified only up to the UsageCore event.
- **Rationale:** Matches the project convention; the walkthrough runbook should cover these by hand.

## Post-Fix Spec Coverage

The fix rounds removed no requirement code (replacements only: `postedCredentials` became `CredentialPostLedger`, `dropdownVisible` became `visibleDropdownWindow`). All spec requirements verified after the fix loop: FR-001 to FR-015 still map to `CredentialHealth`, `CredentialAlertTracker`, `CredentialAlert`, `PendingNotificationQueue`, `CredentialPostLedger`, `NotificationPresenter`, `MenuBarOpener`, `Configuration.notifySignInProblems` and the Settings toggle.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| baseline | make test | 0 | 0 | passed (917 tests) |
| 1 | make test | 0 | 0 | passed (921 tests) |
| 2 | make test | 0 | 0 | passed (921 tests) |
| 3 | make test | 2 | build error | new ledger tests called mutating methods inside `#expect`; rewritten |
| 3 (final) | make test | 0 | 0 | passed (927 tests in 95 suites) |

`make app` built and signed after every round.

## Remaining Findings

None Critical or Important. Remaining Minor: FINDING-11 to FINDING-15 (optional refactors and a triaged ordering case), listed above with reasons.
