# Price Import: LiteLLM and CSV

Date: 2026-10-13
Status: approved in brainstorming, awaiting spec review

## Intent

**What the user asked for:** buttons on the Prices tab that import the latest prices for Anthropic models, the same for OpenAI and possibly other providers, and an "Import from CSV" that imports or overwrites prices from a downloaded CSV file.

**Intended outcome:** spend figures stay accurate when providers change prices or release models, without editing prices by hand or waiting for a new app build. This matters most for the Vertex budget group, where OpenAI models are about to appear next to Claude models.

**Success criteria:**
- One action brings a provider's prices up to date.
- The user sees what an import changes before it takes effect.
- Manual overrides are never silently replaced.
- The app keeps working offline with the prices it already has.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Price source | LiteLLM's `model_prices_and_context_window.json` on GitHub | Neither Anthropic nor OpenAI offers a price API. The LiteLLM file is machine-readable, updated frequently (last change 2026-10-13), and covers Anthropic, OpenAI, Claude and OpenAI on Vertex, and Gemini, including cache prices. Scraping pricing pages breaks on redesigns and lacks Vertex. |
| Layering | Imported prices form their own layer; manual overrides win | Imports never touch manual edits, and a whole import can be dropped. |
| Model scope | An import stores all chat models of the provider; the Prices tab filters to models in use | New models are priced the first time they appear; the table stays short. |
| Storage | Separate file `~/.config/agenttacho/imported-prices.json` | `config.json` stays short and hand-editable; each import replaces only its own batch. |
| Updates | Manual only, from the Import menu | No surprise price changes; no background network traffic. |

Observed during brainstorming: LiteLLM prices Claude Sonnet 5.5 cache reads at $0.10 per million tokens, the built-in table at $0.20. Direct and Vertex prices in LiteLLM are identical for the five current Claude models. The preview step exists so such differences are visible before they apply.

## Price lookup order

For a model id (after the existing normalization in `PriceTable.canonicalModel`), the first match wins:

1. Manual overrides in `config.json` (`priceOverrides`, unchanged).
2. The CSV batch in `imported-prices.json`.
3. LiteLLM batches in `imported-prices.json` (`anthropic`, `openai`, `gemini`; their model sets do not overlap in practice; if they do, the most recently imported batch wins).
4. The built-in `prices.json` in the app bundle.

The existing prefix fallback (`claude-opus-5-5-eu` matches `claude-opus-5-5`) applies to the merged table as today.

`PriceEntry.source` gains an imported case carrying the batch kind, origin (LiteLLM URL or CSV file name) and import time, so the Prices tab can show where each row comes from.

## Storage: `imported-prices.json`

```json
{
  "version": 1,
  "batches": [
    {
      "kind": "anthropic",
      "origin": "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json",
      "importedAt": "2026-10-13T15:00:00Z",
      "entries": [
        { "model": "claude-opus-5-5", "inputPerMTok": 4, "outputPerMTok": 20,
          "cacheWrite5mPerMTok": 5, "cacheWrite1hPerMTok": 8, "cacheReadPerMTok": 0.2 }
      ]
    }
  ]
}
```

- `kind` is one of `anthropic`, `openai`, `gemini`, `csv`. At most one batch per kind.
- Applying an import replaces the batch of its kind and writes the file atomically (temporary file plus rename).
- Removing a batch deletes it from the file.
- A missing file means no imported prices. A file that fails to decode is ignored: the app logs one line, shows a notice on the Prices tab, and uses overrides plus built-in prices. The damaged file stays until the next import replaces it.
- The file is read at launch and after every applied import or removal.

## LiteLLM import

- URL: `https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json`, fetched with an ephemeral, cache-free URL session (same policy as the usage endpoint client), 30-second timeout, response capped at 20 MB.
- Parsing is lenient: the top-level object maps model keys to objects; entries that are not objects or lack the needed fields are skipped, never failing the import.
- Selection per kind, only entries whose `mode` is `chat` (or `responses` for OpenAI):
  - `anthropic`: `litellm_provider == "anthropic"`.
  - `openai`: `litellm_provider == "openai"`, plus `vertex_ai-openai_models` with the `vertex_ai/` prefix removed from the key.
  - `gemini`: `litellm_provider == "gemini"` with any `gemini/` key prefix removed.
- Field mapping, all converted from dollars per token to dollars per million tokens and rounded to 6 decimal places:
  - `input_cost_per_token` to input, `output_cost_per_token` to output (both required; entries without them are skipped).
  - `cache_creation_input_token_cost` to 5-minute cache write.
  - `cache_creation_input_token_cost_above_1hr` to 1-hour cache write.
  - `cache_read_input_token_cost` to cache read.
  - A missing cache field takes the input price, which is neutral for providers that do not bill cache writes separately.
- Dated variants (`claude-opus-4-7-20260416`, `@` suffixes) are normalized with `PriceTable.canonicalModel`. When several keys map to the same canonical id with different prices, the undated key wins; otherwise the first in key order.

## CSV import and export

Format, shared by import and export:

```csv
model,input,output,cache_write_5m,cache_write_1h,cache_read
claude-opus-5-5,4,20,5,8,0.2
```

