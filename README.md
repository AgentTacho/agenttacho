<p align="center">
  <img src="Resources/icons/macos/AgentMeter.png" alt="AgentMeter app icon" width="128">
</p>

# AgentMeter

A macOS menu bar app that shows how much of your coding-agent usage limits you have used, across accounts with different pricing models.

<p align="center">
  <img src="docs/images/agentmeter-dropdown.png" alt="AgentMeter in the menu bar with its dropdown open: a Claude Max subscription at 7% of its 7-day limit with a per-model token breakdown, and a Vertex budget group at 518% of its monthly budget with per-model cost and a per-day trend" width="420">
</p>

Each entry in the bar is an icon and a percentage. Click it for the details.

- **Subscription accounts** (Claude Code on a Claude Pro or Max plan) show the real 5-hour and 7-day utilization that Anthropic reports, plus model-specific weekly limits such as the one for Fable. The bar shows the 7-day window.
- **Token-based accounts** (Claude Code through Google Vertex AI) show spend in USD, computed from Claude Code's local session logs with a built-in price table you can override, measured against a weekly or monthly budget you set. An account either has its own budget or belongs to a budget group.
- **Budget groups** put one or more token-based accounts under one shared budget, either weekly or monthly. A weekly budget lines up with your subscription's 7-day reset, or with a weekday and hour you choose. A monthly budget runs from midnight on the 1st to the end of the calendar month in local time, which suits a company spending limit granted per month.
- **Member shares.** A group member can also appear in the bar on its own, showing its spend as a percent of the group budget. It sits right after its group, or in the group's place when the group itself is hidden.
- The dropdown lists every account and group with its reset time, a per-model breakdown and a per-day trend. macOS notifications fire once when usage crosses one of your thresholds.

In the bar, `⚠` marks an entry at or above its lower notification threshold (80% by default), `‼` marks 100% or more, and `~` marks a value that could not be refreshed and may be out of date.

## Status

A personal project, built for my own setup and shared as is. It currently supports Claude Code only, on macOS 14 or newer with Apple Silicon. The data model already allows other agent harnesses and providers (OpenAI models through Vertex AI are next), but nothing beyond Claude Code is implemented yet.

AgentMeter is not affiliated with Anthropic or Google. The subscription percentages come from an undocumented Anthropic endpoint that Claude Code itself uses (`/api/oauth/usage`). It can change or disappear without notice, and then the subscription rows show an error while token-based accounts keep working.

## Build and run

Requirements: macOS 14 or newer on Apple Silicon, and the Xcode Command Line Tools with Swift 5.10 or newer. There are no third-party Swift packages.

```bash
make test     # unit tests for the UsageCore library (Swift Testing)
make app      # builds build/AgentMeter.app with an ad-hoc signature
make run      # builds and opens the app
```

Run the app bundle rather than `swift run`, because notifications and start at login need an application bundle.

On first launch, AgentMeter creates a configuration with one subscription account if Claude Code is signed in with the default configuration directory `~/.claude`. If you run Claude Code with a different directory (for example through `CLAUDE_CONFIG_DIR`), set that directory as the account's credential directory in Settings.

## Configuration

Everything lives in one JSON file, `~/.config/llm-usage-menubar/config.json`. The settings window (dropdown, "Settings…") writes it, and you can edit it by hand. The app picks up changes at the next refresh. If the file is invalid, the dropdown says so and the last valid configuration stays active.

```json
{
  "version": 1,
  "refreshIntervalSeconds": 300,
  "accounts": [
    { "id": "acc-max", "type": "subscription", "icon": "brands:claude",
      "displayName": "Claude Max", "credentialDirectory": "~/.claude",
      "shownInBar": true, "thresholds": [80, 100] },
    { "id": "acc-vertex", "type": "tokenBased", "icon": "brands:google",
      "displayName": "Claude Code via Vertex", "provider": "vertex",
      "groupId": "grp-vertex", "shownInBar": false },
    { "id": "acc-own", "type": "tokenBased", "icon": "brands:google",
      "displayName": "Personal Vertex", "provider": "vertex",
      "budget": { "period": "monthly", "budgetUSD": 100, "shownInBar": true, "thresholds": [80, 100] } }
  ],
  "groups": [
    { "id": "grp-vertex", "name": "Vertex", "icon": "solid:wallet",
      "period": "monthly", "budgetUSD": 400, "shownInBar": true, "thresholds": [80, 100] }
  ]
}
```

The settings window has four tabs:

