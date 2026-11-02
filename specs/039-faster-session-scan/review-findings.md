# Deep Review Findings

**Date:** 2026-10-28
**Branch:** 039-faster-session-scan
**Rounds:** 1 fix round, re-reviewed
**Gate Outcome:** PASS (the last Important finding fixed after the maintainer's decision, 46a01de)
**Invocation:** quality-gate (ship pipeline, stage review-code)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 4 | 4 | 0 |
| Minor | 16 | 11 | 5 (deferred to brainstorm/idea-inbox.md by the maintainer) |
| Notable | 4 | - | 4 (captured to brainstorm/idea-inbox.md) |
| **Total** | **24** | **15** | **9** |

**Agents completed:** 5/5 internal (Goal Alignment skipped, no PR), plus CodeRabbit and Codex. Copilot is disabled in the configuration.

Spec outcome gaps, recorded in BENCHMARK.md and classified Ambiguous (maintainer decisions, not code findings):

- **SC-001 with SC-002**: under 3 s only with the corpus fully cached (2.910 s at 210%); the runs that read from disk stay at or below 200% (167 to 194%) but take 3.1 to 4.0 s. FR-020 routes this to the maintainer.
- **SC-006**: the Codex reader uses 58% of the baseline CPU, not at most half.
- The cold runs, the real-corpus digest repeat, the in-app incremental check and the responsiveness check are maintainer walkthrough steps (FR-006, FR-009).

## Findings

### FINDING-1
- **Severity:** Important
- **File:** Sources/UsageCore/Bench/ScanBench.swift:142-151
- **Category:** external (security)
- **Source:** Codex
- **Resolution:** fixed (5c55f50)

**What is wrong:** The digest refusal covered the agents' directories, the scanned directory and the configured ones, but not the `projects` or `sessions` tree inside them. When that tree is a link to a shared folder elsewhere, a digest path naming a file in the shared folder passed, and the atomic write replaced the session file.

**Why this matters:** FR-004 says the digest is never written under the agents' directories; the app treats session files as read-only.

**How it was resolved:** The `projects` and `sessions` paths under every protected base join the refused roots; `refuseDigest` resolves them, so the tree a link leads to is refused. Test `digestUnderALinkedSessionTreeIsRefused` (both readers).

### FINDING-2
- **Severity:** Important
- **File:** Sources/UsageCore/Bench/ScanBench.swift:296-302
- **Category:** external (correctness)
- **Source:** Codex
- **Resolution:** fixed (5c55f50)

**What is wrong:** A readable `--dir` whose `projects` or `sessions` folder could not be read passed validation; the reader noted the error and the bench reported a successful scan of zero files.

**Why this matters:** The spec's edge case asks the bench to report an unreadable directory and exit without a report; an empty digest would compare as a real result.

**How it was resolved:** The folder must be readable and listable, else `ScanBenchError.invalid("<folder> folder not readable in <dir>")`. Test `unreadableReadersFolderIsInvalid`.

### FINDING-3
- **Severity:** Minor
- **File:** Sources/UsageCore/Bench/ScanBench.swift:339-358
- **Category:** security
- **Source:** security agent
- **Resolution:** fixed (df8aa61)

**What is wrong:** The check collapsed `..` as text before resolving links, while the write resolves the link first: `work/lnk/../x.digest` with `lnk` pointing into a session tree passed the check and landed in the tree.

**Why this matters:** A bypass of FR-004.

**How it was resolved:** `physicalPath` resolves the digest's folder with `realpath`, as the write reaches it, and that path is checked too. Test `digestThroughALinkAndDotDotIsRefused`.

### FINDING-4
- **Severity:** Minor
- **File:** specs/039-faster-session-scan/quickstart.md:29-31, 52-57
- **Category:** security
- **Source:** security agent
- **Resolution:** fixed (f3f5c5e), file mode part left

**What is wrong:** The quickstart kept the baseline binary and the real-corpus digests in the shared `/tmp/agenttacho-bench`, which another local account could create first; the digest is written with mode 0644.

**Why this matters:** The baseline binary is executed later, and the digests hold project paths and session ids.

**How it was resolved:** The quickstart uses `export BENCH=$(mktemp -d -t agenttacho-bench)`, a per-user directory with mode 700, as BENCHMARK.md already did. Writing the digest owner-only is left as a possible hardening; inside the private directory it is not reachable.

### FINDING-5
- **Severity:** Minor
- **File:** .gitignore
- **Category:** security
- **Source:** security agent
- **Resolution:** fixed (f3f5c5e)

**What is wrong:** Nothing kept a real-corpus digest written inside the worktree out of a commit.

**How it was resolved:** `*.digest` is ignored, except `Tests/UsageCoreTests/Fixtures/digests/*.digest`.

### FINDING-6
- **Severity:** Important
- **Confidence:** 70
- **File:** Sources/UsageCore/Logs/SessionLogSource.swift:128-138, Sources/UsageCore/Logs/ScanWorkers.swift:44-51
- **Category:** production-readiness
- **Source:** production readiness agent
- **Resolution:** fixed (46a01de), as the maintainer decided

**What is wrong:** The whole `LogIndex.update`, including attribution, now runs inside `offload` at utility priority. A match condition's 50 ms limit (spec 038) is measured in wall time, so preemption under load counts against it.

**Why this matters:** A spurious time-out makes the rule sit out for the rest of the refresh and remembers the value as slow, so records can be misattributed until the rules change or the app restarts. The bench ran on an idle machine and cannot show it.

**How it was resolved:** The maintainer chose to run the merge and attribution at the refresh's priority and keep the condition limit as spec 038 defines it. `ScanWorkers.offload` now runs on the global queue of the calling task's priority, without `.enforceQoS`; `forEach` keeps its helpers at utility with `.enforceQoS` and lowers the calling thread to utility while it runs jobs, then sets it back before the merge. The calling thread keeps running jobs: a first attempt that left all jobs to the helpers deadlocked the suite, since no utility thread was given out while every cooperative thread waited. Test `claudeAttributionRunsAtTheRefreshPriority` checks, through a `LogIndex.beforeMerge` hook, that the merge runs at user-initiated priority from a user-initiated refresh and every parse job at utility; it failed before the fix. The bench comparison afterwards compared identical.

### FINDING-7
- **Severity:** Minor
- **File:** Sources/UsageCore/Logs/CodexSessionSource.swift:480-497
- **Category:** production-readiness (memory)
- **Source:** production readiness agent
- **Resolution:** deferred by the maintainer, inbox `codex-parse-byte-cap`

**What is wrong:** The Codex reader hands every changed rollout file to one `forEach` and reads each whole, largest first, so the largest files are in memory together; the old code read one at a time. The Claude Code reader caps a batch at 64 MB.

**What needs to happen:** If long Codex sessions grow large, split the Codex jobs into byte-capped batches as `LogIndex.batches` does.

### FINDING-8
- **Severity:** Minor
- **File:** Sources/UsageCore/Logs/LogIndex.swift:483-497, 413
- **Category:** performance
- **Source:** production readiness agent
- **Resolution:** deferred by the maintainer, inbox `raw-line-copies-without-rules`

**What is wrong:** Every assistant line is copied and kept until the merge, which turns each kept raw line into a `String`, even when no rule reads raw lines (`attributor.needsRawLine` false). The Codex path already skips this.

**What needs to happen:** A measured step: parse from a non-copying view and skip the raw lines when no rule needs them.

### FINDING-9
- **Severity:** Minor
- **File:** Sources/UsageCore/Logs/SessionLogSource.swift:32-42, 85-91, 214-244; Sources/UsageCore/Logs/CodexSessionSource.swift:94-104, 146-152, 421-451
- **Category:** architecture (duplication)
- **Source:** architecture agent
- **Resolution:** deferred by the maintainer, inbox `duplicated-scan-gate`

**What is wrong:** The one-scan-at-a-time gate (flag, waiters, deferred reset) is written twice, with the reset factored differently.

**What needs to happen:** Extract a `ScanGate` value type both actors hold.

### FINDING-10
- **Severity:** Minor
- **File:** Sources/UsageCore/Logs/ScanWorkers.swift:39-51, 107-122
- **Category:** architecture (concurrency idioms)
- **Source:** architecture agent
- **Resolution:** doc comment fixed (f3f5c5e); signature deferred by the maintainer, inbox `scan-workers-api-shape`

**What is wrong:** The public `offload` takes a closure and result that need not be `Sendable` and boxes them unchecked; the box's comment named only one of its two contracts.

**What needs to happen:** Tightening `offload` to `@Sendable` closures and `Sendable` results is an API decision; the comment now states both contracts.

### FINDING-11
- **Severity:** Minor
- **File:** Sources/UsageCore/Logs/SessionLogSource.swift:30-56, 136
- **Category:** architecture
- **Source:** architecture agent
- **Resolution:** deferred by the maintainer, inbox `scan-workers-api-shape`

**What is wrong:** `SessionLogSource` keeps a `ScanWorkers` it only uses for `offload`; the count and the test hook come from the `LogIndex`'s own, so callers pass the value twice, unlike `CodexSessionSource`.

**What needs to happen:** Give the workers one owner, for example the index's, and build the default index from the source's parameter.

### FINDING-12
- **Severity:** Important
- **File:** Tests/UsageCoreTests/ScanWorkersTests.swift:101-114
- **Category:** test-quality
- **Source:** test quality agent
- **Resolution:** fixed (6a57ca2)

**What is wrong:** The test for "offload keeps the pool free" could not fail if `offload` blocked a pool thread, and it discarded the wait result.

**How it was resolved:** `offloadNeverHoldsACooperativeThread` blocks more offloads than the pool has threads and checks that an unrelated task completes and every wait succeeds; the old test checks its wait result.

### FINDING-13
- **Severity:** Minor
- **File:** Tests/UsageCoreTests/ScanConcurrencyTests.swift (gate tests)
- **Category:** test-quality
- **Source:** test quality agent
- **Resolution:** fixed (2690531)

**What is wrong:** The gate tests slept a fixed time before releasing the workers, and `!finished.isSet` could not fail.

**How it was resolved:** Both sources expose `waitingCollects()` for the tests; the tests poll it and check that no second scan started.

### FINDING-14 to FINDING-20 (Minor, test-quality, fixed)

- FINDING-14, the Claude Code refresh line's CPU seconds were tested only through the formatter: now asserted on the real log line (6a57ca2).
- FINDING-15, the fallback shape line and the nested shape object had no test: `aShapeLineLeftToTheFallbackStillNamesTheProfile`, `aNestedShapeObjectInAUserLineNamesNoProfile` (6a57ca2).
- FINDING-16, the bench defaults, linked digest paths and the write error had no test: `defaultsComeFromTheAppsConfiguration`, the two link tests, `digestThatCannotBeWrittenIsInvalid` (5c55f50, df8aa61, bb34cbb).
- FINDING-17, the report test left corpus bytes and the resource lines unchecked: now asserted for both readers (df8aa61).
- FINDING-18, nothing showed `forEach` runs jobs in parallel: `jobsRunInParallelUpToTheCount` (6a57ca2).
- FINDING-19, a JSON boolean in a Codex number field counted 1 or 0 in the old code and nil in the new: the decoding now reads it as before, with tests (8a1cf80, FR-011).
- FINDING-20, the Codex parent rounds had no test for cycles, self parents or unreadable older files: `codexParentRoundsEndOnCyclesAndUnreadableFiles` (6a57ca2).

## Notable Observations

Captured to `brainstorm/idea-inbox.md`:

- **digest-path-app-files** (security): a digest path is not refused when it names the app's configuration or imported-prices file.
- **scan-io-throttle-visibility** (production): utility priority also throttles the scan's disk reads; the refresh line does not name the priority or worker count.
- **bench-code-in-app-binary** (production, architecture): `UsageCore/Bench` is linked into the app; the Package.swift comment now says so.
- **fixture-digest-provenance** (tests): a later `make bench-digests` regenerates the committed digests from new code; a raw-bytes guard test now covers the fixtures' CRLF, non-UTF-8 and incomplete lines (df8aa61).

## External Tools

- **CodeRabbit:** 6 findings, none in scope. Three named files this branch does not change (docs/accounts-and-budgets.md, README.md, brainstorm/idea-inbox.md entries of other specs); three named spec artifacts (research.md, spec.md), one of them asking for a day-of-month check that `ISO8601Timestamp.parseFast` already makes (`daysInMonth`). The re-review of the fix commits found 0.
- **Codex:** FINDING-1 and FINDING-2, both fixed.
- **Copilot:** skipped (disabled in config).

## Post-Fix Spec Coverage

No fix removed code that implements a requirement; all 21 functional requirements were rechecked after the fix round.

## Test Suite Results

| Round | Test Command | Exit Code | Status |
|-------|-------------|-----------|--------|
| before the review | make test | 0 | 2349 + 73 passed |
| after 5c55f50 | make test | 0 | 2351 + 73 passed |
| after df8aa61 to f3f5c5e | make test | 0 | 2360 + 73 passed |
| after 2690531 | make test | 0 | 2360 + 73 passed |
| after bb34cbb | make test | 0 | 2361 + 73 passed |
| after 46a01de | make test | 0 | 2362 + 73 passed (the new priority test failed before the fix) |

The committed fixture digests passed unchanged in every round.
