# Contract: Configuration

## Own budget without an amount (FR-002, FR-003)

Written by this version:

```json
{
  "id": "acc-api",
  "type": "tokenBased",
  "displayName": "API key",
  "budget": {"period": "monthly", "shownInBar": true, "thresholds": [80, 100]},
  "show": "money",
  "valueAs": "claude-opus-5-5"
}
```

- `budget.budgetUSD` absent or `null`: no amount, no limit.
- `budget.budgetUSD` present: must be greater than 0 (spec 003 FR-019), else invalid.
- `budget.shownInBar` and `budget.thresholds` keep their defaults and meaning; without an amount they have no effect.
- A group's `budget.budgetUSD` stays required.

## Spec 041 form, read only (FR-004)

`"noLimit": {"period": "monthly"}` loads as `budget` without an amount, period kept, thresholds `[80, 100]`, `shownInBar` true. Each converted account gives exactly one load note, the name clipped to 32 characters like every load note: `account "<name>": No limit is now an own budget without an amount; the next save writes the new form`. Rules of spec 041 stay: a `noLimit` object with `budgetUSD`, `thresholds` or `shownInBar`, or an account with `noLimit` plus account-level `shownInBar` or `thresholds`, or with both `noLimit` and `budget` or `groupId`, is invalid. `noLimit` is never written.

## `show` (FR-010)

Account-level key of a token-based account: `"automatic"`, `"percent"`, `"tokens"`, `"money"`. Absent means Automatic and is what Automatic writes. An unknown value gives a load note and Automatic. Kept for group members. A change does not trigger a refresh (presentation only).

## `valueAs` (FR-006)

Unchanged key. Applies only to an own budget without an amount, and only to unpriced models.
