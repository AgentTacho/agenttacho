# Quickstart: Dynamic Claude Plan Windows

## Prerequisites

- macOS with the project's toolchain; build only through the Makefile.

## Automated checks

```bash
make test           # UsageCore and DemoMode tests, including ClaudeLimitsTests
make test-release   # release script tests
```

Expected: all pass. The new tests cover the scenarios in spec US1 to US4 (window list from today's answer shape, returning 5-hour group, unknown group, old configuration and last-good files, top-level fallback).

## Demo build

```bash
make app-demo
```

Open the dropdown:

- The Claude Max section shows "7-day" and "Fable" rows, no "5-hour" row; the ● is on "Fable" and the bar entry reads `✳ Fable 50%` (contracts/dropdown-rows.md).
- The Codex section still shows "5-hour" and "weekly".
- With the `variants` scenario, a Claude account shows an extra "daily" row with percent and reset text and no pace note.

## Real app (maintainer, optional)

```bash
make app
```

- The Claude section shows no "5-hour: unavailable" row.
- `~/Library/Logs/agenttacho/usage.log` has one `[subscription] <id>: windows weekly_all/weekly/none, weekly_scoped/weekly/model:Fable (limits)` line after launch and an `ok(7-day N%, Fable N%)` summary per fetch.
- `last-good.json` holds a `windows` list and still the `sevenDay` and `modelLimits` keys.

## Screenshots

Ask the maintainer first, then `scripts/screenshots/capture.sh <site checkout>/src/assets/agenttacho` (AGENTS.md step 4).
