# Data Model: Unified Token Accounts

## TokenMembership (changed meaning, same cases)

| Case | User-facing meaning | Budget owner |
|---|---|---|
| `.group(id, shownInBar)` | member of a budget group | the group |
| `.ownBudget(BudgetSettings)` | own budget with an amount (> 0) | the account |
| `.noLimit(NoLimitSettings)` | own budget without an amount (no limit) | none (spec 041 FR-009) |

## NoLimitSettings (extended)

| Field | Type | Rule |
|---|---|---|
| `period` | `BudgetPeriod` | weekly or monthly, absent means weekly (unchanged) |
| `thresholds` | `[Int]` | NEW; kept, no effect without an amount (FR-003); `[80, 100]` for new accounts and the legacy form, `[]` when a `budget` object omits it |
| `shownInBar` | `Bool` | NEW; kept, no effect without an amount (FR-003); default `true` |

## TokenBasedSettings (extended)

| Field | Type | Rule |
|---|---|---|
| `valueAs` | `String?` | unchanged storage; effective only for `.noLimit`, on unpriced models (FR-006) |
| `show` | `DropdownShow` | NEW; default `.automatic`; kept in every membership (FR-018a) |

## DropdownShow (new)

`automatic`, `percent`, `tokens`, `money`. Pop-up rules: `isEnabled(_:hasAmount:)` (Percent disabled without an amount) and `help(_:hasAmount:)`.

`resolve(hasAmount: Bool, hasPricedUsage: Bool) -> HeadlineMeasure`:

| Stored | Amount | Priced usage | Result |
|---|---|---|---|
| automatic | yes | any | percent |
| automatic | no | yes | money |
| automatic | no | no | tokens |
| percent | yes | any | percent |
| percent | no | any | as automatic (FR-012) |
| tokens | any | any | tokens |
| money | any | any | money |

## OwnBudgetForm (new, Settings draft)

`period`, `amount: Decimal?`, `thresholds`, `shownInBar`. `init(_ membership:)` from `.ownBudget` or `.noLimit`; `membership` returns `.ownBudget` when `amount` is set and `.noLimit` otherwise, carrying period, thresholds and shown-in-bar over in both directions (FR-003, FR-019).

## NoLimitEntry (extended)

| Field | Type | Rule |
|---|---|---|
| `breakdown` | `UsageBreakdown` | now priced (per-model `costUSD`, `priced`) (R4) |
| `unpricedUsage` | `[ModelUsage]` | NEW; per model, only records without a price (Value as input, R5) |
| `spentUSD` | `Decimal` | NEW; sum of priced records' cost in the window |
| `hasPricedUsage` | `Bool` | NEW; at least one priced record in the window (FR-011) |
| `unpricedModels` | `[String]` | NEW, derived from the breakdown; for the incomplete note (FR-007) |

## HeadlineText (new, presentation)

`text`, `tooltip`, `accessibilityText` for a `HeadlineMeasure` and the section's numbers (percent, direction, spent, amount, tokens, period). See [contracts/ui-strings.md](contracts/ui-strings.md).

## Transitions

| From | Action | To | Kept |
|---|---|---|---|
| `.noLimit` | amount entered in the editor | `.ownBudget` | period, thresholds, shownInBar, valueAs, show |
| `.ownBudget` | amount cleared | `.noLimit` | period, thresholds, shownInBar, valueAs, show |
| `.group` | own budget chosen | `.ownBudget` with the group's period, amount, thresholds, shownInBar (spec 004 FR-014, unchanged) | valueAs, show |
| `.ownBudget` / `.noLimit` | group chosen | `.group` (unchanged) | valueAs, show |

Threshold state: dropped when the account stops being a budget owner, baseline on the first refresh after it becomes one (spec 004 FR-015, spec 041 FR-019; existing tracker logic).
