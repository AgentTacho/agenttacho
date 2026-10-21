# Implementation Plan: Dropdown Theme

**Branch**: `032-dropdown-theme` | **Date**: 2026-10-21 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/032-dropdown-theme/spec.md`

## Summary

The dropdown gets a theme (`auto`, `dark`, `light`) stored as the optional configuration key `dropdownTheme`. A pure UsageCore type resolves the theme and the system appearance into a panel style, and a UsageCore palette gives each panel style its background, its band foreground and its four text colors (primary, secondary, warning, critical), each either "the system color as today" or a fixed sRGB value. The palette composes the band and hover backgrounds, and the tests assert with `PillContrast.contrastRatio` 4.5:1 for every text color against each of them, with the real system colors resolved under the matching appearance.

The app layer reads `NSApp.effectiveAppearance` for Auto, sets the panel window's appearance, background and SwiftUI color scheme from the panel style, and hands the palette to the dropdown's views through the environment, where the existing `.secondary`, `.orange` and `.red` text styles are replaced by palette lookups. Bar fills keep the system orange and red (FR-010). Settings > General > Display gets a segmented "Dropdown theme" picker.

The dark panel stays as it is, apart from one color: the dark red text (system red #FF4245) reaches only 3.16:1 on the footer band with Increase Contrast and 3.59:1 on a hover over a tinted band. Clarification Q3 and FR-008 allow changing it, so dark critical text becomes a fixed lighter red (#FF8A84, worst case 4.76:1). The red bar fills stay system red.

## Technical Context

**Language/Version**: Swift 6 (Swift Package, macOS app built through the Makefile)

**Primary Dependencies**: SwiftUI, AppKit; no new dependency

**Storage**: the existing JSON configuration file (`ConfigStore`); one new optional global key `dropdownTheme`, absent for Auto

**Testing**: Swift Testing via `make test` (UsageCore and DemoMode tests); `make test-release` for the scripts

**Target Platform**: macOS 14 or later, menu bar app (`MenuBarExtra` window, 360 pt wide, opaque panel)

**Project Type**: desktop app (UsageCore library, DemoMode library, AgentTacho SwiftUI app)

**Performance Goals**: an appearance or theme switch shows in the open dropdown within one second (SC-002); no other change

**Constraints**: constitution II (logic in UsageCore, test first, doc comments cite FRs), no em or en dash, dark panel unchanged except the critical text color (FR-008), demo scenario covers the shot states (constitution V)

**Scale/Scope**: 2 new UsageCore files, 1 UsageCore file changed, 1 new and 4 changed app files, 2 new and 2 extended test files, 2 docs, 2 earlier specs amended

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | How |
|---|---|---|
| I. Spec-driven development | Pass | spec 032 with clarifications and spec review; amendment notes to specs 025 and 028 (they say "always dark") |
| II. Test-first, logic in UsageCore | Pass | `DropdownTheme`, `PanelStyle`, `DropdownPalette` and the configuration key are UsageCore types with tests first; the views only map palette entries to `Color` and set the window appearance |
| III. Read-only, private by default | Pass | no new file access, credentials or network requests; README "Security and privacy" unchanged |
| IV. One build entry point | Pass | `make test`, `make test-release`, `make app-demo` only |
| V. Screenshots and website follow the UI | Pass | section below; one capture run, light shots of the dropdown change, coverage test checks the orange and red text the light shots rely on |

Post-design re-check: unchanged, no violations, no complexity tracking needed.

## Screenshots and website

| | |
|---|---|
| Shots that change | glance, budget, harnesses, same-provider: their light variants now show the light panel; their dark variants change only where red text shows (lighter red). menubar, prices and menubar-settings do not show the dropdown and should be unchanged; all 14 files are recaptured in one run anyway |
| New shots | none: a change to existing UI, no new landing page card. The General tab with the picker is not one of the seven stems |
| Demo scenario | `Resources/demo/default.json` unchanged: its configuration has no `dropdownTheme`, so the demo app runs with Auto and the capture's appearance switch decides the panel (FR-014). New coverage test in `Tests/DemoModeTests/DefaultScenarioTests.swift`: the default scenario shows orange text (`attentionRows` not empty) and red text (`thresholdCriticalRows` not empty), and its configuration decodes to `dropdownTheme == .auto` |
| Website copy | site checkout: search `src/` for "dark" next to dropdown or panel; `src/data/features.ts` and the comparison data are the likely places. If nothing calls the dropdown dark, no copy change. The social card is regenerated only if `menubar-dark` changed (it should not) |
| README image | unchanged (the README carries no dropdown image) |

## Design

### Theme and panel style (FR-001, FR-003, FR-006)

- New `Sources/UsageCore/Config/DropdownTheme.swift`:
  - `public enum DropdownTheme: String, Codable, CaseIterable, Sendable { case auto, dark, light }`.
  - `public func panelStyle(systemIsDark: Bool) -> PanelStyle`: auto follows `systemIsDark`, dark and light ignore it.
  - `public enum PanelStyle: Equatable, Sendable { case light, dark }` with `isDark`.
- `Configuration`:
  - stored `dropdownThemeValue: DropdownTheme?` with coding key `dropdownTheme` (`case dropdownThemeValue = "dropdownTheme"`), so the synthesized encoder writes nothing for nil (FR-003, research R2).
  - public computed `dropdownTheme: DropdownTheme { get { dropdownThemeValue ?? .auto } set { dropdownThemeValue = newValue == .auto ? nil : newValue } }`; init parameter `dropdownTheme: DropdownTheme = .auto`.
  - `decodeDropdownTheme(_:notes:)` like `decodeDisplayDirection`: missing → auto, no note; `"auto"` → auto (stored nil), no note; unknown, wrong-case, non-string or null → auto with note `dropdownTheme "<value>" is not known, using auto` or `dropdownTheme is not readable, using auto`.
  - `dataRelevant()` sets it to auto: presentation only, no refresh.

### Palette (FR-007 to FR-011)

- New `Sources/UsageCore/Dropdown/DropdownPalette.swift`:
  - `public enum DropdownTextRole: CaseIterable, Sendable { case primary, secondary, warning, critical }`.
  - `public enum DropdownTextColor: Equatable, Sendable { case system(DropdownTextRole), fixed(PillContrast.RGB) }`: `system` means the system color the dropdown draws today (label, secondary label, orange, red) resolved under the panel's appearance.
  - `public struct DropdownPalette: Equatable, Sendable` with `style`, `background: RGB`, `foreground: RGB` (the color the bands and hover fills are drawn from), `func text(_ role:) -> DropdownTextColor`, and the instance method `func backgrounds(increasedContrast: Bool) -> [Background]` (it needs the palette's own background and foreground), where the nested `DropdownPalette.Background` has `kind: Background.Kind` (`enum Kind: CaseIterable, Sendable { case plain, tinted, footer, hoverOnTinted }`) and `rgb: PillContrast.RGB`, the composited color (panel blended with `foreground` at `BandStyle.opacity`, then the 0.06 hover over the tinted band).
  - `public static func forStyle(_ style: PanelStyle) -> DropdownPalette`:
    - dark: background (0.12, 0.12, 0.13) as today, foreground white, primary/secondary/warning `.system`, critical `.fixed(#FF8A84)`.
    - light: background #D5D6D9, foreground black, primary `.system`, secondary `.fixed(#48484A)`, warning `.fixed(#7A2E00)`, critical `.fixed(#8A000A)`.
  - `public static let hoverOpacity = 0.06` moves here from the view so the test and the view share it (FR-011).
- Fixed colors are one value for both contrast settings, chosen to pass the increased-contrast backgrounds (research R3). With Increase Contrast, `.system` colors still adapt as the system does today.

### App layer (thin; FR-002, FR-004 to FR-006, FR-012)

- `DropdownView.swift`:
  - `@State private var systemIsDark` seeded from `NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua`, updated by `.onReceive(NSApp.publisher(for: \.effectiveAppearance))` (research R1).
  - `panelStyle = configuration.dropdownTheme.panelStyle(systemIsDark:)`, `palette = DropdownPalette.forStyle(panelStyle)`.
  - `.background(palette.background)`, `.environment(\.colorScheme, panelStyle.isDark ? .dark : .light)`, `.environment(\.dropdownColors, DropdownColors(palette))`.
  - The window: `window.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)` and `backgroundColor` from the palette, in `onChange(of: panel)` and in a new `onChange(of: panelStyle)`, so a switch reaches an open panel (FR-004, FR-006).
  - `panelBackground` constant is removed in favor of the palette. `bandFill` keeps `Color.primary.opacity(...)` (follows the color scheme, which matches the palette foreground); the 0.06 hover uses `DropdownPalette.hoverOpacity`.
  - Every text `.foregroundStyle(.secondary)`, `.orange`, `.red` in the dropdown becomes `colors.secondary`, `colors.warning`, `colors.critical`; `NoteStyle.color` and `PercentTone.color` take the `DropdownColors`.
- New `DropdownColors` (app side, new file `Sources/AgentTacho/DropdownColors.swift`): an `EnvironmentKey` value with `primary`, `secondary`, `warning`, `critical: AnyShapeStyle`, mapping `.system(.primary)` and `.system(.secondary)` to the hierarchical `.primary` and `.secondary` styles the views use today (so the dark panel draws exactly as before, FR-008), `.system(.warning)` to `Color.orange`, `.system(.critical)` to `Color.red`, and `.fixed(rgb)` to `Color(.sRGB, ...)`.
- `BreakdownView.swift`: its `.secondary` and `Color.orange` text uses `DropdownColors` the same way; `InfoHover`'s icon too.
- `UpdateViews.swift`: only `UpdateLine` (the dropdown footer's update line) changes its container `.foregroundStyle(.secondary)` to `DropdownColors`. `UpdateStatusText` and `UpdateButtons` are shared with `AboutSettingsTab` and stay unchanged (FR-005).
- `RowBarView.swift`: unchanged. Fills keep `Color.orange`/`Color.red` (FR-010); the track keeps `Color.secondary.opacity(0.25)`.
- `SettingsView.swift`: in `Section("Display")`, below "Show usage as", `Picker("Dropdown theme", selection: $draft.dropdownTheme)` with `Text("Auto")`, `Text("Dark")`, `Text("Light")` tags, `.pickerStyle(.segmented)`, and a caption "Auto follows the system appearance. Settings and the menu bar always do." Applied through the draft like the other General settings.
- Not touched: `BarLabel.swift` (menu bar item and the Settings preview capsule), `MenuBarSettingsTab.swift`, the Settings window appearance (FR-005).

### Docs and spec amendments

- `docs/configuration.md`: `dropdownTheme` key, values, default, fallback note.
- `docs/usage.md`: the dropdown follows the system, the theme picker.
- Amendment notes ("amended by spec 032", dated 2026-10-21) where specs 025 (Assumptions) and 028 (Terminology, Assumptions) say the panel is always dark.

## Project Structure

### Documentation (this feature)

```text
specs/032-dropdown-theme/
├── spec.md
├── plan.md              # this file
├── research.md          # Phase 0
├── data-model.md        # Phase 1
├── quickstart.md        # Phase 1
├── contracts/
│   └── dropdown-theme.md
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
Sources/UsageCore/
├── Config/
│   ├── DropdownTheme.swift          # new: DropdownTheme, PanelStyle (FR-001, FR-006)
│   └── Configuration.swift          # dropdownTheme key (FR-003)
└── Dropdown/
    └── DropdownPalette.swift        # new: palette, backgrounds, text roles (FR-007 to FR-011)

Sources/AgentTacho/
├── DropdownColors.swift             # new: palette to SwiftUI Color, environment key
├── DropdownView.swift               # panel style, window appearance, text colors
├── BreakdownView.swift              # text colors from DropdownColors
├── UpdateViews.swift                # UpdateLine text color from DropdownColors
└── SettingsView.swift               # Dropdown theme picker (FR-002)

Tests/UsageCoreTests/
├── DropdownThemeTests.swift         # new: theme to panel style resolution
├── ConfigurationTests.swift         # extended: dropdownTheme decoding, notes, round trip
└── DropdownPaletteTests.swift       # new: contrast against every background, real system colors

Tests/DemoModeTests/
└── DefaultScenarioTests.swift       # orange and red text shown, demo theme is auto (FR-014)

docs/configuration.md, docs/usage.md
specs/025-minimal-dropdown/spec.md, specs/028-section-bands/spec.md  # amendment notes
```

**Structure Decision**: the existing three-target layout. Theme resolution and the palette are pure UsageCore types so the contrast rules are testable; the SwiftUI layer only maps them to `Color` and `NSAppearance`.

## Complexity Tracking

None.
