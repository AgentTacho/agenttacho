# Deep Review Findings

**Date:** 2026-10-22
**Branch:** 035-additional-session-directories
**Rounds:** 3 (initial review; re-review of round 1 fixes by an internal agent, CodeRabbit and Codex; CodeRabbit and Codex on round 2 fixes). The one round 3 finding was fixed and verified by the test suite.
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline, oversight: never)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 6 | 6 | 0 |
| Minor | 18 | 18 | 0 |
| Notable | 3 | - | 3 |
| **Total** | **27** | **24** | **3** |

**Agents completed:** 5/5 internal (Goal Alignment skipped: no PR), plus CodeRabbit and Codex.
**Agents failed:** none. Copilot is disabled in the deep review configuration.

Two further Notables (correctness FINDING-2, architecture FINDING-3) reported the same issue as FINDING-1 below and were merged into it.

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/UsageCore/Logs/Attribution.swift, Sources/UsageCore/Logs/LogIndex.swift, Sources/UsageCore/Logs/CodexSessionSource.swift
- **Category:** correctness
- **Source:** coderabbit (also reported by: correctness-agent, architecture-agent as Notable)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The attribution fingerprint held the configured entries but not their matches, while the FR-012 tie-breaker used the matches. When the claims on an already indexed directory changed without a configuration change, for example when a match left the cap of 100, a matched symlink went away, or a listing failed for one refresh, the indexed records kept their old account.

**Why this matters:**
Sessions stayed Unassigned or on the wrong subscription account until the file or the configuration changed.

**How it was resolved:**
The additional entries left the fingerprint. `Attributor.claimKey(forDirectory:)` names the subscription accounts that could use an additional claim on a directory (only kinds with more than one account). `LogIndex` keeps the key per directory and rereads only the files of a directory whose key changed, or of a file now reached through another directory. The Codex source stores the key with the built records and rebuilds them from the parsed sessions when it changes. An edited list therefore rereads only the folders whose claims changed, never the whole index. Tests: `changedClaimReattributesOnlyThatFolder`, `claimKeyFollowsTieBreakClaims`, `fingerprintIgnoresAdditionalDirectories`, the Codex `additionalClaimSeparatesTwoSubscriptionsEndToEnd`.

**External tool analysis (CodeRabbit):**
> Update LogIndex.update to recompute attribution for already-indexed directories when their canonical wildcard match claims change, including after a refresh. Preserve the existing fingerprint behavior so a membership change does not force rereading every session file.

### FINDING-2
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/UsageCore/Logs/WildcardExpander.swift
- **Category:** production-readiness
- **Source:** production-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The cap of 100 bounded the output of an expansion but not its work. An accepted broad entry such as `~/Library/*/*/sessions` listed and stat-ed every intermediate candidate on every refresh, then checked each candidate twice more.

**Why this matters:**
A mistyped entry could block a source actor for seconds on every refresh and trigger macOS privacy prompts.

**How it was resolved:**
Each level keeps at most `WildcardExpander.levelBudget` (1000) candidates in path order. A truncated expansion is reported once through `WildcardCapLog`. The final folder check is skipped when the last component was a wildcard, and the expander returns canonical paths that the resolver reuses. Tests: `levelBudgetBoundsTheWork`, `truncatedLevelIsLoggedOnce`.

### FINDING-3
- **Severity:** Important
- **Confidence:** 85
- **File:** Sources/UsageCore/Logs/SessionLogSource.swift, Sources/UsageCore/Logs/CodexSessionSource.swift (tests)
- **Category:** test-quality
- **Source:** test-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
No source-level test depended on passing `resolution.additionalByAccount` to the `Attributor`. Every test would have passed if a source passed an empty map.

**Why this matters:**
This wiring is the whole user-visible effect of FR-012.

**How it was resolved:**
Added `additionalClaimSeparatesTwoSubscriptionsEndToEnd` for Claude Code (LogIndexTests) and Codex (CodexAdditionalHomeTests): two subscriptions of one kind, a session in one account's listed folder goes to it, a new folder follows, and the same folder listed on both leaves the sessions Unassigned.

