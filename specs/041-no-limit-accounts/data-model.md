# Data Model: Accounts without a Limit

## TokenMembership (changed)

```text
enum TokenMembership
  case group(id: String, shownInBar: Bool)      // unchanged
  case ownBudget(BudgetSettings)                // unchanged
  case noLimit(NoLimitSettings)                 // NEW (FR-001)
```

Exactly one case per token-based account, by type. Accessors on `TokenBasedSettings`: `groupId`, `ownBudget`, `memberShownInBar` (unchanged), `noLimit: NoLimitSettings?` (new).

## NoLimitSettings (new)

| Field | Type | Rule |
|---|---|---|
| `period` | `BudgetPeriod` (`weekly`, `monthly`) | absent in the file means weekly (FR-002) |

No amount, thresholds or shown-in-bar: not representable, and rejected when present in the file (contracts/config.md).

## TokenBasedSettings (changed)

| Field | Type | Rule |
|---|---|---|
| `valueAs` | `String?` | model id; kept for every membership; used only while the membership is `.noLimit` (FR-003, FR-018); never validated against the price table |

`Account.timeFormat` is unchanged and applies to No limit accounts (spec 025 FR-021 extended).

## NoLimitEntry (new, snapshot)

| Field | Type | Meaning |
|---|---|---|
| `period` | `BudgetPeriod` | the account's period |
| `window` | `DateInterval` | current window of the period (spec 003 rules) |
| `resetAt` | `Date` | end of the window |
| `breakdown` | `UsageBreakdown` | per-model and per-day tokens, `priced: false`; `ModelUsage` keeps 5-minute and 1-hour cache writes apart |
| `totalTokens` | `Int` | input + output + cache write + cache read (FR-006) |
| `stale` | `Bool` | as for other entries (spec 006 FR-005) |

`UsageSnapshot.noLimitAccounts: [String: NoLimitEntry]`, keyed by account id. A No limit account never has an `accountBudgets` entry.

## ReferenceValue (new, computed at presentation time)

```text
enum ReferenceValue
  case none                               // no valueAs
  case missing(model: String)             // valueAs not found in the effective price table
  case value(Decimal, model: String)      // sum over breakdown models of PriceTable.cost(..., price: reference)
```

## NoLimitPresentation (new, texts)

| Field | Example (en_US) |
|---|---|
| `headline` | `48.2M`, `0` |
| `periodLine` | `tokens this month` |
| `resetText` | `resets Dec 1` / `resets in 6d 4h` (section time format) |
| `valueLine` | `≈ $412 at claude-opus-5-5 prices`, `≈ <$1 at claude-opus-5-5 prices`, or nil |
| `valueTooltip` | see contracts/ui-strings.md |
| `notes` | stale, no data, `Value as model gateway-x/foo has no price` (neutral) |
| `accessibilityLabel` | name, tokens with period, reset, value or missing note |

## ValueAsOptions (new)

| Field | Content |
|---|---|
| `primary` | built-in and override entries, sorted by model id |
| `more` | imported (provider, CSV) entries, sorted by model id |
| `unlisted` | the selected id when it resolves only through normalization or prefix fallback, shown as stored |
| `missing` | the selected id when the table has no price for it, else nil |

## Transitions (Settings, FR-018, FR-019)

| From | To | Result |
|---|---|---|
| own budget | No limit | period from the budget; amount, thresholds, shown-in-bar dropped; `valueAs`, `timeFormat` kept; threshold state dropped |
| group | No limit | period from the group; leaves the group; the group stays, also without members (spec 009 FR-002); arrangement per spec 008 FR-006 |
| No limit | own budget | period kept; amount 0 (must be entered, save refused until > 0); thresholds 80, 100; shown in bar on; first refresh sets a threshold baseline |
| No limit | group | joins as a member, member shown-in-bar off; placed last in the group |
| No limit | No limit (period change) | window recomputed at the next refresh |

## Derived rules

- `budgetOwners` and `budgetOwner(forAccount:)` exclude No limit accounts.
- `Arrangement.isEntry` is true, `isShownInBar` false for No limit accounts.
- `WindowResolver.collectionWindow` widens to the month when any No limit account is monthly.
