# Data Model: Price Import

All types live in `UsageCore` (no UI) unless noted. Prices are `Decimal`, US dollars per million tokens.

## ImportKind (new)

`enum ImportKind: String, Codable, CaseIterable, Hashable, Sendable` with cases `anthropic`, `openai`, `gemini`, `csv`.

- `isProvider`: true for the first three.
- `displayName`: "Anthropic", "OpenAI", "Google Gemini", "CSV".
- Layer rank: provider kinds share one layer below `csv`.

## ImportProvenance (new)

`struct ImportProvenance: Hashable, Sendable`. Defined in `ImportedPrices.swift` together with `ImportKind` (task T007), because `PriceSource` needs it.

| Field | Type | Notes |
|---|---|---|
| `kind` | `ImportKind` | |
| `origin` | `String` | LiteLLM URL, or the CSV file name (last path component only) |
| `importedAt` | `Date` | Time the import was applied |

## PriceSource (changed)

Was `enum PriceSource: String { case builtIn, override }`. Becomes:

```swift
public enum PriceSource: Equatable, Sendable {
    case builtIn
    case imported(ImportProvenance)
    case override
}
```

`PriceEntry.source` stays non-persisted; `PriceEntry` encoding is unchanged (decoding still sets `.override`; `PriceTable.effective` restamps the source per layer), so `config.json` and the batch file share the same entry shape. Existing call sites compare with `.builtIn` and `.override` and keep compiling.

`PriceEntry` gains `func samePrices(as other: PriceEntry) -> Bool`, true when all five price fields are equal. This is the only equality used by `PriceDiff`, Apply enablement and the export round trip; synthesized `==` also compares `source` and must not be used there.

## PriceBatch (new)

| Field | Type | Validation |
|---|---|---|
| `kind` | `ImportKind` | |
| `origin` | `String` | non-empty |
| `importedAt` | `Date` | ISO 8601 in the file |
| `entries` | `[PriceEntry]` | canonical, unique model ids; all prices >= 0 |

`provenance: ImportProvenance` is derived.

## ImportedPrices (new, persisted)

| Field | Type | Notes |
|---|---|---|
| `version` | `Int` | 1 |
| `batches` | `[PriceBatch]` | at most one per kind (FR-025) |

Operations (pure, return a new value):

- `replacing(_ batch: PriceBatch)`: drops the batch of the same kind, appends the new one.
- `removing(_ kind: ImportKind)`.
- `batch(for kind:) -> PriceBatch?`.

File format: [contracts/imported-prices-file.md](contracts/imported-prices-file.md).

## ImportedPriceStore (new)

Final class, lock-protected, modeled on `ConfigStore`.

| Member | Behavior |
|---|---|
| `init(fileURL:)` | `Paths.importedPricesFileURL` in the app |
| `load()` | Missing file: empty value, no error. Undecodable or invalid file: empty value, `loadError` set, file left in place (FR-027). |
| `current: ImportedPrices` | Last loaded or saved value |
| `loadError: String?` | Reason shown as a notice on the Prices tab |
| `save(_:)` | Encodes pretty-printed with sorted keys, creates the directory, writes atomically; on failure throws and keeps `current` unchanged (FR-026). Clears `loadError` on success. |

## PriceTable (changed)

New static function:

```swift
static func effective(builtIn: PriceTable, imported: ImportedPrices, overrides: [PriceEntry]) -> PriceTable
```

Layer order, lowest first: built-in, provider batches by ascending `importedAt`, the CSV batch, overrides. Each layer replaces entries with the same canonical id and sets `source`. `merging(overrides:)` stays for existing callers. `price(for:)` and the prefix fallback are unchanged.

## PriceField (new)

`enum PriceField: CaseIterable` with `input`, `output`, `cacheWrite5m`, `cacheWrite1h`, `cacheRead`, plus a key path accessor into `PriceEntry`. Used for per-field diffs and for flagging derived CSV values.

## ProposedImport (new)

| Field | Type | Notes |
|---|---|---|
| `batch` | `PriceBatch` | |
| `skippedRows` | `[SkippedRow]` | CSV only |
| `derived` | `[String: Set<PriceField>]` | CSV only: model id to fields derived from input (FR-015) |

## SkippedRow (new)

| Field | Type | Notes |
|---|---|---|
| `line` | `Int` | 1-based line number in the file, the header is line 1 |
| `reason` | `String` | for example "missing model", "unparsable number in output", "negative number in input", "expected 6 fields, found 4", "duplicate model" |

## PriceDiff (new)

Built by `PriceDiff.compute(current: ImportedPrices, proposed: PriceBatch?, kind: ImportKind, builtIn:, overrides:, usedModels: Set<String>?)`. `proposed == nil` describes a removal.

