# Contract: Prices Tab and Import Sheet

## Prices tab

- Above the table: an **Import** menu button with, in order: "Anthropic prices (LiteLLM)", "OpenAI prices (LiteLLM, direct and Vertex)", "Google Gemini prices (LiteLLM)", divider, "From CSV file…", "Export current prices as CSV…", and, when imports exist, a divider and one "Remove <name> prices (imported <date>)" item per stored import.
- A segmented filter "Used in this window" | "All", remembered across launches; "Used" falls back to all rows before the first snapshot.
- Table columns: Model, Input, Output, Cache 5m, Cache 1h, Cache read, Source, action. Source shows "Built-in", "LiteLLM <date>", "CSV <file name>" or "Manual".
- Below the table: one status line per import ("Anthropic prices from LiteLLM, imported today") and, if the stored file could not be read, a notice in red.
- Editing a row (Override) or "Add model" creates a manual override as today.

## Import sheet

- Provider import: shows a progress indicator while fetching.
- Preview: summary line; sections Changed (old → new per changed field, changed fields highlighted), Removed (fallback price or "unpriced"), Shadowed (with "your override stays in effect" or "the CSV price stays in effect"), New (used models listed; the others behind "N more new models" disclosure), Skipped rows (line and reason), Unchanged count. Derived CSV values carry a "derived" marker.
- Buttons: Cancel (escape) and Apply (default). Apply is disabled when `PriceDiff.isEmpty` and the proposed batch holds the same model ids with the same prices (`samePrices`) as the stored batch of that kind; provenance and `importedAt` are ignored.
- Errors replace the preview with the reason and a Close button. This covers provider fetch errors, CSV file errors (`missing header`, `missing columns`, `no valid rows`, unreadable file) and save failures on Apply.

## Removal

A confirmation dialog: "Remove <name> prices?" with the message "<N> models fall back to another price or become unpriced." Buttons Remove (destructive) and Cancel. A failed save shows an alert with the reason.
