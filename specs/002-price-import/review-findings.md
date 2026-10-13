# Deep Review Findings

**Date:** 2026-10-13
**Branch:** 002-price-import
**Rounds:** 3 fix rounds (plus one trailing Minor fix after round 3)
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline stage 7, review-code)
**Review range:** `git diff bfc283c..HEAD -- Sources Tests README.md`

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 4 | 4 | 0 |
| Minor | 30 | 24 | 6 |
| Notable | 5 | - | 5 |
| **Total** | **39** | **28** | **11** |

**Agents completed:** 5/5 internal (Correctness, Architecture & Idioms, Security, Production Readiness, Test Quality), one combined re-review agent per fix round (3), CodeRabbit (4 runs)
**Skipped:** Goal Alignment (no PR found), Copilot (disabled in config)
**Failed:** Codex (usage limit reached, no findings)

The initial five-agent pass found 0 Critical and 2 Important findings, both in test quality. The re-review agents found 2 more Important findings, each one introduced by the previous round's fix, and all were fixed in the next round. One finding was reported by two agents (Security FINDING-3 and Production FINDING-1, CSV size cap) and is counted once. Below, a finding and the follow-ups that re-review agents or CodeRabbit raised on the same fix share one entry. The summary counts each raw finding once.

## Findings

### FINDING-1 (Important, fixed round 1)
- **Severity:** Important
- **Confidence:** 90
- **File:** Tests/UsageCoreTests/RefreshCoordinatorTests.swift, Sources/UsageCore/Subscription/SubscriptionSource.swift:7
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** fixed (round 1)

**What is wrong:** Every FR-023a test used the `GatedNetworkSource` double. Nothing checked that the real `SubscriptionSource` carries the `NetworkBoundSource` marker. The coordinator decides reuse only through `$0 is NetworkBoundSource`.

**Why this matters:** If someone dropped that one-line conformance, every reprice would call the rate-limited usage endpoint again (FR-023a), and the suite would still pass.

**How it was resolved:** Added `realSourcesCarryTheNetworkBoundMarkerAsExpected`, which checks that a real `SubscriptionSource` is `NetworkBoundSource` and a real `SessionLogSource` is not.

### FINDING-2 (Important, fixed round 1)
- **Severity:** Important
- **Confidence:** 85
- **File:** Tests/UsageCoreTests/RefreshCoordinatorTests.swift (repriceReusesNetworkResultsAndRecomputesRecords)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** fixed (round 1)

**What is wrong:** The test used a constant clock, so `second.lastSuccessfulRefreshAt == first.lastSuccessfulRefreshAt` also held when a reprice wrongly stamped itself as a successful refresh.

**Why this matters:** A regression would make reused subscription data look freshly fetched.

**How it was resolved:** Added an `AdvancingClock` test helper. The test now asserts that the two snapshots have different `generatedAt` and that `lastSuccessfulRefreshAt` stays at the first refresh.

### FINDING-3 (Important, fixed round 2)
- **Severity:** Important
- **Confidence:** 85
- **File:** Sources/LLMUsageMenuBar/PriceImportSheet.swift
- **Category:** correctness (spec deviation introduced by round 1)
- **Source:** re-review round 1
- **Resolution:** fixed (round 2)

**What is wrong:** Round 1 capped the skipped-rows list at 200 entries and showed the rest only as a count.

**Why this matters:** FR-020c says skipped entries are always listed in full, and FR-017 requires every invalid row to be reported with its line number and reason.

**How it was resolved:** The cap was removed, so every skipped row is listed again. FINDING-4 covers the rendering cost.

### FINDING-4 (Important, fixed round 3)
- **Severity:** Important
- **Confidence:** 70
- **File:** Sources/LLMUsageMenuBar/PriceImportSheet.swift
- **Category:** production-readiness (introduced by round 2)
- **Source:** re-review round 2
- **Resolution:** fixed (round 3)

**What is wrong:** Round 2 joined all skipped rows into one `Text`, rebuilt on every body evaluation, inside a non-lazy stack. A crafted 5 MB CSV whose header passes the column check could produce millions of skipped rows.

**Why this matters:** Laying out such a file freezes the menu bar app on the main thread.

**How it was resolved:** `PriceImportPreview` builds the rows once in its initializer, in chunks of 200 lines. Each chunk is one `Text` and a direct child of a `LazyVStack`, so all rows stay listed (FR-020c) and only visible chunks are laid out.

