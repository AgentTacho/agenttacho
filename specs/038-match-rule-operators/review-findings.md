# Deep Review Findings

**Date:** 2026-10-28
**Branch:** 038-match-rule-operators
**Scope:** `git diff main...HEAD` after the rework around session kinds and conditions (base of the review: f86875c)
**Rounds:** 2 fix rounds, each re-reviewed by an independent agent
**Gate Outcome:** PASS (conditional: one Important finding is a design trade-off for the maintainer, FINDING-4)
**Invocation:** quality-gate (speckit-spex-ship, review-code stage, ask=smart)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 4 | 3 | 1 design decision |
| Minor | 22 | 11 | 11 |
| Notable | 4 | - | 4 |
| **Total** | **30** | **14** | **16** |

Duplicates are merged: the OpenCode retry order was reported by correctness, production readiness, architecture and Codex; the remembered condition after a harness change by correctness and Codex.

**Agents completed:** 5/5 internal (Goal Alignment skipped: no PR found), plus 2 re-review agents (one per fix round)
**External tools:** CodeRabbit completed (1 finding, on a spec artifact); Codex completed (2 findings, both also found internally, both fixed); Copilot skipped (disabled in config)

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 85
- **File:** Sources/UsageCore/Config/Configuration.swift (`TokenBasedSettings.choosingKind`, `settingConditionOn`, `validateForSaving`); Sources/AgentTacho/AccountSettingsView.swift (`SessionsFields.lastCondition`)
- **Category:** correctness
- **Source:** correctness agent (also reported by: codex)
- **Round found:** 1
- **Resolution:** fixed (4ff559b)

**What is wrong:** The Settings view remembers the last condition across a harness change. A Claude Code condition on Request id, unticked and then restored after switching the harness to Codex (or after choosing OpenCode Other provider), came back with a field Codex and OpenCode do not offer, and nothing refused it on save.

**Why this matters:** The file then holds `"field":"requestId"` for a Codex account; the next load reads the setting as unreadable, so a Codex account silently becomes "API key without a condition" (a widening) and an OpenCode account loses its kind (FR-004, edge case "Harness change").

**How it was resolved:** `TokenBasedSettings.offered(_:)` maps a remembered condition onto the harness's fields (an unoffered field becomes Model, the operator follows the field) in both transitions, and `validateForSaving` refuses a condition whose field or operator the harness does not offer. Tests: `TokenBasedSessionsTests.rememberedConditionFollowsTheHarness`, `unofferedFieldIsRefusedOnSave`.

### FINDING-2
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/UsageCore/Logs/LogIndex.swift (Phase 1), Sources/UsageCore/Logs/CodexSessionSource.swift
- **Category:** production-readiness
- **Source:** production readiness agent
- **Round found:** 1
- **Resolution:** fixed (e434102)

**What is wrong:** A sat-out file that grew before the next refresh was read from byte 0 but not as a retry. In an actively written session where the condition is slow on new lines (one file of the kind, the typical new gateway account), every refresh re-read the whole file, timed out once more and flagged it again: the condition was never given up.

**Why this matters:** The busiest file lost its incremental read and each refresh paid a full re-read plus a 50 ms time-out, against FR-007 ("when a condition times out again during that retry ... no longer retried") and SC-005.

**How it was resolved:** A flagged file that grew by appending (size at least its parsed offset) is read as a retry, in LogIndex and in the Codex source; a replaced, shorter file stays new data. Tests: `LogIndexTests.loneActiveSlowFileSettlesAfterOneRetry`, `CodexSessionSourceTests.grownSatOutSessionSettlesAfterOneRetry` (both fail without the fix, checked by reverting).

