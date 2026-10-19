# Data Model: Minimal Dropdown

Types are in `UsageCore` unless noted. None is persisted except `TimeFormat`.

## TimeFormat (configuration)

| Field | Type | Rule |
|---|---|---|
| raw value | `relative` or `absolute` | JSON key `timeFormat` on an account object and a group object |

- Absent: `relative`. Unknown or unreadable: `relative` and a load note (no problem notice).
- Encoded always (written on every save).
- `Account.timeFormat`, `BudgetGroup.timeFormat`, default `.relative`.
- `Configuration.timeFormat(for: ArrangedEntry) -> TimeFormat`: the account's value for `.account`, the group's for `.group`. The Unassigned section has no times.
- Settings shows the picker for Claude and Codex subscription accounts, token-based accounts with their own budget, and groups; a token-based account in a group keeps its stored value but shows no picker (FR-021).

## PaceReading

| Field | Type | Meaning |
|---|---|---|
| `pace` | `Pace` | spec 011 pace at the observation time |
| `burn` | `BurnRate?` | spec 017 burn rate from the same inputs; nil when it cannot be computed |

- `UsageSnapshot.paceReading(for: BurnWindowKey) -> PaceReading?`; nil when the key has no pace (spec 011 FR-007).
- `callsForAttention`: `pace.usesAttentionColor(burn:)`.

## RowBar

| Field | Type | Meaning |
|---|---|---|
| `fill` | `Double` 0...1 | used percent / 100, clamped |
| `tick` | `Double?` 0...1 | `pace.expectedPercent / 100`; nil without a pace |
| `tone` | `RowBarTone` | `.neutral`, `.attention`, `.overLimit` |
| `note` | `PaceNote?` | set exactly when `tone == .attention` |

- Built only by `RowBar.make(usedPercent:limitReached:reading:)` for a window row and `RowBar.budget(_:reading:)` for a budget; there is no public initializer.
- The bar keeps its `PaceReading` once and derives `tick`, `tone`, `note` and the accessibility summary from it, so they cannot disagree.
- Tone order: `.overLimit` when the row's rounded percent is 100 or more or `limitReached`; else `.attention` when the reading calls for attention; else `.neutral`.
- A window row's rounded percent is `PercentFormatter.rounded(usedPercent)`. A budget's fill is its unrounded spend share (`GroupEntry.usedPercent`, the fill caps at 1), and its rounded percent is `GroupEntry.percent`, the value the header shows, so the header and the red bar always agree.

## PaceNote

| Field | Type | Meaning |
|---|---|---|
| `pace` | `Pace` | for the status words and the spec 011 run-out |
| `fastRunOut` | `Date?` | spec 017 fast run-out |

- Built only by `RowBar` from its reading.

- `text(times: TimeText) -> String`: `pace.summary(runOutText: times.runOut, fastRunOut:)`, for example "15% ahead · runs out in 2d 13h".
- `tooltip(times:)`: the same text with the run-out in the other format.
- `RowBar.accessibilitySummary(times:)`: the pace summary for any pace, also without a note; "no pace" wording is not added when there is no pace (the label then names window, percent and reset only).

## TimeText

| Input | Type |
|---|---|
| `format` | `TimeFormat` |
| `now` | `Date` (reference time, passed in) |
| `calendar` | `Calendar` (its `timeZone` is used) |
| `locale` | `Locale` |

| Output | Example relative | Example absolute |
|---|---|---|
| `reset(_:)` | "resets in 2h 26m" | "resets 17:20", "resets Fri 09:00", "resets Sun 25. Oct 09:00", "resets Sun 1. Nov" |
| `runOut(_:)` | "in 2d 13h" | "Wed 05:30" |
| `resetTooltip(_:)` | long absolute form | relative form |
| `runOutTooltip(_:)` | long absolute form | relative form |

Relative rules: minutes rounded down; "<1m"; two largest units; zero second unit omitted; not in the future: "now". Absolute rules: calendar days from `startOfDay(now)`; 0 time; 1 to 6 weekday and time; otherwise (later or earlier) weekday, day, month, time; a reset at local midnight not today: weekday, day, month. Examples are en_US-agnostic illustrations; the locale decides the styles.

## SectionNote

| Field | Type | Meaning |
|---|---|---|
| `text` | `String` | exact text as shown today |
| `style` | `NoteStyle` | `.neutral` (secondary), `.warning` (orange), `.alert` (red) |

Notes (FR-029): retrying (neutral), stale with last good value and reason (warning), rejected sign-in (alert), not signed in (neutral), expired credentials (warning), Codex local data (neutral), Codex newer snapshot (neutral), Codex stale (warning, alert when the sign-in was rejected), Codex unavailable (neutral, alert when rejected), no data or refreshing (neutral), budget incomplete prices (warning), budget "stale since <time>" (warning), empty group (neutral), plain "stale" marker of Codex and Unassigned (warning).

## FooterText and DetailsTotal

- `FooterText.lastRefreshed(at:hasSnapshot:isPreliminary:now:calendar:locale:) -> String`; a known last refresh time wins over "Refreshing…".
- `FooterText.paceTooltip(_ status: RefreshPaceStatus?, now:calendar:) -> String?`.
- `DetailsTotal.weekly(tokens:locale:) -> String`: "This week: 45.1M tokens".

## CoverageReport additions (DemoMode)

| Field | Type | Meaning |
|---|---|---|
| `attentionRows` | `[BurnWindowKey]` | keys whose `paceReading(for:)?.callsForAttention` is true after the last frame |
| `singleMemberGroups` | `[String]` | names of groups with exactly one member |
| `absoluteTimeOwners` | `[String]` | display names of accounts and names of groups with `timeFormat == .absolute` |
