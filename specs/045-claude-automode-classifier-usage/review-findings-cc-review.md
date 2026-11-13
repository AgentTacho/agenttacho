# Review Findings

**Date:** 2026-11-13
**Branch:** 045-claude-automode-classifier-usage (PR #11, head bd9465d)
**Rounds:** 3 fix rounds
**Gate Outcome:** PASS (after fix round 3)
**Invocation:** standalone

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 4 | 4 | 0 |
| Minor | 10 | 10 | 0 |
| Notable | 4 | 0 | 4 |
| **Total** | **18** | **14** | **4** |

Fix rounds also found and fixed 9 follow-up issues in the fixes themselves (listed under "Fix rounds" below).

**Reviewers completed:** 9/11 (copilot: disabled, greptile: disabled). Fix-round re-reviews used correctness, production, security and test-quality only; Codex and CodeRabbit were not re-run because the fixes are uncommitted.

## Findings

### FINDING-12
- **Severity:** Important
- **Confidence:** 70
- **File:** Sources/UsageCore/Logs/DecisionLogProbe.swift:205-223
- **Category:** production-readiness
- **Source:** production
- **Round found:** 1
- **Resolution:** fixed (round 1, reworked in round 2)
- **Verdict:** confirmed

**What is wrong:**
A check that missed the 2 s limit wrote its result into a batch nobody read again, so a large decision log on slow storage was read again from the same offset on every refresh, timed out again and never counted.

**Why this matters:**
Silent, permanent undercount for users with a large log on SMB, NFS, a slow USB disk or an iCloud-evicted file, plus repeated reads and repeated time-out log lines.

**How it was resolved:**
The probe now keeps a read limit per directory. A log is read in full by default; after a time-out the directory's limit drops to a quarter (not below 512 KB) and doubles again after each check that finishes in time. The index cuts a partial read at its last complete line, so a slow log makes progress over several refreshes. A line longer than the limit is skipped as malformed instead of read forever. Tests: `timeOutShrinksTheReadLimitAndInTimeChecksRaiseIt`, `largeLogIsReadInStepsOverSeveralRefreshes`, `lineLongerThanTheReadLimitIsSkipped`, `unfinishedLineAloneIsNotSkipped`, `readStopsAtTheReadLimit`.

### FINDING-3
- **Severity:** Important
- **Confidence:** 80
- **File:** Tests/UsageCoreTests/ClassifierAttributionTests.swift:102
- **Category:** test-quality
- **Source:** test-quality
- **Round found:** 1
- **Resolution:** fixed (round 1)
- **Verdict:** confirmed

**What is wrong:**
No test had concurrent sessions in two working directories on different accounts, so FR-005's rule that only the log's own directory covers its rows was unverified.

**Why this matters:**
A refactor that let spans leak across directories would turn every row Unassigned for a user with two repositories on two accounts, with all tests passing.

**How it was resolved:**
`sessionsOfAnotherDirectoryDoNotCoverTheRow` puts a session on acc-b in /raw/V next to the acc-a session in /raw/W and asserts the row keeps acc-a and W's project.

### FINDING-11
- **Severity:** Important (CodeRabbit's rating; the production reviewer rated it Notable)
- **Confidence:** 75
- **File:** Sources/UsageCore/Logs/DecisionLogProbe.swift:187-204
- **Category:** production-readiness
- **Source:** coderabbit (also reported by: production)
- **Round found:** 1
- **Resolution:** fixed (round 1)
- **Verdict:** confirmed (external, not re-judged)

**What is wrong:**
Every in-window working directory got a new thread on every refresh, with no cap.

**Why this matters:**
Hundreds of distinct working directories meant hundreds of threads per refresh.

**How it was resolved:**
At most 64 new checks start per call (`maximumChecksPerCall`); the others report busy, keep their rows, and go first in the next call, ordered by when they were last checked. A global in-flight ceiling was deliberately not added: FR-012 keeps directories that answered in time checked even while others are stuck. Test: `directoriesAboveThePerCallLimitWaitAndGoFirstNextTime`.

### FINDING-14
- **Severity:** Important (CodeRabbit's rating; the orchestrator judged it Minor)
- **Confidence:** 75
- **File:** Sources/UsageCore/Logs/DecisionLogProbe.swift:291-294
- **Category:** external
- **Source:** coderabbit
- **Round found:** 1
- **Resolution:** fixed (round 1)
- **Verdict:** confirmed (external, not re-judged)

**What is wrong:**
The same file with a new modification date but no growth was read from the old parsed offset, keeping stale rows after an in-place rewrite.

**Why this matters:**
Only an in-place rewrite at the same size and inode triggers it; Claude Code appends.

**How it was resolved:**
A known file is continued from its parsed offset only when it grew beyond the last read; otherwise it is read from the start. The read also stops at the size seen by `fstat`, so bytes appended during a read count as growth next time (round 2 follow-up). Test: `fileRewrittenInPlaceAtTheSameSizeIsReadFromTheStart`.

### Minor findings (all fixed)

- **FINDING-13** (`DecisionLogProbe.swift:255-302`, correctness and codex): every `lstat`, `open`, `fstat` or read error was `.absent`, which dropped counted rows. Now only ENOENT/ENOTDIR are absent; other errors are the new `.unreadable` result, which keeps the entry and shows as ", unreadable N" in the summary line only when present.
- **FINDING-8** (`ClassifierRowParser.swift:110`, security and gator; calibrated from Important): future-dated rows fed `AdaptivePace.newestActivity`. Rows after the refresh's `now` are left out of attribution until their time and stay in the index; model names are limited to 128 bytes without spaces or control characters.
- **FINDING-9** (`DecisionLogProbe.swift:88`, security; calibrated from Notable): a log of minimal lines could hold about 1.1M rows. Logs with more than 262,144 rows or more than 16 distinct models are skipped, logged once, and not parsed again until read from the start; parsing stops as soon as a limit is exceeded, which also bounds peak memory (round 3).
- **FINDING-10** (`DecisionLogProbe.swift:113-116`, production and codex): probe state and log-once sets grew forever. Probe state is forgotten after a directory went unnamed for 100 calls and has no check running; log-once sets are pruned by the checked directories and current sessions.
- **FINDING-2** (`ClassifierAttributionTests.swift:66`, test-quality; calibrated from Important): the FR-007 project fallback was untested. Three tests added.
- **FINDING-18** (`DecisionLogProbeTests.swift:242`): the default of 16 stuck checks is now asserted.
- **FINDING-17** (`SessionLogSource.swift:246`): the session key is now the typed `SessionKey` (`.id` / `.file`) with a `loggable` text, replacing the `hasPrefix("/")` guess.
- **FINDING-6** (`ClassifierLogIndex.swift:93`): `known(for:)` renamed to `prepare(for:)` with a doc comment naming its side effect and `resetIndex`.
- **FINDING-7** (`ClassifierLogIndex.swift:126`, weak): the unreachable fallback is an `assertionFailure` guard.
- **FINDING-4** (`ClassifierAttribution.swift:87-117`, weak): one tuple cache replaces the double optional, the parallel map and both force unwraps.
- **FINDING-1** (`README.md:70`, codex): the website privacy update already exists in AgentTacho/agenttacho.github.io#36 (open). No code change; merge it before the release.

## Notable Observations

- **FINDING-5** (gator, weak): a decision log committed to a shared repo adds its in-window rows to teammates' Unassigned totals. This is FR-006 by design and already recorded as NOTABLE-4; changing it needs a maintainer decision.
- **FINDING-15** (goal-alignment, weak): every session record now carries `sessionKey` and `cwd`; already disclosed as NOTABLE-3. The PR description could mention it.
- **FINDING-16** (goal-alignment, weak): constitution III's list of read locations does not name working directories. Wording drift; the read-only rule is kept.
- Round-2 notable (correctness): after a partial read, an in-place rewrite to a size above the read end looks like growth until the catch-up finishes. Needs slow storage plus an in-place rewrite; storing the `fstat` size apart from the read end would close it.

## Fix rounds

| Round | Found by re-review | Fixed |
|-------|--------------------|-------|
| 1 | Append between `fstat` and read forced a re-read from 0 (Important); fixed 8 MB limit still stalled on slow storage and delayed counting on fast storage (Important); distinct model names unbounded (Important); too-large skip logged again after a busy refresh (Minor); test gaps for the partial-read gate, `now` wiring, row-limit log line, boundary, pruning (3 Important, 2 Minor) | round 2 |
| 2 | Row and model limits applied after a full parse, so peak memory was unbounded (Important); adaptive read limit not observable in tests, skipped log offset and log-once forgetting untested (3 Important, test-quality) | round 3 |
| 3 | none | |

## Agent Quality Scores

| Agent | Findings | Precision | Signal/Noise |
|-------|----------|-----------|--------------|
| correctness | 1 | 0.9 | 3.0 |
| gator | 1 | 0.85 | 2.0 |
| production | 2 | 0.85 | 2.0 |
| test-quality | 3 | 0.8 | 3.0 |
| architecture | 4 | 0.75 | 1.5 |
| goal-alignment | 2 | 0.7 | 1.0 |
| security | 2 | 0.6 | 1.5 |
| codex | 1 | 0.5 | 1.0 |
| coderabbit | 2 | 0.5 | 1.0 |

**Meta-review summary:**
- Findings removed (false positive): 0
- Findings calibrated: 3 (FINDING-8 and FINDING-2 Important to Minor, FINDING-9 Notable to Minor)
- Contradictions detected: 0

## Need, Fit and Goal Delivery

| Judgment | Verdict | Evidence |
|----------|---------|----------|
| Need | ESTABLISHED | A GLM probe counted 80,168 tokens against 149,792 billed |
| Fit | FITS | Local-first reading of agent files; README privacy row and site PR #36 |
| Implementation value | JUSTIFIED | No smaller alternative; the complexity is the robustness the spec requires |

All stated goals delivered (SC-001 totals, read-only access, incremental reads, time-based attribution, timed probe, one summary line).

## Test Suite Results

| Round | Command | Outcome |
|-------|---------|---------|
| 1 | make test | passed (2820 + 79) |
| 2 | make test | passed (2827 + 79) |
| 3 | make test | passed (2830 + 79); make test-release passed (266) |

## Remaining Findings

None at Critical or Important. The fixes are uncommitted in the worktree; `spec.md` FR-001, FR-003, FR-004, FR-005, FR-012 and FR-013 were updated to match.
