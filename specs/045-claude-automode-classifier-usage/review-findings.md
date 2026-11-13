# Deep Review Findings

**Date:** 2026-11-13
**Branch:** 045-claude-automode-classifier-usage
**Rounds:** 2
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 1 | 1 | 0 |
| Important | 11 | 11 | 0 |
| Minor | 20 | 9 | 11 |
| Notable | 4 | - | 4 |
| **Total** | **36** | **21** | **15** |

**Agents completed:** 5/5 internal (Goal Alignment skipped: no PR) + 2 external tools (CodeRabbit, Codex; Copilot disabled in config) + 1 re-review agent on the fix commits
**Agents failed:** none

Fix commits:

- `feff31b fix(045): treat classifier counters above 2^32 as malformed`
- `5d2397c perf(045): build session spans in place with counter sets`
- `afe7753 fix(045): reread replaced decision logs and cap stuck probe checks`
- `c0c5103 fix(045): label per-refresh line counts and test the double recording note`
- `d3a53f6 fix(045): keep healthy directories checked under the stuck cap`

`make test` passed after each fix round (2797 + 79 tests at the end).

Two CodeRabbit "major" findings from round 2 (FINDING-13, FINDING-14) were triaged down to Minor. Both need a design decision, and their impact is bounded (see each finding). They are listed as remaining.

## Findings

### FINDING-1
- **Severity:** Critical
- **Confidence:** 85
- **File:** Sources/UsageCore/Logs/ClassifierRowParser.swift:81-87
- **Category:** correctness
- **Source:** correctness-agent (also reported by: security-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1, feff31b)

**What is wrong:** Any non-negative `Int` counter up to `Int.max` was accepted. `UsageRecord.totalTokens` and the Aggregator sums use checked `+`, so one row such as `"inputTokens": 9223372036854775807` crashed the app on every refresh for as long as the file existed.

**Why this matters:** The decision log sits in a working directory, often a git checkout, so it is less trusted than `~/.claude`. A crash loop takes down every other total too, which breaks US4 and FR-004 ("skipped without affecting the other rows").

**How it was resolved:** `ClassifierRowParser.maximumCounter = 1 << 32`. A larger counter makes the line malformed. Even 120,000 rows at the limit (a full 64 MB log) stay far below `Int.max`. Tests: `counterAboveTheLimitIsMalformed`. The unused `ClassifierRow.totalTokens` (an unchecked sum) was removed. Spec evolution candidate: FR-004 could name the bound.

### FINDING-2
- **Severity:** Important
- **Confidence:** 85
- **File:** Sources/UsageCore/Logs/ClassifierAttribution.swift:122-141
- **Category:** production-readiness
- **Source:** production-agent (also reported by: coderabbit, architecture-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1, 5d2397c)

**What is wrong:** `if var span = byKey[key] { span.records.append(...); byKey[key] = span }` copied the shared record array on every append. That is O(k²) per session on every refresh, even with no decision log anywhere.

**Why this matters:** Long sessions have thousands of records, and the cost hit every user on every refresh.

**How it was resolved:** Spans live in an array with an index map and are mutated in place. They keep a `Set<TokenCounters>` instead of whole records, and are built only for directories whose entries have rows. Attribution returns at once when no entry has rows.

**External tool analysis (CodeRabbit):**
> `span` is a copy of `byKey[key]`, which still retains the original `records` array. Appending requires a copy of that shared array under Swift's copy-on-write behavior. For a session with N records, this construction performs quadratic copying on every refresh, including refreshes with no changed logs.

### FINDING-3
- **Severity:** Important
- **Confidence:** 80
- **File:** Sources/UsageCore/Logs/ClassifierAttribution.swift:62-76
- **Category:** production-readiness
- **Source:** production-agent (also reported by: coderabbit)
- **Round found:** 1
- **Resolution:** fixed (round 1, 5d2397c)

**What is wrong:** The double-recording check scanned every record of every covering span for each row. Spans that never match are never flagged, so the work was rows times records, on every refresh.

**Why this matters:** A 64 MB log over a 5,000-record session reaches hundreds of millions of comparisons per refresh.

