# Deep Review Findings

**Date:** 2026-10-13
**Branch:** 001-agentmeter
**Rounds:** 2 fix rounds (plus the spec compliance fix before deep review)
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline stage 7)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 11 | 11 | 0 |
| Minor | 32 | 7 | 25 |
| Notable | 11 | - | 11 |
| **Total** | **54** | **18** | **36** |

Counts are after deduplication. Two findings reported as Important were reclassified to Minor by the orchestrator with the reason recorded on the finding (FINDING-12, FINDING-13).

**Agents completed:** 5/5 internal (correctness, architecture, security, production readiness, test quality) + 1 re-review agent per fix round + CodeRabbit (3 runs)
**Agents skipped:** Goal Alignment (no PR exists for the branch), Copilot (disabled in config)
**Agents failed:** Codex (`codex review --base main` exited with a usage-limit error, no findings recorded)

Fix commits on the branch:

| Commit | Content |
|--------|---------|
| 9dbae20 | Spec compliance fix before deep review: every token-based account listed in the dropdown with its own breakdown (FR-004, FR-008) |
| 9e9e5f5 | Fix round 1: window shift undercount, empty group dead end, notification authorization race, cache-free URL session, zero-usage placeholder records, jq argument injection, 13 new tests |
| 6cdf844 | Fix round 2: denied notification permission no longer latched, pending queue deduplicated |

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 80
- **File:** Sources/UsageCore/Logs/LogIndex.swift:89-99, 145-148
- **Category:** correctness
- **Source:** correctness-agent (also reported by: coderabbit, severity major)
- **Round found:** 1
- **Resolution:** fixed (round 1, commit 9e9e5f5)

**What is wrong:**
The index pruned records with `timestamp < window.start` and skipped unchanged files on the next update. When the window start moved earlier between two refreshes (the user changed the fallback weekday, switched the alignment account, or the alignment account dropped to the fallback), the pruned records were gone and the unchanged files were not re-read. Only the within-one-refresh case was handled by the coordinator's re-run path.

**Why this matters:**
FR-023 requires all usage inside the current window to count. The weekly totals were silently undercounted until the file changed or the week rolled over, which also breaks SC-003.

**How it was resolved:**
`LogIndex` remembers the previous window start and starts over when the new start is earlier. The coordinator's within-refresh re-run keeps working on top of it. Test `earlierWindowStartBetweenUpdatesRecoversPrunedRecords` fails without the change.

**External tool analysis (CodeRabbit):**
> In SessionLogSource.collect, retain the window start used by the previous collection and reset LogIndex when the new context.window.start is earlier; then store the new start before calling index.update. This must also handle coordinator reruns that invoke collect with an earlier window.

### FINDING-2
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/AgentMeter/AccountSettingsView.swift:128-132, Sources/UsageCore/Config/Configuration.swift:365-368
- **Category:** correctness
- **Source:** correctness-agent (also reported by: architecture-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1, commit 9e9e5f5)

**What is wrong:**
Moving a token-based account to another group through the picker left the old group with zero members. Validation then rejected the whole configuration ("has no member accounts") and the Groups tab offers no delete action, so the settings window could not be saved.

**Why this matters:**
FR-019 says removing the last member of a group deletes the group. Only account deletion implemented this. The user ended in a validation error with no way out except moving the account back.

**How it was resolved:**
`Configuration.pruningEmptyGroups()` drops groups without members; the settings window applies it before validation on save and writes the pruned draft back. Test `pruningEmptyGroupsDropsGroupsLeftWithoutMembers` covers it.

### FINDING-3
- **Severity:** Important
- **Confidence:** 72
- **File:** Sources/AgentMeter/NotificationPresenter.swift:27-59
- **Category:** correctness
- **Source:** correctness-agent (also reported by: production-readiness-agent, coderabbit)
- **Round found:** 1
- **Resolution:** fixed (round 1, commit 9e9e5f5; refined in round 2, commit 6cdf844)

