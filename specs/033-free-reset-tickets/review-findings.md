# Deep Review Findings

**Date:** 2026-10-21
**Branch:** 033-free-reset-tickets
**Rounds:** 1
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 5 | 5 | 0 |
| Minor | 13 | 8 | 5 |
| Notable | 5 | - | 5 |
| **Total** | **23** | **13** | **10** |

**Agents completed:** 5/5 internal (Goal Alignment skipped: no PR), plus 2 external tools (CodeRabbit, Codex). Copilot is disabled in config.
**Agents failed:** none. Codex could not run `swift test` in its sandbox, so its runtime validation is incomplete. `make test` ran locally.

The counts are after merging duplicates: Correctness FINDING-2 and Architecture FINDING-3 report the same gap.

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 80
- **File:** Tests/UsageCoreTests/SubscriptionSourceTests.swift (suspend test)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, b9a1ee5)

**What is wrong:** The test of the "plain result alone decides" rule (FR-004, Clarification Q2) compared two runs that answered both the flagged and the plain request with 403. If `attempt` returned the flagged error instead of the plain one, the test would still pass.

**Why this matters:** SC-004 requires a test proving that a refused flag never changes the usage figures or credential health.

**How it was resolved:** `plainFailureAloneDecidesTheEntryAfterARefusal` answers 400 to the flag and 500 to the plain repeat. It compares the result with a control run that saw only the 500 and was never repeated, and checks that a 400-only run differs from that control.

### FINDING-2
- **Severity:** Important
- **Confidence:** 80
- **File:** Tests/UsageCoreTests/SubscriptionSourceTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, b9a1ee5)

**What is wrong:** No test pinned the rule that a 5xx answer to the flagged request is not repeated. Widening the guard to `code >= 400` would double the requests during every server outage, and no test would fail.

**Why this matters:** SC-005 allows only one extra Claude request, the repeat after a client-error refusal (FR-004).

**How it was resolved:** `serverErrorsAreNeverRepeated` (500, 503) asserts the exact request sequences `flag, flag` and then `flag, flag, flag`.

### FINDING-3
- **Severity:** Important
- **Confidence:** 78
- **File:** Tests/UsageCoreTests/SubscriptionSourceTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, b9a1ee5)

**What is wrong:** The contract fixture "HTTP 400 then 500 plain" was checked only for one refresh. Nothing showed that the suspended flag survives further failed plain requests and returns only after a plain success.

**Why this matters:** FR-004 says "each refusal costs at most one extra request". If the flag were reset to on after a failed plain request, every refresh during an outage would cost two requests.

**How it was resolved:** `suspendedFlagSurvivesFailedPlainRequests` runs two more failed plain refreshes, then a plain success, then checks that the flag returns, asserting the exact sequence and the kept tickets at each step.

### FINDING-4
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/AgentTacho/NotificationPresenter.swift:205
- **Category:** external
- **Source:** codex
- **Round found:** 1
- **Resolution:** fixed (round 1, 2626be3)

**What is wrong:** Expiry reminders queued while permission was pending were posted when permission was granted, even if the user had turned the switch off in the meantime.

**Why this matters:** FR-017 says that turning the switch off stops expiry notifications.

**How it was resolved:** `PendingNotificationQueue.dueExpiries(_:notify:now:)` (UsageCore, tested) decides at drain time. With the switch off, every queued reminder is dropped and logged as "not sent (switch off)". A reminder whose expiry has passed is dropped as "not sent (expired while queued)". The presenter reads the switch through a closure on the configuration store.

**External tool analysis (Codex):**
> If an expiry reminder queues while notification permission is pending, turning off "Notify before a free limit reset expires" does not remove it. Granting permission subsequently posts it unconditionally here, despite the switch being off.

### FINDING-5
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/UsageCore/Notifications/ResetTicketExpiryTracker.swift:32-34
- **Category:** external
- **Source:** codex
- **Round found:** 1
- **Resolution:** fixed (round 1, 2626be3)

**What is wrong:** When the user changes an account's Claude Code directory or Codex home while a refresh is running, the snapshot from the old refresh is checked against the new configuration. The tracker matched only by account id, so it notified and recorded the previous login's tickets under the account. Codex accounts with live limits off were not excluded either.

**Why this matters:** A reminder about tickets that belong to another login is wrong, and its record entry suppresses a later reminder for the same expiry time.