### FINDING-4
- **Severity:** Important
- **Confidence:** 85
- **File:** Sources/UsageCore/Logs/OpenCodeSource.swift
- **Category:** correctness
- **Source:** re-review agent
- **Round found:** 2
- **Resolution:** fixed (round 2)

**What is wrong:**
The round 1 stamp for unchanged OpenCode matches used `attributesOfItem`, which does not follow a final symlink. An `opencode.db` link to a database inside the matched folder kept a constant stamp, so the database was never opened again.

**Why this matters:**
New usage behind such a link would have been missed silently.

**How it was resolved:**
The stamp is taken from the resolved database path, next to which SQLite keeps the `-wal` file. Test: `changeBehindAnInFolderLinkIsRead`.

### FINDING-5
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/UsageCore/Logs/OpenCodeSource.swift
- **Category:** external
- **Source:** codex
- **Round found:** 2
- **Resolution:** fixed (round 2)

**What is wrong:**
A cached match whose database lost its read access (`chmod 000`) keeps its size and date, so the stamp shortcut returned cached records as fresh, without an issue or the stale marker.

**Why this matters:**
FR-013 requires a matched database to be handled like a literal one: an unreadable database is an issue and marks OpenCode stale.

**How it was resolved:**
The shortcut also requires the database to be readable; otherwise it goes through the read and its error handling. Test: `unchangedButUnreadableMatchIsAnIssue`.

**External tool analysis (Codex):**
> After a wildcard-matched database has been cached, making it unreadable (for example, with `chmod 000`) leaves its size and modification date unchanged. This shortcut consequently returns cached records as fresh, with no issue or stale marker.

### FINDING-5b
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/UsageCore/Logs/OpenCodeSource.swift
- **Category:** external
- **Source:** codex
- **Round found:** 3
- **Resolution:** fixed (after round 3, verified by `make test`)

**What is wrong:**
The readability check of FINDING-5 covered the database but not its `-wal` file. With read access to `opencode.db-wal` revoked, the stamps stay the same and the shortcut returned cached records as fresh, although SQLite can no longer open the database.

**Why this matters:**
Same as FINDING-5: FR-013 requires an issue and the stale marker.

**How it was resolved:**
`OpenCodeSource.isReadable(database:)` requires the database and, when present, its `-wal` file to be readable before the shortcut is taken. Test: `unchangedMatchWithUnreadableWALIsAnIssue`.

**External tool analysis (Codex):**
> After a wildcard-matched WAL database is cached, revoking read access to `opencode.db-wal` leaves both stamps unchanged and the main database readable. This shortcut then returns cached records as fresh, although SQLite now fails with `unable to open database file`.

### FINDING-6
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/UsageCore/Logs/LogDirectoryScanner.swift, CodexSessionSource.swift, OpenCodeSource.swift
- **Category:** security
- **Source:** security-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** A sandbox copy could ship `projects`, `sessions` or `opencode.db` as a link to the home folder, `/` or another host database, and the scanner followed it.
**Why this matters:** It bypasses FR-006 and FR-009 one level down, with full tree walks and privacy prompts.
**How it was resolved:** For additional directories and OpenCode matches, a session tree or database whose canonical path is outside the directory is skipped with `<dir>: skipped, <name> is a link outside the directory`. Main directories are unchanged. Tests: `projectsLinkOutsideAnAdditionalDirectoryIsSkipped`, `sessionsLinkOutsideAnAdditionalHomeIsSkipped`, `databaseLinkOutsideAMatchIsSkipped`.

### FINDING-7
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/UsageCore/Logs/WildcardExpander.swift
- **Category:** security
- **Source:** security-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The bare `*` refusal is string-based, so another spelling of the home folder (case, firmlink, symlink) let `*` list every home subfolder.
**How it was resolved:** At expansion time a bare `*` never lists a parent whose canonical path is the home folder or `/`; the parent is reported as not listed with the refusal reason. Test: `bareStarUnderAnotherSpellingOfHomeIsNotListed`.