**How it was resolved:** One `Set<TokenCounters>` lookup per covering span. The equality is unchanged: input, output, cache read, and cache write as 5-minute plus 1-hour.

### FINDING-4
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/UsageCore/Logs/DecisionLogProbe.swift:249
- **Category:** external
- **Source:** codex (also reported by: coderabbit, on spec.md and plan.md)
- **Round found:** 1
- **Resolution:** fixed (round 1, afe7753)

**What is wrong:** A log that was deleted and written again past the old parsed offset was read from that offset. The old rows were kept and the new file's first rows were missed.

**Why this matters:** The totals were wrong until the window moved past the rows.

**How it was resolved:** The probe reads `st_ino`. `KnownLogState`, `ReadChunk` and `DecisionLogEntry` carry `fileID`, and another file is read from offset 0. Test: `replacedLongerFileIsReadAgainFromTheStart`. Spec evolution candidate: FR-003 could name file identity.

**External tool analysis (Codex):**
> If a log is replaced with a same-size or larger file, this starts reading at the old `parsedOffset` instead of 0. The index then keeps the old rows and misses replacement content before that offset, so totals become incorrect; detect the replacement and reset the cached entry.

### FINDING-5
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/UsageCore/Logs/ClassifierLogIndex.swift:147-154
- **Category:** external
- **Source:** codex
- **Round found:** 1
- **Resolution:** fixed (round 1, afe7753)

**What is wrong:** An indexed directory could appear only through a new spelling whose first check timed out. That spelling had no canonical directory, so the prune loop dropped the directory's rows. This contradicts FR-012, which says records already read keep counting.

**How it was resolved:** While any spelling in the report has no canonical directory, no entry is dropped for its directory missing from the report. Rows are still pruned by the window. Test: `unresolvedSpellingKeepsTheRows`. FINDING-13 is the remaining design follow-up.

### FINDING-6
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/UsageCore/Logs/DecisionLogProbe.swift:163-181
- **Category:** external
- **Source:** coderabbit (also reported by: security-agent as Minor, production-agent as Notable)
- **Round found:** 1
- **Resolution:** fixed (round 1, afe7753; narrowed in round 2, d3a53f6)

**What is wrong:** Threads blocked on a hung volume stayed blocked, and every refresh could add more threads for new directories. The in-flight set limited this only per raw directory.

**How it was resolved:** `DecisionLogProbe.maximumStuckChecks` (default 16). While that many checks from earlier calls are still running, directories without a check that finished in time are reported busy and tried again on a later refresh. Tests: `stuckChecksAboveTheLimitDeferNewDirectories`. FINDING-14 is the remaining part, a bound inside one refresh.

### FINDING-7
- **Severity:** Important
- **Confidence:** 85
- **File:** Tests/UsageCoreTests/ClassifierAttributionTests.swift:101-135
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, 5d2397c)

**What is wrong:** Every two-account test used overlapping sessions. Nothing covered non-overlapping sessions on different accounts (the edge case, and the second half of the US3 Independent Test), or one session under two spellings of its directory.

**How it was resolved:** Added `nonOverlappingSessionsOnDifferentAccountsEachKeepTheirRows`, `twoSpellingsOfTheDirectoryBuildOneSpan` and `noRowsMeansNoRecords`.

### FINDING-8
- **Severity:** Important
- **Confidence:** 85
- **File:** Tests/UsageCoreTests/SessionLogSourceClassifierTests.swift:272-308
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, c0c5103)

**What is wrong:** The FR-013 double-recording log line was never tested. That includes the once-per-session rule and the rule that a session without an id is not logged by its file path.

**How it was resolved:** Added `possibleDoubleRecordingIsLoggedOncePerSession`. It runs two refreshes with one session that has an id and one without, and checks that no file path appears.

### FINDING-9
- **Severity:** Important
- **Confidence:** 80
- **File:** Tests/UsageCoreTests/ClassifierLogIndexTests.swift:220-262
- **Category:** test-quality
- **Source:** test-quality-agent (also reported by: coderabbit as Minor, on parallel runs)
- **Round found:** 1
- **Resolution:** fixed (round 1, afe7753)

