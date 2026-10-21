# Data Model: Colored Bar Levels

All types below live in `Sources/UsageCore` unless noted.

## LevelColorStyle (enum, Codable)

| Case | Raw value | Meaning |
|---|---|---|
| `text` | `"text"` | Default. The value (and glyph) of an entry at a level is drawn in the level color. |
| `pill` | `"pill"` | An entry at a level is drawn on a rounded background in the level color. |
| `off` | `"off"` | No color. |

Decoding an unknown raw value, a wrong-case value or a non-string value yields `text` plus a load note (research R4). A non-boolean `showLevelSymbols` is a decoding error, like `startAtLogin`. Load notes are kept only when the whole file decodes and validates.

## Configuration (existing, two new fields)

| Field | JSON key | Type | Default when absent | Notes |
|---|---|---|---|---|
| `levelColor` | `levelColor` | `LevelColorStyle` | `.text` | FR-001, FR-003 |
| `showLevelSymbols` | `showLevelSymbols` | `Bool` | `false` | FR-002 |

- Computed `levelDisplay: LevelDisplaySettings` bundles both.
- Both are excluded from `dataRelevant()` (presentation only, no refresh).
- No validation rule: every value is valid (FR-012: Off with symbols off is allowed).

## LevelDisplaySettings (struct, Equatable, Sendable)

| Field | Type |
|---|---|
| `levelColor` | `LevelColorStyle` |
| `showSymbols` | `Bool` |

- `static let default = LevelDisplaySettings(levelColor: .text, showSymbols: false)`

## BarLevel (existing, unchanged)

`normal`, `warning`, `critical` (critical is the spec's over-limit level, including Codex reached limits).

## BarTone (enum)

`neutral`, `warning`, `overLimit`, `onPill(BarLevel)`: the color role of a drawn part. `onPill` parts use the pill text color chosen by `PillContrast` for the pill of that level.

## BarEntryPresentation (struct, Equatable)

Derived from one `BarItem` and `LevelDisplaySettings`; no AppKit types.

| Field | Type | Rule |
|---|---|---|
| `id` | `String` | `BarItem.id` |
| `icon` | `String` | `BarItem.icon` |
| `glyph` | `String?` | `"⚠"` for warning, `"‼"` for over limit, only when `showSymbols`; nil otherwise |
| `valueText` | `String` | `"~"` prefix when stale, then `BarItem.value` |
| `iconTone` | `BarTone` | `.onPill(level)` in pill style at a level, otherwise `.neutral` |
| `textTone` | `BarTone` | tone of glyph, stale marker and value: level tone in text style, `.onPill(level)` in pill style, `.neutral` when off or no level |
| `pill` | `BarLevel?` | the level when style is pill and the entry is at a level, else nil |
| `accessibilityText` | `String` | `"<name> [warning \| over limit] <valueText>"` |

## BarPresentation (enum, pure functions)

- `entries(_ items: [BarItem], settings: LevelDisplaySettings) -> [BarEntryPresentation]`
- `usesColor(_ entries: [BarEntryPresentation]) -> Bool`: true when any tone is not `.neutral` (template image otherwise, research R2)
- `accessibilityText(_ entries: [BarEntryPresentation]) -> String`: joined with two spaces; `"AgentTacho"` when empty

## PillContrast (enum, pure functions)

- `PillContrast.RGB` (nested struct, public memberwise init; sRGB components 0...1)
- `relativeLuminance(_:) -> Double` (WCAG 2)
- `contrastRatio(_:_:) -> Double`
- `textColor(onFill:) -> PillTextColor` (`.black` or `.white`, the higher ratio)

## ConfigurationLoadNotes (final class, internal to the decoding path)

Collects human-readable notes while decoding (for example `levelColor "rainbow" is not known, using text`). Passed via `JSONDecoder.userInfo`; `ConfigStore.takeLoadNotes() -> [String]` returns and clears the notes of the most recent file read.