### FINDING-5 (Minor, fixed round 1)
- **File:** Sources/UsageCore/Pricing/PriceDiff.swift
- **Category:** correctness
- **Source:** correctness-agent
- **Resolution:** fixed (round 1)

**What is wrong:** A removed model's fallback ignored the prefix fallback of `price(for:)` (FR-003). For example, removing `claude-x-latest` was shown as "unpriced" although `claude-x` still prices it.

**How it was resolved:** The removal fallback now uses `after.price(for:)`. A model whose fallback row has the same prices is not listed. Covered by `removalUsesThePrefixFallback`.

### FINDING-6 (Minor, fixed rounds 1 and 2)
- **File:** Sources/LLMUsageMenuBar/App.swift, SettingsView.swift, PriceImportSheet.swift
- **Category:** correctness
- **Source:** correctness-agent; re-review round 1 (follow-up)
- **Resolution:** fixed

**What is wrong:** The Prices tab shows draft overrides, but the preview, removal confirmation and export used the saved ones. They could disagree during the 600 ms debounce or while another tab held an invalid value.

**How it was resolved:** The overrides shown on the tab are passed to the preview, the removal confirmation, the export, and the apply and remove log counts. `PriceImportRequest` now carries `overrides`.

### FINDING-7 (Minor, fixed round 1)
- **File:** Sources/LLMUsageMenuBar/SettingsView.swift (DecimalField)
- **Category:** correctness
- **Source:** correctness-agent
- **Resolution:** fixed (round 1)

**What is wrong:** `DecimalField` showed 4 decimals. "Override" on an imported 6-decimal price (FR-008) rounded it silently.

**How it was resolved:** `DecimalField` now shows `.fractionLength(0...6)`.

### FINDING-8 (Minor, open)
- **File:** Sources/LLMUsageMenuBar/App.swift, Sources/UsageCore/Pricing/PriceTable.swift, SessionLogSource.swift, RefreshCoordinator.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** open (decision: documentation-only; not worth a broad comment rewrite in this feature)

**What is wrong:** New doc comments cite spec 002 FR numbers without naming the spec. The same files cite spec 001 FR numbers, and the numbers collide (for example FR-024 and FR-034).

**What is needed:** Qualify the references, for example `(002 FR-023a)`. Best done in a follow-up comment pass over both specs.

### FINDING-9 (Minor, fixed round 1)
- **File:** Sources/LLMUsageMenuBar/PriceImportSheet.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** fixed (round 1)

**What is wrong:** The `.applying` phase was never rendered, because apply is synchronous.

**How it was resolved:** The phase and its view branches were removed.

### FINDING-10 (Minor, fixed round 1)
- **File:** Sources/UsageCore/Snapshot/RefreshCoordinator.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** fixed (round 1)

**What is wrong:** The doc comment of `requestReprice()` said the endpoint is not called. A reprice without a stored network result silently ran a full refresh.

**How it was resolved:** The doc comment now describes the fallback, and the fallback writes a log line.

### FINDING-11 (Minor, fixed round 1)
- **File:** Sources/UsageCore/Config/Configuration.swift (`samePrices`), ImportedPrices.swift (`validate`)
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** fixed (round 1)

**What is wrong:** These two functions listed the five price fields by hand instead of iterating `PriceField.allCases`.

**How it was resolved:** Both now iterate `PriceField.allCases`.

### FINDING-12 (Minor, fixed round 1)
- **File:** Sources/UsageCore/Pricing/PriceDiff.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** fixed (round 1)

**What is wrong:** `compute(current:proposed:kind:)` accepted a `kind` that differs from `proposed.kind`, which silently produces a wrong preview.

**How it was resolved:** Added `precondition(proposed == nil || proposed?.kind == kind)`.

### FINDING-13 (Minor, fixed rounds 1 to 3)
- **File:** Sources/UsageCore/Pricing/PriceTable.swift, LiteLLMImporter.swift, PriceCSV.swift, Sources/LLMUsageMenuBar/SettingsView.swift
- **Category:** security
- **Source:** security-agent; re-review rounds 1 to 3 (follow-ups)
- **Resolution:** fixed

**What is wrong:** Model ids from the remote list were not validated. That allowed control characters, line breaks, very long keys, and a leading `=`, `+`, `-` or `@` (spreadsheet formula injection in CSV exports).

**How it was resolved:** Added `PriceTable.isAcceptableImportedModelId(_:allowingSpaces:)`:
- LiteLLM entries with such ids are skipped as malformed (FR-013).
- CSV rows get the reason `invalid model id`. Spaces are allowed in CSV.
- "Add model" accepts only ids that pass the CSV rule, so an export re-imports without skipped rows (SC-005).
- CSV ids are trimmed again after canonicalization.

