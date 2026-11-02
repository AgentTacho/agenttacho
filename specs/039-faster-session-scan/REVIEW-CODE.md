# Code Review: Faster Session Scan

**Spec:** specs/039-faster-session-scan/spec.md
**Date:** 2026-10-28
**Reviewer:** Claude (speckit.spex-gates.review-code)
**Diff:** `git diff main...HEAD`, reviewed at c977833; review fixes 5c55f50, df8aa61, 8a1cf80, 6a57ca2, f3f5c5e, 2690531, bb34cbb; after the maintainer's decisions 46a01de, 7872be9, 3fb8ede

## Compliance Summary

**Overall Score: 93% (38/41) after the review fixes; 90% (37/41) before them**

- Functional Requirements: 21/21
- Edge Cases: 12/12 (11/12 before 5c55f50: a readable directory whose `projects` or `sessions` folder could not be read gave an empty report instead of an error)
- Success Criteria: 5/8 (SC-003, SC-004, SC-005, SC-007, SC-008 met; SC-001 and SC-002 met only apart; SC-006 missed)

Every requirement the code can meet is met (33/33). The three open criteria are measured outcomes of BENCHMARK.md, not code deviations: FR-020 routes a miss of SC-001 or SC-002 to the maintainer as its own change, and the cold runs and the real-corpus repeat are maintainer walkthrough steps by FR-006 and FR-009. The deep review therefore ran although the overall score is below 95%; the three criteria are listed as Ambiguous below.

## Functional Requirements

| Req | Implementation | Status |
|---|---|---|
| FR-001 bench through the Makefile, both readers, empty index, app config or given, derived or given window | `make bench-scan`; `ScanBench.run` (`SessionLogSource`/`CodexSessionSource` with `scanTargets`/`homes`), `WindowResolver` as `RefreshCoordinator` | Compliant (defaults now tested, df8aa61) |
| FR-002 report figures | `ScanBenchReport.text`, `ProcessResources.snapshot`, `ScanFigures` | Compliant |
| FR-003 no line content, `~` paths | `PathText.shown`, `oneLine`; tests check no home path and no content | Compliant |
| FR-004 digest fields, stable order, never under agents' directories | `RecordsDigest`, `refuseDigest` | Compliant after 5c55f50 (linked `projects`/`sessions` trees) and df8aa61 (`link/..` paths) |
| FR-005 comparison through the Makefile | `make bench-compare`, `RecordsDigest.compare` | Compliant |
| FR-006 baseline first, record with commit, corpus, condition | BENCHMARK.md baseline `aff144f` and one block per step | Compliant for the implementation; cold runs open as maintainer steps, as the spec assigns them |
| FR-007 `cpu <seconds> s` in both refresh lines | `SessionLogSource.statsLine`, Codex refresh line | Compliant (Claude Code call site now tested, 6a57ca2) |
| FR-008 committed fixture digests, fixture config, fixed window | `Fixtures/digests/*`, `make bench-digests`, `fixtureRecordsEqualTheCommittedDigest` | Compliant |
| FR-009 real-corpus digests identical | BENCHMARK.md "Digest comparisons": identical at every step | Compliant for the implementation; the maintainer's repeat is a walkthrough step |
| FR-010 read-only, offsets, complete lines, CRLF, dedupe, batch cap, re-read rules | `LogIndex.readUnreadBytes`, `SessionLineReader.forEachLine`; merge and batches unchanged | Compliant |
| FR-011 Codex output unchanged | typed decoding; Codex tests unchanged | Compliant after 8a1cf80 (a JSON boolean in a number field counted 1 or 0 before) |
| FR-012 lines in place | `SessionLineReader` over the read buffer; only candidate lines copied | Compliant |
| FR-013 bounded head and tail scans, whole-line fallback, top-level `type` only | `SessionLineClassifier` | Compliant |
| FR-014 only assistant lines decoded, only shape lines searched, undecided as before | `LogIndex.read` switch | Compliant (fallback shape line and nested shape object now tested, 6a57ca2) |
| FR-015 one shared timestamp parser, fallback to the formatter | `ISO8601Timestamp`; both readers call it | Compliant |
| FR-016 Codex typed values | `CodexLine`, `CodexPayload`, `CodexTokenUsage`, `CodexRateLimits` | Compliant |
| FR-017 bounded workers, at most the cores, utility, largest first, every refresh | `ScanWorkers` (default `min(4, cores / 2)`) | Compliant (parallel jobs now tested, 6a57ca2) |
| FR-018 no blocked pool, test of a second refresh during a scan | `ScanWorkers.offload`, scan gate in both sources, `ScanConcurrencyTests` | Compliant (pool test that can fail added, 6a57ca2) |
| FR-019 no dependency | Package.swift adds only the `ScanBench` target | Compliant |
| FR-020 no field extractor | `JSONDecoder` kept | Compliant |
| FR-021 OpenCode untouched | no OpenCode file in the diff | Compliant |

