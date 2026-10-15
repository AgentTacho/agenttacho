# Implementation Plan: Price Import

**Branch**: `002-price-import` | **Date**: 2026-10-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/002-price-import/spec.md`

## Summary

Add a layer of imported prices between the built-in table and manual overrides. Prices come from LiteLLM's public price list (one import per provider: Anthropic, OpenAI direct plus Vertex, Gemini) or from a CSV file, are stored in `imported-prices.json` next to `config.json`, and are always shown as a preview diff before they apply. Applying or removing an import re-prices local session logs without calling the rate-limited usage endpoint. The Prices tab gains an Import menu, a Source column, a "Used in this window" filter and a status line. All parsing, merging and diffing lives in `UsageCore` as pure, unit-tested code; the app layer only wires it to SwiftUI.

## Technical Context

**Language/Version**: Swift 5.10 tools, Swift 6 compiler from the Command Line Tools

**Primary Dependencies**: Foundation, SwiftUI, AppKit (`NSOpenPanel`, `NSSavePanel`); no new packages

**Storage**: JSON files in `~/.config/agentmeter/` (`config.json` unchanged, new `imported-prices.json`)

**Testing**: Swift Testing (`@Suite`, `@Test`, `#expect`) via `make test`; network stubbed with the existing `StubURLProtocol`

**Target Platform**: macOS 14 or later, menu bar app (`MenuBarExtra`), ad-hoc signed

**Project Type**: desktop app with a UI-free core library (`UsageCore`) and a SwiftUI executable (`AgentMeter`)

**Performance Goals**: Parsing the 2.7 MB LiteLLM file and building a preview in under 1 second on Apple silicon; re-pricing after apply completes within one normal session-log refresh (no file re-reads, `LogIndex` re-prices in memory). Measured manually in T022: time from choosing the menu item to the visible preview on the real file, and the `done in X s` refresh log line after Apply

**Constraints**: No background network traffic (FR-034); the usage endpoint is never called by apply or removal (FR-023a); download capped at 20 MB and 30 s; atomic file writes; offline operation unaffected

**Scale/Scope**: About 300 imported models at most (22 Anthropic, about 200 OpenAI chat and responses, about 60 Gemini chat); CSV files of tens of rows

## Global Constraints

Every task inherits these values, copied from the spec:

- Prices are `Decimal`, US dollars per million tokens; provider prices are rounded to 6 decimal places (FR-008, SC-007).
- Layer order, highest first: manual overrides, CSV import, provider imports (most recently imported wins), built-in (FR-001, FR-002).
- Price equality everywhere in this feature (diff, Apply enablement, round trip) compares the five price fields only (`inputPerMTok`, `outputPerMTok`, `cacheWrite5mPerMTok`, `cacheWrite1hPerMTok`, `cacheReadPerMTok`), never `PriceEntry.source`. `PriceEntry` has synthesized `Equatable` that includes `source`, so `==` on entries is wrong for this purpose.
- Provider download: 30 seconds total (`timeoutIntervalForResource`), at most 20 MB, no cache (FR-012).
- CSV derivation factors: 5-minute write 1.25 times input, 1-hour write 2 times, read 0.1 times (FR-015).
- At most one stored import per kind (`anthropic`, `openai`, `gemini`, `csv`) in `~/.config/agentmeter/imported-prices.json`, written atomically (FR-025, FR-026).
- No background price fetches (FR-034); apply and removal never call the usage endpoint (FR-023a).
- No new package dependencies; macOS 14 or later; no em-dash or en-dash characters in code, comments or user-facing strings.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` is the unfilled template, so there are no ratified principles to gate on. The plan follows the conventions established by feature 001 instead:

| Convention (from 001) | This plan |
|---|---|
| Logic in `UsageCore`, UI only in `AgentMeter` | All importers, CSV, diff, storage and merge in `UsageCore/Pricing`; views only call `AppModel` |
| Tests first for core logic, fixtures for external data | Trimmed real LiteLLM excerpt as fixture; every FR in the core has a test |
| Settings apply immediately, no Save button | Apply in the preview sheet is the explicit user action; removal confirms like account removal |
| Credentials never logged | No credentials involved; the log records counts only (FR-033) |
| No unnecessary endpoint calls | Reprice path skips network-bound sources |

Post-design re-check: no new violations. No Complexity Tracking entries.

## Project Structure

### Documentation (this feature)

```text
specs/002-price-import/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── imported-prices-file.md
│   ├── litellm-mapping.md
│   ├── price-csv.md
│   └── prices-tab-ui.md
└── tasks.md             # created by /speckit-tasks
```

### Source Code (repository root)

```text
Sources/UsageCore/
├── Config/
│   ├── Configuration.swift        # PriceSource gains .imported(ImportProvenance)
│   └── Paths.swift                # importedPricesFileURL
├── Pricing/
│   ├── PriceTable.swift           # effective(builtIn:imported:overrides:)
│   ├── ImportedPrices.swift       # NEW: ImportKind, ImportProvenance, PriceBatch, ImportedPrices, ImportedPriceStore
│   ├── PriceImportError.swift     # NEW
│   ├── LiteLLMImporter.swift      # NEW: fetch with cap, mapping per kind
│   ├── PriceCSV.swift             # NEW: parse to ProposedImport, export
│   └── PriceDiff.swift            # NEW: PriceField, ProposedImport, SkippedRow, PriceDiff
├── Logs/SessionLogSource.swift    # uses ImportedPriceStore in its pricer
├── Snapshot/RefreshCoordinator.swift  # NetworkBoundSource, requestReprice()
└── Subscription/SubscriptionSource.swift  # conforms to NetworkBoundSource