**What is wrong:**
Authorization was requested lazily on the first crossing and the notification was posted in the same synchronous pass. While the status was still undetermined, `UNUserNotificationCenter.add` fails with "notifications not allowed", so every crossing of the first batch after install was lost. The tracker had already advanced its baseline, so the crossing was never retried.

**Why this matters:**
FR-028 and SC-006 require exactly one notification per threshold per window. The very first notification after install, the one the US4 independent test exercises, produced only a "failed" log line.

**How it was resolved:**
The presenter now keeps an authorization state (unknown, requesting, granted, denied), queues crossings while a request is in flight, posts the queue once authorization is granted, and requests authorization at launch from the first snapshot so the prompt is answered long before the first crossing.

**External tool analysis (CodeRabbit):**
> Update the notification flow around requestAuthorizationIfNeeded so crossing notifications are not submitted before authorization completes; request authorization at app launch or defer posting crossings until the authorization callback confirms permission, while preserving delivery for already-authorized users.

### FINDING-4
- **Severity:** Important
- **Confidence:** 70
- **File:** Sources/UsageCore/Subscription/UsageEndpointClient.swift:26, 32-43
- **Category:** security
- **Source:** security-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, commit 9e9e5f5)

**What is wrong:**
The production client used `URLSession.shared`, which has a persistent on-disk URL cache and cookie store. The request carries the bearer token in the Authorization header and nothing opted out of caching, so a cacheable 200 response could store a serialized copy of the request, including its headers, in the CFNetwork cache database.

**Why this matters:**
FR-011a forbids copying the credential into any file; the contract says the token is never written. Whether a response got cached depended on server headers the app does not control.

**How it was resolved:**
The client defaults to an ephemeral session with no URL cache, no cookie storage, and a reload-ignoring-cache policy, and sets the same policy on each request so an injected session cannot cache either. Test `defaultSessionNeverPersistsRequestsOrCookies` pins the configuration.

### FINDING-5
- **Severity:** Important
- **Confidence:** 85
- **File:** Tests/UsageCoreTests/RefreshCoordinatorTests.swift:268-282
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, commit 9e9e5f5)

**What is wrong:**
`alignmentSurvivesProviderOutage` simulated the outage with a stale entry that still carried a status, so the coordinator could re-derive the reset from the entry on every refresh. The assertions held even if the coordinator never remembered the reset.

**Why this matters:**
The spec edge case about keeping the last fetched reset during an outage is about the coordinator's memory, which the test did not isolate.

**How it was resolved:**
A third phase feeds a stale entry with no status at all and asserts the window stays aligned to the remembered reset. The first refresh's window source is asserted too.

### FINDING-6
- **Severity:** Important
- **Confidence:** 85
- **File:** Tests/UsageCoreTests/LogIndexTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, commit 9e9e5f5)

**What is wrong:**
The attribution-fingerprint reset branch in `LogIndex.update` had no test; only the price-change branch was covered.

**Why this matters:**
FR-013 lets the user add a custom marker per account; the only way an already indexed file is re-attributed is this branch. A fingerprint missing a field would keep old attributions until restart without any test noticing.

**How it was resolved:**
`attributionRuleChangeRereadsUnchangedFiles` indexes the custom-marker fixture, re-runs with an identical attributor (no re-read), then adds an account with a custom marker and asserts the file is re-read and the EU record moves to the new account.

### FINDING-7
- **Severity:** Important
- **Confidence:** 80
- **File:** Tests/UsageCoreTests/LogIndexTests.swift:134-147
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, commit 9e9e5f5)

**What is wrong:**
`rereadsOnlyAppendedBytes` checked that a partial last line is not consumed but never completed the line on a later append and verified it is then parsed. The newline-free chunk path of `readCompleteLines` was also unexercised.

**Why this matters:**
The spec edge case implies the partial record is picked up once complete; an off-by-one in the consumed count would drop or duplicate it.

**How it was resolved:**
`partialLastLineIsParsedOnceCompleted` writes half a record, completes it on a later append, asserts the third record appears and the parsed offset equals the size, then appends a newline-free fragment and asserts it is read but not consumed.