**How it was resolved:** The tracker now does what `CredentialAlertTracker` does. Each account has an identity: the Claude Code directory, or the Codex home with live limits on. `configurationChanged(_:now:)` sets a fence for an account whose identity is new or changed, and the tickets of snapshots generated before the fence are ignored. `AppModel.saveConfiguration` calls it. Codex accounts with live limits off never notify, and their record entries stay until the account is removed. Tests: `ResetTicketExpiryTrackerFenceTests`.

**External tool analysis (Codex):**
> Unlike `CredentialAlertTracker`, this tracker has no configuration-change timestamp or identity fence. Ignore snapshots started before an account's identity changed and exclude Codex accounts whose live limits were disabled.

### FINDING-6
- **Severity:** Minor
- **File:** Sources/UsageCore/Notifications/PendingNotificationQueue.swift
- **Category:** correctness
- **Source:** correctness-agent
- **Resolution:** fixed (round 1, 2626be3)

If permission stayed pending while a group moved from the 3-day to the 24-hour step, both alerts were posted at once, and expired ones were posted too. Now a queued alert for the same account and expiry time is replaced by the newer step, and expired alerts are dropped at drain time (see FINDING-4).

### FINDING-7
- **Severity:** Minor
- **File:** Sources/UsageCore/Subscription/SubscriptionSource.swift, CodexLimitsSource.swift
- **Category:** correctness
- **Source:** correctness-agent (also reported by: architecture-agent)
- **Resolution:** fixed (round 1, 2626be3)

A changed Claude Code directory or Codex home did not reset `loggedTicketFailures`. A second flag drop for the new sign-in therefore went unlogged (FR-019). Both sources now reset it, and the comment no longer attributes the flag reset to FR-004. Test: `directoryChangeLogsADroppedFlagAgain`.

### FINDING-8
- **Severity:** Minor
- **File:** Sources/UsageCore/Subscription/ResetTickets.swift:55
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** fixed (round 1, 2626be3)

The label "malformed" was used for both a temporary failure (an undecodable usage answer) and a clearing failure (a bad block). The first one logged in a run hid the other for the rest of that run. The temporary kind is now "undecodable".

### FINDING-9
- **Severity:** Minor
- **File:** Sources/UsageCore/Subscription/ResetTickets.swift:142
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** fixed (round 1, 2626be3)

`present(_:)` was declared `throws` but never threw. The `throws` and the `try` at its call sites are removed.

### FINDING-10
- **Severity:** Minor
- **File:** Sources/AgentTacho/App.swift, NotificationPresenter.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** fixed (round 1, 2626be3)

A queued expiry reminder left no log line until it was posted or denied (FR-019 says to log them "as threshold notifications are"). The presenter now logs "queued (authorization pending): ..." when it queues one.

### FINDING-11
- **Severity:** Minor
- **File:** Sources/UsageCore/Notifications/ResetTicketNoticeStore.swift:28
- **Category:** security
- **Source:** security-agent
- **Resolution:** fixed (round 1, 2626be3)

A stored epoch near `Int64.max` loaded as 2^63 and trapped when it was written back, so one malformed entry in the defaults domain caused a crash loop. Entries are now read only when the epoch lies between 0 and the end of year 9999. Tested in `defaultsStoreIgnoresUnparsableEntries`.

### FINDING-12
- **Severity:** Minor
- **File:** Tests/UsageCoreTests/SubscriptionSourceTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** fixed (round 1, b9a1ee5)

The 401/429 test asserted `sent().last == "flag"`, which also passes if nothing was sent. It now checks the exact sequence.

### FINDING-13
- **Severity:** Minor
- **File:** Tests/UsageCoreTests/CodexLimitsSourceTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** fixed (round 1, b9a1ee5)

The not-due Codex step could pass because of a fresh read. It now asserts that the plan-limit and credit request counts do not change.

### FINDING-14 (remaining)
- **Severity:** Minor
- **File:** Sources/UsageCore/Subscription/SubscriptionSource.swift, CodexLimitsSource.swift
- **Category:** architecture
- **Source:** architecture-agent

Both sources duplicate the ticket bookkeeping (`lastTickets`, `loggedTicketFailures`, the once-per-kind log line). A small `ResetTicketLedger` in UsageCore would hold it in one place. This is a refactor only, with no behavior change.

### FINDING-15 (remaining)
- **Severity:** Minor
- **File:** Sources/UsageCore/Subscription/UsageEndpointClient.swift:160-170
- **Category:** architecture
- **Source:** architecture-agent

`fetch(token:includeTickets:)` uses a Bool to decide whether `tickets` is nil, which leaves a dead `?? .tickets([])` at the call site. Splitting it into `fetch` and `fetchWithTickets` would remove it. This is an API cleanup.

