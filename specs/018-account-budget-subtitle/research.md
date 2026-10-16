# Research: Account Budget Subtitle

## R1: Amount formatting (FR-003)

- **Decision**: `BudgetAmountFormatter.amount(_:locale:)` and `text(_:period:locale:)` (signatures in tasks.md Interfaces). `amount` rounds to cents with `NSDecimalRound(..., 2, .plain)` (Foundation formatting would round half to even), then formats with `.currency(code: "USD").locale(locale)` and `.precision(.fractionLength(0))` when the rounded value is whole, `.precision(.fractionLength(2))` otherwise; `text` appends " / month" or " / week". en_US: "$400 / month", "$99.50 / week".
- **Rationale**: `UsageFormat.budget` (app target) uses `fractionLength(0...2)` and shows "$99.5"; the spec requires "$99.50". The formatter lives in `UsageCore` so tests can pin `Locale(identifier: "en_US")` (spec Assumptions).
- **Alternatives considered**: moving `UsageFormat` into `UsageCore` (wider change, other callers' formats unchanged by this spec).

## R2: Description type (FR-001, FR-002, FR-007a, FR-008)

- **Decision**: `AccountBudgetDescription` as in tasks.md Interfaces: `Kind` carries `amount: Decimal` and `period`, so both the visible "$400 / month" and the spoken "$400 per month" (`BudgetAmountFormatter.amount` plus `BudgetPeriod.perUnit`) are built from it. The view gets `visiblePrefix`, `iconId`, `visibleSuffix` (group) or `visibleText` (otherwise), and `accessibilityText`; `make(for:in:locale:)` returns nil for subscription accounts (FR-006). A `GroupListSubtitle.text(group:memberCount:locale:)` helper gives the Groups row text (FR-004, SC-004).
- **Rationale**: the view only draws the icon glyph between prefix and suffix (`labelText(iconId, size: caption)` concatenated as `Text`), so the whole wording is tested in `UsageCore`. Reading the draft `Configuration` passed in keeps FR-005 automatic: the list re-renders from `draft` on every edit.
- **Alternatives considered**: an `AttributedString` with the glyph inside (UsageCore would need the icon font).

## R3: View changes (FR-005a, FR-007)

- **Decision**: in `AccountSettingsView`, replace `subtitle(_:)` by a small view builder: subscription accounts keep their `SubscriptionPlatform` name; token-based accounts render `Text(visiblePrefix) + labelText(iconId, size: NSFont.preferredFont(forTextStyle: .caption1).pointSize) + Text(" " + visibleSuffix)` (the caption size, so the glyph matches the text) with `.lineLimit(1)`, `.truncationMode(.tail)` and `.accessibilityLabel(accessibilityText)`. `GroupSettingsView` row text becomes `GroupListSubtitle.text(group:memberCount:)`.
- **Rationale**: `labelText` already returns `Text` with the icon font and the "?" fallback the picker also shows (FR-007, clarification Q3).
- **Alternatives considered**: `pickerText` (a `Label` with an `NSImage`, sized for menus, not for caption text).