| Field | Type | Meaning |
|---|---|---|
| `newModels` | `[PriceEntry]` | no price before, priced after (`newUsed + newOther`) |
| `newUsed` | `[PriceEntry]` | new models that a used id resolves to (exact or prefix fallback, research R9); listed in full (FR-020c) |
| `newOther` | `[PriceEntry]` | the remaining new models, collapsed behind a count; with `usedModels == nil` every new model is here |
| `changed` | `[PriceChange]` | effective price from the proposed batch differs from before |
| `removed` | `[PriceRemoval]` | the replaced batch priced it, the result does not come from the new batch, and the price changes; `fallback: PriceEntry?` (nil means unpriced) |
| `shadowed` | `[PriceShadow]` | proposed price differs from the effective one because a higher layer wins; `winner: PriceSource` |
| `unchangedCount` | `Int` | in the proposed batch, effective price equal before and after, not shadowed |
| `isEmpty` | `Bool` | no new, changed or removed models (shadowed and unchanged do not count) |
| `summary` | `String` | "12 new, 3 changed, 1 removed, 7 unchanged, 1 shadowed" (zero categories omitted, "no changes" when all zero; when only unchanged or shadowed models remain, prefixed with "no new, changed or removed models; ", for example "no new, changed or removed models; 7 unchanged", which is what quickstart scenario 6 expects) |

`PriceChange`: `model`, `before: PriceEntry`, `after: PriceEntry`, `changedFields: [PriceField]`.

Classification rules: [research.md R6](research.md).

## LiteLLMImporter (new)

| Member | Behavior |
|---|---|
| `static let defaultURL` | `https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json` |
| `static let priceListSession: URLSession` | Ephemeral, `urlCache = nil`, `timeoutIntervalForRequest = 30`, `timeoutIntervalForResource = 30` |
| `init(session: URLSession = LiteLLMImporter.priceListSession, url: URL = LiteLLMImporter.defaultURL, maxBytes: Int = 20 * 1024 * 1024)` | All injectable for tests |
| `fetch() async throws -> Data` | Streams with a 20 MB cap; errors: `network`, `httpStatus(Int)`, `tooLarge`, `timeout` |
| `static func batch(from: Data, kind:, origin:, importedAt:) throws -> PriceBatch` | Selection and mapping per [contracts/litellm-mapping.md](contracts/litellm-mapping.md); throws `notJSON` or `noUsableEntries(kind)` |

## PriceCSV (new)

| Member | Behavior |
|---|---|
| `static func parse(_ text: String, origin: String, importedAt: Date) throws -> ProposedImport` | Format per [contracts/price-csv.md](contracts/price-csv.md); throws `missingHeader`, `missingColumns([String])`, `noValidRows` |
| `static func export(_ table: PriceTable) -> String` | Comma separator, dot decimals, header plus one row per entry sorted by model |

## Errors

`PriceImportError: Error, CustomStringConvertible` with cases `network(String)`, `httpStatus(Int)`, `timeout`, `tooLarge`, `notJSON`, `noUsableEntries(ImportKind)`, `missingHeader`, `missingColumns([String])`, `noValidRows`, `unreadableFile(String)`, `saveFailed(String)`. Descriptions are the user-facing reasons (FR-024).

## RefreshCoordinator (changed)

- `protocol NetworkBoundSource: UsageSource {}`; `SubscriptionSource` conforms.
- Private `lastNetworkResults: [String: SourceResult]`, filled after every full refresh with the results of network-bound sources.
- `requestReprice()`: like `requestRefresh()` but the run collects only non-network sources and reuses each network source's stored result (logged as reused). When a refresh is already running, sets `pendingReprice`; when it ends, a pending full refresh (`pending`) wins, otherwise a reprice runs, so a reprice never calls the usage endpoint (FR-023a). When a network-bound source has no stored result, behaves as `requestRefresh()`.
- `repriceAndWait() async -> UsageSnapshot`: mirrors `refreshAndWait()` for tests.

## SessionLogSource (changed)

Takes an optional `importedPrices: ImportedPriceStore? = nil` init parameter (after `builtInPrices`). Per refresh: `pricer = PriceTable.effective(builtIn: builtInPrices, imported: store?.current ?? .empty, overrides: configuration.priceOverrides)`.

## App layer (`AgentMeter`)

`AppModel` gains `importedPriceStore`, observable `importedPrices: ImportedPrices`, `importedPricesNotice: String?`, and:

- `previewProviderImport(_ kind:) async throws -> (ProposedImport, PriceDiff)`
- `previewCSVImport(url:) throws -> (ProposedImport, PriceDiff)`
- `applyImport(_:) throws`: save, update `importedPrices`, clear `importedPricesNotice`, log one line (FR-033), `requestReprice()`; a failed save throws `PriceImportError.saveFailed` and changes nothing
- `removeImport(_ kind:) throws`: same, for removal
- `removalImpact(_ kind:) -> PriceDiff`
- `exportPrices(to url:) throws`
- `effectivePrices(overrides:) -> PriceTable` and `usedModels: Set<String>?`

State transitions of the import sheet: `loading` (provider fetch) → `preview` | `failed(reason)`; `preview` → Apply → `applying` → closed | `failed(saveFailed)`; Cancel closes without change. A CSV import starts in `preview` or `failed(reason)` (no loading state).
