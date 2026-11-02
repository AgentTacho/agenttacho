# Contract: UI Strings

Examples in en_US. Placeholders in angle brackets.

## Dropdown section (FR-011 to FR-015)

| Element | Text |
|---|---|
| Header | icon, `<account name>`, bold `<compact tokens>` without unit (for example `48.2M`, `950K`, `0`); tooltip `<exact count> tokens this <week|month>` (`48,213,507 tokens this month`) |
| Second line | the value line on the left, or `this week` / `this month` without one; reset text right-aligned; the reset text moves below when both do not fit (`resets in 2d 4h` or `resets Mon 09:00`, section time format) |
| Value line | `≈ $412 at <model id> prices` (rounded half up); above 0 and below one dollar `≈ <$1 at <model id> prices`; exactly 0 `≈ $0 at <model id> prices` |
| Value tooltip | `What these tokens would have cost at <model id> prices. Nothing was spent.` |
| Missing-model note (neutral) | `Value as model <model id> has no price` |
| Stale and no-data notes | as for an own budget's section (spec 025 FR-029) |
| Accessibility label | `<account name>, <compact tokens> tokens this <week|month>, <reset text>[, about <amount> at <model id> prices | , less than $1 at <model id> prices | , Value as model <model id> has no price]` |

The value line never contains "spent" or "of" (FR-012).

## Settings: account editor (FR-016, FR-017)

| Element | Text |
|---|---|
| Budget picker items | `Own budget`, `No limit`, then groups by icon and name |
| Period picker | as for an own budget (`Weekly`, `Monthly`) |
| Value as pop-up label | `Value as` |
| Value as items | `None`, primary model ids, submenu `More` with imported model ids |
| Missing selection | `<model id> (no price)` |
| Caption below the pop-up | `Shows what this account's tokens would have cost at this model's prices.` |
| Times picker | as today (`Relative`, `Absolute`) |

## Settings: new account sheet

| Element | Text |
|---|---|
| Budget picker items | groups, `Own budget`, `No limit` (existing order, `No limit` appended) |
| Caption with No limit | `Counts tokens without a limit. Not shown in the menu bar.` |

## Settings: lists

| Element | Text |
|---|---|
| Accounts subtitle | `<session kind> · no limit / week`, `<session kind> · no limit / month` |
| Accounts subtitle, VoiceOver | `<session kind>, no limit, per week` / `per month` |
| Menu Bar tab row caption | `No limit`, no "Show in bar" checkbox |
