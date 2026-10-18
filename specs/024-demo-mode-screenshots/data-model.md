# Data model: Demo build and screenshot capture

All types are in the new `DemoMode` target unless noted. The JSON format is in [contracts/scenario-format.md](contracts/scenario-format.md).

## Scenario

| Field | Type | Rule |
|---|---|---|
| `name` | String | equals the file name without `.json` |
| `configuration` | `Configuration` (UsageCore) | decoded with the app's own decoder; must validate |
| `importedPrices` | imported price batches (UsageCore format of `imported-prices.json`) | optional |
| `claude` | `[accountId: ClaudeWindows]` | each id is a `subscription` account in `configuration` |
| `codex` | `[accountId: CodexWindows]` | each id is a `codexSubscription` account |
| `usage` | `[UsageEntry]` | each `account` is an account id in `configuration` |
| `frames` | `[Frame]` | offsets strictly increasing, all > 0 |

Validation failures produce a `ScenarioError` with the JSON path and a message (FR-013).

## ClaudeWindows

`plan` (`pro`, `max`), `fiveHour` and `sevenDay` as `WindowValue`, optional `models` (`[name: WindowValue]` for model limits). Becomes `SubscriptionEntry(status: SubscriptionStatus(fiveHour:sevenDay:modelLimits:subscriptionType:fetchedAt: now), state: .ok, fetchOutcome: success)`.

## CodexWindows

`plan` (`plus`, `pro`), `windows: [WindowValue]` each with `lengthMinutes`. Becomes `CodexLimitsEntry(observation: CodexLimitObservation(planType:observedAt: now, origin: .live, windows:), state: .live)`; the scenario's configuration sets `liveLimits: true` so the threshold tracker accepts it.

## WindowValue

`used` (percent, 0 to 100) and `resetsIn` (duration). The reset time is `launch + resetsIn`, fixed for the whole run.

## UsageEntry

| Field | Rule |
|---|---|
| `at` | negative duration from launch (`-2d3h`) |
| `account` | account id |
| `harness` | `claudeCode`, `codex`, `openCode` |
| `model` | must be priced (built-in or `importedPrices`) for token-based accounts |
| `project` | path-like name, shown by its last component (`~/src/checkout-service`) |
| `input`, `output`, `cacheRead`, `cacheWrite` | token counts, `cacheWrite` counts as 5-minute writes |

Becomes `UsageRecord` with `timestamp = launch + at` (moved into the current month for monthly-budget accounts, research R6), a stable `messageId` from the scenario name and index, and `costUSD` from `PriceTable.effective(builtIn:imported:overrides:)` like `SessionLogSource` does.

## Frame

`at` (positive duration), optional `claude` and `codex` (partial `WindowValue` changes per account and window), optional `usage` (entries appended from this frame on).

## ScenarioPlayer

An actor created with the scenario and the launch date. `state(at now: Date)` returns the merged values of all frames with `launch + at <= now`. Pure apart from the clock; every demo source asks it on `collect`.

## Durations

`[-]` then one or more of `Nd`, `Nh`, `Nm`, `Ns` in this order (`2h10m`, `-3d`, `12s`). Anything else is a `ScenarioError`.

## Paths (UsageCore, changed)

`Paths(home:appFolder:)` with `appFolder` default `agenttacho`. The four file locations use `appFolder` in place of the fixed `agenttacho` (`.config/<appFolder>/`, `Library/Logs/<appFolder>/`, `Library/Application Support/<appFolder>/`). The demo uses `agenttacho-demo`.

## UpdateState (UsageCore, changed)

New case `.demoBuild` with title and line text "Demo build: updates are off".

## Coverage (DemoMode, test support)

`ScenarioCoverage.evaluate(scenario:launch:)` runs the scenario through a `RefreshCoordinator` with the three demo sources and a test clock: one refresh at launch, one after each frame. It returns the bar levels, markers, pace states of the dropdown meters, threshold crossings between the first and last refresh, incomplete budgets and the harnesses with usage. The coverage test compares it with FR-014.
