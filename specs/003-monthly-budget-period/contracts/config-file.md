# Contract Delta: Configuration File (budget groups)

Extends `specs/001-agenttacho/contracts/config-file.md`. Only the `groups` entries change.

## New form (written by the app)

```json
"groups": [
  {
    "id": "grp-vertex",
    "name": "Vertex",
    "label": "V",
    "period": "monthly",
    "budgetUSD": 400,
    "shownInBar": true,
    "thresholds": [50, 90]
  }
]
```

## Legacy form (still read)

```json
{ "id": "grp-vertex", "name": "Vertex weekly", "label": "V", "weeklyBudgetUSD": 60, "shownInBar": true, "thresholds": [80, 100] }
```

Loads as `period: weekly`, `budgetUSD: 60`.

## Decoding rules

| `period` | `budgetUSD` | `weeklyBudgetUSD` | Result |
|----------|-------------|-------------------|--------|
| absent or `"weekly"` | present | any | weekly, `budgetUSD` |
| absent or `"weekly"` | absent | present | weekly, `weeklyBudgetUSD` |
| `"monthly"` | present | any | monthly, `budgetUSD` |
| `"monthly"` | absent | present | **decode error** |
| any | absent | absent | **decode error** |
| other string, or not a string | any | any | **decode error** |

A decode error rejects the whole file; the app keeps the last valid configuration and shows the error in the dropdown (spec 001 FR-033).

## Encoding rules

- Every group is written with `period` and `budgetUSD`; `weeklyBudgetUSD` is never written (FR-004).
- Loading a legacy file does not rewrite it; the new form appears on the next save from the settings window.
- `budgetUSD` must be greater than 0 after decoding; otherwise validation fails with a message naming the period (FR-019).
