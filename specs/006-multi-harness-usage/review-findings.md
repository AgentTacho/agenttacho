# Deep Review Findings

**Date:** 2026-10-14
**Branch:** 006-multi-harness-usage
**Rounds:** 1 fix round (plus a minor follow-up commit)
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 1 | 1 | 0 |
| Important | 8 | 8 | 0 |
| Minor | 28 | 16 | 12 |
| Notable | 6 | - | 6 |
| **Total** | **43** | **25** | **18** |

Counts are after deduplication (correctness FINDING-1 with test-quality FINDING-1, architecture FINDING-1 with production FINDING-6, architecture FINDING-4 with production FINDING-5).

**Agents completed:** 5/6 (Goal Alignment skipped: no PR for the branch) + CodeRabbit
**External tools:** CodeRabbit completed (1 finding, 0 on the fix commit). Codex failed (usage limit reached). Copilot skipped (disabled in config).

Fix commits: `ce8b5ab` (round 1), `9d759cd` (minor follow-ups).

## Findings

### FINDING-1
- **Severity:** Critical (raised from Important after checking real data)
- **Confidence:** 95
- **File:** Sources/UsageCore/Logs/CodexSessionParser.swift (copied-history detection)
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** Forked and subagent rollout files copy the parent's `token_count` events. The parser treated them as copied only when `timestamp <= metaTime`. A read-only scan of the 38 forked files on the user's machine showed the copied events stamped 1 to 2 ms after the meta line, so they counted as the child's own usage.

**Why this matters:** The parent's tokens were counted a second time for every fork and subagent (SC-002, zero double counting). Copied plan markers also became the child's own markers (FR-014).

**How it was resolved:** The copied phase is now contiguous. It starts at the repeated parent `session_meta` and ends at the first `token_count` stamped at least 1 s after the fork. The child's own first turn took at least 3.8 s in the real data. During the phase, events only set the baseline, and plan markers are ignored. If the first meta has no timestamp, the repeated meta anchors the phase. Tests: `copiedHistoryStampedMillisecondsAfterTheForkAddsNoUsage`, `ownPlanMarkerAfterCopiedHistoryCounts`, `copiedHistoryWithoutFirstMetaTimestampIsAnchoredOnTheRepeatedMeta`, and copied markers added to the subagent fixture.

