# Research: Accounts without a Limit

All decisions refer to the code on `main` at the time of planning (spec 039 merged). Line numbers are hints, not contracts.

## R1: Membership model

- **Decision**: add `case noLimit(NoLimitSettings)` to `TokenMembership` (`Config/Configuration.swift`), with `NoLimitSettings { period: BudgetPeriod }`. Add `valueAs: String?` to `TokenBasedSettings` (account level, beside the membership), with an accessor `noLimit: NoLimitSettings?` like `ownBudget`.
- **Rationale**: a third membership case makes "exactly one of" (FR-001) a property of the type, and every exhaustive `switch` on the membership (encode, `validate`, `dataRelevant`, `AccountBudgetDescription`) is found by the compiler. `valueAs` sits outside the membership because FR-003 and FR-018 keep it across switches, the same way `Account.timeFormat` survives a stay in a group.
- **Alternatives considered**: a `BudgetSettings` with an optional amount (rejected: every budget consumer would need to handle "no amount", and thresholds and shown-in-bar would have to be forbidden by validation instead of by type); `valueAs` inside `noLimit` (rejected: lost on a switch, contradicting FR-018).

## R2: Configuration keys and validation

- **Decision**: flat account keys as today. `"noLimit": {"period": "weekly" | "monthly"}` (absent `period` means weekly) and `"valueAs": "<model id>"`. Decoding in `Account.init(from:)` counts the present keys among `groupId`, `budget` and `noLimit`: exactly one, else the existing "set exactly one" errors, reworded to name all three. `NoLimitSettings` decoding rejects the keys `budgetUSD`, `thresholds` and `shownInBar` inside `noLimit` with a "No limit has no amount, thresholds or menu bar setting" error (FR-002). An account-level `shownInBar` together with `noLimit` is rejected too (it belongs to group members). `valueAs` is decoded for every token-based account and never validated against the price table (FR-003). Encoding writes `noLimit` with `period`, and `valueAs` with `encodeIfPresent`.
- **Rationale**: matches how `budget`, `condition` and `headlineWindow` are stored; a hand-edited file gets the same kind of message as today (spec 001 FR-033, `ConfigStore.loadLocked`).
- **Alternatives considered**: a `"budget": {"kind": "noLimit"}` discriminator (rejected: breaks the existing `budget` decoding and every hand-edited file's mental model).

## R3: Counting window and snapshot entry

- **Decision**: `Aggregator.aggregate` resolves a No limit account's period from `settings.noLimit?.period` (today's fallback `budgetOwner(forAccount:)?.budget.period ?? .weekly` would make it weekly), uses `groupWindow(period)` for its records, and writes `NoLimitEntry` into a new `UsageSnapshot.noLimitAccounts: [String: NoLimitEntry]`. `NoLimitEntry` holds `period`, `window`, `resetAt`, `breakdown` (tokens only, `priced: false`, per-model `ModelUsage` with 5-minute and 1-hour cache writes apart), `totalTokens` and `stale`. `tokenAccounts` keeps its entry as today (the Harnesses tab and other per-account consumers are unchanged). `WindowResolver.collectionWindow` widens to the month when a monthly No limit account exists, as it does for a monthly budget owner. `RefreshCoordinator` carries `noLimitAccounts` over on a failed refresh like `accountBudgets`, and its per-owner log line gets a "no limit" variant with the token total.
- **Rationale**: a separate map keeps `accountBudgets`, and with it `paceKeys`, `BurnRate.budgetEntry`, `ThresholdTracker` (over `budgetOwners`) and `BarLayout` free of No limit accounts by construction (FR-009). `priced: false` means `unpricedModels` and `incomplete` are never set for the section (FR-008).
- **Alternatives considered**: a `GroupEntry` with `budgetUSD == 0` (rejected: percent, pace and thresholds would all need guards); reading `tokenAccounts` in the dropdown (rejected: it is weekly only and has no reset time).

## R4: Value computation

