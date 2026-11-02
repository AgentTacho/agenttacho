# Data Model: Dynamic Claude Plan Windows

## ClaudeWindow (identity), replaces the enum in `Pace/ObservationLog.swift`

| Field | Type | Notes |
|---|---|---|
| rawValue | String | `fiveHour`, `sevenDay`, `model:<name>`, `model:<name>:<kind>`, `limit:<kind>` (spec FR-004) |

- `static let fiveHour`, `static let sevenDay`, `static func model(_:)` for the common identities.
- Used in `BurnWindowKey.claude(accountId, ClaudeWindow)`, `HeadlineChoice.claude(_)`, the threshold `WindowKind.rawValue` and the last-good `identity`.

## ClaudeLimit (one Claude window), in `Subscription/ClaudeLimits.swift`

| Field | Type | Notes |
|---|---|---|
| identity | ClaudeWindow | FR-004 |
| kind | String | from the entry; `five_hour` / `seven_day` for the fallback |
| group | String? | from the entry; `five_hour` / `weekly` for the fallback |
| length | TimeInterval? | from the group mapping (FR-003); nil for an unknown group |
| name | String | display name (FR-003, FR-005) |
| modelName | String? | set for a model limit |
| allowancePercentOfWeekly | Int? | model limits only (`weekly_scoped_shares`) |
| utilizationPercent | Double | |
| resetsAt | Date? | nil: not started, or reset passed in the effective status |

Derived: `isModelLimit` (`modelName != nil`), `isPlanWindow`.

Validation (builder): entry needs `percent` and a kind or a group; `resets_at` null or parseable; scope with only a surface is skipped; duplicate identity skipped (first wins).

## SubscriptionStatus (changed)

| Field | Type | Notes |
|---|---|---|
| windows | [ClaudeLimit] | FR-006 order |
| subscriptionType | String? | unchanged |
| fetchedAt | Date | unchanged |
| windowReport | ClaudeWindowReport? | set by the endpoint client for the FR-012 log line (fallback used, read and skipped entries); nil for saved values |

Accessors: `window(_ identity:)` (for example `window(.sevenDay)`), `planWindows`, `modelLimitWindows`, `defaultWindow` (FR-009), `effective(now:)` zeroes every window past its reset (spec 010 FR-016). Removed: stored `fiveHour`, `sevenDay`, `modelLimits`, `fiveHourPace`, `sevenDayPace`, `pace(of: ModelLimit)`; added `pace(of: ClaudeLimit, now:)`.

`ModelLimit` is removed (a temporary typealias during the migration, tasks T006 and T031); the dropdown row reads a `ClaudeLimit`. Public fixtures `ClaudeLimit.fiveHour/.sevenDay/.model` serve both test targets and DemoMode.

## ClaudeGroupMapping

| Group (lowercased) | Length | Name |
|---|---|---|
| `weekly` | 7 days | 7-day |
| `five_hour`, `session`, `5h` | 5 hours | 5-hour |
| other | none | from group (else kind): lowercased, `_` as space |

## HeadlineChoice (changed)

`case claude(ClaudeWindow)`, `case codexWindow(String)`. `stored`: identity raw value or `window:<name>`. `parse(raw, forCodex: false)` accepts `fiveHour`, `sevenDay`, `model:` plus a non-empty rest, `limit:` plus a non-empty rest.

## SavedClaudeValues (last-good, changed)

| Key | Notes |
|---|---|
| credentialDirectory, fetchedAt | unchanged |
| windows | new, optional: list of `{identity, kind, group?, lengthSeconds?, name, modelName?, utilizationPercent, resetsAt?, allowancePercentOfWeekly?}` |
| fiveHour, sevenDay, modelLimits | legacy, still written for windows with identity `fiveHour`, `sevenDay`, and the `model:<name>` limits; read when `windows` is absent |

## Threshold state

Key `(subscription, accountId, WindowKind(rawValue: identity, displayName: name))` per plan window with a reset time. Live set from the latest successful status; when there is none, the previous keys of the account stay live.

## Demo scenario (DemoMode)

`ClaudeWindows`: `plan`, `limits: [ScenarioClaudeLimit]`, `tickets`. `ScenarioClaudeLimit`: `kind`, `group`, `model?`, `used`, `resetsIn?`. `ClaudeChange.limits: [identity: WindowChange]`.

## State transitions

- Window appears in a successful answer: row shown, threshold baseline set on first sighting, pace from the next observations.
- Window missing from a successful answer: row gone, threshold key dropped silently, headline falls back (stored choice kept).
- Fetch fails: last-good list shown stale; no keys dropped.
