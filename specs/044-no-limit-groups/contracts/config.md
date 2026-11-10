# Contract: Configuration Form of a Group

`~/.config/agenttacho/config.json`, `groups[]`. Every key below is optional unless marked required; files of earlier versions load unchanged.

```json
{ "id": "grp-free", "name": "Free models", "icon": "solid:gift",
  "period": "monthly", "shownInBar": true, "thresholds": [80, 100],
  "valueAs": "claude-opus-5-5", "show": "tokens" }
```

| Key | Type | Rule |
|---|---|---|
| `id`, `name` | string | required, as today |
| `budgetUSD` | number or `null` | absent or `null`: no amount (FR-001). Present: must be > 0, otherwise the file is invalid with today's message (`Monthly budget of group "<name>" must be greater than 0.`) |
| `weeklyBudgetUSD` | number | legacy, read as today; used only when `budgetUSD` is absent |
| `period` | `"weekly"` or `"monthly"` | as today; kept without an amount |
| `shownInBar`, `thresholds` | | as today; kept and validated without an amount, no effect until an amount exists (FR-002) |
| `timeFormat` | | as today |
| `valueAs` | model id | new for groups; any string; a model without a price is valid (missing-model note) |
| `show` | `"automatic"`, `"percent"`, `"tokens"`, `"money"` | new for groups; absent means Automatic; an unknown value reads as Automatic and logs `group "<name>": unknown show value "<value>", using Automatic` once per load |

Writing:

- `budgetUSD` only when the group has an amount; never `null`.
- `valueAs` when set.
- `show` only when not Automatic.
- `weeklyBudgetUSD` never.

Behavior keys (`valueAs`, `show`) are presentation only: changing them does not start a refresh (`dataRelevant()` masks them).