Sources/AgentMeter/
├── App.swift                      # AppModel: store, import/apply/remove/export, usedModels
├── SettingsView.swift             # PriceSettingsTab: Import menu, Source column, filter, status line
└── PriceImportSheet.swift         # NEW: preview and apply, error state

Tests/UsageCoreTests/
├── Fixtures/litellm/excerpt.json  # NEW: trimmed real entries
├── ImportedPricesTests.swift      # NEW
├── LiteLLMImporterTests.swift     # NEW
├── PriceCSVTests.swift            # NEW
├── PriceDiffTests.swift           # NEW
├── LogIndexTests.swift            # extended: SessionLogSource prices with imported entries
├── PriceTableTests.swift          # extended: layer order, prefix fallback on merged table
├── RefreshCoordinatorTests.swift  # extended: reprice skips network-bound sources
└── StubURLProtocol.swift          # extended: key by request URL when no key header is set

README.md                          # new "Prices" section
```

**Structure Decision**: Keep the existing two-target layout. New pricing code goes into `Sources/UsageCore/Pricing/` next to `PriceTable.swift`; the only new view file is `PriceImportSheet.swift`.

## Implementation Phases

1. **Core model and storage**: `ImportKind`, `ImportProvenance`, `PriceSource` change, `PriceBatch`, `ImportedPrices`, `ImportedPriceStore`, `Paths.importedPricesFileURL`, `PriceTable.effective`. Tests: storage round trip, atomic replace of one kind, removal, damaged file, layer order, recency within the provider layer, prefix fallback on the merged table.
2. **Diff**: `PriceField`, `ProposedImport`, `SkippedRow`, `PriceDiff` with the classification table from research R6, used-model split, summary string. Tests per category including shadowing by CSV and by override, removal fallback to a lower layer and to unpriced, removal impact (`proposed == nil`).
3. **LiteLLM importer**: fixture (already created during planning at `Tests/UsageCoreTests/Fixtures/litellm/excerpt.json`: real entries plus synthetic dated, no-cache, malformed, no-output and non-object cases), mapping, selection per kind, prefix stripping, variant merging, missing cache fields, malformed entries, fetch errors and size cap through `StubURLProtocol`.
4. **CSV**: parser and exporter with all dialect cases, derived values, duplicates, no valid rows, export round trip (SC-005).
5. **Reprice path**: `NetworkBoundSource`, `requestReprice()`, `repriceAndWait()`, a per-source cache of the last network-bound results, a pending-reprice flag next to the pending-refresh flag, `SessionLogSource` reading the store. Test: a reprice yields a snapshot with new costs while the network-bound source is not called a second time, also when the reprice is requested during a running refresh.
6. **App wiring**: `AppModel` methods, logging, load notice, `usedModels`.
7. **UI**: Prices tab (Import menu, Source column, filter, status line, notice), `PriceImportSheet`, removal confirmation, open and save panels.
8. **Polish**: quickstart manual run, README section on price import.

## Risks

- **LiteLLM schema drift**: lenient parsing skips odd entries; a total failure surfaces as "no usable entries" without changing prices.
- **`PriceSource` enum change**: it loses its `String` raw value. No code reads `rawValue`; today it is only compared in `PriceTableTests` and `ConfigurationTests` and assigned in `PriceTable.swift` and `SettingsView.swift` (`copy.source = .override`), all of which keep compiling. `ImportProvenance` must be `Equatable` and `Sendable` because `PriceEntry` and `PriceTable` synthesize `Equatable` over `source`.
- **Entry equality**: because `PriceEntry ==` includes `source`, a naive diff would report every re-imported model as changed (new `importedAt`). See Global Constraints: compare price fields only.
- **Reprice during a running refresh**: folding a reprice into the existing pending full refresh would call the usage endpoint, which FR-023a forbids. The coordinator keeps a separate pending-reprice flag; a pending full refresh (timer, wake, manual) still wins when both are set.
- **`LogIndex` re-pricing**: `LogIndex.update` re-prices indexed records whenever the `PriceTable` value differs (`PriceTable` equality includes `source` and provenance), so no change to `LogIndex` is needed.
- **Shared files with the settings work**: `SettingsView.swift` and `App.swift` were just reworked on main (commit `bfc283c`); this branch starts from that commit, so there is no merge conflict.

## Complexity Tracking

No constitution violations to justify.