- A header row is required. Column names are matched case-insensitively and in any order. Values are dollars per million tokens.
- Required columns: `model`, `input`, `output`. Missing cache columns are derived from input: 5-minute write 1.25 times, 1-hour write 2 times, read 0.1 times. The preview marks derived values.
- The separator is comma or semicolon, detected from the header line. With semicolon, a decimal comma (`2,50`) is accepted. Double-quoted fields and a leading UTF-8 byte-order mark are handled.
- Rows that fail (missing model, unparsable or negative number, wrong column count) are reported with line number and reason and skipped.
- Importing a CSV replaces the whole `csv` batch: models absent from the new file lose their CSV price.
- Export writes the current effective table (all rows, all sources) in this format, so export, edit and re-import round-trips.

## Preview and apply

Every import first produces a proposed batch, then a diff against the current effective table:

- **New:** models with no current price.
- **Changed:** models whose effective price would change; each changed field shows the old and new value.
- **Unchanged:** count only.
- **Shadowed:** models where a manual override keeps winning; listed with "your override stays in effect".
- **Skipped rows:** CSV only, with line and reason.

The preview sheet shows a one-line summary ("12 new, 3 changed, 7 unchanged, 1 shadowed"), the new and changed rows with differences highlighted, shadowed rows, and skipped rows. **Apply** writes the batch and triggers a refresh; **Cancel** discards it. Like every other setting, an applied import takes effect immediately; removing a batch from the Import menu undoes it.

## Prices tab

- An **Import** menu button above the table:
  - Anthropic prices (LiteLLM)
  - OpenAI prices (LiteLLM, direct and Vertex)
  - Google Gemini prices (LiteLLM)
  - From CSV file… (standard open panel, `.csv` and plain text)
  - Export current prices as CSV… (standard save panel)
  - Remove imported prices: one item per existing batch, with its date.
- A **Source** column: built-in, LiteLLM with import date, CSV with file name, or manual.
- A filter: **Used in this window** (default) or **All**. "Used" means models that appear in the current snapshot's breakdowns plus every model with a manual override.
- A status line below the table with the age of each batch, for example "Anthropic prices from LiteLLM, imported today".
- Editing a row and "Add model" keep working as today and create manual overrides.

## Errors

| Situation | Behavior |
|---|---|
| No network, timeout, non-200, response over 20 MB | Error in the sheet, nothing changes |
| LiteLLM file not JSON or no usable entries for the kind | Error in the sheet naming the reason, nothing changes |
| CSV without header or without required columns | Error in the sheet, nothing changes |
| Some CSV rows invalid | Listed in the preview; valid rows can still be applied |
| `imported-prices.json` unreadable at launch | Logged once, notice on the Prices tab, fall back to overrides plus built-in |
| Write of `imported-prices.json` fails | Error in the sheet; previous file untouched (atomic write) |

Each applied import or removal writes one line to the diagnostic log, for example "prices: imported 22 anthropic prices from LiteLLM (3 changed, 12 new)". Price values are not credentials; logging counts is enough.

## Components

New code in `UsageCore` (no UI, unit-tested):

- `Pricing/ImportedPrices.swift`: batch model, kinds, load and atomic save of `imported-prices.json`.
- `Pricing/LiteLLMImporter.swift`: fetch (injectable transport) and mapping to a batch per kind.
- `Pricing/PriceCSV.swift`: CSV parsing to a batch with per-row errors, and CSV export of a table.
- `Pricing/PriceDiff.swift`: diff of a proposed batch against the effective table.
- `Pricing/PriceTable.swift`: merging gains the imported layer between built-in and overrides.

App changes in `AgentTacho`:

- `SettingsView.swift` Prices tab: Import menu, Source column, filter, status line.
- New `PriceImportSheet.swift`: preview and apply.
- `App.swift`: load imported prices at launch, rebuild the effective table after apply or removal, trigger a refresh.

## Testing

Unit tests in `UsageCoreTests`, with a trimmed excerpt of the real LiteLLM file as a fixture (a handful of Anthropic, OpenAI, Vertex OpenAI and Gemini entries, one dated duplicate, one entry without cache fields, one malformed entry):

- LiteLLM mapping: per-token to per-million conversion with exact decimals, provider selection per kind, `vertex_ai/` and `gemini/` prefix removal, dated-variant merging, missing cache fields, malformed entries skipped, response size cap.
- Lookup order: override over CSV over LiteLLM over built-in, prefix fallback on the merged table.
- Storage: round trip, atomic replace of one kind, removal, damaged file falls back.
- CSV: comma and semicolon, decimal comma, quoted fields, byte-order mark, missing optional columns (derived values flagged), invalid rows reported, export then import round trip.
- Diff: new, changed (field level), unchanged, shadowed.

Manual check: Import menu, preview sheet, apply and remove, Source column and filter.

## Out of scope

- Automatic or scheduled price updates.
- Different prices for the same model by provider or region (for example Vertex regional surcharges).
- Editing imported rows in place (an edit creates a manual override, as today).
- Currencies other than USD.