**What is wrong:** The SC-004 test had one session record per directory and identical row times, so FINDING-2 and FINDING-3 were invisible to it. It also timed a single sample, and its `.serialized` comment was misleading.

**How it was resolved:** Each of the 50 directories now has 200 session records over 30 minutes, with about 186 rows spread across them. The assertion is on the median of five steady-state runs, and the `.serialized` trait was removed.

### FINDING-10
- **Severity:** Important
- **Confidence:** 80
- **File:** Tests/UsageCoreTests/DecisionLogProbeTests.swift:138-221
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, afe7753)

**What is wrong:** No test had canonicalization hang, although FR-012 puts standardizing the path under the same limit.

**How it was resolved:** Added `blockedCanonicalizationTimesOut`.

### FINDING-11
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/UsageCore/Logs/DecisionLogProbe.swift:98-102, 158-169
- **Category:** correctness
- **Source:** re-review agent
- **Round found:** 2
- **Resolution:** fixed (round 2, d3a53f6)

**What is wrong:** The round 1 cap deferred every directory once 16 checks were stuck. Checks hung on one volume would then stop all decision logs from being read, against FR-012 ("The other working directories continue").

**How it was resolved:** Only directories without a check that finished in time are deferred: new ones, or ones that timed out last time. Directories whose last check finished in time continue, and the test checks this.

### FINDING-12
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/UsageCore/Logs/DecisionLogProbe.swift:242, 262
- **Category:** external
- **Source:** coderabbit
- **Round found:** 2
- **Resolution:** fixed (round 2, d3a53f6)

**What is wrong:** A replacement with the same size and modification date returned "unchanged" before the inode comparison ran.

**How it was resolved:** Both unchanged checks now also require the same inode. Test: `replacedFileWithTheSameSizeAndDateIsReadAgain`.

## Remaining Findings

### FINDING-13
- **Severity:** Minor (CodeRabbit: major; re-review agent: Minor)
- **File:** Sources/UsageCore/Logs/ClassifierLogIndex.swift:157-171
- **Category:** correctness
- **Source:** coderabbit (also reported by: re-review agent)
- **Classification:** ambiguous (design decision)

**What is wrong:** The FINDING-5 guard is global. While any spelling stays unresolved (its first check never returns), entries of other directories whose sessions all left the window are not dropped. Their rows keep counting, as Unassigned, because no span exists for them.

**Why Minor:** The rows were counted until the previous refresh. They count only as Unassigned, they still leave with the window, and they persist only while a spelling of an in-window session hangs forever.

**Options:**
- (a) Remember the raw spellings that last mapped to each entry, and keep an entry only while one of them is in the report. This loses the FINDING-5 case, a brand-new spelling.
- (b) Hold entries for a bounded number of refreshes after a spelling first appears unresolved.
- (c) Keep the current rule.

### FINDING-14
- **Severity:** Minor (CodeRabbit: major)
- **File:** Sources/UsageCore/Logs/DecisionLogProbe.swift:158-181
- **Category:** production-readiness
- **Source:** coderabbit
- **Classification:** ambiguous (design decision)

**What is wrong:** The stuck cap bounds threads across refreshes, but a single refresh still starts one thread per distinct in-window directory. On a first refresh with many directories on a hung volume, all of those threads can block.

**Why Minor:** The count is bounded by the distinct working directories of one window, and each directory has at most one check. Once 16 checks are stuck, no further unproven directory is started. FR-012 asks for every directory to be checked within its own 2 s.

**Option:** Admit at most N new (unproven) directories per refresh and defer the rest. This delays first reads of their logs.

### Other remaining Minor findings

