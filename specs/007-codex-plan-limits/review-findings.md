# Deep Review Findings

**Date:** 2026-10-14
**Branch:** 007-codex-plan-limits
**Rounds:** 1 fix round (plus a Minor follow-up)
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 5 | 5 | 0 |
| Minor | 26 | 6 | 20 |
| Notable | 4 | - | 4 |
| **Total** | **35** | **11** | **24** |

Counts are after deduplication. The redirect issue was reported by three agents (security, architecture, test quality), and the not-due state bug by two (correctness, architecture).

**Agents completed:** 5/5 internal (Goal Alignment skipped: no PR found), plus 2 external tools (CodeRabbit, Codex). Copilot was skipped (disabled in config).
**Agents failed:** none.

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 85
- **File:** Sources/UsageCore/Subscription/CodexLimitsSource.swift (`.notDue` branch of `collect`)
- **Category:** correctness
- **Source:** correctness-agent (also reported by: architecture-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The `.notDue` branch checked `lastLive[id]` before `lastFailure[id]`. When a fetch had failed after an earlier success, the next refresh that made no request (a reprice, or a manual refresh within the 60 s spacing) showed the old live result as `.live` again. It also ignored a newer snapshot.

**Why this matters:**
FR-006 lets a skipped refresh keep the live state only for a result that is still current. The flip also broke the "a value never jumps back and fires twice" guarantee behind FR-015. Example: live 70%, then a newer snapshot at 85% shown stale (the 80% threshold fires), then a reprice shows 70% as live, then the next failure shows 85% again, and the 80% notification fires a second time.

**How it was resolved:**
A recorded failure now takes precedence: the entry goes through `fallback` (the newer of the live result and the snapshot, still stale with the failure reason). Only without a failure does the kept live result stay `.live`. New test: `notDueAfterAFailureStaysStale`. data-model.md transition updated.

### FINDING-2
- **Severity:** Important
- **Confidence:** 80
- **File:** Sources/UsageCore/Subscription/CodexUsageClient.swift; Tests/UsageCoreTests/CodexUsageClientTests.swift
- **Category:** security
- **Source:** security-agent (also reported by: architecture-agent, test-quality-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The client used the shared `UsageEndpointClient.defaultSession`, a plain `URLSession` with no delegate, so it followed HTTP 3xx redirects automatically. It never checked where the answer came from. No test covered redirects.

**Why this matters:**
FR-019 allows contact with `https://chatgpt.com/backend-api/wham/usage` only. A redirect would send the request, with `Authorization: Bearer <token>` and `ChatGPT-Account-ID`, to another host. That breaks FR-019 and risks leaking the credential (FR-018). With the guard removed, the new test showed that the stub received a second request to the redirect target.

**How it was resolved:**
- `CodexUsageClient` now has its own ephemeral, cache-free and cookie-free session with `timeoutIntervalForResource = 45`.
- Every request passes a task delegate whose `willPerformHTTPRedirection` returns nil, so this holds for any injected session.
- A refused redirect surfaces as `httpStatus(3xx)`.
- An answer from an unexpected scheme, host or path is rejected.
- `StubURLProtocol` gained a redirect mode, and `redirectIsRefused` asserts the 302 error and that no request reached the other host.
- The contract table and README were updated.

### FINDING-3
- **Severity:** Important
- **Confidence:** 85
- **File:** Sources/UsageCore/Snapshot/UsageSnapshot.swift (`PercentFormatter.rounded`)
- **Category:** security
- **Source:** security-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
Both Codex parsers accept any finite `used_percent`, and `PercentFormatter.rounded` then converts the value to `Int` without a range check. A value such as `1e19` traps in Swift.

**Why this matters:**
A snapshot counts at any age (FR-004), so one corrupt rollout line or a bad service answer would crash the app on every refresh, starting at launch. That is a crash loop, and it also violates FR-021.

**How it was resolved:**
`PercentFormatter.rounded` clamps to +/- 1e9 before converting. Tests for `1e19` and `-1e19` were added. The snapshot parser also rejects non-finite `resets_at`.

### FINDING-4
- **Severity:** Important
- **Confidence:** 85
- **File:** Sources/UsageCore/Subscription/CodexLimitsSource.swift
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, refined after the re-review)

**What is wrong:**
After an HTTP 401, every scheduled refresh sent the same rejected bearer token again (about 288 requests a day at the default interval). This went on until Codex rewrote `auth.json`.

**Why this matters:**
Sending a revoked token to an undocumented third-party service over and over, from a background app, looks like abuse. It can trigger account protection, and the answer cannot change until the credential does.

**How it was resolved:**
- A SHA-256 digest of a token rejected with 401 is kept in memory per Codex home and is never logged or persisted.
- While the token in `auth.json` matches the digest, no request is made. The entry shows stale "Codex sign-in rejected, run Codex to renew it" and still reports the source error (FR-006).
- The digest clears on a successful fetch, when the home leaves the configuration, on a manual refresh, or when live limits are turned off (added after the round-1 re-review).
- A 403 is still retried, because it can come from the service front end rather than from the sign-in.
- Tests: `rejectedTokenIsNotSentAgain` and `forbiddenTokenIsRetried`. The 401 phase of `codexHomeIsNeverChanged` was moved last.

### FINDING-5
- **Severity:** Important
- **Confidence:** 85
- **File:** Tests/UsageCoreTests/CodexLimitsSourceTests.swift (`turningLiveOffDiscardsTheLiveResult`)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The test passed even without `lastLive[account.id] = nil`, because the live-off branch never reads `lastLive`.

**Why this matters:**
FR-005 requires discarding kept live results when live limits are off. A regression would bring a stale pre-toggle live value back after the setting is turned on again.

**How it was resolved:**
The test now turns live limits back on with the service offline. It asserts that the snapshot (14:20) is shown, not the discarded live result (15:00).

### Minor findings fixed

- **Threshold mode mismatch** (correctness): ThresholdTracker now skips entries computed under the other live-limits setting and keeps their state (FR-015). Tests: `entryOfTheOtherSettingIsSkipped`, plus updated toggle and plan-change tests.
- **Log detail** (architecture, production): the FR-020 log note now carries the error description (`request failed: usage endpoint returned HTTP 401`) and the reason for skipped requests. Only the app's own error types are described, never token text.
- **Non-finite `resets_at`** (architecture, part of the duplication finding): the parser now rejects it, as the client already did.
- **End-to-end leak check** (test quality): `codexHomeIsNeverChanged` now checks the real reader's log for the token, the refresh and id token sentinels, and the account id.
- **Reset-passed state retention** (test quality): `resetPassedWindowIsSkipped` now seeds state and checks that it survives.
- **Round-1 re-review:** a manual refresh or a live-limits toggle allows a rejected token to be tried again, and the 403 retry behavior has a test.

## Remaining Findings (all Minor)

These do not block the gate.

- **CodeRabbit:** `lastFetchAt` is also recorded for transport failures, so a manual refresh within 60 s of an offline failure does not retry. This matches the spacing rule of spec 001, so it was kept.
- **Security F3:** `CodexCredential` has no `CustomReflectable`. `dump()` or `Mirror` would show the token. No such call exists today.
- **Security F4 / Production F4:** unbounded reads. `auth.json` and every rollout file are read whole. A cold scan of a home without plan snapshots reads all history on the first refresh.
- **Production F2:** ~~`Retry-After` is not capped.~~ Resolved by decision (see Resolved Ambiguities).
- **Architecture F4:** the coordinator's Codex carry-over branch is reachable only through a test fake, because `collect` never throws. The name is also duplicated as `CodexLimitsSourceName`.
- **Architecture F5:** window validation is duplicated between the parser and the client.
- **Architecture F6:** unreachable branches remain: `case nil` in the fetch result switch, and the "no live limits yet" default.
- **Architecture F7:** the client's `observedAt` is overwritten by the source.
- **Architecture F8:** `batchIssueCount` now also counts Codex account errors.
- **Test quality F4, F5, F6, F7, F9 to F15:** gaps in coverage or verification method:
  - coordinator-level leak test
  - URLError leak case
  - `rate_limit_reached_type` without a 100% window
  - forked child snapshot
  - US1-3 percent update
  - US2-2 expired with a snapshot
  - dropdown text mapping untested (app target)
  - account removal cleanup
  - growing rollout file
  - carry-over edge cases
  - FR-020 log lines per path

## Resolved Ambiguities

The code review left three spec ambiguities. The user decided them on 2026-10-14; the spec Clarifications record each one.

1. **Newer local snapshot between fetches (FR-005 vs FR-006): resolved.** When no request was due (`.local` trigger or spacing) and the last attempt did not fail, the newest of the kept live result and the newest snapshot is shown without stale marking. A newer snapshot gets the new state `CodexLimitsState.newerSnapshot`: unstyled bar, "As of <time>" in the dropdown, threshold keys still follow the live-limits setting. A newer live result stays `.live`. After a failure the selection stays stale, as before. FR-005, FR-006, research R6 and data-model.md updated. Tests: `notDueShowsANewerSnapshotWithoutStaleMarking`, `notDueKeepsALiveResultNewerThanTheSnapshot`, `notDueAfterAFailureShowsANewerSnapshotAsStale`, `newerSnapshotIsNotStale`, `newerSnapshotUsesTheLiveKeys`.
2. **401 suppression and 403 retry: resolved, kept as implemented.** FR-003 now states the rule: after an HTTP 401 the same token is not sent again until Codex replaces it, the user refreshes manually, live limits are turned off and on, a later fetch for that Codex home succeeds, or the app restarts. A 403 is retried on the normal schedule. No code change.
3. **Retry-After cap (Production F2): resolved.** A stated wait counts up to one hour (`CodexLimitsSource.maximumRetryAfter = 3600`); a longer one counts as one hour. Only the Codex gate changed; the Claude `EndpointPolicy` is untouched. FR-007 amended. Test: `retryAfterIsCappedAtOneHour`.

The Claude usage client redirect hardening (NOTABLE-3) stays out of scope; it is tracked in `brainstorm/idea-inbox.md` as `claude-client-redirect-guard`.

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/Subscription/CodexLimitsSource.swift (collect)
- **Category:** correctness
- **Source:** correctness-agent
- **Description:** The actor reads state before `await withTaskGroup` and writes it afterwards. Reentrant `collect` calls would interleave.
- **Rationale:** Today the RefreshCoordinator serializes refreshes. A second caller would break this assumption without any visible sign.

### NOTABLE-2
- **File:** Sources/UsageCore/Subscription/CodexLimitsSource.swift, Sources/UsageCore/Logs/CodexSessionSource.swift
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Description:** Both sources enumerate and parse the same rollout files on every refresh.
- **Rationale:** Extracting the snapshot during the existing token parse would halve the I/O for active sessions.

### NOTABLE-3
- **File:** Sources/UsageCore/Subscription/UsageEndpointClient.swift
- **Category:** production-readiness / security
- **Source:** production-readiness-agent, security-agent
- **Description:** The Claude usage client still uses a session that follows redirects and has no resource timeout. The Codex client now has its own guarded session.
- **Rationale:** The same FR-011a reasoning applies to the Claude token. This is outside the scope of spec 007.

### NOTABLE-4
- **File:** Sources/UsageCore/Subscription/*
- **Category:** security
- **Source:** security-agent
- **Description:** Verified clean:
  - token flow only through locals and the request
  - fixed error strings
  - no writes to a Codex home
  - no refresh-token decode or refresh endpoint
  - live limits off means no read and no request
  - JWT `exp` used only to skip requests
- **Rationale:** Recorded as evidence for the security focus of this review.

## Post-Fix Spec Coverage

The fix rounds only added or reordered code; nothing was deleted. Spot check: FR-001 to FR-021 still map to the implementation listed in REVIEW-CODE.md. All spec requirements were verified after the fix loop.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| baseline | make test | 0 | 0 | passed (551 tests) |
| 1 (first run) | make test | 1 | 1 | `codexHomeIsNeverChanged` expected 5 requests; the 401 phase now suppresses the token, so the phase order was adjusted |
| 1 | make test | 0 | 0 | passed (555 tests) |
| follow-up | make test | 0 | 0 | passed (556 tests) |
| ambiguity decisions | make test | 0 | 0 | passed (562 tests) |