### FINDING-8
- **Severity:** Important
- **Confidence:** 80
- **File:** Tests/UsageCoreTests/RefreshCoordinatorTests.swift, Tests/UsageCoreTests/ConfigurationTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, commit 9e9e5f5)

**What is wrong:**
The edge case "two subscription accounts with different reset timestamps, the designated one wins, defaulting to the first configured one" had no test; `effectiveAlignmentAccountId` was never called from a test.

**Why this matters:**
A regression that always used an arbitrary entry of the unordered subscriptions dictionary would pass the suite.

**How it was resolved:**
`effectiveAlignmentAccountDefaultsToFirstSubscription` covers the lookup; `designatedAlignmentAccountDecidesBetweenTwoSubscriptions` runs the coordinator with two subscription accounts, asserts the designated reset wins, rewrites the config without a designation, and asserts the first account's reset is used.

### FINDING-9
- **Severity:** Important
- **Confidence:** 80
- **File:** Tests/UsageCoreTests/LogIndexTests.swift:81-102
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, commit 9e9e5f5)

**What is wrong:**
`SessionLogSource.collect` was only exercised for the throw and empty cases. Directory deduplication, the attributor built with the injected paths, and the diagnostic log line were untested, and the scanner's and the attributor's separate canonical-path helpers were never checked for agreement.

**Why this matters:**
The directory tie-breaker of FR-013 only works while both helpers stay byte-identical; temp directories on macOS live under a symlinked path, exactly where they could drift.

**How it was resolved:**
`sourceScansDefaultAndConfiguredDirectoriesAndBreaksTiesByDirectory` runs the source over two directories under a test home, asserts the duplicate default directory is scanned once, that the records of each file go to the account whose credential directory contains it, and that the log line reports both files.

### FINDING-10
- **Severity:** Important
- **Confidence:** 82
- **File:** Tests/UsageCoreTests/AggregatorTests.swift:54-64, Tests/UsageCoreTests/ThresholdTrackerTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, commit 9e9e5f5)

**What is wrong:**
Percent rounding at exactly .5 was untested in all three rounding paths (group percent, bar percent, threshold tracker).

**Why this matters:**
FR-009a mandates nearest whole number; the two code paths use different APIs that happen to agree today. A later change would move threshold crossings without a failing test.

**How it was resolved:**
Added 50.5 and 49.5 percent group cases, `percentFormatterRoundsHalfAwayFromZero`, and `halfPercentRoundsUpToTheThreshold` (79.4 then 79.5 with threshold 80 yields one crossing at 80).

### FINDING-11
- **Severity:** Important
- **Confidence:** 80
- **File:** Sources/AgentMeter/NotificationPresenter.swift:47-59, 77-88
- **Category:** production-readiness
- **Source:** re-review-agent (round 1) (also reported by: coderabbit round 1)
- **Round found:** 2
- **Resolution:** fixed (round 2, commit 6cdf844)

**What is wrong:**
The round-1 state machine latched the denied state for the lifetime of the process. Enabling notifications later in System Settings had no effect until relaunch.

**Why this matters:**
A menu bar app runs for weeks; "deny at launch, enable later" is a normal path. FR-028 was then silently violated for the rest of the run, a regression against the pre-fix code.

**How it was resolved:**
A denied state re-queries authorization on the next crossing (the system does not prompt again once answered). The pending queue also keeps only the newest crossing per threshold and window so an unanswered prompt cannot end in a burst of stale notifications (the Minor queue finding of the same re-review).

**External tool analysis (CodeRabbit):**
> Update send's cached `.denied` path to refresh the current notification permission through `UNUserNotificationCenter` before dropping a crossing, and update `authorization` from the result so permission changes take effect without restarting the app.

