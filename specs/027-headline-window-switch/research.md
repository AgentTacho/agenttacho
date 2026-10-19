# Research: Headline Window Switch

## R1: Where the choice lives in the configuration

- **Decision**: one optional account field `headlineWindow` (a string), held in `SubscriptionSettings` and `CodexSubscriptionSettings` and flattened into the account object by `Account`'s hand-written `Codable`, like `shownInBar` and `thresholds`. Absent means the default window; the encoder writes it only when set.
- **Rationale**: the choice belongs to one subscription account and must travel with the file (spec Assumptions). `Account` already decodes per-kind fields by hand, and `timeFormat` shows the pattern for a tolerant decode that records a `ConfigurationLoadNotes` entry instead of throwing (spec FR-010).
- **Alternatives considered**: a top-level map `accountId -> window` (rejected: survives account removal as garbage, and the Settings draft merge would need a second key path); `UserDefaults` like the view picker (rejected: the spec makes it a configuration value).

## R2: The string encoding

- **Decision**: Claude accounts: `"fiveHour"`, `"sevenDay"`, `"model:<model name>"`; Codex accounts: `"window:<spec 007 FR-009 name>"` (for example `"window:5-hour"`, `"window:weekly"`). A Codex name must match `N-hour`, `N-day` or `weekly`. Any other value, a value of the other account kind, an empty model name or a non-string is ignored (default window) and noted in the diagnostic log; the next save writes the value in effect (nothing).
- **Rationale**: the prefix makes the kind check of FR-010 a plain parse; the names are the ones the dropdown shows, so a hand edit is readable. Model names match exactly, including case (FR-006).
- **Alternatives considered**: a JSON object `{ "kind": ..., "name": ... }` (heavier for a hand edit, no gain); storing the default explicitly (rejected: clicking the default row clears the choice, FR-001).

## R3: Resolving the headline

- **Decision**: a new `UsageCore` type `HeadlineWindow` (`Sources/UsageCore/Bar/HeadlineWindow.swift`) with two static resolvers, one for a Claude status and one for a Codex entry, at the snapshot time. It returns the resolved window identity, whether it is the default, its rounded percent (nil when unavailable), its pace, its burn key (`BurnWindowKey`), the tag text and the accessibility name. `BarLayout.subscriptionItem` and `codexItem` and both dropdown headers use it; `SubscriptionStatus.barPercent` and `CodexLimitsEntry.barWindow` stay as the default window's accessors.
- **Rationale**: one place decides the bar value, the level, the markers and the header (FR-007, FR-013), so they can never disagree. The burn inputs already exist for every Claude window, model limit and Codex window (`UsageSnapshot.burnInputs(for:)`), and so do the paces (`fiveHourPace`, `pace(of:)`), so the markers need no new pace code.
- **Alternatives considered**: computing it in the views (rejected: constitution II); changing `barPercent` itself (rejected: it is also the default-window accessor used by the coverage and the level rule of FR-007).

## R4: The level rule

- **Decision**: Claude: critical when the headline or the 7-day window rounds to 100% or more; otherwise `BarLayout.level` of the headline percent with the account's thresholds. Codex: critical when any effective window reached its limit (unchanged); otherwise `BarLayout.level` of the headline percent. Without a headline percent the level is normal.
- **Rationale**: clarification of 2026-10-19 (FR-007); with the default window this is exactly today's rule.

## R5: The tag

- **Decision**: `"5h"` for Claude 5-hour; `"7d"` for Claude 7-day (never shown, it is the default); the model name for a model limit, cut to its first 7 characters plus "…" when longer than 8; Codex: `"Nh"` for `N-hour`, `"Nd"` for `N-day`, `"wk"` for `weekly`. `BarItem` gains `tag: String?` (nil for the default window and for every budget or member entry) and `windowName: String?` for the accessibility text. `BarPresentation` puts the tag after the icon in the icon's tone and adds the window name to the accessibility text; the app's `BarLabel` draws it.
- **Rationale**: FR-008, FR-009. Keeping the tag a separate field (not part of `value`) leaves the stale marker, glyph and value logic of spec 012 untouched.

## R6: Saving a click

- **Decision**: `Configuration.settingHeadline(_ choice: HeadlineChoice?, accountId:)` in `UsageCore` returns the new configuration (nil clears the choice; choosing the default window clears it too). The app's `AppModel.setHeadline(accountId:choice:)` saves it through `ConfigStore` with a log line "headline window of <id>: <value>" and no refresh. `Configuration.dataRelevant()` resets `headlineWindow`, so `needsRefresh` stays false (FR-011).
- **Rationale**: the existing `saveConfiguration` is written for the Settings window and logs "saved from settings"; a separate small entry point keeps the log honest and skips the timer and credential checks that do not apply.

## R7: Settings draft merge

- **Decision**: `Configuration.keepingHeadlineChoices(of current: Configuration)` copies each account's `headlineWindow` from `current` (by account id) into a candidate. The Settings window applies it to its candidate in `applyNow()` against `model.configuration`, and its `onChange(of: model.configuration)` patches `draft` and `applied` the same way when the draft has unapplied edits, and a pending `undoTarget`, so a dropdown click never shows up as a Settings edit or an extra undo step and a later Settings save keeps it (FR-010).
- **Rationale**: the Settings window applies edits 600 ms after typing from its own draft; without the merge a draft taken before the click would write the old choice back.

## R8: Row interaction in the dropdown

- **Decision**: `LimitRowLayout` gains a marker slot (12 pt, `●`, `○` on hover, empty otherwise), a `contentShape(Rectangle())` with `onTapGesture`, an `onHover` state that draws a rounded rectangle in `Color.primary.opacity(0.06)` (the system's subtle fill on the always-dark panel) behind the name line and the bar, and `accessibilityAction(named: "Show in menu bar")` plus `.isSelected` on the headline row, whose label comes from `RowText.window(isHeadline: true)` in `UsageCore`. The headline row shows no hover state. Tooltips stay (`.help` on name and reset text keep working under a tap gesture).
- **Rationale**: FR-002, FR-003 and the clarifications. A `Button` would restyle the row and swallow the inner tooltips; a tap gesture keeps the layout of spec 025.

## R9: Demo and coverage

- **Decision**: `Resources/demo/default.json` sets `"headlineWindow": "fiveHour"` on `acc-max`. The coverage report gains the bar entries' tags and each subscription's headline row; the default scenario test checks `acc-max` has tag "5h" and the headline row "5-hour" (`ResolvedHeadline.rowName`), and keeps its existing checks. If the 5-hour headline removes the only `↗`, `↑` or a level from the bar, the implementation tunes the demo values (for example the 5-hour window's used percent or reset) until the existing checks pass again (FR-015).
- **Rationale**: the menu bar shot then shows the feature; the coverage test proves it.
