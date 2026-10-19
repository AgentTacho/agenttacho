# Data Model: Headline Window Switch

## HeadlineChoice (UsageCore, stored)

The chosen window of one subscription account (spec Key Entities "Headline choice").

| Case | Account kind | Stored as |
|---|---|---|
| `claudeFiveHour` | subscription | `"fiveHour"` |
| `claudeSevenDay` | subscription | `"sevenDay"` (resolves to the default; never written by a click) |
| `claudeModel(name)` | subscription | `"model:<name>"`, name non-empty, exact case |
| `codexWindow(name)` | codexSubscription | `"window:<name>"`, name `N-hour`, `N-day` or `weekly` |

- Held as `headlineWindow: HeadlineChoice?` in `SubscriptionSettings` (Claude cases only) and `CodexSubscriptionSettings` (Codex case only); nil is the default window.
- Decode: invalid string, wrong kind, empty model name or non-string: nil plus a `ConfigurationLoadNotes` entry (FR-010). Encode: written only when non-nil.
- Presentation only: `Configuration.dataRelevant()` sets it to nil (FR-011).

## ResolvedHeadline (UsageCore, computed)

The window in effect for one account at one snapshot (spec Key Entities "Resolved headline").

| Field | Meaning |
|---|---|
| `claudeWindow` | `ClaudeWindow` (`.fiveHour`, `.sevenDay`, `.model(name)`) for a Claude account, else nil |
| `codexName` | the Codex window name for a Codex account, else nil |
| `rowName` | the row's displayed name: "5-hour", "7-day", the model name, the Codex window name |
| `isDefault` | true for the 7-day window or the longest effective Codex window |
| `percent` | rounded percent, nil when the window has no values (fixed window unavailable) |
| `pace` | the window's pace at the snapshot time, nil without one |
| `burnKey` | `BurnWindowKey` of the window, for `↑` |
| `tag` | nil when `isDefault`, otherwise the FR-008 text |
| `accessibilityName` | "5-hour window", "Fable weekly limit", "weekly window" |

Resolution (FR-006):

1. No choice, or the choice is the default window: default window.
2. Claude fixed choice (`fiveHour`, `sevenDay`): that window, also without values.
3. Claude model choice: the model limit with that exact name in the effective status, else the default window.
4. Codex choice: the last effective window with that name, else the default window; when it is the longest window it is the default (no tag).
5. Before the first values, a Claude account that is not signed in, or a Codex entry without windows: the bar keeps "…" or "--" without a tag. A signed-in Claude entry without a status (stale without last good values, expired credentials) still resolves a fixed choice: "5h --" with the tag.
6. Two effective Codex windows with one name: the last one, like `barWindow` and the burn inputs.

## BarItem (UsageCore, changed)

Two new fields, nil for budgets, members and default-window entries:

- `tag: String?`: drawn after the icon in the icon's tone (FR-009).
- `windowName: String?`: the resolved headline's `accessibilityName`, only together with `tag`.

## Level (FR-007, research R4)

| Account | Critical when | Otherwise |
|---|---|---|
| Claude | headline percent >= 100 or 7-day percent >= 100 | `BarLayout.level(headline percent, thresholds)` |
| Codex | any effective window reached its limit | `BarLayout.level(headline percent, thresholds)` |

## Coverage report (DemoMode, changed)

- `barTags: [String: String]`: bar entry id to tag, for entries with a tag.
- `headlineRows: [String: String]`: subscription account id to the headline row's name.
