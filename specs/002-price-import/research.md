# Research: Price Import

All technical unknowns from the plan's Technical Context are resolved here. Observations about the LiteLLM file come from the copy fetched on 2026-10-13 (2.7 MB, 644 KB of it not relevant).

## R1. Shape of the LiteLLM price list

**Decision**: Treat the file as a JSON object mapping model keys to objects. Read `litellm_provider`, `mode`, `input_cost_per_token`, `output_cost_per_token`, `cache_creation_input_token_cost`, `cache_creation_input_token_cost_above_1hr`, `cache_read_input_token_cost`. Skip any value that is not an object (the first key, `sample_spec`, documents the schema and has no provider of interest).

**Observed**:

| Provider value | Entries | Notes |
|---|---|---|
| `anthropic` | 22 | Keys without prefix (`claude-opus-5-5`); dated duplicates such as `claude-opus-4-7-20260416` carry identical prices |
| `openai` | 216 | Mostly `chat`, codex models use `mode: responses`; also embeddings, images and audio, which are excluded by mode |
| `vertex_ai-openai_models` | 3 | Keys like `vertex_ai/openai/gpt-oss-120b-maas`; one entry is a Google Gemma model filed under this provider |
| `gemini` | 85 | Keys prefixed `gemini/`; many `image_generation` entries, excluded by mode |
| `vertex_ai-anthropic_models` | 38 | Not imported (Claude on Vertex is priced like direct Claude, see spec Assumptions) |

Recent OpenAI entries carry `cache_creation_input_token_cost` equal to 1.25 times input, so the mapping does not need provider-specific defaults.

**Alternatives considered**: Scraping provider pricing pages (rejected in brainstorming: breaks on redesigns, no Vertex data). Importing `vertex_ai-anthropic_models` as well (rejected: identical to direct prices today, and region-specific ids would bloat the table).

## R2. Precision of per-token prices

**Decision**: Parse the raw JSON with `JSONSerialization` (numbers arrive as `NSNumber` backed by `Double`), convert with `Decimal(double) * 1_000_000`, then round to 6 decimal places with `NSDecimalRound` in `.plain` mode (FR-008).

**Rationale**: Values like `3.75E-6` are not exact in binary, but every price in the file has far fewer than 6 significant decimals per million tokens, so rounding restores the intended value exactly (`3.75`, `0.1`, `0.0075`). Test: every Anthropic entry in the fixture equals the built-in table's value except the known Sonnet 5.5 cache read difference.

**Alternatives considered**: `JSONDecoder` with `Decimal` fields (still routes through `Double` on this platform and fails on mixed-type values such as `"mode": "one of: ..."` in `sample_spec`, which would make lenient parsing harder).

## R3. Download limits

**Decision**: An ephemeral `URLSession` with `urlCache = nil`, `requestCachePolicy = .reloadIgnoringLocalCacheData`, `timeoutIntervalForResource = 30` (a total limit; `timeoutIntervalForRequest` alone is an idle timeout between packets and would let a slow download run longer than 30 seconds), `timeoutIntervalForRequest = 30`, and `bytes(for:)` streaming that aborts once more than 20 MB have arrived (also checks `expectedContentLength` up front). Non-200 status is an error. `URLError.timedOut` maps to `timeout`, other transport errors to `network(reason)`. The session and URL are injectable for tests (`StubURLProtocol`, already used by the usage endpoint tests). `StubURLProtocol` keys handlers by the `X-Stub-Key` or `Authorization` header; the price list request carries neither, so the stub gains a fallback to the request URL as key and each test injects a unique URL.

**Rationale**: Same cache policy as `UsageEndpointClient` (FR-012). Streaming enforces the cap even when the server omits `Content-Length`.

## R4. Re-pricing without calling the usage endpoint (FR-023a)

**Decision**: Add `RefreshCoordinator.requestReprice()`. It runs a refresh that collects only from sources that do not use the network and reuses the previous refresh's results for the others. A new marker protocol `NetworkBoundSource` identifies such sources; `SubscriptionSource` adopts it. The coordinator stores the last `SourceResult` of every network-bound source after each full refresh; a reprice reuses those and logs them as reused instead of calling the source. If any network-bound source has no stored result yet, the reprice runs as a full refresh. If a refresh is in flight, a reprice request sets a separate `pendingReprice` flag; when the running refresh ends, a pending full refresh wins, otherwise a reprice runs. Folding the request into the existing `pending` flag would trigger a full refresh and call the usage endpoint, which FR-023a forbids.