The contracts were updated to match.

### FINDING-14 (Minor, fixed rounds 1 and 2)
- **File:** Sources/UsageCore/Diagnostics/DiagnosticLog.swift
- **Category:** security
- **Source:** security-agent; re-review round 1 (U+2028/U+2029)
- **Resolution:** fixed

**What is wrong:** A CSV file name or the reason for an invalid file could contain line breaks, and those could forge log lines.

**How it was resolved:** `DiagnosticLog.append` escapes control characters and U+2028/U+2029 in the source and the message. Covered by `controlCharactersCannotAddLines`.

### FINDING-15 (Minor, fixed rounds 1 and 2)
- **File:** Sources/LLMUsageMenuBar/App.swift (previewCSVImport)
- **Category:** security, production-readiness
- **Source:** security-agent, production-readiness-agent (duplicate); CodeRabbit round 1 (bounded read)
- **Resolution:** fixed

**What is wrong:** CSV import had no size cap and read the whole file on the main actor.

**How it was resolved:** The file is read through `FileHandle.read(upToCount: 5 MB + 1)`, and larger files are rejected as unreadable. README and price-csv.md mention the limit. Parsing still runs on the main actor, which is acceptable at 5 MB.

### FINDING-16 (Minor, open)
- **File:** Sources/LLMUsageMenuBar/SettingsView.swift (PriceSettingsTab)
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Resolution:** open (decision: performance tuning without measurement)

**What is wrong:** The tab recomputes the effective table, the used-model resolution and a per-row `firstIndex` on every body evaluation. It also renders a non-lazy `Grid`, which can hold several hundred rows after three provider imports with the "All" filter.

**What is needed:** If typing lag shows up in practice, cache the table and the visible rows in state, and switch to a lazy container for "All".

### FINDING-17 (Minor, fixed round 1)
- **File:** Sources/LLMUsageMenuBar/App.swift
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Resolution:** fixed (round 1)

**What is wrong:** Failed provider imports, failed CSV reads and failed exports left no trace in the diagnostic log.

**How it was resolved:** Each failure is logged with its reason and no prices. Cancellation is not logged.

### FINDING-18 to FINDING-22 (Minor, fixed round 1)
- **File:** Tests/UsageCoreTests/{LiteLLMImporterTests,PriceCSVTests,PriceDiffTests,ImportedPricesTests}.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** fixed (round 1)

Coverage gaps closed with new tests:
- Rounding to 6 decimals with non-tie values. Null and boolean cache values fall back to the input price, and a negative cache price skips the entry (FR-008, FR-009, FR-013, SC-007).
- Merging of `@YYYYMMDD` variants (FR-011).
- CSV line numbers across quoted line breaks, blank lines and CRLF; more fields than the header; negative or unparsable cache cells; an empty input cell; a quoted semicolon header (FR-016, FR-017).
- Cross-provider removal falling back to another provider, and cross-provider changed (US1-6).
- `save` of an invalid value keeps `current` and the file. An unsupported version, a non-canonical id, a duplicate id or an empty origin is invalid on load (FR-026, FR-027).

### FINDING-23 (Minor, open)
- **File:** Tests/UsageCoreTests/LogIndexTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** open (needs a real Vertex OpenAI session log id; quickstart scenario 3 covers it manually)

**What is wrong:** No test ties an importer output id to a Vertex OpenAI model id as it appears in a session log (SC-006).

### FINDING-24 (Minor, open)
- **File:** Tests/UsageCoreTests/LiteLLMImporterTests.swift, StubURLProtocol.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** open (StubURLProtocol cannot set headers; the streaming cap is tested)

**What is wrong:** The early `Content-Length` rejection and the exact-limit boundary are not tested.

### FINDING-25 (Minor, open)
- **File:** Tests/UsageCoreTests/RefreshCoordinatorTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** open

**What is wrong:** No test covers a reprice that reuses a stored failed network result (error timestamps, `lastSuccessfulRefreshAt == nil`), or a network source registered after the last full refresh.

### FINDING-26 (Minor, open)
- **File:** Tests/UsageCoreTests/PriceCSVTests.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** open

**What is wrong:** The SC-005 round-trip test builds its layers with helpers, not with real `PriceCSV.parse` and `LiteLLMImporter.batch` outputs that include derived values.

