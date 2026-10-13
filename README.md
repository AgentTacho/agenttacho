# AgentMeter

A macOS menu bar app that shows how much of your coding-agent usage limits you have used, across accounts with different pricing models.

```
✻ 42%  V ⚠87%
```

Each entry in the bar is a short label (text or an icon) and a percentage. Click it for the details.

- **Subscription accounts** (Claude Code on a Claude Pro or Max plan) show the real 5-hour and 7-day utilization that Anthropic reports, plus model-specific weekly limits such as the one for Fable. The bar shows the higher of the two main windows.
- **Token-based accounts** (Claude Code through Google Vertex AI) show spend in USD, computed from Claude Code's local session logs with a built-in price table you can override, measured against a weekly budget you set.
- **Budget groups** put one or more token-based accounts under one shared weekly budget. The week lines up with your subscription's 7-day reset, or with a weekday and hour you choose.
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
    { "id": "acc-max", "type": "subscription", "label": "M", "icon": "brands:claude",
      "displayName": "Claude Max", "credentialDirectory": "~/.claude",
      "shownInBar": true, "thresholds": [80, 100] },
    { "id": "acc-vertex", "type": "tokenBased", "label": "VC",
      "displayName": "Claude Code via Vertex", "provider": "vertex", "groupId": "grp-vertex" }
  ],
  "groups": [
    { "id": "grp-vertex", "name": "Vertex weekly", "label": "V",
      "weeklyBudgetUSD": 60, "shownInBar": true, "thresholds": [80, 100] }
  ]
}
```

The settings window has four tabs:

- **General**: refresh interval (default 5 minutes, minimum 1 minute), which subscription account sets the weekly window, the fallback weekday and hour, start at login, and extra Claude Code directories to scan.
- **Accounts**: display name, label text or icon, the credential directory for subscription accounts, provider and budget group for token-based accounts, notification thresholds, and an optional custom marker for telling apart two accounts of the same kind.
- **Groups**: name, label, weekly budget, whether the group shows in the bar, and notification thresholds.
- **Prices**: the built-in prices in USD per million tokens, with your own overrides and extra models.

Labels are 1 to 3 characters, or a [Font Awesome Free](https://fontawesome.com) icon chosen from a searchable picker. They must be unique across all accounts and groups.

## How it works

- **Session logs.** AgentMeter reads Claude Code's session files under `~/.claude/projects` and any extra directories you configure. After the first scan it only rereads files that changed. A request id starting with `req_vrtx_` marks a Vertex session; other `req_` ids are direct Anthropic sessions.
- **Prices.** The built-in table is in `Sources/UsageCore/Resources/prices.json`. A model without a price is counted as unpriced, and its group total is marked incomplete until you add a price.
- **Subscription limits.** At each refresh, AgentMeter reads Claude Code's stored login from the macOS keychain through Apple's `/usr/bin/security` tool, and asks Anthropic's usage endpoint for the current utilization. Claude Code's keychain items already trust that tool, so no keychain dialog appears.

## Privacy

- AgentMeter only reads Claude Code's session logs and keychain items. It never writes to them and never refreshes or changes your login.
- The only network request goes to `api.anthropic.com` with your own token, to fetch your usage. There is no telemetry and no other server.
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