## Edge Cases

All 12 are handled: a key outside the bounded portion, a nested `type` only, no `type` key, a file replaced or shrunk, a file growing during the read, one file above the batch cap, timestamp forms the fast path does not take, few cores, a directory without `projects` or an unreadable one (the unreadable `projects`/`sessions` folder since 5c55f50), an unreadable or invalid configuration, a missing or unreadable digest, and a cold run without `purge` (disk bytes in the report).

## Success Criteria

| Criterion | Status | Evidence |
|---|---|---|
| SC-001 under 3 s warm and cold | Partial | 2.910 s with the corpus cached, 3.117 to 4.047 s when memory pressure evicted part of it; cold run open (maintainer step) |
| SC-002 at most 200% | Partial | 167 to 194% in the runs from disk, 210% in the cached run; not met together with SC-001 |
| SC-003 peak memory not above baseline | Met | 278 to 334 MB against 752 MB |
| SC-004 digests identical | Met | fixture digests in the suite; every step identical on the real corpus |
| SC-005 incremental refresh not slower | Met | 0.735 to 0.801 s against 0.769 s |
| SC-006 Codex CPU at most half | Missed | 58% of the baseline (0.271 s against 0.469 s, five runs each) |
| SC-007 benchmark record | Met for the automated gates | warm runs and fixture digests; cold rows added at the walkthrough |
| SC-008 suite passes, Codex expectations unchanged | Met | `make test` 2362 + 73 tests; Codex suites only gained tests |

## Spec-Declared Constants

The spec has no `## Constants` section; check skipped.

## Deep Review Report

**Gate:** PASS. One fix round with an independent re-review and a CodeRabbit re-review, then the maintainer's decisions on the rest. No Critical finding. All four Important findings are fixed with tests that fail without the fix; the last one (FINDING-6, attribution's 50 ms regex limit measured on a utility-priority thread) was fixed in 46a01de as the maintainer decided: the merge and attribution run at the refresh's priority, the parse jobs stay at utility. Details in `review-findings.md`.

| Agent | Found | Fixed | Remaining | Status |
|---|---|---|---|---|
| Correctness | 0 | 0 | 0 | completed (fuzzed classifier and timestamp parser against the old path, 0 mismatches) |
| Architecture & Idioms | 4 | 1 (comments) | 3 Minor, 1 Notable | completed |
| Security | 4 | 3 | 1 Notable | completed |
| Production Readiness | 5 | 1 | 2 Minor (deferred to the inbox), 2 Notable | completed |
| Test Quality | 10 | 9 | 1 Notable (partly addressed) | completed |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR found) |
| Re-review, fix round 1 | 0 | 0 | 0 | completed (one note below the bar: the permission-based tests fail if run as root) |
| CodeRabbit (external) | 6 | 0 | 0 in scope | completed (all six on files outside this diff or on spec text; the re-review of the fixes found 0) |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 2 | 2 | 0 | completed |
| Test Suite (regression) | 0 | 0 | 0 | passed after every fix commit |

**Fix commits:**
- 5c55f50 fix(bench): refuse linked session trees and unreadable reader folders
- df8aa61 fix(bench): check the digest path as the write reaches it
- 8a1cf80 fix(scan): Codex booleans in number fields count as before
- 6a57ca2 test(scan): pool, parallel jobs, parent cycles and fallback shape lines
- f3f5c5e docs(bench): private bench directory, ignored digests, accurate comments
- 2690531 test(scan): wait for the queued collects instead of sleeping
- bb34cbb test(bench): a digest that cannot be written is an error
- 46a01de fix(scan): attribution runs at the refresh's priority
- 7872be9 docs(bench): review fix comparison and the maintainer's decision
- 3fb8ede docs(inbox): field extractor follow-up and four deferred review findings

**Maintainer decisions (2026-10-28):**
- FINDING-6: fixed as decided (46a01de). The bench comparison right after it, back to back with the baseline binary, compared identical (87385 records) and took 3.732 s at 173% against 9.192 s at 344%.
- SC-001 together with SC-002, and SC-006: missed as measured, accepted for this feature; the spec targets stay. The hand-written field extractor (FR-020, approach B) is the measured follow-up (BENCHMARK.md "Maintainer decision", inbox `hand-written-field-extractor`).
- The Minor design findings (FINDING-7 to FINDING-11) stay unfixed on this branch and are recorded in `brainstorm/idea-inbox.md`: `codex-parse-byte-cap`, `raw-line-copies-without-rules`, `duplicated-scan-gate`, `scan-workers-api-shape`.