**Rationale**: `LogIndex.update` already re-prices indexed records when the `PriceTable` value changes, so the session log source needs no change besides receiving the new table. Keeping the decision in the coordinator avoids teaching each source about refresh purposes.

**Alternatives considered**: A flag in `RefreshContext` that `SubscriptionSource` honors (spreads the rule over sources); calling `Aggregator` directly from the app (duplicates snapshot assembly and threshold handling).

## R5. Where imported prices live at runtime

**Decision**: `ImportedPriceStore`, a lock-protected final class like `ConfigStore`, owns `~/.config/agenttacho/imported-prices.json` (new `Paths.importedPricesFileURL`). It loads at launch, saves atomically (`Data.write(options: .atomic)`), and exposes `current` plus `loadError`. `SessionLogSource` receives the store and builds its pricer per refresh with `PriceTable.effective(builtIn:imported:overrides:)`. The settings window reads the same store through `AppModel`.

**Rationale**: Mirrors the established config pattern, keeps `config.json` short, and makes the layered merge a pure, testable function.

## R6. Layer merge and shadowing

**Equality**: "equal" and "different" below compare the five price fields only, never `PriceEntry.source` (synthesized `PriceEntry ==` includes `source`, and every new batch carries a new `importedAt`).

**Decision**: `PriceTable.effective` applies layers from lowest to highest: built-in, provider batches ordered by `importedAt` ascending (so the most recent wins, FR-002), the CSV batch, manual overrides. Each layer replaces entries by canonical model id and stamps `PriceEntry.source`. The prefix fallback in `price(for:)` operates on the merged map unchanged (FR-003).

`PriceDiff` compares the effective table before and after replacing the batch of the proposed kind, restricted to models present in the old or the new batch of that kind:

| Before | After | After source | Category |
|---|---|---|---|
| none, and no prefix-fallback row | priced | any | new |
| none, priced through the prefix fallback | priced, equal to the fallback row | proposed kind | unchanged (counted) |
| none, priced through the prefix fallback | priced, different | proposed kind | changed (old values from the fallback row) |
| priced | no own row | n/a | removed (falls back to the prefix-fallback row of `price(for:)`, or "unpriced"); not listed when the fallback row has equal prices |
| priced | priced, different | proposed kind | changed (per-field old and new) |
| priced | priced, different | lower layer | removed (falls back to the shown price) |
| equal | equal | higher layer, and the proposed price differs | shadowed (names the winning source) |
| equal | equal | otherwise, model in the proposed batch | unchanged (counted) |
| equal | equal | model only in the replaced batch | not listed (nothing changes for it, and it is not part of the proposed import) |

**Rationale**: Comparing before and after effective tables puts every model in exactly one category (FR-020) and handles shadowing by CSV or by a manual override the same way (FR-020a).

## R7. CSV dialect

**Decision**: A small hand-written parser: strip a leading UTF-8 byte-order mark; detect the separator from the header line (semicolon if it contains `;` and no `,` outside quotes, else comma); split records on newlines outside double quotes, with `""` as an escaped quote; trim whitespace around fields. With semicolon separators, a single `,` inside a numeric field is read as the decimal point. Numbers parse with `Decimal(string:locale: en_US_POSIX)`. Export writes comma separators, dot decimals, a header row, and quotes a model id only if it contains a comma, quote or newline.

**Rationale**: No CSV library is in the dependency graph, and the format is small. The parser is pure and fully unit-testable.

## R8. Removing an import and confirmation

**Decision**: The confirmation counts affected models by running the same `PriceDiff` with `proposed == nil` for that kind: removed models (falling back or becoming unpriced) are the affected ones.

**Rationale**: One diff implementation serves preview and removal (FR-023).

## R9. The "Used in this window" filter

**Decision**: Used models are the union of `ModelUsage.model` (canonicalized) over every breakdown in the current snapshot (subscription accounts, token accounts, groups and Unassigned), plus every manually overridden model. A table entry counts as used when a used id resolves to it with the same rule as `PriceTable.price(for:)` (exact canonical match or prefix fallback), so a used `claude-opus-5-5-eu` marks the `claude-opus-5-5` row. `PriceDiff` applies the same rule when splitting new models (FR-020c). With no snapshot yet, the filter shows all rows. The choice is stored with `@AppStorage("priceFilter")` (FR-030).
