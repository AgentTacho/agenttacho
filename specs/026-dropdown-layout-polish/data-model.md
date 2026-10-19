# Data Model: Dropdown Layout Polish

No persisted configuration change. One UI preference: `showsMemberTables` (Bool, `UserDefaults`, default false).

## MemberDisplay (UsageCore)

| Field | Type | Rule |
|---|---|---|
| `lines` | `[String]` member ids | members with a usage entry, in member order, only when the group has two or more members |
| `tables` | `[String]` member ids | members with a non-empty breakdown, in member order, only when there are two or more such members |
| `showsAccountsButton` | `Bool` | `!tables.isEmpty` |

## DayRowTotal (UsageCore)

| Field | Type | Rule |
|---|---|---|
| `text` | `String` | Σ value: `CompactFormat.usd(sum of costUSD)` for cost rows, `CompactFormat.millions(sum of totalTokens)` for token rows; "0" for no usage |
| `tooltip` | `String` | "Total: <exact>" plus "\nincomplete: some usage is unpriced" when the budget is incomplete |

## CompactFormat (UsageCore)

- `millions(_ tokens: Int) -> String`: "0", "<1", whole millions with grouping (moved from `UsageFormat.millions`).
- `usd(_ value: Decimal, locale:) -> String`: "<1", whole below 1,000, compact name above ("1.6K") (moved from `UsageFormat.compactUSD`).

## FooterErrors (UsageCore)

- `visible(_ errors: [SourceError], limit: Int = 3) -> [FooterErrorLine]`; `FooterErrorLine { text: String; tooltip: String }`; with more than `limit` errors the last line is "+N more" whose tooltip lists every error.

## FooterText additions (UsageCore)

- `statusTooltip(statusText: String, isTruncated: Bool, paceText: String?) -> String?`.
- `DetailsTotal` is removed (spec 025 FR-014 superseded).

## CoverageReport additions (DemoMode)

- `memberDisplays: [String: MemberDisplay]` keyed by group name.
