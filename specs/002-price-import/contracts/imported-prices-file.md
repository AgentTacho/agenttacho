# Contract: Imported Prices File

Path: `~/.config/agenttacho/imported-prices.json`. Written only by the app (apply or removal of an import). Readable by hand; hand edits are not supported but a valid file is honored.

```json
{
  "batches" : [
    {
      "entries" : [
        {
          "cacheReadPerMTok" : 0.2,
          "cacheWrite1hPerMTok" : 8,
          "cacheWrite5mPerMTok" : 5,
          "inputPerMTok" : 4,
          "model" : "claude-opus-5-5",
          "outputPerMTok" : 20
        }
      ],
      "importedAt" : "2026-10-13T15:00:00Z",
      "kind" : "anthropic",
      "origin" : "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
    }
  ],
  "version" : 1
}
```

Rules:

- `kind` is one of `anthropic`, `openai`, `gemini`, `csv`. At most one batch per kind; a file with two batches of one kind is invalid.
- `importedAt` is ISO 8601 with time zone.
- Entries use the same shape as `priceOverrides` in `config.json`. Model ids are canonical (no `-YYYYMMDD` or `@YYYYMMDD` suffix) and unique within a batch. Prices are non-negative numbers.
- Writes are atomic (temporary file plus rename) with sorted keys and pretty printing.
- Missing file: no imported prices. Invalid file: ignored with one diagnostic log line and a notice on the Prices tab; it stays on disk until the next applied import or removal overwrites it with a file holding only the batches known to the app (none, plus the new one).
