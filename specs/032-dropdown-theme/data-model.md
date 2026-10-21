# Data Model: Dropdown Theme

## DropdownTheme (UsageCore, Config)

The user's choice for the dropdown's look (spec FR-001).

| Value | Meaning |
|---|---|
| `auto` | follow the system appearance (default, not stored) |
| `dark` | always the dark panel |
| `light` | always the light panel |

- Raw values are the configuration strings, lowercase.
- `panelStyle(systemIsDark:) -> PanelStyle`: `auto` maps `true` to `.dark` and `false` to `.light`; `dark` and `light` ignore the argument.

## PanelStyle (UsageCore, Config)

What a theme resolves to at a moment: `light` or `dark`, with `isDark`.

## Configuration key `dropdownTheme`

| Stored JSON | `dropdownTheme` | Load note |
|---|---|---|
| key missing | `auto` | none |
| `"auto"` | `auto` | none |
| `"dark"` / `"light"` | `dark` / `light` | none |
| `"Dark"`, `"sepia"` (any other string) | `auto` | `dropdownTheme "<value>" is not known, using auto` |
| `null`, number, bool, object | `auto` | `dropdownTheme is not readable, using auto` |

- Saving: `auto` writes no key; `dark` and `light` write their raw value.
- Never makes the configuration invalid. Presentation only: `dataRelevant()` resets it, so a change starts no refresh.

## DropdownPalette (UsageCore, Dropdown)

The colors of one panel style (FR-007 to FR-011).

| Field | Dark | Light |
|---|---|---|
| `background` | sRGB (0.12, 0.12, 0.13) | #D5D6D9 |
| `foreground` (bands, hover) | white | black |
| `text(.primary)` | `.system(.primary)` | `.system(.primary)` |
| `text(.secondary)` | `.system(.secondary)` | `.fixed(#48484A)` |
| `text(.warning)` | `.system(.warning)` | `.fixed(#7A2E00)` |
| `text(.critical)` | `.fixed(#FF8A84)` | `.fixed(#8A000A)` |
| `text(.link)` | `.fixed(#6CB4FF)` | `.fixed(#003E99)` |

- `DropdownTextColor.system(role)`: the system color the dropdown used before (label, secondary label, orange, red), resolved under the panel's appearance, adapting to Increase Contrast.
- `DropdownTextColor.fixed(rgb)`: an sRGB value, the same with and without Increase Contrast.
- `hoverOpacity = 0.06`.
- `backgrounds(increasedContrast:) -> [Background]`: `plain` (the panel), `tinted`, `footer` (panel blended with `foreground` at `BandStyle.opacity`), `hoverOnTinted` (the tinted band blended with `foreground` at `hoverOpacity`). Blend: `panel * (1 - a) + foreground * a` per sRGB component, the same as SwiftUI drawing an opaque color at opacity `a` over an opaque background.

## Invariants (tested)

- Every `.fixed` text color reaches 4.5:1 against every background of its palette, for both contrast settings (FR-007).
- Every `.system` text color, resolved under the palette's appearance and alpha-blended onto each background, reaches 4.5:1 with the normal contrast setting (FR-007, FR-013).
- For each band style and contrast setting, the band differs from the plain panel (ratio > 1.0) and the light band's ratio is at most the dark band's (FR-011).
- The dark palette's background and the dark `.system` roles equal what the dropdown drew before (FR-008).