### FINDING-12
- **Severity:** Minor (reported as Important, reclassified)
- **Confidence:** 70
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift:116-120, 153, 184
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:**
A failed source is classified as "record source" or "subscription source" by the unrelated trait `isWindowSensitive`; a second non-window-sensitive source would overwrite the single failure string, and `register` does not enforce unique names.

**Why this matters:**
The seam only works because there is exactly one source of each kind today. A future harness source would be misclassified into the wrong staleness path.

**Reclassification reason:** no current behavior is affected; FR-017 is about the stored configuration format, which is unaffected. Address when a second source is added: add an explicit `kind` trait to `UsageSource`, collect failures per source name, reject duplicate names in `register`.

### FINDING-13
- **Severity:** Minor (reported as Important, reclassified)
- **Confidence:** 70
- **File:** Sources/UsageCore/Logs/LogIndex.swift:101-111, 163-185
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:**
Changed files are read whole into memory and every line is copied a second time, for all changed files at once under `concurrentPerform`. On a cold start or after an index reset, peak memory is roughly twice the sum of the largest in-window files times the core count.

**Why this matters:**
Very long sessions produce files of tens of MB; a cold parse can spike well above the 100 MB SC-008 envelope for a few seconds.

**Reclassification reason:** SC-008 bounds the steady state between refreshes, which is unaffected; the incremental path reads only the tail. Suggested fix when needed: parse `Data` slices without per-line copies, or read in fixed chunks carrying the trailing partial line over, and bound parallelism.

### Remaining Minor findings