### FINDING-8
- **Severity:** Minor
- **Confidence:** 78
- **File:** Sources/UsageCore/Logs/OpenCodeSource.swift, SessionDirectoryResolver.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** OpenCode duplicated the report construction and log loops, and the resolver had a dead `.openCode` path.
**How it was resolved:** `WildcardReport.init(_:)` and `WildcardReport.listingLines` are shared by all three sources, the resolver returns an empty resolution for OpenCode, and OpenCode dedups matches by canonical path. The resolver's home and `/` filter stays, because it also covers literal entries.

### FINDING-9
- **Severity:** Minor
- **Confidence:** 76
- **File:** Sources/UsageCore/Logs/LogDirectoryScanner.swift, WildcardExpander.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** Three canonical-path helpers, and the resolver's canonical path was thrown away.
**How it was resolved:** `ScanTarget` carries the resolver's canonical path, the scanner's private copy is gone (it uses `Attributor.canonical`), and `LocalDirectoryFileSystem.canonicalPath` documents that any implementation must agree with `Attributor.canonical`.

### FINDING-10
- **Severity:** Minor
- **Confidence:** 80
- **File:** Sources/UsageCore/Logs/SessionDirectoryResolver.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** A local `isSubscription` meant "Claude or Codex subscription" next to `AccountKind.isSubscription` (Claude only), with a lookup per entry.
**How it was resolved:** `AdditionalSessionEntry.joinsTieBreak` is set in `Configuration.additionalSessionEntries(for:)`.

### FINDING-11
- **Severity:** Minor
- **Confidence:** 75
- **File:** LogDirectoryScanner.swift, SessionLogSource.swift, CodexSessionSource.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** `scan(directories:)`, `directories(for:)` and `homes(for:)` were public, used only by tests, with long doc comments that restated the resolver's rules.
**How it was resolved:** They are internal test helpers with short comments that point to `SessionDirectoryResolver`.

### FINDING-12
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/AgentTacho/AccountSettingsView.swift, Sources/UsageCore/Config/AccountDirectoryText.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** Three editors repeated the same section construction, and the text helpers quietly accept `.openCode`.
**How it was resolved:** `AdditionalSessionDirectoriesSection(harness:directories:)` is used at all three call sites, and the text helpers document that no account has the OpenCode harness.

### FINDING-13
- **Severity:** Minor
- **Confidence:** 75
- **File:** Sources/UsageCore/Logs/WildcardExpander.swift
- **Category:** production-readiness
- **Source:** production-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** Listing errors dropped their reason, and a folder deleted between the check and the listing was reported as an error.
**How it was resolved:** `WildcardListingError` carries the reason (`cannot list <path>: <reason>`), and ENOENT or ENOTDIR from the listing is `.missing`.

### FINDING-14
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Logs/Attribution.swift
- **Category:** production-readiness
- **Source:** production-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, together with FINDING-1)

**What is wrong:** Any edit to any account's list emptied the whole Claude Code index.
**How it was resolved:** The entries are out of the fingerprint; only directories whose claim key changed are read again.

### FINDING-15
- **Severity:** Minor
- **Confidence:** 70
- **File:** Sources/UsageCore/Logs/OpenCodeSource.swift
- **Category:** production-readiness
- **Source:** production-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, refined in round 2 by FINDING-4 and FINDING-5)

**What is wrong:** Up to 100 matched databases were opened and queried on every refresh, even when unchanged.
**How it was resolved:** A matched database is opened again only when the size or date of the database or its `-wal` file changed. Test: `unchangedMatchIsNotOpenedAgain`.

### FINDING-16
- **Severity:** Minor
- **Confidence:** 72
- **File:** Sources/UsageCore/Logs/OpenCodeSource.swift
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** A literal OpenCode entry listed after a wildcard that also matched it took the wildcard's silent skip, losing its spec 006 problem report.
**How it was resolved:** Literal locations are resolved first. Test: `literalAfterWildcardKeepsItsProblemReport`.