### FINDING-2
- **Severity:** Important
- **Confidence:** 90
- **File:** Sources/UsageCore/Logs/CodexSessionParser.swift (delta loop)
- **Category:** correctness
- **Source:** correctness-agent (also reported by: test-quality-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** An all-zero `token_count` in the middle of a session set `previous` to zero before the zero-delta check. The next event then counted the whole running total again.

**Why this matters:** This double counted usage (FR-008a, SC-002). The only fixture zero event sat at the start of the file, so the tests did not catch it.

**How it was resolved:** All-zero totals are skipped before the baseline is touched. Test: `zeroEventMidSessionKeepsTheBaseline`.

### FINDING-3
- **Severity:** Important
- **Confidence:** 85
- **File:** Sources/UsageCore/Logs/OpenCodeSource.swift (`parse`, `count`)
- **Category:** security
- **Source:** security-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** `Int(Double)` traps when the value is out of range, and the token sums could overflow. The values come from untrusted database JSON.

**Why this matters:** A single corrupt row would crash the app on every launch, in a loop.

**How it was resolved:** Non-finite and negative values are clamped to 0, and large values to 2^50. Codex `Totals` gets the same clamp (security minor FINDING-2). Tests: `hugeTokenValuesDoNotTrap` (OpenCode and parser).

### FINDING-4
- **Severity:** Important
- **Confidence:** 80
- **File:** Sources/UsageCore/Logs/CodexSessionSource.swift (scan and read errors)
- **Category:** architecture
- **Source:** architecture-agent (also reported by: production-readiness-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** Codex enumeration errors and unreadable-file errors became source errors, but their text never reached the diagnostic log. The per-home line still claimed a clean read.

**Why this matters:** FR-022 requires the log to name the reason a location failed.

**How it was resolved:** Every scan and read error is now logged with its location.

### FINDING-5
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/UsageCore/Logs/OpenCodeSource.swift (first read)
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, margin added in follow-up)

**What is wrong:** The first read started at watermark 0. It loaded the whole OpenCode history into memory on every launch and on every reset.

**Why this matters:** SC-003 budgets for histories of 100,000 messages, and this cost grew with the whole history.

**How it was resolved:** The read starts at `max(watermark, windowStart - 1 h)`. A row's update time is no earlier than its completion time. The one-hour margin covers rows whose update time trails completion. Test: `firstReadSkipsHistoryBeforeTheWindow`.

### FINDING-6
- **Severity:** Important
- **Confidence:** 70
- **File:** Sources/UsageCore/Logs/CodexSessionSource.swift (record building)
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** Every refresh rebuilt every Codex record: attribution, pricing, project lookup, and a string of `metaLine` plus the event line. That happened even when no file had changed.

**Why this matters:** It worked against the FR-004 and SC-003 goal of an incremental refresh with no changes in under 1 s.

**How it was resolved:** Built records are cached per file and keyed by auth-mode hint. The cache clears when the attribution fingerprint or the price table changes. Raw line text is built only when an account has a custom marker. Tests: `priceOverrideRepricesWithoutReparsing`, `ruleChangeReattributesWithoutReparsing`.

### FINDING-7
- **Severity:** Important
- **Confidence:** 80
- **File:** Tests/UsageCoreTests/CodexSessionSourceTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** No Codex test covered a session that crosses the window start.

**How it was resolved:** Added `sessionCrossingTheWindowStartCountsOnlyInsideUsage`.

### FINDING-8
- **Severity:** Important
- **Confidence:** 80
- **File:** Tests/UsageCoreTests/OpenCodeSourceTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The fixture forced rollback-journal mode, but OpenCode runs in WAL mode. No test read a WAL database with an open writer.

**How it was resolved:** The fixture now takes a journal mode. Added `walDatabaseWithOpenWriterIsRead`, which covers uncheckpointed rows and an open write transaction: the refresh is neither stale nor blocked.

### FINDING-9
- **Severity:** Important
- **Confidence:** 80
- **File:** Tests/UsageCoreTests/OpenCodeSourceTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The OpenCode re-price path (a price override added after the first read) was untested (FR-019).

**How it was resolved:** Added `priceOverrideRepricesStoredMessages`, which asserts no rows are read again.

### Minor findings

| ID | Source | File | Description | Resolution |
|----|--------|------|-------------|------------|
| M-1 | security | CodexSessionParser.swift | Token value overflow on corrupt lines | fixed (clamp) |
| M-2 | security | OpenCodeSource.swift:292-309 | Read-only open of a WAL database can create `-wal`/`-shm` side files when OpenCode is not running | remaining |
| M-3 | architecture | CodexSessionSource.swift / OpenCodeSource.swift | Duplicated `Location` type and location resolution | remaining |
| M-4 | architecture | Attribution.swift | Hardcoded `"apikey"` instead of `Attributor.codexAPIKeyHint` | fixed |
| M-5 | architecture, production | CodexSessionSource.swift | Test-only `resolvedRawRecords` kept every raw record | fixed (replaced by `lastHints`) |
| M-6 | architecture | CodexSessionSource.swift | Two diverging reset paths | fixed (shared `reset()`) |
| M-7 | architecture | CodexSessionSource.swift:76-230 | Long `collect` mixing scan, auth resolution, build, log | remaining |
| M-8 | architecture | UsageSnapshot.swift:336-344 | `RecordBatch.issues` doc says per location, but Codex adds per-file issues | remaining |
| M-9 | architecture | AccountSettingsView.swift | Dead `isSubscription` | fixed |
| M-10 | architecture | AccountSettingsView.swift:300-345, 465-477 | `NewAccountSheet.Kind` re-declares kinds and icons; new Codex accounts store `harness: .codex` although it is inert | remaining |
| M-11 | architecture | UsageSnapshot.swift:383-385 | `planAccounts` name is vague next to part B | remaining |
| M-12 | architecture | CodexSessionSource.swift:203, OpenCodeSource.swift:206 | `SessionLogSource.summarizeProjectNotes` used from sibling sources | remaining |
| M-13 | correctness | CodexSessionParser.swift | Plan marker taken from copied parent events | fixed |
| M-14 | correctness | ImportedPrices.swift | Collapsing legacy `@` ids rejected the whole file | fixed (dedupe) |
| M-15 | production | CodexSessionSource.swift:158-167 | Orphan-parent lookup scans older files linearly each refresh; `outsideSessions` never pruned | remaining |
| M-16 | production | CodexSessionSource.swift:125-147 | Active rollout file re-read in full on each change; first read is sequential | remaining |
| M-17 | test-quality | AggregatorTests.swift | Per-harness sort test passed without cost ranking | fixed |
| M-18 | test-quality | CodexSessionSourceTests.swift | `filter().allSatisfy` without count | fixed |
| M-19 | test-quality | CodexSessionSourceTests.swift, OpenCodeSourceTests.swift | No "harness removed" test for files or the database | fixed |
| M-20 | test-quality | CodexSessionSourceTests.swift, OpenCodeSourceTests.swift | Unreadable home, unreadable file, empty or corrupt `opencode.db` branches untested | remaining |
| M-21 | test-quality | CodexSessionSourceTests.swift | No test for a subagent whose parent is missing | fixed |
| M-22 | test-quality | RefreshCoordinatorTests.swift | `planAccounts` carry-over as stale on a failed record source untested | remaining |
| M-23 | coderabbit | CodexSessionParser.swift:117 | Message ids collide when `total_tokens` is missing | fixed |
| M-24 | re-review | CodexSessionParser.swift | First meta without timestamp disables copied-history detection | fixed |
| M-25 | re-review | ImportedPrices.swift | Dedupe comment misstated the guarantee | fixed |
| M-26 | re-review | CodexSessionSourceTests.swift | Cache invalidation by rule change and by parent mode change untested | partly fixed (rule change); parent-mode change remaining |
| M-27 | re-review | OpenCodeSourceTests.swift | First-read bound untested | fixed |
| M-28 | re-review | Fixtures/codex/subagent-session.jsonl | Orphan test trivially true (no copied markers) | fixed |

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/Logs/OpenCodeSource.swift:294-306
- **Category:** security
- **Source:** security-agent
- **Description:** No `SQLITE_DBCONFIG_DEFENSIVE` or `trusted_schema=OFF` on the opened database.
- **Rationale:** Defence in depth against a crafted database in a user-configured directory.

### NOTABLE-2
- **File:** CodexSessionSource.swift, OpenCodeSource.swift, LogIndex.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** Three sources use three policies for "rules or prices changed". `SourceOutput.records` and `.recordBatch` overlap.
- **Rationale:** A single policy would avoid three implementations of every future fix.

### NOTABLE-3
- **File:** Sources/UsageCore/Logs/OpenCodeSource.swift, CodexSessionParser.swift
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Description:** Raw JSON is kept per record for custom markers, and the live-id query runs on every incremental refresh.
- **Rationale:** Memory and per-refresh work grow with the history, not with changes.

### NOTABLE-4
- **File:** Sources/UsageCore/Logs/OpenCodeSource.swift:158-182
- **Category:** correctness
- **Source:** correctness-agent
- **Description:** FR-009 relies on OpenCode bumping `time_updated` when a message completes.
- **Rationale:** This is an unverified harness invariant. Re-selecting ids seen incomplete would remove the dependency.

### NOTABLE-5
- **File:** Sources/UsageCore/Logs/CodexSessionParser.swift
- **Category:** correctness
- **Source:** re-review
- **Description:** The copied-history phase ends by time (1 s). A child turn that completes within 1 s of the fork would be treated as baseline.
- **Rationale:** A structural signal, such as the child's own `task_started`, would remove the time assumption.

### NOTABLE-6
- **File:** Sources/UsageCore/Logs/OpenCodeSource.swift
- **Category:** correctness
- **Source:** re-review
- **Description:** The first-read bound assumes `time_updated >= time.completed`.
- **Rationale:** Mitigated with a one-hour margin. The contract could state the invariant.

## Goal Alignment

Skipped (no PR found for the branch).

## Post-Fix Spec Coverage

The fix commits removed only the test-only `resolvedRawRecords` and the dead `isSubscription`. All functional requirements (FR-001 to FR-022, including FR-008a, FR-008b, FR-020a and FR-020b) keep their implementation. The fixes strengthen FR-004, FR-008a, FR-014, FR-019, FR-022 and SC-002.

All spec requirements verified after fix loop.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| baseline | make test | 0 | 0 | passed (442 tests) |
| 1 | make test | 0 | 0 | passed (456 tests) |
| follow-up | make test | 0 | 0 | passed (459 tests) |

Test suite passed in all fix rounds.

## Remaining Findings

No Critical or Important findings remain. The 12 remaining Minor findings (M-2, M-3, M-7, M-8, M-10, M-11, M-12, M-15, M-16, M-20, M-22, M-26 parent-mode part) are refactors, small doc fixes, or extra tests. None blocks the feature.
