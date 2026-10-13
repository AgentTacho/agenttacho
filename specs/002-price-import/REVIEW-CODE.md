# Code Review: Price Import

**Spec:** specs/002-price-import/spec.md (formats from contracts/*.md)
**Date:** 2026-10-13
**Branch:** 002-price-import
**Reviewer:** Claude (speckit-spex-gates-review-code, ship pipeline stage 7)
**Scope:** `git diff bfc283c..HEAD -- Sources Tests README.md`: Sources/UsageCore/Pricing (ImportedPrices, LiteLLMImporter, PriceCSV, PriceDiff, PriceImportError, PriceTable), Config, Logs/SessionLogSource, Snapshot/RefreshCoordinator, Subscription/SubscriptionSource, Sources/LLMUsageMenuBar (App, PriceImportSheet, SettingsView), the tests, and README.md

## Compliance Summary

**Overall Score: 100%** (before and after the fix loop)

- Functional Requirements: 40/40 (FR-001 to FR-034, including FR-017a, FR-017b, FR-020a, FR-020b, FR-020c and FR-023a)
- Edge Cases: 11/11
- Success Criteria: SC-002, SC-003, SC-005 and SC-007 are verified by code and tests. SC-004 and SC-006 are verified by code; SC-006 still needs a real Vertex OpenAI session to confirm the model id. SC-001 is a UI timing goal that was not measured.
- Spec-declared constants: the spec has no `## Constants` section, so this check was skipped.

## Detailed Review

### Functional Requirements

| Requirement | Implementation | Status | Notes |
|-------------|---------------|--------|-------|
| FR-001 layer order | PriceTable.effective | Compliant | built-in, then provider batches by `importedAt`, then CSV, then overrides |
| FR-002 newest provider wins | PriceTable.effective (sorted by importedAt), AppModel.applyImport stamps apply time | Compliant | |
| FR-003 normalization and prefix fallback on merged table | PriceTable.price(for:) on the effective table | Compliant | After the fix, the preview diff also respects the prefix fallback |
| FR-004 imports never touch overrides | ImportedPriceStore separate file; overrides applied last | Compliant | |
| FR-005 source per price | PriceSource.imported(ImportProvenance) | Compliant | |
| FR-006 Anthropic, OpenAI (direct + Vertex), Gemini | LiteLLMImporter.selection | Compliant | |
| FR-007 all chat models, OpenAI responses | selection modes | Compliant | |
| FR-008 per million, 6 decimals | LiteLLMImporter.perMillion | Compliant | tested with non-tie values |
| FR-009 five fields, cache default input, skip without input/output | LiteLLMImporter.batch | Compliant | |
| FR-010 prefix stripping | selection.prefix | Compliant | |
| FR-011 dated variants | candidate merge, undated wins, else latest date | Compliant | |
| FR-012 30 s, 20 MB, no cache | priceListSession, streaming cap | Compliant | |
| FR-013 malformed entries skipped | perMillion, id rule | Compliant | |
| FR-014 header, optional columns, any order | PriceCSV.parse | Compliant | |
| FR-015 derived cache prices flagged | derivationFactors, ProposedImport.derived, DerivedMarker | Compliant | |
| FR-016 separators, decimal comma, quotes, BOM | detectSeparator, splitRecords, number | Compliant | |
| FR-017 / 017a / 017b row errors, duplicates, no valid rows | PriceCSV.parse | Compliant | |
| FR-018 CSV replaces CSV | ImportedPrices.replacing | Compliant | |
| FR-019 export format and round trip | PriceCSV.export | Compliant | |
| FR-020 to FR-020c preview categories | PriceDiff.compute, PriceImportPreview | Compliant | after the fix, all skipped rows are listed and rendered lazily |
| FR-021 apply replaces same kind, recompute | AppModel.applyImport, requestReprice | Compliant | |
| FR-022 cancel discards | PriceImportSheet Cancel | Compliant | |
| FR-023 removal with confirmation and count | SettingsView confirmationDialog, AppModel.removeImport | Compliant | |
| FR-023a reprice without usage endpoint | RefreshCoordinator reprice mode, NetworkBoundSource | Compliant | marker conformance is now guarded by a test |
| FR-024 errors shown, prices unchanged | PriceImportError, sheet failed state, alerts | Compliant | |
| FR-025 to FR-027 separate file, atomic, load and notice | ImportedPriceStore, AppModel init | Compliant | |
| FR-028 Import menu | PriceSettingsTab.importMenu | Compliant | |
| FR-029 source column | ReadOnlyPriceRow, PriceFormat.source | Compliant | |
| FR-030 filter, default, remembered | @AppStorage("priceFilter"), visibleEntries | Compliant | |
| FR-031 status line with age | statusLines, PriceFormat.status | Compliant | |
| FR-032 edit creates override | Override button, Add model | Compliant | |
| FR-033 one log line with counts | applyImport/removeImport log lines | Compliant | |
| FR-034 no background fetch | provider fetch only from the Import menu | Compliant | |

### Edge Cases

All 11 edge cases are compliant:
- dated variants
- missing cache prices
- malformed entries
- no usable entries
- more than 20 MB
- the same model in two provider imports
- damaged file at launch (log line, notice, replaced by the next import)
- save failure
- suffix normalization
- BOM and quotes
- offline operation

### Extra Features (Not in Spec)

- **CSV file size limit of 5 MB** (added in the fix loop). This is a hardening limit, documented in the README and contracts/price-csv.md. Recommendation: keep.
- **Model id rule for imports.** LiteLLM skips such ids as malformed; CSV reports them as "invalid model id" (added in the fix loop). This prevents spreadsheet formula injection and log forging, and keeps the SC-005 round trip intact. It is documented in both contracts. Recommendation: keep.
- **Failure log lines for imports and export** (added in the fix loop). This complements FR-033 for diagnosis. Recommendation: keep.

## Code Quality Notes

The pricing core is pure and well tested: 230 tests in total, 15 of them added during this review. The before/after effective-table diff gives one consistent mechanism for preview, shadowing and removal impact. The riskiest change is the second run mode of `RefreshCoordinator`. It is covered by tests for reprice, pending precedence and fallback. The marker conformance of the real sources is now covered too.

## Recommendations

### Critical (Must Fix)
- None.

### Spec Evolution Candidates
- None. The fix loop updated research.md R6 and the contracts to describe the prefix-fallback classification, the id rule and the 5 MB limit. None of these changes a requirement.

### Optional Improvements
- The 6 open Minor findings in review-findings.md (FINDING-8, FINDING-16, FINDING-23 to FINDING-26).
- The 5 Notable observations, captured in brainstorm/idea-inbox.md.

## Conclusion

Compliance is 100%, and no Critical or Important findings remain. Ready for verification.

## Deep Review Report

**Gate: PASS** (after fix round 3)
**Agents completed:** 5/5 internal + 1 re-review agent per round (3) + CodeRabbit (4 runs)
**Skipped:** Goal Alignment (no PR), Copilot (disabled in config)
**Failed:** Codex (usage limit error, no findings)

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 4 | 4 | 0 |
| Minor | 30 | 24 | 6 |
| Notable | 5 | - | 5 |
| **Total** | **39** | **28** | **11** |

Review Agents:

| Agent                   | Found | Fixed | Remaining | Status    |
|-------------------------|-------|-------|-----------|-----------|
| Correctness             |     4 |     3 |         1 | completed |
| Architecture & Idioms   |     7 |     4 |         3 | completed |
| Security                |     4 |     3 |         1 | completed |
| Production Readiness    |     3 |     2 |         1 | completed |
| Test Quality            |    12 |     7 |         5 | completed |
| Re-review (rounds 1-3)  |     9 |     9 |         0 | completed |
| Goal Alignment          |     0 |     0 |         0 | skipped (no PR found) |
| CodeRabbit (external)   |     1 |     1 |         0 | completed (initial run 0 findings, round 1 one Minor, rounds 2 and 3 none) |
| Copilot (external)      |     0 |     0 |         0 | skipped (disabled in config) |
| Codex (external)        |     0 |     0 |         0 | failed (usage limit) |
| Test Suite (regression) |     0 |     0 |         0 | passed (230 tests, 21 suites) |
|-------------------------|-------|-------|-----------|-----------|
| Total                   |    40 |    29 |        11 |           |

The per-agent rows count the CSV size cap twice, since Security and Production Readiness both reported it. The severity table above is deduplicated. Remaining counts include Notable observations.

Agent Leaderboard MVP: Test Quality (12 findings)

Key fixes applied:
1. A test now checks that the real `SubscriptionSource` is network-bound, so a reprice never calls the usage endpoint (test-quality, FR-023a).
2. The reprice test uses an advancing clock, so it now proves `lastSuccessfulRefreshAt` is not moved (test-quality).
3. All skipped CSV rows are listed again (FR-020c), rendered as lazy 200-line chunks (re-review rounds 1 and 2).
4. The preview diff respects the prefix fallback for removed and "new" models (correctness, re-review).
5. The preview, removal confirmation, export and log counts use the overrides shown on the tab (correctness, re-review).
6. Model id rule for LiteLLM, CSV and Add model: no formula-leading, control-character or line-break ids (security, re-review).
7. The diagnostic log escapes control characters and line separators (security, re-review).
8. CSV import is limited to 5 MB through a bounded read; import, CSV and export failures are logged (security, production-readiness, coderabbit).
9. DecimalField shows 6 decimals, so overriding an imported price keeps its value (correctness).
10. Fifteen tests added for rounding, non-number cache values, @-dated variants, CSV line numbers and quoting, cross-provider diffs, invalid save and load, id rules and log escaping (test-quality).

Post-fix spec coverage: 40/40 requirements verified, all covered.

Notable observations: 5 captured to brainstorm/idea-inbox.md

Details: specs/002-price-import/review-findings.md
