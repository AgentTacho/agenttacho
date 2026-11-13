# Code Review: Claude Code Auto-mode Classifier Usage (spec 045)

**Spec:** specs/045-claude-automode-classifier-usage/spec.md
**Date:** 2026-11-13
**Reviewer:** Claude (speckit-spex-gates-review-code)

## Compliance Summary

**Overall Score: 97% (33/34)**

- Functional Requirements: 16/17 (FR-001 to FR-016 and FR-008a; FR-016 partial, see below)
- Success Criteria: 5/5
- Edge Cases: 12/12
- Spec-declared constants: none (no `## Constants` section)

## Functional Requirements

| FR | Implementation | Status |
|---|---|---|
| FR-001 | `DecisionLogProbe.logPath` (only `<cwd>/.automode_decisions.jsonl`). Raw directories are deduplicated, and canonical spellings are claimed once per call. Detection uses `lstat` with `S_IFREG`, then `open(O_RDONLY\|O_NOFOLLOW\|O_NONBLOCK)` and `fstat`. `maximumSize` is 64 MB, and a skip is logged once per file through `loggedTooLarge`. | Compliant |
| FR-002 | `classifierStep` checks only directories of in-window Claude Code session records with a `cwd`. `inspect` does not read a log older than the window, and `update` drops it. | Compliant |
| FR-003 | Unchanged, grown, shorter, incomplete-line and gone files are handled by `inspect` and `ClassifierLogIndex.update`. Since the review, the file identity (inode) is compared too (FINDING-4, FINDING-12). | Compliant |
| FR-004 | `ClassifierRowParser.parse` checks for a JSON object, a finite numeric `ts`, a non-empty model, and non-negative integer counters with at least one above zero. Unknown fields are ignored. Since the review, counters above 2^32 are malformed (FINDING-1). | Compliant |
| FR-005 | `spansByDirectory` keys spans by session key and canonical directory. The session key is the session id, or the file path (`LogIndex`). Spans use in-window records only, with a 300 s grace period and inclusive `covers`. | Compliant |
| FR-006 | `account(of:)` uses the union over `Set<String?>`. It never applies match rules to a row, and attribution is recomputed every refresh from the current spans. | Compliant |
| FR-007 | The project comes from the covering span, or else from a span in the same directory (`projects.project(forCwd:)`). | Compliant |
| FR-008 | Counters map to input, cache read, cache write (5-minute) and output. Records are priced by `PriceTable`, and `costUSD` is never decoded. | Compliant |
| FR-008a | Row id is `<canonical log path>#<line offset>`. There is no dedupe against session records (requestId `""`). | Compliant |
| FR-009 | `normalizedModel` removes one trailing `[...]` marker. | Compliant |
| FR-010 | `RecordOrigin.classifier`. No consumer reads it. | Compliant |
| FR-011 | Session records only gain `sessionKey` and `cwd`. Their keys, pricing and dedupe are unchanged (SC-003 test). | Compliant |
| FR-012 | Each check runs on its own thread, with canonicalization inside the 2 s limit. A busy directory gets no new check, a time-out is logged once until a check finishes, and rows of a timed-out directory keep counting. The review added a cap on stuck checks that leaves healthy directories running (FINDING-6, FINDING-11). | Compliant |
| FR-013 | The summary line counts logs read, rows counted, assigned, unassigned, without usage and malformed. Each possible double recording is noted once per session. Nothing beyond directories, counts and session ids is logged. | Compliant |
| FR-014 | No write, create or delete call on any decision log or setting (`refreshWritesNothingInTheWorkingOrConfigDirectory`). | Compliant |
| FR-015 | Only six fields are decoded. The row keeps only time, model and counters. | Compliant (see Minor on chunk retention) |
| FR-016 | The README "How it works" entry and the "Security and privacy" row are both present. The website's privacy section lives in the site repository and is not part of this diff, so it cannot be verified here. | Partial |

## Success Criteria

- SC-001: `probeFixtureGivesTheCombinedTotal` gives 149,792.
- SC-002: `repeatedRefreshesCountEachRowOnce`.
- SC-003: `withoutDecisionLogSessionRecordsAreUnchanged`.
- SC-004: `steadyStateStepOverFiftyLogsTakesUnderFiftyMilliseconds`, now with realistic sessions and the median of five runs.
- SC-005: `newSessionOnAnotherAccountMakesCoveredRowsUnassigned` and the attribution tests.

## Edge Cases

All 12 trace to the code above: removed worktree, slow volume, logs before the window, missing cwd, sessions at different times, the grace period, two spellings, another classifier model, a missing `classifierModel`, an unmounted volume, a session split over two accounts, and decisions without counters. Two of them gained tests in this review: different times on different accounts, and two spellings in attribution.

## Extra Features (Not in Spec)

These were added during the review. They are spec evolution candidates:

- The counter bound of 2^32 (FR-004).
- File identity by inode in the incremental read (FR-003).
- `maximumStuckChecks = 16` (FR-012).

## Deviations Fixed During Review

- FR-003: a replaced log of the same or larger size kept the old rows (afe7753, d3a53f6).
- FR-012: rows were dropped when a new spelling timed out (afe7753), and the round 1 cap stalled healthy directories (d3a53f6).
- US4 and FR-004: a hostile counter crashed every refresh (feff31b).

## Deep Review Report

**Gate: PASS** (0 Critical, 0 Important remaining after 2 fix rounds). Details are in `review-findings.md`.

| Agent | Found | Fixed | Remaining | Status |
|---|---|---|---|---|
| Correctness | 3 | 1 | 2 | completed |
| Architecture & Idioms | 9 | 4 | 4 (+1 Notable) | completed |
| Security | 4 | 2 | 1 (+1 Notable) | completed |
| Production Readiness | 7 | 4 | 1 (+2 Notable) | completed |
| Test Quality | 8 | 7 | 1 | completed |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR) |
| Re-review (fix commits) | 2 | 1 | 1 | completed |
| CodeRabbit (external) | 7 | 5 | 2 | completed (2 more findings on spec artifacts, same issue as Codex FINDING-4) |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 2 | 2 | 0 | completed |
| Test Suite (regression) | 0 | 0 | 0 | passed |

Duplicates across agents are counted once in the totals below.

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 1 | 1 | 0 |
| Important | 11 | 11 | 0 |
| Minor | 20 | 9 | 11 |
| Notable | 4 | - | 4 |

MVP: Architecture & Idioms (9 findings)

Key fixes applied:

1. Counters above 2^32 are malformed, so a hostile log cannot crash every refresh (correctness, security).
2. Session spans are built in place with a token counter set and only where rows exist (production, CodeRabbit).
3. A replaced decision log is read from the start, by inode, at any size or date (Codex, CodeRabbit).
4. Rows of a directory stay while a spelling is unresolved (Codex).
5. A cap on stuck probe checks that defers only unproven directories (CodeRabbit, re-review).
6. The summary line marks per-refresh line counts, and records are appended in place (architecture, production).
7. Tests:
   - non-overlapping sessions and two spellings in attribution;
   - the double-recording log line;
   - blocked canonicalization;
   - index branches;
   - no malformed count for an unfinished line;
   - FR-015 sentinel;
   - a realistic SC-004 timing test.

Two CodeRabbit "major" findings were triaged to Minor; both need a design decision:

- `ClassifierLogIndex.swift:157-171`: one unresolved spelling keeps unrelated entries, counted as Unassigned.
- `DecisionLogProbe.swift:158-181`: no admission bound inside one refresh.

Post-fix spec coverage: 17/17 requirements verified. No requirement code was removed.
