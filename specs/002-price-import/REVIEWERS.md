# Review Guide: Price Import

**Generated**: 2026-10-13 | **Spec**: [spec.md](spec.md)

## Why This Change

Spend figures are only as good as the price table behind them. Today the app ships a fixed built-in table, and the only way to correct it is to type overrides by hand. When a provider changes prices or releases a model, spend goes wrong until the next app build. This is most pressing for the Vertex budget group, where OpenAI models are about to appear next to Claude models and have no built-in prices at all, so their usage shows up as unpriced.

## What Changes

The Prices tab gains an Import menu. One click fetches current prices for Anthropic, OpenAI (direct and Vertex) or Google Gemini from LiteLLM's public price list; another reads a CSV file. Every import is shown as a preview diff (new, changed, removed, shadowed, unchanged, skipped) before anything changes, and applying it re-prices local usage immediately without calling the rate-limited usage endpoint. Imported prices form their own layer between built-in prices and manual overrides, live in a separate `imported-prices.json`, can be removed individually, and the effective table can be exported as CSV. The table shows each row's source and by default only the models used in the current window. Manual overrides keep working exactly as before. No breaking changes for users; internally `PriceSource` loses its `String` raw value.

## How It Works

- **Layering** (`UsageCore/Pricing`): `PriceTable.effective(builtIn:imported:overrides:)` merges, lowest first, built-in prices, provider batches by ascending import time (newest wins), the CSV batch, and manual overrides. Each entry carries its source (`PriceSource.imported(ImportProvenance)` is new). The existing id normalization and prefix fallback run on the merged table unchanged.
- **Storage**: `ImportedPriceStore` mirrors `ConfigStore` (lock-protected, atomic writes) and owns `~/.config/llm-usage-menubar/imported-prices.json`, holding at most one batch per kind. A damaged file is ignored with a log line and a notice in the tab.
- **Importers**: `LiteLLMImporter` streams the 2.7 MB JSON with a 20 MB cap and a 30 s total timeout through an uncached ephemeral session, filters by provider and mode, strips `vertex_ai/` and `gemini/` prefixes, converts per-token prices to per-million rounded to 6 decimals, and merges dated variants. `PriceCSV` is a small hand-written parser and exporter (comma or semicolon, decimal comma, quotes, BOM).
- **Preview**: `PriceDiff.compute` compares the effective table before and after replacing the batch of the proposed kind, which puts every affected model in exactly one category. The same function with `proposed == nil` gives the removal impact for the confirmation dialog.
- **Re-pricing**: `RefreshCoordinator.requestReprice()` re-runs only sources that are not `NetworkBoundSource` and reuses the last stored result of the subscription source. `SessionLogSource` builds its pricer from the store on every collect, and `LogIndex` already re-prices indexed records in memory when the price table value changes.
- **UI** (`LLMUsageMenuBar`): `AppModel` gains preview, apply, remove and export methods; `PriceSettingsTab` gets the Import menu, Source column, filter and status line; the new `PriceImportSheet` shows loading, preview and failure states.

## When It Applies

**Applies when**:
- The user chooses a provider import, a CSV import, a removal or an export on the Prices tab.
- Session logs are priced, on every refresh, using the merged table.
- The app launches and loads `imported-prices.json`.

**Does not apply when**:
- Running in the background: there is no automatic or scheduled price fetching (FR-034).
- Regional or per-provider price differences (for example Vertex surcharges): direct and Vertex prices are treated as identical, as today.
- Claude on Vertex (`vertex_ai-anthropic_models`) is not imported separately, because its prices match direct Anthropic prices.
- Non-USD prices and scraping of provider pricing pages are out of scope.

## Key Decisions

1. **LiteLLM as the price source.** Neither Anthropic nor OpenAI offers a price API, and scraping pricing pages breaks on redesigns and has no Vertex data. LiteLLM's JSON is public, machine-readable and covers all three providers. Risk: schema drift, mitigated by lenient per-entry parsing.
2. **A fixed layer order, overrides > CSV > provider > built-in, regardless of age.** An older import still beats a newer app build's built-in prices; the status line shows each import's age so stale imports are visible. Alternative (newest wins across layers) was rejected as unpredictable.
3. **Separate file for imported prices.** Keeps `config.json` short and hand-editable, and lets a damaged import file fail without affecting configuration.
4. **Preview computed as a before/after diff of the effective table.** This one mechanism handles shadowing by overrides or CSV, fallbacks on removal, and the removal confirmation count, instead of special-casing each.
5. **Re-pricing without the usage endpoint.** A `NetworkBoundSource` marker plus a stored last result per network source keeps the decision in the coordinator instead of teaching each source about refresh purposes. A reprice requested during a running refresh sets its own pending flag, so it does not turn into an extra endpoint call.
6. **Hand-written CSV parser.** No CSV library is in the dependency graph and the format is small; the parser is pure and fully unit-tested.

## Areas Needing Attention

- **Price equality.** `PriceEntry`'s synthesized `==` includes `source`. The diff, the Apply enablement and the export round trip must compare the five price fields only (`samePrices(as:)`), otherwise every re-imported model shows as changed. Worth checking in the diff code.
- **Coordinator change.** `RefreshCoordinator` gains a second run mode, a result cache and a second pending flag. This is the riskiest core change; check the interplay of timer, wake, manual refresh and reprice requests, and that a reprice never calls `SubscriptionSource`.
- **Export re-import moves everything into the CSV layer.** Re-importing a full export shadows later provider imports and newer built-in prices for all models. The spec accepts this (the preview shows them as shadowed, and removing the CSV import restores the lower layers), but users may be surprised.
- **Vertex OpenAI ids.** The importer maps `vertex_ai/openai/gpt-oss-120b-maas` to `openai/gpt-oss-120b-maas`. SC-006 depends on that matching the id in real session logs, which can only be confirmed with a real Vertex OpenAI session (quickstart scenario 3).
- **Known data difference.** LiteLLM lists a different Claude Sonnet 5.5 cache read price than the built-in table. The preview surfaces it; the feature does not decide which is right.
- **CSV encoding.** Only UTF-8 (with or without BOM) is read; other encodings are reported as an unreadable file.

## Open Questions

No open questions identified.

## Review Checklist

- [ ] Key decisions are justified
- [ ] Breaking changes are documented with migration guidance
- [ ] Scope matches the stated boundaries
- [ ] Success criteria are achievable
- [ ] No unstated assumptions
- [ ] Apply and removal never trigger a request to the usage endpoint (FR-023a)
- [ ] Manual overrides are never modified by an import (FR-004)
- [ ] The diagnostic log records counts only, never individual prices (FR-033)

---

<!-- Code phase sections are appended below this line by the phase-manager command -->
<!-- Each phase section follows the template below -->

<!--
## Phase N: [Phase Name] (YYYY-MM-DD)

### What Changed

[Summary of files and functionality added/modified]

### Spec Compliance

[Which requirements this phase addresses, compliance score]

### Focus Areas for Review

[Where the reviewer should concentrate]

### AI Assumptions

[Decisions made during implementation that were not in the spec]
-->
