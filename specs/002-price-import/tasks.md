---
description: "Task list for the price import feature"
---

# Tasks: Price Import

**Input**: Design documents from `specs/002-price-import/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Included. The plan requires tests first for all `UsageCore` logic (Swift Testing, `make test`). UI tasks are verified manually through quickstart.md.

**Organization**: Tasks are grouped by user story. Foundational work (layered price model, storage, diff, reprice path) blocks all stories.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: User story from spec.md (US1 to US5)

## Conventions

- Build and test only through the Makefile: `make test` (it selects the macOS 26 SDK and the Swift Testing plugin path). If tests fail with "catalog not found", delete `.build/out/Products/Debug/UsageCoreTests.xctest` and rerun.
- Never use em-dash or en-dash characters in code comments or user-facing strings.
- Match the existing code style: doc comments that cite FR numbers, `Decimal` for prices, `@Suite struct ...Tests` with `@Test func`.
- Do not call the real network in tests; use `StubURLProtocol.makeSession()` from `Tests/UsageCoreTests/StubURLProtocol.swift`.
- Fixtures load through `Bundle.module` (see `Tests/UsageCoreTests/FixtureSupport.swift`).
- Interfaces: `data-model.md` is the interface registry for this feature. Every type, member and signature named there is binding; a task that consumes an earlier task's output uses exactly those names. The plan's Global Constraints section applies to every task.
- Price equality in diffs, Apply enablement and round trips uses `PriceEntry.samePrices(as:)`, never `==` (synthesized `==` also compares `source`).

---

## Phase 1: Setup

- [X] T001 Confirm the baseline builds and all existing tests pass on branch `002-price-import` by running `make test` from the repository root; record the passing test count in the task notes (baseline: 146 tests in 17 suites passed)
- [X] T002 Add `importedPricesFileURL` (`~/.config/agentmeter/imported-prices.json`) to `Sources/UsageCore/Config/Paths.swift`, next to `configFileURL`, with a doc comment

---

## Phase 2: Foundational (blocks all user stories)

**Purpose**: Layered price model, imported price storage, diff engine and the endpoint-free reprice path.

### Tests first

- [X] T003 [P] Write `Tests/UsageCoreTests/ImportedPricesTests.swift`: encode/decode round trip of `ImportedPrices` matching contracts/imported-prices-file.md; `replacing` replaces only the batch of the same kind; `removing`; a batch with a negative price is invalid on load; `ImportedPriceStore.load` with missing file (empty, no error), with `{` (empty, `loadError` set, file untouched), with two batches of one kind (invalid); `save` writes atomically and clears `loadError`; after a damaged-file load, `save(current.replacing(batch))` writes a file holding only that batch; a save into an unwritable directory throws and leaves `current` unchanged
- [X] T004 [P] Extend `Tests/UsageCoreTests/PriceTableTests.swift`: `PriceTable.effective` layer order override > CSV > provider > built-in with correct `source` on each entry; the more recently imported provider batch wins for a shared model (FR-002); prefix fallback (`claude-opus-5-5-eu`) resolves against an imported entry (FR-003); `effective` returns override entries unchanged apart from canonical id and source (FR-004); `PriceEntry.samePrices(as:)` ignores `source`; existing `merging(overrides:)` behavior unchanged
- [X] T005 [P] Write `Tests/UsageCoreTests/PriceDiffTests.swift` covering research.md R6: new, changed with per-field `changedFields`, unchanged count, shadowed by override (winner `.override`), shadowed by CSV for a provider import (winner `.imported(csv)`), removed with fallback to a lower layer, removed to unpriced, removal impact with `proposed == nil`, removal of a provider batch whose models are shadowed by CSV counts zero affected, models outside the old and new batch are ignored, a model only in the replaced batch whose effective price is unchanged is not listed, re-importing an identical batch with a later `importedAt` yields only unchanged (no changed), each model in exactly one category, `newUsed`/`newOther` split with `usedModels` (a used `claude-new-1-eu` puts `claude-new-1` into `newUsed`) and everything in `newOther` with `usedModels == nil`, `isEmpty`, `summary` text including "no changes"
- [X] T006 [P] Extend `Tests/UsageCoreTests/RefreshCoordinatorTests.swift`: register a fake `NetworkBoundSource` that counts calls and a fake record source; after one `refreshAndWait`, `repriceAndWait` produces a new snapshot that reflects changed record costs and keeps the subscription values while the network-bound source was called only once; `requestReprice` before any refresh behaves like a full refresh; `requestReprice` during a running refresh (network source blocked on a continuation) results in exactly one follow-up reprice and the network-bound source is still called once; `requestRefresh` plus `requestReprice` during a running refresh results in a follow-up full refresh

### Implementation

- [X] T007 Create `Sources/UsageCore/Pricing/ImportedPrices.swift` with `ImportKind` (cases, `isProvider`, `displayName`) and `ImportProvenance` (`Hashable, Sendable`) per data-model.md; change `PriceSource` in `Sources/UsageCore/Config/Configuration.swift` to `enum PriceSource: Equatable, Sendable { case builtIn, imported(ImportProvenance), override }`; add `PriceEntry.samePrices(as:)`; fix any compile errors at existing call sites (`PriceTable.swift`, `SettingsView.swift`, `PriceTableTests.swift`, `ConfigurationTests.swift`)
- [X] T008 Extend `Sources/UsageCore/Pricing/ImportedPrices.swift` with `PriceBatch` (Codable, ISO 8601 dates, `provenance`), `ImportedPrices` (`version`, `batches`, `empty`, `replacing`, `removing`, `batch(for:)`, validation of one batch per kind and non-negative prices) and `ImportedPriceStore` (lock-protected, `load`, `current`, `loadError`, atomic `save`) per data-model.md; make T003 pass
- [X] T009 [P] Create `Sources/UsageCore/Pricing/PriceImportError.swift` with the cases listed in data-model.md and user-facing `description` strings
- [X] T010 Add `static func effective(builtIn:imported:overrides:) -> PriceTable` to `Sources/UsageCore/Pricing/PriceTable.swift` (layers per research.md R6, canonical ids, `source` stamped with provenance); make T004 pass
- [X] T011 Create `Sources/UsageCore/Pricing/PriceDiff.swift` with `PriceField` (key paths into `PriceEntry`), `SkippedRow`, `ProposedImport`, `PriceChange`, `PriceRemoval`, `PriceShadow` and `PriceDiff.compute(current:proposed:kind:builtIn:overrides:usedModels:)` plus `summary`; make T005 pass
- [X] T012 Add `protocol NetworkBoundSource: UsageSource {}`, `requestReprice()` and `repriceAndWait()` to `Sources/UsageCore/Snapshot/RefreshCoordinator.swift` per data-model.md (store `lastNetworkResults` after each full refresh, reuse them in a reprice and log them as reused, collect the others; when running set `pendingReprice`, with a pending full refresh taking precedence; full refresh when a network-bound source has no stored result; `runLoop` takes the mode of each iteration); make `SubscriptionSource` in `Sources/UsageCore/Subscription/SubscriptionSource.swift` conform; make T006 pass
- [X] T013 Give `SessionLogSource` in `Sources/UsageCore/Logs/SessionLogSource.swift` an optional `ImportedPriceStore` init parameter and build its pricer with `PriceTable.effective(builtIn:imported:overrides:)`; add a test to `Tests/UsageCoreTests/LogIndexTests.swift` (where the existing `SessionLogSource` tests live) that saving an imported batch to the store and collecting again re-prices an already indexed record without re-reading its file
- [X] T014 Wire the store into `AppModel` in `Sources/AgentMeter/App.swift`: create `ImportedPriceStore(fileURL: paths.importedPricesFileURL)`, load at launch, log one line and set `importedPricesNotice` when `loadError` is set, pass the store to `SessionLogSource`, expose observable `importedPrices`, and add `applyImport(_ proposal: ProposedImport) throws` (compute the diff, save `replacing`, on failure throw `saveFailed` with nothing changed, update state, clear `importedPricesNotice`, `log.append(source: "prices", message: "imported N <kind> prices from <origin> (X new, Y changed, Z removed)")`, call `coordinator.requestReprice()`) and `effectivePrices(overrides:)`
- [X] T015 Run `make test`; all foundational tests (T003 to T006, T013) pass (183 tests in 19 suites)

**Checkpoint**: Imported prices can be stored, merged, diffed and applied programmatically; the usage endpoint is not called on apply.

---

## Phase 3: User Story 1 - Update a provider's prices with one action (Priority: P1) MVP

**Goal**: Import menu items for Anthropic, OpenAI and Gemini fetch the LiteLLM list, show a preview, and apply on confirmation.

**Independent Test**: With network, choose "Anthropic prices (LiteLLM)", see the summary and the Sonnet 5.5 cache read change, apply, see the new price take effect after recomputation (quickstart scenarios 1 to 3, 8).

### Tests for User Story 1

- [X] T016 [P] [US1] Add two synthetic entries to `Tests/UsageCoreTests/Fixtures/litellm/excerpt.json` (`claude-test-variant` and `claude-test-variant-20260501` with different prices, and `claude-test-negative` with a negative `input_cost_per_token`), then write `Tests/UsageCoreTests/LiteLLMImporterTests.swift` against the fixture: per-kind selection (anthropic excludes `vertex_ai/claude-*`; openai includes `gpt-5-codex` with mode `responses` and the two `vertex_ai/openai/*` keys as `openai/gpt-oss-*`, excludes `text-embedding-3-large`; gemini strips `gemini/` and excludes `gemini-3-pro-image`); exact conversions (`claude-opus-5-5` input 4, cache 1h 8, cache read 0.2; `claude-sonnet-5-5` cache read 0.1; `claude-haiku-5-5` cache read 0.01); missing cache fields take the input price (`claude-test-nocache`, `gpt-oss-120b` cache read); `claude-test-malformed`, `claude-test-no-output`, `claude-test-not-object` and `sample_spec` skipped; `claude-opus-4-7` and its dated twin merge to one entry; `claude-test-dated-20260101` and `-20260301` merge to `claude-test-dated` with the later date's prices; `claude-test-variant` keeps the undated entry's prices; `claude-test-negative` skipped; `noUsableEntries` for a body without matching entries; `notJSON` for an array body
- [X] T017 [P] [US1] Extend `Tests/UsageCoreTests/StubURLProtocol.swift` so that a request without `X-Stub-Key` and `Authorization` headers is keyed by its URL string (existing tests unaffected), then add fetch tests to `Tests/UsageCoreTests/LiteLLMImporterTests.swift` with a unique injected URL per test: HTTP 200 returns the body; HTTP 404 throws `httpStatus(404)`; a body over the configured cap throws `tooLarge` (inject `maxBytes` small); a handler throwing `URLError(.timedOut)` throws `timeout`; `URLError(.notConnectedToInternet)` throws `network`; `defaultURL` is the LiteLLM raw GitHub URL from contracts/litellm-mapping.md; `priceListSession` has `urlCache == nil`, `timeoutIntervalForResource == 30` and `timeoutIntervalForRequest == 30`; the default `maxBytes` is 20 MB

### Implementation for User Story 1

- [X] T018 [US1] Create `Sources/UsageCore/Pricing/LiteLLMImporter.swift` per contracts/litellm-mapping.md and research.md R1 to R3: `defaultURL`, `priceListSession` (ephemeral, `urlCache = nil`, 30 s request and resource timeout), injectable session, URL and `maxBytes` (default 20 MB), `fetch()` streaming with `bytes(for:)` and mapping `URLError.timedOut` to `timeout`, and `static func batch(from:kind:origin:importedAt:)` using `JSONSerialization`, per-million conversion with `NSDecimalRound` to 6 places, prefix stripping, canonicalization and variant merging; make T016 and T017 pass
- [X] T019 [US1] Add `previewProviderImport(_ kind: ImportKind) async throws -> (ProposedImport, PriceDiff)` and `usedModels: Set<String>?` (union of canonical `ModelUsage.model` over all breakdowns in `snapshot`, nil without a snapshot) to `AppModel` in `Sources/AgentMeter/App.swift`; the fetch runs only from this method, never from a timer or at launch (FR-034)
- [X] T020 [US1] Create `Sources/AgentMeter/PriceImportSheet.swift` per contracts/prices-tab-ui.md: states loading, preview, failed; summary line; Changed (old and new per field, changed fields highlighted), Removed (fallback or "unpriced"), Shadowed (winner wording "your override stays in effect" or "the CSV price stays in effect"), New (used listed, others in a `DisclosureGroup` "N more new models"), Unchanged count; Cancel (escape) and Apply (default action, disabled per the rule in contracts/prices-tab-ui.md); Apply calls `model.applyImport` and shows a save error in place
- [X] T021 [US1] Add the Import menu with the three provider items to `PriceSettingsTab` in `Sources/AgentMeter/SettingsView.swift`; pass `model` into the tab; selecting an item opens `PriceImportSheet` in loading state and runs `previewProviderImport`; compute the tab's table with `model.effectivePrices(overrides: draft.priceOverrides)`
- [X] T022 [US1] Build with `make app`, run quickstart.md scenarios 1, 2, 3 and 8, and confirm the diagnostic log shows the `prices:` line, no usage endpoint request caused by Apply, and no price list request without a menu action; time the Anthropic and OpenAI previews on the real file (target: preview visible within 30 seconds including download, SC-001; parsing and diffing under 1 second per the plan) and note the `done in X s` refresh line after Apply (automated part done: `make app` succeeds; one live run against the real LiteLLM file: 2.79 MB downloaded in 0.195 s, parse plus diff 0.031 s Anthropic (17 entries, 5 new, 1 changed: claude-sonnet-5-5 cacheRead, 11 unchanged), 0.033 s OpenAI (123 entries), 0.031 s Gemini (40 entries). Manual UI check deferred to walkthrough: scenarios 1, 2, 3, 8, the `prices:` log line and the `done in X s, ..., reprice (network sources reused)` line after Apply)

**Checkpoint**: MVP. Provider prices can be imported with preview; spend recomputes without an endpoint call.

---

## Phase 4: User Story 2 - Import prices from a CSV file (Priority: P2)

**Goal**: "From CSV file…" reads a CSV, shows the same preview with skipped rows and derived values, and applies valid rows.

**Independent Test**: Import a CSV with two valid rows and one invalid row; the preview lists two models and one skipped row with line and reason (quickstart scenario 4).

### Tests for User Story 2

- [X] T023 [P] [US2] Write `Tests/UsageCoreTests/PriceCSVTests.swift` for parsing per contracts/price-csv.md: comma and semicolon separators, decimal comma with semicolon, quoted fields with separator and escaped quotes, leading byte-order mark, `\r\n`, empty lines ignored, case-insensitive columns in any order, unknown columns ignored, derived cache values (1.25x, 2x, 0.1x) flagged in `derived`, row errors with 1-based line numbers (missing model, unparsable number, negative number, wrong field count, duplicate model with last row winning), file errors `missingHeader`, `missingColumns`, `noValidRows`, model ids canonicalized

### Implementation for User Story 2

- [X] T024 [US2] Create `Sources/UsageCore/Pricing/PriceCSV.swift` with `static func parse(_:origin:importedAt:) throws -> ProposedImport` per research.md R7; make T023 pass
- [X] T025 [US2] Add `previewCSVImport(url: URL) throws -> (ProposedImport, PriceDiff)` to `AppModel` in `Sources/AgentMeter/App.swift` (read the file as `Data` and decode as UTF-8; a read failure or invalid UTF-8 maps to `unreadableFile(reason)`; origin is the file name)
- [X] T026 [US2] Add "From CSV file…" to the Import menu in `Sources/AgentMeter/SettingsView.swift` using `NSOpenPanel` (allowed types `.commaSeparatedText` and `.plainText`), then open `PriceImportSheet` with the CSV preview, or in the failed state with the reason when `previewCSVImport` throws (FR-024)
- [X] T027 [US2] Extend `Sources/AgentMeter/PriceImportSheet.swift` with the Skipped rows section (line and reason) and a "derived" marker on derived values in New and Changed rows
- [X] T028 [US2] Run quickstart.md scenario 4 manually (automated part done: the scenario 4 CSV is parsed in `PriceCSVTests.quickstartScenarioFour` with derived 3.125, 5, 0.25 and line 3 skipped as "missing model"; `make app` succeeds. Manual UI check deferred to walkthrough)

**Checkpoint**: CSV prices import with preview; provider imports unaffected.

---

## Phase 5: User Story 3 - See where each price comes from (Priority: P2)

**Goal**: Source column, "Used in this window" filter, status line per import, and the damaged-file notice.

**Independent Test**: After a provider and a CSV import, every row shows its source, the filter limits rows to used plus overridden models, the status line names each import and its age (quickstart scenarios 5 and 9).

- [X] T029 [US3] Add a Source column to the price grid in `Sources/AgentMeter/SettingsView.swift` ("Built-in", "LiteLLM <date>", "CSV <file name>", "Manual") using `PriceEntry.source`; imported rows render like built-in rows with the Override button, which copies the entry into `draft.priceOverrides` as today (FR-032)
- [X] T030 [US3] Add the segmented filter "Used in this window" | "All" stored with `@AppStorage("priceFilter")` to `PriceSettingsTab` in `Sources/AgentMeter/SettingsView.swift`; "Used" shows rows that a used id resolves to (exact or prefix fallback, research R9) plus every manually overridden model, and all rows when `usedModels` is nil
- [X] T031 [US3] Add the status line below the table in `Sources/AgentMeter/SettingsView.swift` with one entry per import ("Anthropic prices from LiteLLM, imported today", relative dates via `RelativeDateTimeFormatter` or day granularity), plus `model.importedPricesNotice` in red when set
- [X] T032 [US3] Run quickstart.md scenarios 5 and 9 manually (automated part done: `make app` succeeds; damaged-file handling covered by `ImportedPricesTests.damagedFileIsIgnoredAndLeftInPlace`. Manual UI check deferred to walkthrough)

**Checkpoint**: Price provenance is visible and the table stays short by default.

---

## Phase 6: User Story 4 - Remove an import (Priority: P3)

**Goal**: One removal item per stored import, with a confirmation that states the impact.

**Independent Test**: Remove the CSV import after confirming; affected models fall back and spend recomputes (quickstart scenario 7).

- [X] T033 [US4] Add `removalImpact(_ kind: ImportKind) -> PriceDiff` and `removeImport(_ kind: ImportKind) throws` to `AppModel` in `Sources/AgentMeter/App.swift` (save `removing`, on failure throw `saveFailed` with nothing changed, update state, clear `importedPricesNotice`, `log.append(source: "prices", message: "removed <kind> prices (N models affected)")`, call `requestReprice()`)
- [X] T034 [US4] Add removal items "Remove <name> prices (imported <date>)" to the Import menu in `Sources/AgentMeter/SettingsView.swift`, each opening a `confirmationDialog` "Remove <name> prices?" with "<N> models fall back to another price or become unpriced." and destructive Remove; show an alert on save failure
- [X] T035 [US4] Run quickstart.md scenario 7 manually (automated part done: `make app` succeeds; removal impact covered by `PriceDiffTests.removalImpactWithoutProposedBatch`. Manual UI check deferred to walkthrough)

**Checkpoint**: Every import can be undone deliberately.

---

## Phase 7: User Story 5 - Export prices as CSV (Priority: P3)

**Goal**: Export the effective table as CSV that re-imports without changes.

**Independent Test**: Export, re-import unchanged, the preview reports no new, changed, removed or skipped rows (quickstart scenario 6).

- [X] T036 [P] [US5] Add export tests to `Tests/UsageCoreTests/PriceCSVTests.swift`: header and column order, comma separator, dot decimals without trailing zeros, rows sorted by model, quoting of a model id with a comma, and the round trip: export a table with built-in, imported and override rows, parse it, run `PriceDiff.compute` as a CSV import, expect zero new, changed, removed and skipped (SC-005)
- [X] T037 [US5] Add `static func export(_ table: PriceTable) -> String` to `Sources/UsageCore/Pricing/PriceCSV.swift`; make T036 pass
- [X] T038 [US5] Add `exportPrices(to url: URL) throws` to `AppModel` in `Sources/AgentMeter/App.swift` and "Export current prices as CSV…" to the Import menu in `Sources/AgentMeter/SettingsView.swift` using `NSSavePanel` (default name `prices.csv`); show an alert with the reason when writing fails
- [X] T039 [US5] Run quickstart.md scenario 6 manually (automated part done: `make app` succeeds; round trip covered by `PriceCSVTests.exportRoundTripReportsNoChanges`. Manual UI check deferred to walkthrough)

**Checkpoint**: All five stories delivered.

---

## Phase 8: Polish & Cross-Cutting

- [X] T040 [P] Add a "Prices" section to `README.md` describing the Import menu, the LiteLLM source, the CSV format (link to the column list), layer order and where imported prices are stored
- [X] T041 [P] Update the doc comment at the top of `Sources/UsageCore/Pricing/PriceTable.swift` to describe the four layers and cite FR-001 to FR-003
- [X] T042 Run `make test` and `make app`; fix warnings introduced by this feature; confirm no em-dash or en-dash characters in changed files (`rg '[—–]' Sources Tests README.md`) (215 tests in 21 suites pass; `make app` succeeds; the only build warning is the pre-existing one in `IconPickerSheet.swift:94`; no dash characters in changed source, test or README files, the only hit in the repo is the third-party Font Awesome LICENSE.txt. The manual quickstart walkthrough is deferred to the user)

---

## Dependencies & Execution Order

- Phase 1 → Phase 2 → user stories.
- Within Phase 2: T007 before T008 to T011; T003 to T006 can be written in parallel first; T009 parallel to T008; T010 needs T008; T011 needs T010; T012 independent of T008 to T011; T013 needs T010; T014 needs T008, T009, T011, T012, T013.
- US1 (Phase 3) needs Phase 2. It introduces `PriceImportSheet` and the Import menu that US2, US4 and US5 extend.
- US2 needs US1's sheet and menu (T020, T021).
- US3 needs Phase 2 plus `usedModels` (T019) and the `model` parameter of `PriceSettingsTab` (T021); run after US1.
- US4 needs US1's menu (T021).
- US5 needs US2's `PriceCSV.swift` (T024) and the menu (T021).
- Phase 8 last.

## Parallel Opportunities

- Phase 2 tests: T003, T004, T005, T006 together (different files).
- US1 tests: T016 and T017 touch the same test file; write them together, then T018.
- US2 test T023 can be written while US1 UI tasks run.
- US5 test T036 can be written once T024 exists.
- Polish: T040 and T041 together.

## Implementation Strategy

1. **MVP**: Phases 1 to 3. Provider imports with preview and endpoint-free re-pricing deliver the core value (accurate spend for new and repriced models, including OpenAI on Vertex).
2. **Increment 2**: US2 (CSV) and US3 (provenance and filter).
3. **Increment 3**: US4 (removal) and US5 (export).
4. Run the full quickstart before declaring done.
