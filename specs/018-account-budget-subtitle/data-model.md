# Data Model: Account Budget Subtitle

No persisted data changes.

## AccountBudgetDescription (new, UsageCore, derived)

| Field | Type | Meaning |
|---|---|---|
| `provider` | String | `Provider.displayName` of the token-based account |
| `budget` | Kind | `.group(iconId, name, amount, period)`, `.ownBudget(amount, period)` or `.missingGroup` |

Derived texts:

| Kind | Visible text (en_US) | Accessibility text |
|---|---|---|
| group | "Vertex · " + icon + " Vertex, $400 / month" | "Vertex, group Vertex, $400 per month" |
| own budget | "OpenAI · own budget, $50 / week" | "OpenAI, own budget, $50 per week" |
| missing group | "Vertex · no group" | "Vertex, no group" |

Built from an `Account` and the `Configuration` draft; nil for subscription and Codex subscription accounts.

## BudgetAmountFormatter (new, UsageCore)

- Input: amount (`Decimal`), `BudgetPeriod`, `Locale`.
- Output: currency amount rounded to cents, no decimals when whole, two otherwise, plus " / month" or " / week".
- Used by both Settings lists (spec SC-004).
