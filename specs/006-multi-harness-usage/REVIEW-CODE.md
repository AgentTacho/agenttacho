# Code Review: Multi-Harness Usage (Codex and OpenCode)

**Spec:** specs/006-multi-harness-usage/spec.md
**Date:** 2026-10-14
**Reviewer:** Claude (speckit.spex-gates.review-code)
**Diff:** `git diff main...HEAD` (branch 006-multi-harness-usage)

## Compliance Summary

**Overall Score: 97.7% (43/44)**

- Functional Requirements: 26/26 (100%)
- Edge Cases: 12/12 (100%)
- Success Criteria: 5/5 (100%, SC-003 by design, not benchmarked in this review)
- User Story narrative: 0/1 (one minor deviation, see US4)

Baseline `make test`: 442 tests in 50 suites passed.

## Detailed Review

### Functional Requirements

| FR | Implementation | Status | Notes |
|----|----------------|--------|-------|
| FR-001 | `App.swift:99-128` registers `OpenCodeSource` and `CodexSessionSource` next to `SessionLogSource` | Compliant | Claude Code path untouched apart from attribution refactor |
| FR-002 | `CodexSessionSource.swift:101-111`, `OpenCodeSource.swift:121-141` | Compliant | Missing default location logs "skipped", no issue |
| FR-003 | `Configuration.codexHomes/openCodeDirectories`, `SettingsView.swift` `DirectoryListSection`; dedupe by canonical home/db path and canonical file path | Compliant | |
| FR-004 | Codex re-parses only when size or mtime changed (`CodexSessionSource.swift:133`); OpenCode watermark on `time_updated` (`OpenCodeSource.swift:158-182`); parser skips undecodable lines | Compliant | |
| FR-005 | `OpenCodeSource.swift:186-192` keeps records, `staleHarnesses: [.openCode]`; busy timeout 250 ms | Compliant | |
| FR-006 | `RecordBatch.issues` become `SourceError`s naming harness and location (`RefreshCoordinator.swift`) | Compliant | |
| FR-007 | `RawUsageRecord` gains harness, providerHint, reasoningTokens, sessionId | Compliant | |
| FR-008 | `CodexSessionParser.swift:113-122` input minus cached minus cache-write; reasoning stays in output | Compliant | |
| FR-008a | Delta of running totals, unchanged/null-info/zero events skipped (`CodexSessionParser.swift:96-108`) | Compliant | |
| FR-008b | `OpenCodeSource.parse` adds reasoning to output and keeps `reasoningTokens` | Compliant | |
| FR-009 | Completed assistant messages only, keyed by message id, timestamp = `time.completed` | Compliant | |
| FR-010 | `projects.project(forCwd:)` in both sources | Compliant | |
| FR-011 | `Attributor` token-based candidates match all harnesses | Compliant | |
| FR-012 | `Provider.builtInRule(for:)` in `Attribution.swift` | Compliant | |
| FR-013 | Custom marker matched against meta+token line (Codex) and message JSON (OpenCode) | Compliant | |
| FR-014 | Per-session plan marker, re-resolved every refresh, parent inheritance incl. parents in older files | Compliant | |
| FR-015 | Tie-breaker by Codex home for same-kind subscription candidates | Compliant | |
| FR-016 | `Provider.openai`, icon, default name, settings picker | Compliant | |
| FR-017 | `AccountKind.codexSubscription`, `planAccounts` weekly token-only entries, skipped in `BarLayout`, no thresholds editor | Compliant | |
| FR-018 | Optional keys, harness decoded but unused in attribution; `tokenBasedAccounts` excludes codex plans | Compliant | |
| FR-019 | OpenCode `cost` never decoded | Compliant | |
| FR-020 | Reasoning priced as output; no dedicated reasoning price exists in the table | Compliant | |
| FR-020a | `PriceTable.canonicalModel` strips `@suffix`; imported batches normalized | Compliant | |
| FR-020b | Cache writes go to `cacheWrite5mTokens` | Compliant | |
| FR-021 | `UsageBreakdown.perHarness`, "Harnesses" details mode in `BreakdownView` | Compliant | |
| FR-022 | Per-location log lines with record counts or skip/fail reason | Compliant | |

### Edge Cases

