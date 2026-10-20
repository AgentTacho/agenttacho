# Data Model: Site Reframe Screenshots

## Demo account `acc-max-personal` (new, `Resources/demo/default.json`)

| Field | Value |
|---|---|
| `type` | `subscription` |
| `icon` | `brands:claude` |
| `displayName` | `Claude Max · Personal` |
| `harness` | `claudeCode` |
| `credentialDirectory` | `~/.claude-personal` |
| `shownInBar` | `true` |
| `thresholds` | `[80, 100]` |

Plan data (`claude.acc-max-personal`): `plan: max`, `fiveHour {used 20, resetsIn 2h30m}`, `sevenDay {used 35, resetsIn 3d12h}`, no model limits. Usage: four records within the week on `claudeCode`.

Changed: `acc-max.displayName` becomes `Claude Max · Work`. Arrangement: `acc-max, acc-max-personal, acc-codex, grp-company, acc-side`.

Validation (coverage tests, last frame): both are `subscription` on `claudeCode` with different directories; adjacent in arrangement; both in the bar; window levels differ by at least 15 points; the second is `normal` level and on pace; the first has a non-empty breakdown and its 7-day attention row.

## Shot markers (accessibility identifiers, demo and real app alike)

| Identifier | Element | Who gets it |
|---|---|---|
| `agenttacho.claudeSection` | whole subscription section | first of `BarLayout.shotClaudeAccountIds` |
| `agenttacho.claudeSection2` | whole subscription section | second of `BarLayout.shotClaudeAccountIds` |
| `agenttacho.claudeDetails` | the section's details disclosure | first only |
| `agenttacho.details` | budget details (unchanged) | shot budget owner |
| `agenttacho.budgetRow` | budget row (unchanged) | shot budget owner |
| `agenttacho.claudePlan`, `agenttacho.paceRow` | removed | |

## Crop geometry (`fill_crop`)

Inputs: window frame `W` and region frame `R` in points. `m = min(R.x - W.x, R.y - W.y, W.x+W.w - (R.x+R.w), W.y+W.h - (R.y+R.h), 0.04 * min(R.w, R.h))`. Output `(R.w+2m) x (R.h+2m)` at `(R.x-W.x-m, R.y-W.y-m)`, all times 2. Fails when `2m < 4` or `(R.w+2m)/(R.h+2m)` is outside `[0.75, 4/3]`.