| ID | File | Source | Description | Suggested fix |
|----|------|--------|-------------|---------------|
| FINDING-14 | Sources/AgentMeter/SettingsView.swift:250-262 | correctness-agent, coderabbit | `ThresholdsField` seeds its text only in `onAppear`; switching the selection between two accounts or groups keeps the view identity, so the field shows the previous entity's thresholds and the first keystroke writes derived values into the newly selected entity | Give `AccountEditor` and `GroupEditor` an `.id(selection)` and sync the text on `thresholds` changes |
| FINDING-15 | Sources/UsageCore/Logs/Attribution.swift:63-69, 94-101 | correctness-agent | A custom marker replaces the account's built-in rule; FR-013 reads as additive. Adding a marker to the only Vertex account makes its ordinary sessions Unassigned | Keep the built-in rule alongside the marker (marker matches still win), or state the replace semantics in the spec and the settings label (spec evolution candidate) |
| FINDING-16 | Sources/UsageCore/Subscription/SubscriptionSource.swift:68-70, BarLabel.swift:66-68, DropdownView.swift | architecture-agent | `credentialsExpired` carries the previous status but no `lastGoodAt`; the bar shows `--` while the dropdown shows the old rows without a stale marker | Treat it as a stale variant with `lastGoodAt`, or return `status: nil` |
| FINDING-17 | Several files (RefreshCoordinator, Aggregator, LogIndex, Attribution, ...) | architecture-agent | Comments cite task ids and research section numbers (`T040`, `T055`, `research R3`, `tasks.md`) | Replace with FR numbers or a one-line statement of the behavior |
| FINDING-18 | Sources/UsageCore/Logs/LogIndex.swift:152-158, SessionRecordParser.swift:60 | architecture-agent | The dedupe key expression is written three times | One `dedupeKey` helper on both record types |
| FINDING-19 | Attribution.swift:113-117, LogDirectoryScanner.swift:85-89, SessionRecordParser.swift:101-115, UsageEndpointClient.swift:84-98, RefreshCoordinator.swift:274-276 | architecture-agent | `canonical(_:)` and the ISO 8601 formatter pair are duplicated; the coordinator allocates a formatter per call | `Paths.canonical(_:)` and a shared `ISO8601` helper |
| FINDING-20 | RefreshCoordinator.swift:176-179, 256-272, SubscriptionSource.swift:49, SessionLogSource.swift:52-57 | architecture-agent, production-readiness-agent | Every source outcome is logged twice per refresh with two formatting implementations | One owner per log line; sources return a note the coordinator logs |
| FINDING-21 | BarLabel.swift:93-95, Configuration.swift:198-199, UsageSnapshot.swift:18, SubscriptionSource.swift:73, DropdownView.swift | architecture-agent | Dead or write-only members: `BarLabelBuilder.plainText`, `PriceEntry.source` (UI decides by membership instead), `SubscriptionStatus.subscriptionType`, `GroupEntry.members` | Delete or use each |
| FINDING-22 | BarLabel.swift:117-122 | architecture-agent | `SubscriptionState.isStale` lives in the app target while `isOk` is in UsageCore | Move next to `isOk`, make public |
| FINDING-23 | RefreshCoordinator.swift:53, 57, 107-108 | architecture-agent | `previousSnapshot` and `latestSnapshot` never diverge | Remove one |
| FINDING-24 | RefreshCoordinator.swift:122-236 | architecture-agent | `performRefresh` is 115 lines interleaving window alignment, staleness carry-over, aggregation and logging | Extract four helpers |
| FINDING-25 | App.swift:103-108 | architecture-agent | `openLog` writes "log opened" once, only to create the file | `DiagnosticLog.ensureFileExists()` |
| FINDING-26 | Configuration.swift:340-350 | architecture-agent | `validate()` builds `Paths()` against the real home while everything else injects `Paths` | `validate(paths:)` with a default |
| FINDING-27 | RefreshCoordinator.swift:122-157 | production-readiness-agent | The first refresh after launch parses with the fallback window and, when the aligned window starts earlier, resets and parses everything again on roughly half of all launches | Collect the subscription source first, then run the log source once with the final window |
| FINDING-28 | KeychainCredentialReader.swift:22-41, SubscriptionSource.swift:29-42, App.swift:54-60 | production-readiness-agent | Keychain reads run in parallel per account and retry every refresh after a denial, so a user who clicked Deny or Allow-once gets dialogs on every tick; the first-launch presence check runs under the config store lock | Back off per account after `errSecUserCanceled` or `errSecAuthFailed`, serialize keychain reads, compute the default outside the lock |
| FINDING-29 | App.swift:187-205 | production-readiness-agent | On wake the handler and the timer's missed tick both fire, and the first request loses the race with Wi-Fi, so the bar shows stale for a full interval after every wake | Restart the timer on wake and delay the wake refresh a few seconds or retry once on network errors; log the trigger |
| FINDING-30 | UsageEndpointClient.swift:52-54 | production-readiness-agent | Non-200 responses are reduced to the status code; body, request id and `retry-after` are dropped | Carry the request id and the first 200 characters of the body in the error |
| FINDING-31 | DiagnosticLog.swift:22-37 | production-readiness-agent | Rotation keeps two generations of 5 MB, so the log occupies up to 10 MB while FR-036 names 5 MB | Rotate at half the cap, or truncate instead of rotating; also drop one of the duplicate per-source lines (FINDING-20) |
| FINDING-32 | Tests/UsageCoreTests/LogIndexTests.swift:20-23, 34-35 | test-quality-agent | Several index tests rely on the wall clock being past the fixed window start through file mtimes | Give `writeRecords` and `Fixtures.install` an explicit modification date |
| FINDING-33 | Tests/UsageCoreTests/ConfigStoreTests.swift | test-quality-agent | The "file deleted after a valid load" branch of `ConfigStore.load` is untested | Delete the file after a save and assert the last valid config is kept with an io error and no recreated file |
| FINDING-34 | Tests/UsageCoreTests/RefreshCoordinatorTests.swift | test-quality-agent | The `snapshots` stream the UI subscribes to is never read in a test | Consume one snapshot from the stream and compare with `latestSnapshot` |
| FINDING-35 | Tests/UsageCoreTests/AggregatorTests.swift | test-quality-agent | Records attributed to a configured subscription account absent from the subscriptions dictionary are emitted nowhere (reachable on first launch while offline); no test pins the intended outcome | Add a test asserting where such tokens belong, then adjust the aggregator if needed |
| FINDING-36 | Tests/UsageCoreTests/WindowResolverTests.swift:60-69 | test-quality-agent | The aligned roll-forward is not tested at exactly `now == resetsAt` | Add the boundary case |

