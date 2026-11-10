# Contract: UI Strings

en_US. `<period>` is "week" or "month"; `<adjective>` is "weekly" or "monthly". Strings already defined by spec 043 are reused verbatim and only referenced here.

## Dropdown: group section without an amount

| Element | Text |
|---|---|
| Headline, Money | spec 043 `HeadlineText.spent`: "$93"; tooltip "$93.46 spent this month" |
| Headline, Tokens | spec 043 `HeadlineText.tokens`: "48.2M"; tooltip "48.2 million tokens this month" |
| Line below headline | spec 043: value line "≈ $412 at claude-opus-5-5 prices" when Price tokens as is set, else "spent this month" (Money) or "this month" (Tokens), left of the reset text |
| Notes | spec 043: "incomplete, unpriced" (Money, unpriced records, no Price tokens as); missing-model note "Price tokens as: <model id> has no price" |

## Dropdown: member lines

| Group | Measure | Trailing text | Tooltip and accessibility text |
|---|---|---|---|
| with amount | any | "$181 (36%)" (today) | "$181.40 spent this month, 36% of the $500 budget" |
| without amount | Money | "$93", "<$1", "$0" | "$92.84 spent this month"; with unpriced records: "$0 spent this month, 48.2 million tokens without a price" |
| without amount | Tokens | "48.2M" | "48.2 million tokens this month" |

Member lines never contain "≈".

## Settings: group editor

| Element | Text |
|---|---|
| Amount placeholder | "No limit" (`OwnBudgetForm.amountPlaceholder`) |
| Help, disabled thresholds and "Show in menu bar" | "Set a <adjective> budget to use thresholds and the menu bar." (`needsBudgetHelp`) |
| "Price tokens as" label, caption, disabled help | as `OwnBudgetForm.valueAsLabel`, `valueAsCaption`, `valueAsDisabledHelp` |
| "Dropdown shows" label and entries, Percent help | as spec 043 (`DropdownShow`) |

## Settings: Groups tab list

| Case | Subtitle | VoiceOver |
|---|---|---|
| with amount | "$400 / month, 2 member(s)" (today) | same text |
| without amount | "no limit / month, 2 member(s)" | "No limit, monthly, 2 members" |

## Settings: Accounts list (member subtitle)

| Case | Subtitle |
|---|---|
| member of a group with amount | today's text ("Company budget, $500 / month") |
| member of a group without amount | "Free models, no limit / month" |

## Settings: Menu Bar tab

| Row | Caption | Checkbox | Help |
|---|---|---|---|
| group without amount | "No limit" | disabled, unchecked | "Set a <adjective> budget to show this group in the menu bar." |
| member of such a group | "Member share" | disabled, unchecked | "Set a <adjective> budget for the group to show this account in the menu bar." |

## Settings: account editor (member)

| Element | Text |
|---|---|
| "Show this account's share in the menu bar", disabled while the group has no amount | help "Set a <adjective> budget for the group to show this account in the menu bar." |

## Settings: remove group sheet

| Case | Destination note for "each to its own budget" |
|---|---|
| with amount | today's wording |
| without amount | "Each account gets its own budget with this group's period and settings, without an amount." |

## Diagnostic log

`[refresh] no limit group <name> (<period>, <window start> to <window end>, <time zone>): <tokens> tokens, <spend> USD spent[, unpriced: <models>][, stale]`