### FINDING-17 to FINDING-23
- **Severity:** Minor
- **Category:** test-quality
- **Source:** test-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

- FINDING-17: two main claims plus one additional claim were untested; added `twoMainClaimsStayUnassignedDespiteOneAdditional`.
- FINDING-18: the SubscriptionSource SC-004 test used the real home folder and a dead fixture; it now uses `Paths(home:)` with credential files in the literal and matched folders.
- FINDING-19: unreadable content under additional targets was untested; added `unreadableFolderUnderAdditionalProjectsIsOnlyNoted` and `unreadableRolloutUnderAdditionalHomeIsOnlyLogged`.
- FINDING-20: refusal bypass spellings (`~/./*`, `~//*/claude`, `/./*`, `~//`, `/Users/tester/.`) were added to the refusal tests.
- FINDING-21: expander edge cases added: two `*` levels, exactly 100 matches, `/` through a symlink, a self-referencing link.
- FINDING-22: the cap line for OpenCode and the listing line format were untested; added `capLineIsLoggedOnce` (OpenCode) and `listingLinesNameTheReason`.
- FINDING-23: the "additional snapshots never feed plan limits" test had no positive control; it now shows the same snapshot in the main home gives a `.snapshot` observation.

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/Logs/CodexSessionSource.swift
- **Category:** security
- **Source:** security-agent
- **Description:** Sessions from main and additional homes share one id space for the parent lookup, so a sandbox rollout with the id of a host session could decide the host session's auth mode.
- **Rationale:** Needs a known or copied session id; worth keying by origin or letting main homes win later.

### NOTABLE-2
- **File:** Sources/UsageCore/Logs/WildcardExpander.swift
- **Category:** production-readiness
- **Source:** production-agent
- **Description:** Above 100 matches the cap keeps the first 100 in name order, so with timestamped sandbox names the newest folders are the ones dropped.
- **Rationale:** A spec choice (FR-005); a later spec could order by modification date or make the cap configurable.

### NOTABLE-3
- **File:** Tests/UsageCoreTests/CodexSessionSourceTests.swift
- **Category:** test-quality
- **Source:** test-agent
- **Description:** Two Codex session tests used an unreadable `auth.json` as if it proved the file is never opened.
- **Rationale:** The comments now say what the tests show and point to the recording reader tests for SC-004.

## Post-Fix Spec Coverage

The fix loop removed only duplicated code (the scanner's private canonical helper, the OpenCode report construction, the resolver's account lookup). All spec requirements verified after the fix loop:

| Requirement | Implementation | Status |
|-------------|---------------|--------|
| FR-001 to FR-003 | Configuration.swift, AccountSettingsView.swift (`AdditionalSessionDirectoriesSection`) | ✓ |
| FR-004, FR-005 | WildcardExpander.swift, WildcardCapLog.swift | ✓ |
| FR-006, FR-007 | SessionDirectoryEntry.swift, Configuration.swift, WildcardExpander.swift | ✓ |
| FR-008, FR-009 | SessionDirectoryResolver.swift, LogDirectoryScanner.swift, CodexSessionSource.swift | ✓ |
| FR-010, FR-011 | CodexLimitsSource.swift (unchanged), Attribution.swift | ✓ |
| FR-012 | Attribution.swift (`accountId`, `claimKey`), LogIndex.swift, CodexSessionSource.swift | ✓ |
| FR-013 | OpenCodeSource.swift | ✓ |
| FR-014 to FR-017 | AccountDirectoryText.swift, README.md, docs/configuration.md, docs/development.md | ✓ |

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| 1 | make test | 0 | 0 | passed (2064 + 70 tests) |
| 2 | make test | 0 | 0 | passed (2066 + 70 tests) |
| 3 | make test | 0 | 0 | passed (2067 + 70 tests) |

`make app-demo` built the app after round 1, and again after the final round.

## Remaining Findings

None at Critical or Important severity.