### Fixed Minor findings

| ID | File | Source | Description | Resolution |
|----|------|--------|-------------|------------|
| FINDING-37 | SessionRecordParser.swift:17-51 | correctness-agent | Placeholder assistant records for API errors (model `<synthetic>`, all counts zero) were indexed and surfaced as unpriced models and Unassigned rows | Dropped at parse time; mirrored in `scripts/sum-vertex.sh`; test `dropsZeroUsagePlaceholderRecords` (round 1) |
| FINDING-38 | scripts/sum-vertex.sh:57-64 | security-agent | The window bounds were spliced into the jq program text; an unvalidated argument became jq code | Passed as `--arg` (round 1) |
| FINDING-39 | Tests/UsageCoreTests/RefreshCoordinatorTests.swift:190 | test-quality-agent | A disjunction whose left side is always true never checked the source error | Replaced with exact source-name and staleness assertions (round 1) |
| FINDING-40 | Tests/UsageCoreTests/ThresholdTrackerTests.swift:135-140 | test-quality-agent | The token-account test passed trivially because the snapshot carried no token accounts | Snapshot now carries token and Unassigned usage that rises between observations (round 1) |
| FINDING-41 | Tests/UsageCoreTests/AggregatorTests.swift | test-quality-agent | Output, cache-write 5m/1h and cache-read sums were never asserted per model or per day | `perModelAndPerDayTotalsCoverEveryTokenClass` (round 1) |
| FINDING-42 | Tests/UsageCoreTests/UsageEndpointClientTests.swift | test-quality-agent | The unparsable `resets_at` branch was untested | `unparsableResetDateIsADecodingError` (round 1) |
| FINDING-43 | NotificationPresenter.swift:23, 54-58 | re-review-agent (round 1) | The pending queue was unbounded and could flush a burst of stale crossings | Deduplicated per threshold and window, newest wins (round 2) |

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/Diagnostics/DiagnosticLog.swift:34-37
- **Category:** correctness
- **Source:** correctness-agent
- **Description:** Rotation keeps the live file plus one older generation, so the on-disk total is 10 MB while FR-036 says 5 MB.
- **Rationale:** Whether the cap applies to the live file or the total is a spec ambiguity worth settling.

### NOTABLE-2
- **File:** Sources/UsageCore/Notifications/ThresholdTracker.swift:92-102
- **Category:** correctness
- **Source:** correctness-agent
- **Description:** After a window reset the tracker records a baseline instead of treating the previous value as 0, so a window that starts above a threshold never notifies.
- **Rationale:** FR-028 mandates the baseline only for the first refresh after launch; the stricter reading would notify. A spec note would remove the ambiguity.

### NOTABLE-3
- **File:** Sources/UsageCore/Logs/SessionLogSource.swift:29-37
- **Category:** correctness
- **Source:** correctness-agent
- **Description:** A subscription account's credential directory is not scanned unless also listed under log directories, so the FR-013 directory tie-breaker needs the path in two settings.
- **Rationale:** Unioning the credential directories into the scan set would remove the duplication.

### NOTABLE-4
- **File:** Sources/UsageCore/Config/Configuration.swift:5-13, 77
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** `Account.harness` is stored but never read; scanner, parser and attributor have no seam keyed by harness.
- **Rationale:** FR-017 holds at the data-model level; a second harness will need a `HarnessAdapter` (layout, parser, rules).

### NOTABLE-5
- **File:** Sources/UsageCore/Config/ConfigStore.swift:49-64
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** A successful reload of a hand-edited configuration leaves no trace in the diagnostic log.
- **Rationale:** US3 scenario 4 promises pickup; the log cannot confirm it happened.