### FINDING-3
- **Severity:** Important
- **Confidence:** 75
- **File:** Sources/UsageCore/Logs/LogIndex.swift, Sources/UsageCore/Logs/CodexSessionSource.swift
- **Category:** correctness (regression of FINDING-2's fix)
- **Source:** re-review agent, round 1
- **Round found:** 2
- **Resolution:** fixed (b28dc48)

**What is wrong:** With grown sat-out files counted as retries, a grown file sorted before an unchanged sat-out file could time out on a newly appended line inside the retry phase, give the condition up, and leave the unchanged file's sat-out records unretried for good.

**Why this matters:** A time-out on new data cancelled the retry of other records, which FR-007 does not allow.

**How it was resolved:** Three tiers in both sources: retries of unchanged files, then retries of grown files, then everything else. Test: `LogIndexTests.unchangedRetriesRunBeforeGrownOnes` (fails with the two-tier order, checked by reverting).

### FINDING-4
- **Severity:** Important
- **Confidence:** 70
- **File:** Sources/UsageCore/Logs/LogIndex.swift (Phase 1, `fresh` for flagged files)
- **Category:** production-readiness
- **Source:** production readiness agent
- **Round found:** 1
- **Resolution:** remaining, design decision for the maintainer

**What is wrong:** A time-out early in a cold read (first refresh, rule change, window reset) flags every Claude Code file in which the condition was then skipped, and the next refresh reads each of them again from byte 0, because LogIndex keeps no raw lines.

**Why this matters:** For an Other provider or Vertex account that covers most of the user's work, the second refresh repeats most of the cold read once. The cost is bounded (one extra read; afterwards the retry either succeeds or gives the condition up), but it scales with the log volume, not with the 100 ms of SC-005.

**What needs to happen:** This is the trade-off accepted at the first code review (per-entry re-read instead of stored raw lines). Options: accept it; re-read only from the first skipped record; or cap the bytes re-read per refresh. Not changed autonomously.

### FINDING-5
- **Severity:** Minor
- **File:** Sources/UsageCore/Logs/OpenCodeSource.swift
- **Category:** correctness
- **Source:** correctness agent (also reported by: production readiness, architecture, codex)
- **Resolution:** fixed (e434102)

OpenCode retried per database, interleaved with earlier databases' new rows, so a time-out in new rows of one database made the condition sit out for another database's retries and they never settled. Now a pre-pass retries the sat-out messages of every database before any new rows; the main loop skips the retried ids. Test: `OpenCodeSourceTests.retriesOfEveryDatabaseRunBeforeNewRows`.

### FINDING-6 to FINDING-12 (Minor, fixed in 0d56a35 and 1bb35ab)
- Architecture: unused `DetectionRule.requestIdPrefix` and `.providerHint` removed (Attribution.swift).
- Architecture: SwiftUI view `MatchRuleNotes` renamed `SectionNotes`, doc cites FR-013, FR-018.
- Architecture: wrong spec citations corrected (AccountSettingsView FR-008/FR-016, FR-015 twice; ConfigStore FR-008); stale `Candidate.customMarker` doc (Attribution.swift).
- Test quality: OpenCode sit-out test asserts the record goes to `acc-vertex` (was `!= "acc-slow"`, which also passed for Unassigned).
- Test quality: misleading duplicate assertion in `AttributionTests.conditionBeatsPlainWithinAKind` removed; Codex overlap test asserts the names (US1 scenario 4); kind matrix gets an empty OpenCode provider and a Codex record without auth.
- Security (Notable, docs part): docs/configuration.md now says the 50 ms limit applies per record and a moderately slow pattern slows every refresh.
- Spec compliance: the subscription marker caption also shows on Codex subscriptions and now names the Codex home (FR-018, 1bb35ab).
- Correctness (Notable, comment part): `SessionKind.fallback` doc no longer claims an unreadable Codex setting never widens.

### Remaining Minor findings
- **Architecture:** `Attributor.timeOuts`/`skippedDecisions` are public, read only by tests, with docs that describe an older mechanism (Attribution.swift 241-249, MatchRuntime.swift 150-158).
- **Architecture:** "rule" still names a condition in MatchRuntime and the sources' comments (`init(rules:)`, "given-up rules").
- **Architecture:** `StoredMatchRule.migrated` reads spec 037 presets through `SessionKind.kind(stored:)`, coupling a frozen format to the live stored values (Configuration.swift, `StoredMatchRule`).
- **Architecture:** the view decides when the checkbox and Condition row show, and normalizes the operator, instead of UsageCore helpers (AccountSettingsView.swift `SessionsFields`, `ConditionControls.op`).
- **Architecture:** `Attributor.sitOutLogLine` hard-codes "50 ms".
- **Production readiness:** the account editor computes `matchOverlaps` and `directoryOnlyConflict` (with symlink resolution) on every body evaluation (AccountSettingsView.swift 326-329, 474-479).
- **Test quality:** the remembered condition (untick then tick restores it) lives in view state without a test (AccountSettingsView.swift `SessionsFields`).
- **Test quality:** no test for an invalid regex in a first-038 `matchRule` (two notes), unasserted conditions of three accounts in `oneFileWithEveryEarlierForm`, no attribution test of a migrated v0.8.0 marker (SessionKindStorageTests).
- **Test quality:** wall-clock bounds in MatchRuntimeTests can be flaky under parallel CPU load.
- **Test quality (round 2):** no Codex test for the three-tier retry order (LogIndex has one).
- **CodeRabbit:** specs/038-match-rule-operators/RUNBOOK.md steps 5 to 12 still describe the Custom/matchRule flow; the walkthrough stage rewrites the runbook.

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/Config/MatchCondition.swift 182-217, MatchRuntime.swift 115-148
- **Category:** security
- **Source:** security agent
- **Description:** The 50 ms limit is per record, not per refresh: a pattern that costs a few to 49 ms on every long line never sits out.
- **Rationale:** Self-inflicted availability only; the docs now say so. A per-refresh budget per condition would close it.

### NOTABLE-2
- **File:** LogIndex.swift, CodexSessionSource.swift, OpenCodeSource.swift, SessionLogSource.swift
- **Category:** architecture
- **Source:** architecture agent
- **Description:** The FR-007 retry protocol (flags, retry sets, ordering, epilogue with match memory and sit-out log lines) is written three times.
- **Rationale:** It already diverged once (OpenCode order, now fixed); a shared helper would keep the sources aligned.

### NOTABLE-3
- **File:** Sources/UsageCore/Config/SessionKind.swift `fallback(for:)`, Configuration.swift `decodeSessions`
- **Category:** correctness
- **Source:** correctness agent
- **Description:** An unreadable Codex condition (or 037 Codex custom rule) falls back to API key without a condition, which counts every API-key session; a readable kind is also discarded when only the condition is unreadable.
- **Rationale:** FR-011 mandates this; a spec evolution could keep the kind and use a condition that matches nothing.

### NOTABLE-4
- **File:** Sources/UsageCore/Logs/LogIndex.swift Phase 1
- **Category:** correctness
- **Source:** re-review agent, round 1
- **Description:** A grown sat-out file's re-read counts as the retry, so a time-out only on a newly appended line gives the condition up.
- **Rationale:** That bounds the cost (SC-005); FR-007 could say explicitly that a sat-out file that grew counts as retried, including its new lines.

## Post-Fix Spec Coverage

The fix rounds removed code only in Attribution.swift (two unused `DetectionRule` cases) and replaced one sort expression per source. All FR-001 to FR-020 keep their implementation; `make test` passed after every round.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| baseline | make test | 0 | 0 | 2258 + 73 passed |
| 1 | make test | 0 | 0 | 2262 + 73 passed |
| 2 | make test | 0 | 0 | 2264 + 73 passed |
| final (1bb35ab) | make test | 0 | 0 | 2264 + 73 passed |

## Remaining Findings

FINDING-4 (Important, design decision) and the eleven Minor findings above. None is a spec deviation that blocks the walkthrough.