### FINDING-27 (Minor, fixed round 2)
- **File:** Sources/UsageCore/Pricing/PriceDiff.swift
- **Category:** correctness
- **Source:** re-review round 1
- **Resolution:** fixed (round 2)

**What is wrong:** A model already priced through the prefix fallback was reported as "new".

**How it was resolved:** Such a model is now reported as unchanged (same prices) or changed (the old values come from the fallback row). research.md R6 was updated. Covered by `modelPricedThroughThePrefixFallbackIsNotNew`.

### FINDING-28 (Minor, fixed round 2)
- **File:** specs/002-price-import/research.md, contracts/litellm-mapping.md, contracts/price-csv.md
- **Category:** architecture
- **Source:** re-review round 1
- **Resolution:** fixed (round 2)

**What is wrong:** The docs did not describe the new prefix-fallback rules, the id rule or the 5 MB limit.

**How it was resolved:** The R6 table, the skip rule and the CSV row and file errors are now documented.

## Notable Observations

### NOTABLE-1
- **File:** Sources/UsageCore/Logs/SessionLogSource.swift
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** Imported prices reach the log source through an injected store, not through `RefreshContext`.
- **Rationale:** Overrides and imports for one refresh are read at different moments.

### NOTABLE-2
- **File:** Sources/LLMUsageMenuBar/App.swift (saveConfiguration)
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** Manual override edits still run a full refresh, which calls the usage endpoint.
- **Rationale:** A price-only change could use the reprice path.

### NOTABLE-3
- **File:** Sources/UsageCore/Pricing/LiteLLMImporter.swift
- **Category:** security
- **Source:** security-agent
- **Description:** There is no upper sanity bound for imported prices.
- **Rationale:** The preview is the only guard against an upstream mistake.

### NOTABLE-4
- **File:** Sources/LLMUsageMenuBar/App.swift
- **Category:** test-quality
- **Source:** test-quality-agent
- **Description:** The apply, remove and export orchestration lives in the untested app target.
- **Rationale:** A UsageCore service would make FR-021, FR-026 and FR-033 testable.

### NOTABLE-5
- **File:** Sources/UsageCore/Config/Configuration.swift (decodeDecimal)
- **Category:** correctness
- **Source:** correctness-agent
- **Description:** Prices decode through `Double`. A CSV value with more than about 15 significant digits differs after a relaunch.
- **Rationale:** This is low impact, and rounding CSV values to 6 decimals would avoid it.

## Post-Fix Spec Coverage

The fix loop removed only dead UI code (the unrendered `.applying` phase) and the round 1 row cap, which round 2 reverted. Every functional requirement was re-checked against the code after round 3.

| Requirement group | Implementation | Status |
|-------------|---------------|--------|
| FR-001 to FR-005 layering and sources | PriceTable.effective, PriceSource.imported | ✓ |
| FR-006 to FR-013 provider import | LiteLLMImporter (fetch, batch, perMillion, id rule) | ✓ |
| FR-014 to FR-019 CSV import and export | PriceCSV.parse/export | ✓ |
| FR-020 to FR-020c preview | PriceDiff.compute, PriceImportPreview (all skipped rows listed) | ✓ |
| FR-021 to FR-024 apply, cancel, remove, errors | AppModel.applyImport/removeImport, PriceImportSheet, SettingsView | ✓ |
| FR-023a reprice without endpoint | RefreshCoordinator.requestReprice, NetworkBoundSource | ✓ |
| FR-025 to FR-027 storage | ImportedPriceStore | ✓ |
| FR-028 to FR-032 Prices tab | PriceSettingsTab | ✓ |
| FR-033, FR-034 logging, no background fetch | AppModel log lines, Import menu only | ✓ |

All spec requirements were verified after the fix loop.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| baseline | make test | 0 | 0 | passed (215 tests) |
| 1 | make test | 0 | 0 | passed (227 tests) |
| 2 | make test | 1, then 0 | 2, then 0 | first run: two new tests had wrong expectations (the CSV id rule was too strict for an existing quoting test, and one changed-fields list was wrong). Both were corrected in the same round, and the rerun passed (229 tests). |
| 3 | make test | 0 | 0 | passed (229 tests) |
| final | make test | 0 | 0 | passed (230 tests, 21 suites) |

`make app` built `build/AgentMeter.app` after every round.

## Remaining Findings

No Critical or Important findings remain. The 6 open Minor findings are FINDING-8, FINDING-16 and FINDING-23 to FINDING-26. They cover documentation qualifiers, performance tuning without a measured problem, and test gaps that need infrastructure or real data. None affects spec compliance.