- **Decision**: a pure function in `Pricing/ReferenceValue.swift`: `ReferenceValue.make(breakdown: [ModelUsage], valueAs: String?, prices: PriceTable) -> ReferenceValue` with cases `.none` (no Value as model), `.missing(model: String)` (no price found) and `.value(Decimal, model: String)`. The price is looked up with `PriceTable.price(for:)` (same normalization and prefix fallback as records, FR-003), and each model's tokens are priced with the static `PriceTable.cost(input:output:cacheWrite5m:cacheWrite1h:cacheRead:price:)`, then summed. It is called at presentation time by `NoLimitPresentation` with the effective price table the app already builds for the Prices tab (`AppModel.effectivePrices(overrides: configuration.priceOverrides)`); `ScenarioCoverage` builds the same table from the scenario's prices.
- **Rationale**: summing per model over the breakdown equals summing per record (cost is linear in tokens), so FR-007's "as if each record had named the Value as model" holds and SC-003 is testable to the cent. Computing at presentation time needs no price state in `RefreshCoordinator` and follows an override or import change immediately (story 2, scenario 4).
- **Alternatives considered**: computing in the record sources (rejected: they price each record by its own model and would need the account's settings); passing the price table into `Aggregator` (rejected: a change of prices would wait for the next refresh, and the aggregator stays price-free today).

## R5: Switching between budget choices

- **Decision**: new `Configuration.movingAccountToNoLimit(_ accountId:)`: from an own budget takes its `period`; from a group takes the group's `period`, removes the account from the group's members and keeps the group, also when it is left without members (spec 009 FR-002; `reconcilingArrangement` places the account); keeps `valueAs` and `timeFormat`. `movingAccountToOwnBudget` is widened to accept a No limit account: prefilled `BudgetSettings(period: noLimit.period, budgetUSD: 0, shownInBar: true, thresholds: [80, 100])`; `validateForSaving()` already refuses an amount of 0 or less with the period-naming message (spec 003 FR-019), which is FR-018's "must be entered". `movingAccountToGroup` accepts a No limit account like an own-budget one. The arrangement follows spec 008 FR-006 through the same helpers that handle group exits today. Threshold state: `ThresholdTracker` keys its state by budget owner and fingerprint; an owner that disappears loses its state, and a new owner starts with a baseline (spec 004 FR-015); tests pin both directions (FR-019).
- **Rationale**: reuses the existing transitions and their arrangement and group-cleanup handling; the empty amount is enforced by the validator that already guards every save.
- **Alternatives considered**: a separate "amount required" state in the draft (rejected: duplicate validation).

## R6: Arrangement and Menu Bar tab

- **Decision**: `Arrangement.isEntry` returns true for `.noLimit` (else the account has no dropdown section), `isShownInBar` returns false and `settingShownInBar` is a no-op for it. `ArrangementEditor.rows` keeps listing it; `MenuBarSettingsTab.info(for:)` gets the caption "No limit", and the row hides its "Show in bar" checkbox. A new No limit account is placed at the end (spec 008 FR-005).
- **Rationale**: FR-010; one place decides whether an entry can be in the bar.
- **Alternatives considered**: leaving No limit accounts out of the arrangement and adding their sections separately (rejected: order would not be user-controlled).

## R7: Dropdown texts and formatting

- **Decision**: `Dropdown/NoLimitPresentation.swift` builds, from `NoLimitEntry`, `ReferenceValue`, the time format and a locale: `headline` (compact tokens, for example "48.2M", "0"), `periodLine` ("tokens this week" / "tokens this month"), `resetText` (via `TimeText.reset`), `valueLine` ("≈ $412 at claude-opus-5-5 prices", "≈ <$1 at ... prices"), `valueTooltip`, `notes` (stale and no-data notes as for an own budget, plus `SectionNote.valueAsMissing(model:)` neutral) and `accessibilityLabel`. A core `CompactFormat.tokens(_:locale:)` moves the formatting of `UsageFormat.tokens` into UsageCore (same `compactName` notation, 0 to 1 fraction digits); `UsageFormat.tokens` calls it. Whole-dollar amounts use the locale currency format with zero fraction digits, rounded half up (`Decimal` rounding, plain mode, unlike the banker's rounding of `CompactFormat.usd`); exactly 0 shows "≈ $0", above 0 and below 1 "≈ <$1".
- **Rationale**: FR-011 to FR-015a; texts are testable without SwiftUI, and the headline uses the same token format as other sections.
- **Alternatives considered**: formatting in the view (rejected by constitution II and FR-015a).

## R8: Value as pop-up entries

- **Decision**: `Pricing/ValueAsOptions.swift` (first in `Dropdown/`, moved after the code review): `ValueAsOptions.make(prices: PriceTable, selected: String?) -> ValueAsOptions` with `primary` (entries whose effective source is built-in or override, sorted by model id), `more` (imported provider and CSV entries, sorted by model id) `unlisted` (the selected id when it is priced only through normalization or prefix fallback, for example `claude-opus-5-5@default`; shown selected as stored, never rewritten) and `missing` (the selected id when `prices.price(for:)` finds nothing, shown selected with the suffix " (no price)"). "None" is the view's first item and maps to `nil`. Control: a `Menu` labeled with the current choice, holding "None", the `primary` ids, a nested `Menu("More")` with the `more` ids, and the `unlisted` or `missing` entry, each as a button with a checkmark on the selected one; a plain `Picker` cannot hold a selectable submenu on macOS 14.
- **Rationale**: FR-017 and clarification 2; the effective table already resolves each model to one source (`PriceEntry.source`).
- **Alternatives considered**: a searchable sheet (rejected: heavier than a macOS pop-up, and HIG prefers the standard control).

## R9: Settings layout

- **Decision**: `TokenBasedEditor`'s budget picker gets "No limit" after "Own budget" and before the groups (tag `"\u{0}no-limit"`); `NoLimitFields` shows `PeriodPicker`, the "Value as" pop-up and `TimeFormatPicker`. `NewAccountSheet` offers "No limit" after "Own budget", with the period picker and no amount. Subtitle: `AccountBudgetDescription.Kind.noLimit(period:)` renders "<session kind> · no limit / week" or "/ month", VoiceOver "<session kind>, no limit, per week" (FR-020).
- **Rationale**: standard macOS pop-up controls (AGENTS.md: HIG first); mirrors the own-budget layout so the editor changes shape only where the choice differs.
- **Alternatives considered**: a segmented control for the three choices (rejected: groups are a list of names, which a pop-up already holds).

## R10: Tests

- **Decision**: Swift Testing suites, written first:
  - `NoLimitConfigurationTests`: decode/encode round trip, exactly-one errors for every pair and none, forbidden keys inside `noLimit`, `shownInBar` with `noLimit`, `valueAs` kept on own-budget and group accounts, absent period means weekly.
  - `NoLimitTransitionTests`: all six switch paths (SC-004), emptied group kept, `valueAs` and `timeFormat` kept, amount 0 refused by `validateForSaving()`.
  - `NoLimitAggregationTests`: monthly window, collection window widening, totals of all token kinds, no `accountBudgets` entry, no `incomplete`, stale propagation.
  - `ReferenceValueTests`: hand-computed value with 5-minute and 1-hour cache writes (SC-003), missing model, normalization (`@suffix`, dated id), `.none`.
  - `NoLimitPresentationTests`: headline, period line, value line rounding (`≈ <$1`, half up), tooltip wording without "spent"/"of", notes, accessibility label, en_US locale.
  - `ValueAsOptionsTests`, `AccountBudgetDescriptionTests` (No limit cases), `ArrangementTests` (isEntry, never shown in bar), `BarLayoutTests` and `ThresholdTrackerTests` (no entry, no notification, baseline after a switch to a budget).
  - `DefaultScenarioTests` extensions (plan "Screenshots and website").
- **Rationale**: every FR maps to a core test; the SwiftUI layer only renders tested values.