### NOTABLE-6
- **File:** Sources/UsageCore/Subscription/SubscriptionSource.swift:59-63, 87-90
- **Category:** security
- **Source:** security-agent
- **Description:** The credential-read error path falls back to `String(describing: error)`; the no-token guarantee holds by Foundation's error formatting, not by construction.
- **Rationale:** An allow-list mapping (fixed strings for decoding errors, type names otherwise) plus a sentinel test would make FR-011a hold by design.

### NOTABLE-7
- **File:** Sources/AgentMeter/KeychainCredentialReader.swift:43-47
- **Category:** security
- **Source:** security-agent
- **Description:** The first-launch presence check reads the full secret item to answer yes or no.
- **Rationale:** A `kSecReturnAttributes` query answers presence without materializing the token.

### NOTABLE-8
- **File:** Makefile:38
- **Category:** security
- **Source:** security-agent
- **Description:** The ad-hoc signature changes every build, so "Always Allow" on the keychain item stops working after each rebuild and each click edits the harness's keychain item ACL.
- **Rationale:** A stable signing identity (`SIGN_IDENTITY ?= -`) makes one consent persist.

### NOTABLE-9
- **File:** Sources/UsageCore/Logs/SessionLogSource.swift:42-49
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Description:** The directory scan and the parallel parse run synchronously inside an actor on the cooperative thread pool.
- **Rationale:** No deadlock today; a dedicated serial queue bridged with a continuation would keep the pool free when more sources arrive.

### NOTABLE-10
- **File:** Sources/AgentMeter/BarLabel.swift:30-95
- **Category:** test-quality
- **Source:** test-quality-agent
- **Description:** `BarLabelBuilder` implements FR-002, FR-003 and FR-005 as pure functions but lives in the untested app target.
- **Rationale:** Moving it (minus `attributed`) into UsageCore would let the threshold-glyph and ordering rules be unit tested.

### NOTABLE-11
- **File:** Sources/UsageCore/Logs/LogIndex.swift:70-76, Sources/UsageCore/Snapshot/RefreshCoordinator.swift:144-157
- **Category:** architecture
- **Source:** re-review-agent (round 1)
- **Description:** After the round-1 fix the index restarts itself on an earlier window start, and the coordinator's `resetForEarlierWindow` path does the same thing a second way; only the coordinator path logs it.
- **Rationale:** One mechanism should remain, and the index should report the restart so the log explains the full re-read.

## Goal Alignment

Skipped: no pull request exists for the branch, so no declared goals could be extracted beyond the spec, which the compliance matrix in REVIEW-CODE.md covers.

## Post-Fix Spec Coverage

Fix rounds removed lines in the notification presenter (rewritten), the dropdown group section (restructured) and the test files (assertions replaced). The requirements behind the removed code were re-verified:

| Requirement | Implementation | Status |
|-------------|---------------|--------|
| FR-004: dropdown lists all accounts and groups | DropdownView.swift GroupSection member rows, SubscriptionSection | ✓ |
| FR-008: breakdown and trend per group and token-based account | DropdownView.swift GroupSection (group and per-member BreakdownView) | ✓ |
| FR-009, FR-016: Unassigned entry, unpriced flagging | Aggregator.swift unchanged; SessionRecordParser.swift drops only zero-usage records | ✓ |
| FR-011a: credentials never written | UsageEndpointClient.swift defaultSession, SubscriptionSource.swift unchanged | ✓ |
| FR-019: last member removal deletes the group | Configuration.swift removingAccount(id:) and pruningEmptyGroups() | ✓ |
| FR-023: only usage inside the window counts | LogIndex.swift lastWindowStart restart, Aggregator.swift filter | ✓ |
| FR-028: one notification per threshold per window | NotificationPresenter.swift post(_:), ThresholdTracker.swift unchanged | ✓ |

All spec requirements verified after the fix loop.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| 1 | make test | 0 | 0 | passed (128 tests in 15 suites, after correcting one expectation in a newly added test) |
| 2 | make test | 0 | 0 | passed (128 tests in 15 suites) |

The app target was rebuilt with `make build` after every round. Test suite passed in all fix rounds.
