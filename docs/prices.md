# Prices

Spend is computed from token counts and a price table in USD per million tokens. Each model's price comes from the first of these layers that has it:

1. **Manual**: prices you enter or override on the Prices tab (stored in `config.json`).
2. **CSV**: the prices of the last CSV file you imported.
3. **Provider imports**: Anthropic, OpenAI or Google Gemini prices from LiteLLM. When two of them price the same model, the more recent import wins.
4. **Built-in**: the table shipped with the app.

The **Import** menu on the Prices tab offers:

- **Anthropic prices (LiteLLM)**, **OpenAI prices (LiteLLM, direct and Vertex)** and **Google Gemini prices (LiteLLM)**. These download LiteLLM's public price list ([`model_prices_and_context_window.json`](https://github.com/BerriAI/litellm/blob/main/model_prices_and_context_window.json)) once, when you choose the item. Nothing is fetched in the background.
- **From CSV file…** reads a CSV file with a header row. `model`, `input` and `output` are required; `cache_write_5m`, `cache_write_1h` and `cache_read` are optional and default to 1.25, 2 and 0.1 times the input price. Commas or semicolons work as separators, and with semicolons a decimal comma (`2,50`) is accepted too. Files larger than 5 MB are rejected. A new CSV import replaces the previous one. The full format is in [`specs/002-price-import/contracts/price-csv.md`](../specs/002-price-import/contracts/price-csv.md).
- **Export current prices as CSV…** writes the effective table in the same format, so you can edit it in a spreadsheet and import it again.
- **Remove … prices** for each stored import, after a confirmation that says how many models fall back to another price.

Every import shows a preview first: new, changed, removed and shadowed models (a shadowed model keeps a higher-ranked price, such as your override), plus skipped CSV rows with their line numbers. Nothing changes until you choose Apply. Applying or removing an import re-prices the session logs right away without asking Anthropic's usage endpoint again.

The table shows each row's source and, by default, only the models used in the current window plus your overrides; switch the filter to **All** to see every model. Imported prices are stored in `~/.config/agenttacho/imported-prices.json`, one batch per import kind.
