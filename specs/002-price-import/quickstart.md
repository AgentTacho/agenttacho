# Quickstart: Price Import

Validation guide for the price import feature. Contracts: [imported-prices-file](contracts/imported-prices-file.md), [litellm-mapping](contracts/litellm-mapping.md), [price-csv](contracts/price-csv.md), [prices-tab-ui](contracts/prices-tab-ui.md).

## Prerequisites

- macOS 14 or later, Command Line Tools with the macOS 26 SDK (the Makefile selects it).
- Network access for provider imports.
- Optional: a backup of `~/.config/llm-usage-menubar/` if you want to restore your state afterwards.

## Automated checks

```bash
make test
```

Expected: all suites pass, including `ImportedPricesTests`, `LiteLLMImporterTests`, `PriceCSVTests`, `PriceDiffTests`, the extended `PriceTableTests`, and the reprice test in `RefreshCoordinatorTests`. The LiteLLM tests run against `Tests/UsageCoreTests/Fixtures/litellm/excerpt.json`, a trimmed copy of the real file, and never touch the network.

## Manual scenarios

Build and start the app:

```bash
make app && open build/AgentMeter.app
```

Open Settings and choose the Prices pane.

1. **Provider import (US1).** Import menu, "Anthropic prices (LiteLLM)". Expect a preview with a summary line. Claude Sonnet 5.5 appears under Changed with cache read 0.2 → 0.1. Apply. The Source column shows "LiteLLM" with today's date for Anthropic models, the status line reads "Anthropic prices from LiteLLM, imported today", and `~/.config/llm-usage-menubar/imported-prices.json` exists with one `anthropic` batch. The diagnostic log has one `prices:` line with counts. The log shows no new request to the usage endpoint for this recomputation.
2. **Shadowing (US1).** Override the Claude Opus 5.5 input price by hand, import Anthropic again. Expect Opus 5.5 under Shadowed with "your override stays in effect".
3. **OpenAI on Vertex (US1, SC-006).** Import "OpenAI prices". Expect a large collapsed "N more new models" group; models already used in the window are listed. After Apply, a session using `openai/gpt-oss-120b-maas` (if present in the logs) is priced.
4. **CSV import (US2).** Create `prices.csv`:

   ```csv
   model;input;output
   claude-test-model;2,50;10
   ;1;1
   ```

   Import it. Expect `claude-test-model` as new with derived cache prices 3.125, 5, 0.25 marked "derived", and line 3 skipped with "missing model". Apply; the source shows "CSV prices.csv".
5. **Filter (US3).** Switch between "Used in this window" and "All"; quit and relaunch; the choice is kept.
6. **Export round trip (US5).** Export as CSV, re-import the file unchanged. Expect "no new, changed or removed" in the summary.
7. **Removal (US4).** Import menu, remove the CSV prices. Confirm the dialog names the import and the number of affected models. After removal, `claude-test-model` disappears or shows unpriced.
8. **Offline (SC-004).** Turn off the network and start a provider import. Expect an error naming the reason; nothing changes; spend figures stay as before.
9. **Damaged file.** Quit, write `{` into `imported-prices.json`, start the app. Expect a red notice on the Prices tab and built-in plus manual prices in use. A new import replaces the file.