- **Sources/UsageCore/Logs/DecisionLogProbe.swift:99, 102, 203-208** (production): `lastCanonical` and `reportedTimeOut` never shrink for directories that stop appearing. This is slow, unbounded growth. Fix: prune both to this call's directories plus in-flight ones at the end of `check`. Unambiguous.
- **Sources/UsageCore/Logs/DecisionLogProbe.swift:228-257** (correctness): `EACCES`, `EIO`, `EMFILE`, a failed `fstat` and read errors are reported as `.absent`, so the entry is dropped for one refresh and read in full next time. Fix: add an `.unreadable` result that keeps the entry like `.timedOut`. Ambiguous: it adds a result kind and a diagnostic counter.
- **Sources/UsageCore/Logs/DecisionLogProbe.swift:118-176** (correctness): the claim on a canonical directory lasts one call. A second spelling can start another check of a directory whose check is still hung, at most one per spelling. Fix: a probe-level set of claimed canonical directories. Unambiguous.
- **Sources/UsageCore/Logs/SessionLogSource.swift:192-215 and DecisionLogProbe.swift:249-260** (security): the read chunks, which hold the raw line content, stay in the step result until `collect` returns, and peak memory is 64 MB per log with no total budget. Fix: strip the chunk payloads after `index.update` and add a total byte budget per refresh. Ambiguous: the budget is a design choice.
- **Sources/UsageCore/Logs/ClassifierLogIndex.swift:76-100** (architecture): `prepare(window:)` is called twice per refresh, and the required order lives only in a doc comment. Fix: `known(for:)` owns the order. Unambiguous.
- **Sources/UsageCore/Logs/SessionLogSource.swift:237-242** (architecture): whether a session key is logged depends on `key.hasPrefix("/")`, an encoding chosen in `LogIndex`. It is now covered by the FINDING-8 test. Fix: an explicit session key kind. Unambiguous.
- **Sources/UsageCore/Logs/LogIndex.swift:429-436** (architecture): `UsageRecord(raw:)` sets `cwd`, and the only caller overwrites it with the shared string. Fix: a `cwd:` parameter. Unambiguous.
- **Sources/UsageCore/Logs/ClassifierAttribution.swift:55-85** (architecture): the pricing cache sits next to `PriceTable.cost(model:...)` and duplicates its composition. Fix: move the memoization into `PriceTable`. Unambiguous.
- **Tests/UsageCoreTests/SessionLogSourceClassifierTests.swift:112-127** (test quality): no end-to-end test runs a priced model with a `[1m]` marker and non-zero cache write through pricing. Fix: a variant with `claude-opus-5-5[1m]` rows that checks `costUSD` against `pricer.cost(model: "claude-opus-5-5", ...)`. Unambiguous.

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/Logs/DecisionLogProbe.swift:163-181
- **Category:** production-readiness
- **Source:** production-agent
- **Description:** Every refresh starts a thread per distinct in-window working directory, even when no decision log exists anywhere.
- **Rationale:** Caching the canonical path per raw directory for the life of the window, and limiting how many checks run at once, would cut the per-refresh syscall and thread burst.

### NOTABLE-2
- **File:** Sources/UsageCore/Logs/SessionLogSource.swift:173-182
- **Category:** production-readiness
- **Source:** production-agent
- **Description:** The classifier step's duration and `bytesRead` are never logged.
- **Rationale:** A slower refresh in the field cannot be traced to the probe or to attribution.

### NOTABLE-3
- **File:** Sources/UsageCore/Logs/UsageRecord.swift:47-87
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** The shared `UsageRecord` gained `sessionKey`, `cwd` and `origin` for this feature only.
- **Rationale:** A per-session summary from `LogIndex` would keep the priced record narrow.

### NOTABLE-4
- **File:** Sources/UsageCore/Logs/ClassifierLogIndex.swift:171
- **Category:** security
- **Source:** security-agent
- **Description:** A decision log committed to a repository is counted like Claude Code's own, and rows with future timestamps are kept. Uncovered rows join Unassigned (FR-006).
- **Rationale:** Dropping rows later than now plus a small skew, and saying in the README that a committed log counts too, would limit inflation from foreign files.

## Post-Fix Spec Coverage

The fix rounds removed no requirement code. `matchesCounters` and `SessionSpan.records` became a counter set with the same equality, and `ClassifierRow.totalTokens` was unused. FR-001 to FR-016 and FR-008a are verified against the code after the fixes (see REVIEW-CODE.md).

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| 1 | make test | 0 | 0 | passed (2796 + 79) |
| 2 | make test | 0 | 0 | passed (2797 + 79) |

Test suite passed in all fix rounds.
