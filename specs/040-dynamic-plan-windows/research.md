# Research: Dynamic Claude Plan Windows

## R1: The endpoint answer today

- **Decision**: Treat `limits[]` as the source of the window list (spec FR-001), with the top-level `five_hour` / `seven_day` objects as a fallback only (FR-002).
- **Rationale**: One read-only request on 2026-11-02 (structure only) returned `five_hour: null`, a `seven_day` object with new dollar fields, about 20 null codenamed top-level keys, and `limits` with two entries: `{kind: weekly_all, group: weekly, scope: null, is_active: false}` and `{kind: weekly_scoped, group: weekly, scope: {model: {display_name: "Fable"}, surface: null}, is_active: true}`. Every entry has `percent`, `severity` and `resets_at`. `limits` is the general list; the top-level keys are a legacy view that keeps growing codenames.
- **Alternatives considered**: top-level keys with a name table (codenames stay unknown); both merged (two sources that must agree, `seven_day` duplicates `weekly_all`).

## R2: Window identity type

- **Decision**: Replace the `ClaudeWindow` enum (`fiveHour`, `sevenDay`, `model(String)`) with a struct `ClaudeWindow: Hashable, Sendable` holding one `rawValue: String`, the identity of spec FR-004 (`fiveHour`, `sevenDay`, `model:<name>`, `model:<name>:<kind>`, `limit:<kind>`). Keep `static let fiveHour`, `static let sevenDay` and `static func model(_ name: String)` so most call sites keep compiling.
- **Rationale**: The identity is already the stored form of `HeadlineChoice` (`fiveHour`, `sevenDay`, `model:<name>`); making it the key type removes the mapping layer and lets `BurnWindowKey.claude(id, window)`, the threshold `WindowKind` and the headline share one value. A struct mirrors how `WindowKind` already handles data-driven Codex windows (spec 007 research R8).
- **Alternatives considered**: add `case limit(String)` and `case modelKind(String, String)` to the enum (every switch grows, and the stored form needs its own mapping); key by array index (not stable across refreshes).

## R3: Status model