- **General**: refresh interval (default 5 minutes, minimum 1 minute), which subscription account sets the weekly window, the fallback weekday and hour (both apply to weekly budgets, of groups or of accounts with their own budget, and to Unassigned only), start at login, and extra Claude Code directories to scan.
- **Accounts**: display name, icon, the credential directory for subscription accounts, and an optional custom marker for telling apart two accounts of the same kind. A token-based account has a provider and a budget: either its own (period, amount, whether it shows in the bar, notification thresholds) or a budget group. A group member can show its share of the group budget in the bar.
- **Groups**: name, icon, period (weekly or monthly) and budget, whether the group shows in the bar, and notification thresholds.
- **Prices**: prices in USD per million tokens, with their source, your own overrides and extra models, and an Import menu (see [Prices](#prices)).

Every account and group has one [Font Awesome Free](https://fontawesome.com) icon, chosen from a searchable picker. New entries start with a default: the Claude icon for subscriptions, the Google icon for Vertex accounts, and a wallet for groups. Several entries may share an icon; the dropdown and settings show each icon next to its name. Older configuration files with text labels still load: the labels are ignored and entries without an icon get the default.

## How it works

- **Session logs.** AgentMeter reads Claude Code's session files under `~/.claude/projects` and any extra directories you configure. After the first scan it only rereads files that changed. A request id starting with `req_vrtx_` marks a Vertex session; other `req_` ids are direct Anthropic sessions.
- **Prices.** The built-in table is in `Sources/UsageCore/Resources/prices.json`, and imported prices and your overrides are layered on top of it (see [Prices](#prices)). A model without a price is counted as unpriced, and the total of its budget (a group or an own budget) is marked incomplete until you add a price.
- **Subscription limits.** At each refresh, AgentMeter reads Claude Code's stored login from the macOS keychain through Apple's `/usr/bin/security` tool, and asks Anthropic's usage endpoint for the current utilization. Claude Code's keychain items already trust that tool, so no keychain dialog appears.

## Prices

Spend is computed from token counts and a price table in USD per million tokens. Each model's price comes from the first of these layers that has it:

1. **Manual**: prices you enter or override on the Prices tab (stored in `config.json`).
2. **CSV**: the prices of the last CSV file you imported.
3. **Provider imports**: Anthropic, OpenAI or Google Gemini prices from LiteLLM. When two of them price the same model, the more recent import wins.
4. **Built-in**: the table shipped with the app.

The **Import** menu on the Prices tab offers:

- **Anthropic prices (LiteLLM)**, **OpenAI prices (LiteLLM, direct and Vertex)** and **Google Gemini prices (LiteLLM)**. These download LiteLLM's public price list ([`model_prices_and_context_window.json`](https://github.com/BerriAI/litellm/blob/main/model_prices_and_context_window.json)) once, when you choose the item. Nothing is fetched in the background.
- **From CSV file…** reads a CSV file with a header row. `model`, `input` and `output` are required; `cache_write_5m`, `cache_write_1h` and `cache_read` are optional and default to 1.25, 2 and 0.1 times the input price. Commas or semicolons work as separators, and with semicolons a decimal comma (`2,50`) is accepted too. Files larger than 5 MB are rejected. A new CSV import replaces the previous one. The full format is in [`specs/002-price-import/contracts/price-csv.md`](specs/002-price-import/contracts/price-csv.md).
- **Export current prices as CSV…** writes the effective table in the same format, so you can edit it in a spreadsheet and import it again.
- **Remove … prices** for each stored import, after a confirmation that says how many models fall back to another price.

Every import shows a preview first: new, changed, removed and shadowed models (a shadowed model keeps a higher-ranked price, such as your override), plus skipped CSV rows with their line numbers. Nothing changes until you choose Apply. Applying or removing an import re-prices the session logs right away without asking Anthropic's usage endpoint again.

The table shows each row's source and, by default, only the models used in the current window plus your overrides; switch the filter to **All** to see every model. Imported prices are stored in `~/.config/llm-usage-menubar/imported-prices.json`, one batch per import kind.

## Privacy

- AgentMeter only reads Claude Code's session logs and keychain items. It never writes to them and never refreshes or changes your login.
- The regular network request goes to `api.anthropic.com` with your own token, to fetch your usage. A provider price import downloads LiteLLM's price list from `raw.githubusercontent.com`, without credentials, only when you choose it from the Import menu. There is no telemetry and no other server.
- Tokens stay in memory for the duration of one request. They are not written to the configuration, the log, notifications, or any other file.
- A diagnostic log at `~/Library/Logs/llm-usage-menubar/usage.log` (capped at 5 MB) records one line per refresh with percentages, spend totals and errors, but never credentials. "Open log" in the dropdown shows it.

## Development

- `Sources/UsageCore`: all logic (configuration, log parsing, pricing, attribution, weekly windows, aggregation, thresholds, icon catalog), with no UI code.
- `Sources/LLMUsageMenuBar`: the SwiftUI menu bar app.
- `Tests/UsageCoreTests`: Swift Testing suites with small synthetic session-log fixtures.
- `scripts/sum-vertex.sh <start> <end> [dir...]`: recomputes Vertex spend for a window with `jq`, as an independent check of the app.
- `scripts/build-icon-catalog.sh`: regenerates the bundled Font Awesome files from a pinned release, with an integrity check.
- `specs/001-llm-usage-menubar` and `docs/superpowers/specs`: the specification, plan and design notes the app was built from.

## Credits

The icons are [Font Awesome Free](https://fontawesome.com) 7.3.1 by Fonticons, Inc. The icons are licensed under CC BY 4.0, the fonts under SIL OFL 1.1, and the code under MIT. See `Sources/UsageCore/Resources/FontAwesome/LICENSE.txt`.

## License

Apache License 2.0, see [LICENSE](LICENSE). The bundled Font Awesome files keep their own licenses, listed above.

---

Author: Roland Huß [AIA PAI Nc Hin R Claude Opus 5.5 v1.0](https://aiattribution.github.io/statements/AIA-PAI-Nc-Hin-R-?model=Claude%20Opus%205.5-v1.0)
