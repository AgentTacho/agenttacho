# Contract: UI Strings

Examples in en_US. Placeholders in angle brackets. Strings not listed here are unchanged from spec 041 `contracts/ui-strings.md`.

## Dropdown headline (FR-013, FR-016)

| Measure | Headline | Tooltip | Accessibility |
|---|---|---|---|
| Percent | as today (`37%`, remaining `63%`, over `−15%`) | as today | as today |
| Tokens | `48.2M` | `48.2 million tokens this month` (scale word `million` or `billion` from a million on; below a million the exact count, `950,000 tokens this week`) | `48.2 million tokens this month` (compact count spelled with its scale word) |
| Money, spent | `$37`; `$0` for exactly 0; `<$1` above 0 and below one dollar | `$37.42 spent this month` | `$37.42 spent this month` |
| Money, remaining mode, left | `$63` | `$62.58 left of $100/month` | `$62.58 left of $100/month` |
| Money, remaining mode, over | `−$12` (typographic minus U+2212); below one dollar `<$1` left, `−<$1` over | `$12.40 over $100/month` | `$12.40 over $100/month` |

Rounding of the visible Money amount: whole dollars, half up. A Money headline never contains "≈".

## Section without an amount: line below the headline (FR-014, FR-015)

| Case | Left of the reset text |
|---|---|
| Value as model set and priced | value line `≈ $412 at <model id> prices` (spec 041), also `≈ $0 at <model id> prices` |
| Value as model set, no price | missing-model note `Price tokens as: <model id> has no price` (neutral) instead of the value line |
| No Value as model, Money headline | `spent this week` / `spent this month` |
| No Value as model, Tokens headline | `this week` / `this month` |

| Value tooltip | Text |
|---|---|
| Only unpriced usage | `What these tokens would have cost at <model id> prices. Nothing was spent.` (spec 041) |
| Also priced usage | `What the tokens of models without a price would have cost at <model id> prices. Nothing was spent for them.` |

The "incomplete, unpriced" note (FR-007), shared with every budget section: `incomplete, unpriced: <model>, <model>, <model> and <K> more`. At most three model ids are named, each clipped to 32 characters (`...` appended); `and <K> more` only when there are more than three.

## Settings: account editor (FR-017, FR-018, FR-018a)

| Element | Text |
|---|---|
| Budget picker items | `Own budget`, then groups by icon and name (no `No limit`) |
| Amount field placeholder | `No limit` |
| Help on disabled thresholds and "Show in menu bar" | `Set a monthly budget to use thresholds and the menu bar.` (`weekly` for a weekly period) |
| "Show in menu bar" without an amount | disabled and unchecked; the kept value applies again once an amount is entered |
| Price tokens as pop-up label | `Price tokens as` (spec 041's `Value as`, renamed in walkthrough step 6; the configuration key stays `valueAs`) |
| Help on disabled Price tokens as | `Price tokens as applies only without a monthly budget.` (`weekly` for a weekly period) |
| Dropdown shows pop-up label | `Dropdown shows` |
| Dropdown shows items | `Automatic`, `Percent`, `Tokens`, `Money` |
| Help on disabled Percent (no amount) | `Percent needs a monthly budget. The headline follows Automatic.` (`weekly` for a weekly period) |
| Price tokens as caption | `Shows what the tokens of models without a price would cost at this model's prices.` |

## Settings: new account sheet

| Element | Text |
|---|---|
| Budget picker items | groups, `Own budget` (no `No limit`); preselection unchanged (first group when one exists) |
| Caption with an empty amount | `Without a monthly budget the account has no limit and is not shown in the menu bar.` (`weekly` for a weekly period) |
| Caption with an amount | unchanged: `Shown in the menu bar, with notifications at 80% and 100%. To share a budget with other accounts, create a budget group in the Groups tab first.` |
| Caption with a group chosen | unchanged: `To share a budget with other accounts, create a budget group in the Groups tab first.` |
| Amount error (also groups and the account editor) | `The weekly budget must be greater than 0.` / `The monthly budget must be greater than 0.` below the field, for an amount of 0 or less; an empty own budget amount has none |

## Settings: lists (FR-020, FR-021)

| Element | Text |
|---|---|
| Accounts subtitle | unchanged: `<session kind> · no limit / week`, `/ month` |
| Menu Bar tab caption | `No limit` |
| Menu Bar tab checkbox | `Show in bar`, disabled and unchecked, help `Set a monthly budget to show this account in the menu bar.` (the account's period) |
