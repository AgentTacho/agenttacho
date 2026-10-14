# Review Findings

**Date:** 2026-10-14
**Branch:** 007-codex-plan-limits ([#2](https://github.com/rhuss/agentmeter/pull/2))
**Rounds:** 1
**Gate Outcome:** PASS (after fix round 1)
**Invocation:** standalone

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 1 | 1 | 0 |
| Minor | 20 | - | 0 |
| Notable | 3 | - | 2 |
| **Total** | **24** | **22** | **2** |

Minor and Notable fixes were applied too (the user chose "apply all suggested fixes"); 22 of 24 findings are fixed. Tests: 576 pass (562 before, 14 new).

**Reviewers completed:** 9/10 (copilot: disabled). Codex and CodeRabbit ran as command reviewers; CodeRabbit reported no findings.

## Findings

### FINDING-2
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Config/Configuration.swift:720-720
- **Category:** security
- **Source:** security
- **Round found:** 1
- **Resolution:** fixed (round 1)
- **Verdict:** confirmed

**What is wrong:**
Duplicate Codex home validation compares paths.expand(...) which does not resolve symlinks or `..`, while CodexLimitsSource keys rejectedTokens/gates by Attributor.canonical; a live-off account on a symlinked alias clears rejectedTokens[home] each refresh, so a 401-rejected token is resent on every refresh (FR-003) and the credential of a live-off home is read (FR-019).

**Suggested fix:**
Validate duplicates with Attributor.canonical(paths.expand(...)); only clear rejectedTokens when no live-on account uses that canonical home.

**How it was resolved:**
Configuration.validate now compares Attributor.canonical(paths.expand(...)); CodexLimitsSource only clears a rejected token when no live-on account uses that canonical home. Tests: aliasedCodexHomeIsInvalid, aliasedHomesShareOneRequestAndTheRejection.

### FINDING-4
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/UsageCore/Notifications/ThresholdTracker.swift:158-158
- **Category:** gator
- **Source:** gator
- **Round found:** 1
- **Resolution:** fixed (round 1)
- **Verdict:** confirmed

**What is wrong:**
When the Codex entry has no observation, the tracker keeps all codexPlan keys for the account including the other live-setting prefix, so toggling live limits off (entry unavailable) and on again reuses the old baseline and fires a crossing instead of a fresh baseline (FR-015).

**Suggested fix:**
Retain only keys whose windowKind rawValue has the prefix codex-<live|local>- matching the current setting.

**How it was resolved:**
Without a usable entry, the tracker keeps only the keys of the current live-limits setting (WindowKind.codexPrefix). Test: toggleWhileUnavailableStartsANewBaseline.

### FINDING-5
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Notifications/ThresholdTracker.swift:166-166
- **Category:** correctness
- **Source:** correctness
- **Round found:** 1
- **Resolution:** fixed (round 1)
- **Verdict:** confirmed

**What is wrong:**
The guard `let windowEnd = window.resetsAt else { continue }` also skips windows whose source never provided a reset time (reset_at/resets_at optional in both parsers), so those windows never fire threshold notifications (FR-014) although the bar shows warning style.

**Suggested fix:**
Distinguish raw-missing reset (evaluate with .distantFuture) from passed reset (skip).

**How it was resolved:**
A window the source gave no reset time is evaluated with .distantFuture; only a passed reset is skipped. Test: windowWithoutResetTimeIsChecked.

### FINDING-6
- **Severity:** Notable
- **Confidence:** 70
- **File:** Sources/UsageCore/Notifications/ThresholdTracker.swift:569-569
- **Category:** architecture
- **Source:** architecture
- **Round found:** 1
- **Resolution:** fixed (round 1)
- **Verdict:** weak

**What is wrong:**
matchesLiveLimits encodes CodexLimitsState-to-live-setting mapping inside the notification tracker; belongs on the model.

**Suggested fix:**
Consider CodexLimitsState.impliedLiveLimits.

**How it was resolved:**
Moved to CodexLimitsState.impliedLiveLimits; ThresholdTracker.matchesLiveLimits removed. Test: impliedLiveLimits.

### FINDING-7
- **Severity:** Minor
- **Confidence:** 72
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift:297-297
- **Category:** architecture
- **Source:** architecture
- **Round found:** 1
- **Resolution:** fixed (round 1)
- **Verdict:** confirmed

**What is wrong:**
batchIssueCount now also counts per-account Codex limit source errors (line 338) but its name still says batch issues.

**Suggested fix:**
Rename (e.g. nonFatalSourceErrorCount) and update comment at 394-398.

**How it was resolved:**
Renamed to isolatedErrorCount with updated comments.

### FINDING-8
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift:348-393
- **Category:** architecture
- **Source:** architecture
- **Round found:** 1
- **Resolution:** fixed (round 1)
- **Verdict:** confirmed
- **Contradiction:** CONTRA-1

**What is wrong:**
Codex limits failure/carry-over path in the coordinator is unreachable in production: CodexLimitsSource.collect never throws, so the branch (346-353) and carry-over block (380-393) only run for test stubs; it also introduces a name-string check and duplicates CodexLimitsState transition rules.

**Suggested fix:**
Delete the branch, or mark the source by protocol and put stale conversion on CodexLimitsEntry (markedStale(reason:)).

**How it was resolved:**
Kept as a safeguard (see CONTRA-1); the name check uses CodexLimitsSource.sourceName and the stale conversion moved to CodexLimitsEntry.markedStale(reason:).

### FINDING-9
- **Severity:** Notable
- **Confidence:** 75
- **File:** Sources/UsageCore/Snapshot/UsageSnapshot.swift:441-441
- **Category:** goal-alignment
- **Source:** goal-alignment
- **Round found:** 1
- **Resolution:** informational (Notable)
- **Verdict:** weak

**What is wrong:**
PercentFormatter.rounded now clamps to +/-1e9 for every caller (Claude, budgets), an undeclared behaviour change.

**Suggested fix:**
Mention in PR description.

**How it was resolved:**
Informational, no change.

### FINDING-10
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/UsageCore/Subscription/CodexCredentialReader.swift:84-86
- **Category:** goal-alignment
- **Source:** goal-alignment
- **Round found:** 1
- **Resolution:** fixed (round 1)
- **Verdict:** weak
- **Calibrated Severity:** Important -> Minor

**What is wrong:**
When auth.json is missing, the reader also opens and parses <codexHome>/config.toml (cli_auth_credentials_store) but the PR goal says AgentMeter only reads auth.json and the README Privacy list (README.md:145) omits config.toml.

**Suggested fix:**
Add config.toml to the README privacy bullet and PR description, or drop the check and use noPlanSignIn.

**How it was resolved:**
README privacy list now names the one config.toml setting read when auth.json is missing.

### FINDING-11
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/UsageCore/Subscription/CodexLimits.swift:6-6
- **Category:** architecture
- **Source:** architecture
- **Round found:** 1
- **Resolution:** fixed (round 1)
- **Verdict:** confirmed

**What is wrong:**
Module-level public let CodexLimitsSourceName (UpperCamelCase) duplicates CodexLimitsSource.sourceName; other sources use only a static sourceName.

**Suggested fix:**
Delete the global; use CodexLimitsSource.sourceName in coordinator and tests.

**How it was resolved:**
Global CodexLimitsSourceName removed; CodexLimitsSource.sourceName is the only definition.

### FINDING-12
- **Severity:** Minor
- **Confidence:** 85
- **File:** Sources/UsageCore/Subscription/CodexLimitsSource.swift:57-57
- **Category:** architecture
- **Source:** architecture
- **Round found:** 1
- **Resolution:** fixed (round 1)
- **Verdict:** confirmed

**What is wrong:**
Attempt.liveLimits field is always true; the comparison at line 269 effectively only compares the home.

**Suggested fix:**
Replace Attempt with attemptedHome: [String: String] or keep only home.

**How it was resolved:**
Attempt replaced by attemptedHome: [String: String].

### FINDING-13
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/UsageCore/Subscription/CodexLimitsSource.swift:163-170
- **Category:** external
- **Source:** codex
- **Round found:** 1
- **Resolution:** fixed (round 1)
- **Verdict:** confirmed

**What is wrong:**
When two accounts use alternate spellings of the same Codex home (`..` or symlink), configuration permits them but both plans share the canonical home; the loop launches one task per plan before the shared gate updates, so each scheduled refresh sends duplicate requests with the same sign-in.

**Suggested fix:**
Coalesce plans by canonical home or reject canonical aliases during validation.

**How it was resolved:**
One request per canonical Codex home per refresh (results keyed by home); aliases are also rejected by validation. Test: aliasedHomesShareOneRequestAndTheRejection.

### FINDING-15
- **Severity:** Minor
- **Confidence:** 72
- **File:** Sources/UsageCore/Subscription/CodexLimitsSource.swift:238-239
- **Category:** architecture
- **Source:** architecture
- **Round found:** 1
- **Resolution:** fixed (round 1)
- **Verdict:** confirmed

**What is wrong:**
Unreachable `case nil` in the .fetch branch and the reason literal "no live limits yet" duplicated at 201 and 239 while other reasons are static lets.

**Suggested fix:**
Add static let noLiveLimitsYetReason; replace case nil with preconditionFailure/guard.

**How it was resolved:**
static noLiveLimitsYetReason; the impossible missing result is a guard with assertionFailure and a safe fallback.

### FINDING-16
- **Severity:** Notable
- **Confidence:** 75
- **File:** Sources/UsageCore/Subscription/CodexLimitsSource.swift:395-395
- **Category:** production-readiness
- **Source:** production
- **Round found:** 1
- **Resolution:** informational (Notable)
- **Verdict:** confirmed

**What is wrong:**
CodexSessionSource and CodexLimitsSource each enumerate and parse the same sessions tree every refresh, doubling I/O for long sessions.

**Suggested fix:**
Extract the snapshot in the same parse pass or share a file index.

**How it was resolved:**
Not changed: sharing one parse pass between CodexSessionSource and CodexLimitsSource is a larger refactor; the live-result bound (FINDING-17) already removes the second read after successful fetches.

### FINDING-17
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/UsageCore/Subscription/CodexLimitsSource.swift:402-419
- **Category:** production-readiness
- **Source:** production
- **Round found:** 1
- **Resolution:** fixed (round 1)
- **Verdict:** confirmed

**What is wrong:**
newestSnapshot only stops early once a snapshot is found; for homes with no plan snapshot every rollout file is read in full on the first refresh after each launch (in-memory cache), blocking the serialized launch refresh.

**Suggested fix:**
Bound by file count/age, skip when a newer live result exists, or scan tails first.

**How it was resolved:**
Partly: the scan now stops at files no newer than the kept live result, and a successful fetch scans nothing (FR-004 'any age' kept, so no file-count cap). A home with no snapshot and no live result is still scanned in full once per launch. Test: liveResultBoundsTheSnapshotScan.

### FINDING-18
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Subscription/CodexLimitsSource.swift:408-408
- **Category:** production-readiness
- **Source:** production
- **Round found:** 1
- **Resolution:** fixed (round 1)
- **Verdict:** confirmed

**What is wrong:**
When contents(atPath:) returns nil for a rollout file the loop silently continues without logging, unlike CodexSessionSource:157, and retries each refresh.

**Suggested fix:**
Log via log?.append like CodexSessionSource.

**How it was resolved:**
Unreadable rollout files are logged as '<home>: error: cannot read <path>'. Test: unreadableRolloutFileIsLogged.

### FINDING-19
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Subscription/CodexUsageClient.swift:114-114
- **Category:** architecture
- **Source:** architecture
- **Round found:** 1
- **Resolution:** fixed (round 1)
- **Verdict:** confirmed

**What is wrong:**
observedAt is stamped by the client clock and always overwritten with `now` in CodexLimitsSource.live (line 310); two owners of the observation time.

**Suggested fix:**
Pass observedAt into fetch or drop the overwrite.

**How it was resolved:**
CodexUsageClient.fetch(_:observedAt:) takes the refresh time; the client clock only parses Retry-After.

### FINDING-20
- **Severity:** Minor
- **Confidence:** 72
- **File:** Sources/UsageCore/Subscription/CodexUsageClient.swift:169-175
- **Category:** architecture
- **Source:** architecture
- **Round found:** 1
- **Resolution:** fixed (round 1)
- **Verdict:** confirmed

**What is wrong:**
Window validation (finite percent, length bounds, minute rounding, finite reset) duplicated between CodexUsageClient.Window.window() and CodexSessionParser.limitSnapshot (177-187).

**Suggested fix:**
Add a failable CodexLimitWindow.init?(minutes:usedPercent:resetEpoch:) used by both.

**How it was resolved:**
Shared CodexLimitWindow.init?(minutes:usedPercent:resetEpoch:) used by the client and the parser. Test: windowFromSourceValues.

### FINDING-21
- **Severity:** Important
- **Confidence:** 85
- **File:** Tests/UsageCoreTests/CodexLimitsSourceTests.swift:211-211
- **Category:** test-quality
- **Source:** test-quality
- **Round found:** 1
- **Resolution:** fixed (round 1)
- **Verdict:** confirmed

**What is wrong:**
Snapshot cache invalidation on append to an existing rollout file is untested; dropping the size/modificationDate comparison in newestSnapshot (CodexLimitsSource.swift:405) would pass all tests.

**Suggested fix:**
Append a newer token_count line to the cached file, bump mtime, assert new values and lastFilesParsed == 1.

**How it was resolved:**
Test appendedSnapshotInACachedFileIsRead (mutation-checked: fails if the size/date comparison is dropped).

### FINDING-22
- **Severity:** Minor
- **Confidence:** 70
- **File:** Tests/UsageCoreTests/CodexLimitsSourceTests.swift:351-351
- **Category:** test-quality
- **Source:** test-quality
- **Round found:** 1
- **Resolution:** fixed (round 1)
- **Verdict:** confirmed

**What is wrong:**
logNamesSourceTimeAndReason only checks the describe(entry) prefix; FR-020 skip/failure notes are never asserted.

**Suggested fix:**
Assert full log lines for failed fetch, not-due, rate-limit block, live off.

**How it was resolved:**
logNamesSourceTimeAndReason asserts the 'request failed' note; new logNamesWhyNoRequestWasMade covers fetched, not due, rate limited and live off.

### FINDING-23
- **Severity:** Minor
- **Confidence:** 75
- **File:** Tests/UsageCoreTests/CodexLimitsSourceTests.swift:614-614
- **Category:** test-quality
- **Source:** test-quality
- **Round found:** 1
- **Resolution:** fixed (round 1)
- **Verdict:** confirmed

**What is wrong:**
FR-003 release of a rejected token by toggling live limits off and on is untested.

**Suggested fix:**
After 401, collect with liveLimits false then true; assert request count increases.

**How it was resolved:**
rejectedTokenIsNotSentAgain now covers the off/on toggle release.

### FINDING-24
- **Severity:** Minor
- **Confidence:** 85
- **File:** Tests/UsageCoreTests/CodexSessionParserTests.swift:253-253
- **Category:** test-quality
- **Source:** test-quality
- **Round found:** 1
- **Resolution:** fixed (round 1)
- **Verdict:** confirmed
- **Calibrated Severity:** Important -> Minor

**What is wrong:**
reachedMarksTheFullWindow uses a fixture at used_percent 100, so the >=100 rule alone marks it reached and rate_limit_reached_type parsing (CodexSessionParser.swift:186) is never exercised.

**Suggested fix:**
Add a fixture with reached-type and windows below 100 (97/40), assert [true,false].

**How it was resolved:**
Test reachedTypeMarksTheHighestWindowBelowFullPercent (mutation-checked).

### FINDING-25
- **Severity:** Minor
- **Confidence:** 75
- **File:** Tests/UsageCoreTests/CodexSessionParserTests.swift:260-260
- **Category:** test-quality
- **Source:** test-quality
- **Round found:** 1
- **Resolution:** fixed (round 1)
- **Verdict:** confirmed

**What is wrong:**
Forked-file test expects nil because the child's only post-fork token_count has rate_limits null; a parser ignoring all snapshots in forked files would also pass.

**Suggested fix:**
Give the child event a real rate_limits object and assert it is returned.

**How it was resolved:**
Test forkedFileGivesTheChildSnapshot.

### FINDING-26
- **Severity:** Minor
- **Confidence:** 85
- **File:** Tests/UsageCoreTests/RefreshCoordinatorTests.swift:1090-1090
- **Category:** test-quality
- **Source:** test-quality
- **Round found:** 1
- **Resolution:** fixed (round 1)
- **Verdict:** confirmed
- **Calibrated Severity:** Important -> Minor

**What is wrong:**
entrySourceErrorBecomesASourceError never asserts lastSuccessfulRefreshAt, so removing the batchIssueCount increment (which keeps one account's error from failing the whole refresh) would go unnoticed.

**Suggested fix:**
Assert snapshot.lastSuccessfulRefreshAt == snapshot.generatedAt.

**How it was resolved:**
entrySourceErrorBecomesASourceError asserts lastSuccessfulRefreshAt.

### FINDING-27
- **Severity:** Minor
- **Confidence:** 75
- **File:** Tests/UsageCoreTests/RefreshCoordinatorTests.swift:1104-1104
- **Category:** test-quality
- **Source:** test-quality
- **Round found:** 1
- **Resolution:** fixed (round 1)
- **Verdict:** confirmed
- **Contradiction:** CONTRA-1

**What is wrong:**
failingSourceCarriesPreviousEntriesOverAsStale only covers the .live state; .newerSnapshot, .localOnly/.stale/.unavailable, sourceError clearing and removed accounts are not covered.

**Suggested fix:**
Parameterize over previous states and add removed-account case.

**How it was resolved:**
markedStaleKeepsLocalAndFailedStates covers every state; failingSourceCarriesOnlyConfiguredAccountsWithoutTheirErrors covers sourceError clearing, .newerSnapshot and removed accounts.

## Agent Quality Scores

| Agent | Findings | Precision | Signal/Noise |
|-------|----------|-----------|--------------|
| architecture | 8 | 0.9 | 2.0 |
| test-quality | 7 | 0.71 | 2.5 |
| production | 4 | 0.75 | 1.5 |
| goal-alignment | 3 | 0.67 | 0.5 |
| security | 2 | 0.85 | 1.0 |
| correctness | 1 | 0.9 | 1.0 |
| gator | 1 | 1.0 | 1.0 |
| codex | 1 | 0.9 | 1.0 |

**Meta-review summary:**
- Findings removed (false positive): 3
- Findings calibrated: 4 (3 Important -> Minor, 1 removed)
- Contradictions detected: 1 (CONTRA-1: FINDING-8 wants the coordinator carry-over deleted, FINDING-27 wants it tested; resolved by keeping it on CodexLimitsEntry.markedStale and testing every state)

## Removed Findings (Meta-Review)

### FINDING-1 (removed as false-positive)
- **Severity:** Notable
- **File:** Sources/UsageCore/Config/Configuration.swift:313
- **Category:** security
- **Source:** security
- **Verdict:** false-positive
- **Reasoning:** liveLimits defaulting to on for existing configs is required by FR-016/FR-017 and documented in the README.

### FINDING-3 (removed as false-positive)
- **Severity:** Notable
- **File:** Sources/UsageCore/Notifications/ThresholdTracker.swift:8
- **Category:** goal-alignment
- **Source:** goal-alignment
- **Verdict:** false-positive
- **Reasoning:** The WindowKind struct refactor is planned in research.md R8 and plan.md.

### FINDING-14 (removed as false-positive)
- **Severity:** Minor
- **File:** Sources/UsageCore/Subscription/CodexLimitsSource.swift:231
- **Category:** production-readiness
- **Source:** production
- **Verdict:** false-positive
- **Reasoning:** FR-003 explicitly says a 403 is not remembered and the token is sent again on the normal schedule (test forbiddenTokenIsRetried).

## Goal Delivery

| Goal | Status |
|------|--------|
| 1. Plan windows, bar entry, threshold notifications | Delivered |
| 2. Live limits, read-only sign-in, no redirects | Delivered (README now lists the config.toml read) |
| 3. Stale fallback to the newest snapshot | Delivered |
| 4. Windows from the data, longest in bar, critical when reached | Delivered |
| 5. Settings and defaults | Delivered |
| 6. Part A follow-ups | Delivered |

## Test Suite Results

- Before fixes: 562 tests in 63 suites passed.
- After fixes: 576 tests in 63 suites passed (`make test`).
- Mutation check: dropping the cache size/date comparison, the reached-type parsing, or the tracker's prefix filter each fails exactly its new test.