All 12 edge cases are handled: partial last line skipped; busy DB stale; streaming message counted on completion and replaced by id; per-session auth mode; window filtering by record timestamp; cwd fallback via `ProjectResolver`; unknown provider to Unassigned unless custom marker; cache/reasoning split; repeated events; `@default` model ids; harness removal (missing db or files drop their records, deleted OpenCode rows pruned via live-id check); incremental OpenCode reads.

### User Story narrative

#### US4: "The dropdown and the diagnostic log show which harnesses were found and read."
**Status:** Minor deviation
**Issue:** The diagnostic log lists every harness and location read (FR-022), but the dropdown only shows source errors for failed locations, not which harnesses were found.
**Impact:** Minor. The acceptance scenarios and FR-022 are met.
**Recommendation:** Spec evolution: narrow the narrative to "the diagnostic log shows which harnesses were read; the dropdown shows failures", or add a small harness status line later.

### Extra Features (Not in Spec)

- `LiteLLMImporter` key ranking change for non-date `@` suffixes and `PriceBatch` decode normalization: needed to keep FR-020a consistent with existing imported price files. Helpful, recommend noting in spec.
- OpenCode live-id check prunes deleted messages: implements the "Harness removed" edge case. Helpful.

### Spec-Declared Constants

The spec has no `## Constants` section; check skipped.

## Recommendations

### Critical (Must Fix)
- None from spec compliance.

### Spec Evolution Candidates
- [ ] US4 narrative about the dropdown listing found harnesses.

## Conclusion

Spec compliance 97.7%, above the 95% deep review threshold. The only deviation is the US4 narrative (a spec evolution candidate). The deep review passed after one fix round.

## Deep Review Report

**Gate: PASS** (after fix round 1)
**Invocation:** quality-gate (ship pipeline)
**Details:** [review-findings.md](review-findings.md)
**Fix commits:** `ce8b5ab`, `9d759cd`

| Agent                   | Found | Fixed | Remaining | Status |
|-------------------------|-------|-------|-----------|--------|
| Correctness             |     5 |     4 |         1 | completed (1 Notable) |
| Architecture & Idioms   |    12 |     5 |         7 | completed (6 Minor, 1 Notable) |
| Security                |     4 |     2 |         2 | completed (1 Minor, 1 Notable) |
| Production Readiness    |     7 |     4 |         3 | completed (2 Minor, 1 Notable) |
| Test Quality            |    10 |     8 |         2 | completed (2 Minor) |
| Goal Alignment          |     0 |     0 |         0 | skipped (no PR found) |
| CodeRabbit (external)   |     1 |     1 |         0 | completed (0 findings on fix commit) |
| Copilot (external)      |     0 |     0 |         0 | skipped (disabled in config) |
| Codex (external)        |     0 |     0 |         0 | failed (usage limit reached) |
| Re-review (round 1)     |     7 |     5 |         2 | completed (1 Minor partial, 1 Notable) |
| Test Suite (regression) |     0 |     0 |         0 | passed (442, then 456, then 459 tests) |
| **Total (deduplicated)**|  **43** | **25** |    **18** | |

Severity after deduplication: Critical 1/1 fixed, Important 8/8 fixed, Minor 16/28 fixed, Notable 6 (informational, captured to brainstorm/idea-inbox.md).

MVP: Architecture & Idioms (12 findings)

Key fixes applied:
1. Codex fork and subagent files: the copied parent burst (stamped 1 to 2 ms after the fork in real data) no longer double counts parent usage, and copied plan markers no longer count as the child's own (correctness, Critical).
2. An all-zero Codex event mid-session no longer resets the baseline, which had caused the full total to be counted again (correctness, test-quality).
3. OpenCode and Codex token values are clamped instead of trapping on corrupt input (security).
4. OpenCode first read is bounded to the window (minus one hour), not the whole history (production).
5. Codex records are cached per file and rebuilt only on auth-mode, rule or price changes; raw line text is built only for custom markers (production).
6. Every Codex scan or read failure is written to the diagnostic log (FR-022) (architecture, production).
7. Collapsing legacy `@` price ids keeps one entry instead of rejecting the import file (correctness).
8. New tests: WAL database with an open writer, re-pricing without re-reading, window-crossing Codex session, harness removal, orphan subagent, rule-change re-attribution, first-read bound.

Remaining findings: no Critical or Important. 12 Minor items (refactors, doc text, extra error-branch tests) are listed in review-findings.md.

Post-fix spec coverage: 26/26 functional requirements verified (all covered).

Notable observations: 6 captured to brainstorm/idea-inbox.md.