### FINDING-16 (remaining)
- **Severity:** Minor
- **File:** Sources/AgentTacho/NotificationPresenter.swift
- **Category:** architecture
- **Source:** architecture-agent

The bundle and authorization gate is now written three times (crossings, credential alerts, expiry alerts). A shared `dispatch` helper would keep future changes in one place.

### FINDING-17 (remaining, needs a spec decision)
- **Severity:** Minor
- **File:** Sources/UsageCore/Subscription/ResetTickets.swift:116-131
- **Category:** security
- **Source:** security-agent

The Codex decoder has no limit on the raw `credits` list (Claude grants are capped at 200). A very large list of non-available credits passes the 50-usable check. Adding a limit changes contracts/external-sources.md.

### FINDING-18 (remaining, needs a spec decision)
- **Severity:** Minor
- **File:** Sources/UsageCore/Subscription/SubscriptionSource.swift:407-419
- **Category:** production-readiness
- **Source:** production-readiness-agent

The HTTP code of a flag refusal, and the flag moving into and out of `.suspended`, are not logged. Logging them changes the log texts in contracts/texts.md.

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/Subscription/CodexLimitsSource.swift:559-565
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Description:** The credit request runs on the snapshot's critical path, so a slow credit endpoint adds up to 10 s to every Codex refresh.
- **Rationale:** FR-005 says the request "never holds up the refresh". The timeout limits the delay but does not remove it.

### NOTABLE-2
- **File:** Sources/UsageCore/Subscription/CodexLimitsSource.swift
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Description:** There is no backoff and no off-for-run state for a credit endpoint that keeps failing. `Retry-After` on a credit 429 is ignored.
- **Rationale:** A credit endpoint that has gone away doubles the requests to chatgpt.com. Changing this needs an amendment to FR-001.

### NOTABLE-3
- **File:** Sources/UsageCore/Subscription/SubscriptionSource.swift:410-419
- **Category:** security
- **Source:** security-agent
- **Description:** A 403 answer to the flagged request is repeated without the flag, although the app treats 403 as a rejected sign-in elsewhere.
- **Rationale:** FR-004 names 403 explicitly, and the cost is bounded to one repeat.

### NOTABLE-4
- **File:** Sources/UsageCore/Notifications/ResetTicketExpiryTracker.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** The notice record stores steps that were emitted, not steps that were posted.
- **Rationale:** This matches threshold notifications. A step lost while permission is denied never returns.

### NOTABLE-5
- **File:** Sources/UsageCore/Subscription/SubscriptionSource.swift, CodexLimitsSource.swift
- **Category:** correctness
- **Source:** correctness-agent
- **Description:** If the user switches login in the same directory and the next ticket read fails, the previous login's tickets stay visible.
- **Rationale:** FR-003 allows this. Closing the gap needs a credential fingerprint and a spec decision.

All five were captured to brainstorm/idea-inbox.md.

## Post-Fix Spec Coverage

The fix round added code and tests and removed none of the feature's behavior. Step 7b was checked anyway: FR-001 to FR-021 still map to the same implementation, and FR-014, FR-017 and FR-018 are now stricter (identity fence, drain-time checks). All spec requirements were verified after the fix loop.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| baseline | make test | 0 | 0 | passed (1868 + 70) |
| 1 | make test | 0 | 0 | passed (1877 + 70) |

`make build` (release) is also clean. The only warnings are in files this feature did not touch.

## Remaining Findings

None at Critical or Important. The five remaining Minor findings (FINDING-14 to FINDING-18) do not block. FINDING-17 and FINDING-18 change a contract, so they need a decision by the maintainer.

## Maintainer Decisions (2026-10-21)

- **FINDING-17: fixed.** The Codex credit list is capped at 200 records like Claude's grants (`codexTooManyCreditRecordsClears`); contracts/external-sources.md updated.
- **FINDING-18: fixed.** The flag-dropped and flag-suspended log lines name the refusal's status (`flag-dropped-http-<code>`, `flag-suspended-http-<code>`); contracts/texts.md updated, tests extended.
- **NOTABLE-1: spec reworded.** FR-005 now says the credit request adds at most 10 seconds to a refresh and never makes it fail.
- **NOTABLE-2: idea inbox** (`codex-credit-backoff`).
- **NOTABLE-3: kept** as FR-004 states it.
- **NOTABLE-4, NOTABLE-5: kept** (allowed by the spec; in the idea inbox).
- **FINDING-14 to FINDING-16: left** as refactors for a later cleanup.

`make test` after the decisions: 1878 + 70 passed.