- **Decision**: `SubscriptionStatus` holds `windows: [ClaudeLimit]` in FR-006 order and a `windowReport`, built by one tested function (`ClaudeLimits.build`, signature in tasks.md Phase 1 Interfaces) from the decoded answer. Convenience accessors stay for the few places that need a fixed window: `window(_ id: ClaudeWindow)`, `sevenDay` (the window with identity `sevenDay`, for budget alignment and the at-or-above-100% rule), `planWindows`, `modelLimits`. The stored `fiveHour` and `sevenDay` properties and their initializer go away; a test helper builds statuses from a list.
- **Rationale**: The UI, thresholds, pace and headline then loop over one list. Keeping `sevenDay` as a computed accessor keeps budget alignment (RefreshCoordinator lines 281, 619) and `barPercent` unchanged in meaning (spec FR-017).
- **Alternatives considered**: keep `fiveHour` and `sevenDay` stored next to an `extraWindows` list (two places to read, the hardcoding stays); a separate model limit type in a parallel list (today's split, which FR-006 ordering and FR-004 identities make awkward).

## R4: Group mapping and names

- **Decision**: A small table in UsageCore: `weekly` gives 7 days and "7-day"; `five_hour`, `session`, `5h` give 5 hours and "5-hour". Unknown groups: no length, name from group (else kind), lowercased, `_` to space. A plan window of a known group without that group's identity is named from its kind. A further model limit of the same model is named "<model> <group words>", or "<model> <kind words>" when its group is `weekly` or missing. Duplicate identities: only the first in response order is kept (FR-005).
- **Rationale**: Spec FR-003 to FR-005. Matching group names exactly (after lowercasing) keeps the table predictable.
- **Alternatives considered**: parse lengths out of names (`daily` as 1 day): guessing, and wrong for names like `rolling`.

## R5: Ordering

- **Decision**: Stable sort: plan windows with a length by length ascending, ties in response order; then plan windows without a length in response order; then model limits in response order. The top-level fallback produces the 5-hour then the 7-day window.
- **Rationale**: Spec FR-006 keeps today's visual order (5-hour, 7-day, model limits) for the known shape.

## R6: Pace and burn rate

- **Decision**: `ClaudeLimit.paceInputs(observedAt:)` uses `length` (nil means no pace) and `resetsAt` (nil means no pace). Model limits get the length of their group (clarification Q2). `PaceReading.paceKeys` and `burnInputs(for:)` iterate `status.windows` with `.claude(id, window.identity)`. `Pace.fiveHourSeconds` stays as the 5-hour group's length.
- **Rationale**: Spec FR-007; one function replaces `fiveHourPace`, `sevenDayPace` and `pace(of: ModelLimit)`.

## R7: Threshold tracker

- **Decision**: For each Claude subscription account, the live keys are the plan windows of the latest status (`WindowKind(rawValue: identity.rawValue, displayName: window.name)`), so `fiveHour` and `sevenDay` keep today's raw values and existing state. Windows without a reset time are skipped (as today). A key not in the latest successful status is removed without a crossing; the tracker's existing removal of non-live keys does this once the live set comes from the status. When the account has no successful status (stale, preliminary), keep the previous keys alive so a failed fetch does not drop state.
- **Rationale**: Spec FR-008, edge case "failed fetch". Today the live set is the fixed pair, independent of the status.
- **Alternatives considered**: keep the fixed pair plus extras (would keep a dead `fiveHour` key forever).

## R8: Headline

- **Decision**: `HeadlineChoice` gets `case claude(ClaudeWindow)` in place of `claudeFiveHour`, `claudeSevenDay`, `claudeModel`; `stored` is the identity's raw value; `parse` accepts `fiveHour`, `sevenDay`, a non-empty `model:...` and a non-empty `limit:...` for a Claude account. `HeadlineWindow.claude(...)` resolves: chosen identity present in the status, else the default (FR-009: `sevenDay`, else longest with length, else first plan window in order), else no headline (percent nil, no tag). The tag rule moves to `tag(claude window: ClaudeLimit)`: "5h" for `fiveHour`, "7d" for `sevenDay`, else the display name cut to 7 plus "…" when longer than 8. A click on the default row stores nil; any other row stores its identity. Accessibility: "<name> window" for plan windows, "<model> weekly limit" for a model limit with identity `model:<name>`, "<name> limit" for further model limits.
- **Rationale**: Spec FR-009 to FR-011, FR-015. The at-or-above-100% rule uses the default window instead of the fixed 7-day window.
- **Alternatives considered**: keep the three cases and add one: every switch on `HeadlineChoice` would still name the fixed windows.

## R9: Last-good file

- **Decision**: `SavedClaudeValues` gets an optional `windows: [SavedClaudeLimit]` key (identity, kind, group, length seconds or nil, name, model name or nil, percent, reset, allowance). On write it fills `windows` and also the legacy `fiveHour`, `sevenDay` and `modelLimits` for the windows with those identities and the `model:<name>` limits; `version` stays 1. On read, `windows` wins when present; otherwise the legacy fields are converted (5-hour group window, weekly window, weekly model limits).
- **Rationale**: Spec FR-014 and clarification Q3; the old reader decodes the legacy keys with `decodeIfPresent` and ignores unknown keys, so a downgrade keeps working.
- **Alternatives considered**: version 2 (old reader drops the file); list only (old reader shows no Claude values after a downgrade).

## R10: Diagnostic log

- **Decision**: `SubscriptionSource` (or the coordinator) keeps, per account, the last logged window signature (the set of `kind/group/scope` strings; the line prints them in response order); on a successful fetch whose signature differs from the last one (first fetch included), it writes `[subscription] <account id>: windows <kind>/<group>/<scope>, ... (limits|fallback)`. Skipped entries (no kind and group, surface scope, duplicate identity) are listed with a `skipped` marker. The summary line becomes `ok(<name> <percent>%, ...)`.
- **Rationale**: Spec FR-012, clarification Q1. Strings from the answer that reach the log are kinds, groups and model display names only, the same class of data the last-good file already keeps.

## R11: Demo scenario format

- **Decision**: `ClaudeWindows` in `Scenario.swift` gets `limits: [ScenarioClaudeLimit]` (`kind`, `group`, optional `model`, `used`, `resetsIn`), replacing `fiveHour`, `sevenDay` and `models`. `ClaudeChange` gets `limits: [String: WindowChange]` keyed by identity (`sevenDay`, `model:Fable`). `DemoSources` builds the status through the same UsageCore builder as the endpoint client (no second parser). The validation paths become `claude.<id>.limits[<n>]`. `default.json`: `acc-max` gets `weekly_all` 70% and `weekly_scoped` Fable, headline `model:Fable`; `acc-max-personal` gets `weekly_all` only. `variants.json` gains an unknown-group window (`daily_all` / `daily`) so the dropdown shows a row without pace.
- **Rationale**: Spec FR-020. A list lets the scenario show both today's shape and a future one.
- **Alternatives considered**: keep `fiveHour` optional plus a list for extras (two formats in one file).

## R12: Settings and docs wording

- **Decision**: Threshold help: "each plan window (for example the 7-day window) is checked on its own"; plan description: "Shows the plan limits Anthropic reports (such as the 7-day window and model limits) and the tokens used through the plan." Docs and README name "the plan windows Anthropic reports (today the 7-day window and model limits such as Fable's)".
- **Rationale**: Spec FR-016; no wording that goes stale with the next plan change.
