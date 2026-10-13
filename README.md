# LLM Usage Menu Bar

A macOS menu bar app that shows how much of each LLM usage limit you have consumed, across accounts with different pricing models.

- **Subscription accounts** (Claude Max via Claude Code): the real 5-hour and 7-day utilization reported by Anthropic's usage endpoint, read with the OAuth token Claude Code keeps in your login keychain. The bar shows the higher of the two windows.
- **Token-based accounts** (Claude Code via Google Vertex): USD spend computed from Claude Code's local session logs with a built-in, overridable price table, against a self-set weekly budget owned by a budget group.
- **Budget groups** combine one or more token-based accounts under one weekly budget. Their week aligns with the subscription's 7-day reset (or a configurable weekday when no reset is known).
- The dropdown shows every account and group with reset times, a per-model breakdown and a per-day trend. macOS notifications fire once per threshold per window.

The bar reads like `M 42%  V ⚠87%`: a 1 to 3 character label per entry, a warning glyph at or above the lowest configured threshold (80% by default), `‼` at or above 100%, and `~` while the value is stale.

## Build and run

Requirements: macOS 14 or newer, Apple Silicon, the Xcode Command Line Tools with Swift 5.10 or newer. No third-party packages.

```bash
make test     # unit tests for UsageCore (Swift Testing)
make app      # assembles build/LLM Usage.app with Info.plist and an ad-hoc signature
make run      # launches the bundle
```

The first launch creates a default configuration with one subscription account when Claude Code is signed in. Keychain consent: on the first keychain read macOS asks whether the app may read the "Claude Code-credentials" item. Click **Always Allow**. The ad-hoc signature changes with every rebuild, so the dialog returns after each `make app`; a developer certificate makes it stick.

Run from the bundle, not with `swift run`: notifications and keychain access need an application bundle.

## Configuration

One JSON file at `~/.config/llm-usage-menubar/config.json`, written by the settings window and editable by hand. The app reloads it at the next refresh when the modification time changed; an invalid file is reported in the dropdown while the last valid configuration stays active.

Settings window (dropdown, "Settings…"):

- **General**: refresh interval (default 300 s, minimum 60 s), the subscription account that aligns the weekly window, the weekday and hour fallback, start at login, additional Claude Code directories to scan.
- **Accounts**: label, display name, custom detection marker, credential directory and thresholds for subscription accounts, provider and budget group for token-based accounts. A token-based account must join an existing group or create a new one; removing the last member removes the group.
- **Groups**: name, label, weekly budget, shown in bar, thresholds.
- **Prices**: the built-in table (USD per million tokens) with per-model overrides and new models.

Labels are 1 to 3 characters and unique across accounts and groups together.

## Where the data comes from

- Session logs: `~/.claude/projects/**/*.jsonl` plus any configured directories. Only files changed since the previous refresh are re-read. Vertex sessions are recognized by the `req_vrtx_` request id prefix; direct Anthropic sessions by `req_` without a provider infix. A custom marker (any substring of the raw assistant record) can separate accounts the built-in rules cannot.
- Prices: `Sources/UsageCore/Resources/prices.json`. Models with no price are counted as unpriced and the containing total is flagged incomplete so you can add a price.
- Credentials are read only at refresh time and never written anywhere.

## Diagnostics

Every refresh writes one line per source to `~/Library/Logs/llm-usage-menubar/usage.log` (capped at 5 MB, one older generation kept). "Open log" in the dropdown opens it. `scripts/sum-vertex.sh <start> <end> [dir...]` recomputes the Vertex spend for a window with `jq` to cross-check the app.

## Layout

- `Sources/UsageCore`: all logic (configuration, parsing, pricing, attribution, windows, aggregation, thresholds), no UI.
- `Sources/LLMUsageMenuBar`: the SwiftUI menu bar app.
- `Tests/UsageCoreTests`: Swift Testing suites with JSONL fixtures.
- `specs/001-llm-usage-menubar`: specification, plan, research and quickstart.
