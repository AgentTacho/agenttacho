# Research: Dropdown Theme

## R1: Following the system appearance while a theme overrides it

**Decision**: Read the system appearance from `NSApp.effectiveAppearance` (`bestMatch(from: [.aqua, .darkAqua])`), observed with `NSApp.publisher(for: \.effectiveAppearance)`. Resolve the panel style in UsageCore and apply it three ways: the panel window's `appearance` (`.aqua` or `.darkAqua`), its `backgroundColor`, and `.environment(\.colorScheme, ...)` on the SwiftUI content.

**Rationale**: The app never sets `NSApp.appearance`, so its effective appearance is the system's and stays so when the dropdown window is forced to one appearance. Reading `@Environment(\.colorScheme)` instead would read the forced value back (circular for Dark and Light). Setting the window appearance keeps AppKit-drawn parts (scroll indicators, tooltips, focus rings) in step with the SwiftUI content, which is why spec 025 already set `.darkAqua` on the window. The KVO publisher fires on the system switch, so an open panel follows within one second (FR-006, SC-002).

**Alternatives considered**: `DistributedNotificationCenter` `AppleInterfaceThemeChangedNotification` (undocumented, fires before the effective appearance updates); setting `window.appearance = nil` for Auto (works, but then Light and Dark need a second code path, and reading the resolved style for the palette still needs the system value).

## R2: Omitting `dropdownTheme` from the configuration for Auto

**Decision**: Store `dropdownThemeValue: DropdownTheme?` under the coding key `dropdownTheme`, expose a non-optional computed `dropdownTheme`, and normalize Auto to nil in the setter. The synthesized `encode(to:)` uses `encodeIfPresent` for optionals, so Auto writes nothing (FR-003).

**Rationale**: `Configuration` has a custom decoder but a synthesized encoder; every other key is always written. A custom encoder for the whole struct would be a large change for one key. The computed property keeps the call sites (`$draft.dropdownTheme`) simple, and `Equatable` stays correct because Auto is always nil.

**Alternatives considered**: always write the key (violates FR-003 and the brainstorm's "absent when left at Auto"); a hand-written `encode(to:)` (larger change, more to keep in sync with `CodingKeys`).

## R3: Text colors that reach 4.5:1 on every background

**Decision**: Measure each text color against four composited backgrounds per panel and contrast setting: plain panel; tinted band (foreground at 0.04, 0.08 with Increase Contrast); footer band (0.07, 0.12); hover (0.06) over a tinted band. Chosen colors and their worst case (normal / increased contrast), from the WCAG 2 formula in `PillContrast`:

| Panel | Role | Color | Worst ratio |
|---|---|---|---|
| dark #1F1F21 | primary | system label (white 85%) | 9.39 / 8.37 |
| dark | secondary | system secondary label (white 55%) | 4.94 / 4.55 |
| dark | warning | system orange (#FF9230 on macOS 26) | 5.52 / 4.86 |
| dark | critical | fixed #FF8A84 (was system red #FF4245: 3.59 / 3.16) | 5.41 / 4.76 |
| light #D5D6D9 | primary | system label (black 85%) | 9.38 / 8.72 |
| light | secondary | fixed #48484A (system black 50% misses 4.5:1) | 5.08 / 4.65 |
| light | warning | fixed #7A2E00 (system #FF8D28 far below 4.5:1) | 5.27 / 4.83 |
| light | critical | fixed #8A000A (system #FF383C far below 4.5:1) | 5.60 / 5.14 |
| dark | link | fixed #6CB4FF (system link #419CFF: 4.36 / 3.83 on the footer band) | 5.64 / 4.96 |
| light | link | fixed #003E99 (system link #007AFF: 2.23 / 2.05) | 5.44 / 4.98 |

**Rationale**: The worst case is the footer band with Increase Contrast, where the red source error lines and the orange "stale" marker sit, or the hover over a tinted band. A fixed light value that passes the increased-contrast backgrounds also passes the normal ones, so one value per role is enough. The light hues stay orange and red (FR-009). The dark red is the only dark change: it already missed 4.5:1 on bands before this feature, and clarification Q3 lets FR-007 win.

**Alternatives considered**: the system's increased-contrast variants (#C93400, #D70015 light; #FF6961 dark) as fixed values: they miss 4.5:1 on the light bands (3.56, 3.63) and the dark footer (3.85). A white light panel: slightly better ratios, but harsher than the system's light surfaces and further from the dark panel's off-black.

**Tests**: The palette test composes the backgrounds with `BandStyle.opacity` and `DropdownPalette.hoverOpacity` and asserts the ratio for every `.fixed` color. For `.system` colors it resolves `NSColor.labelColor`, `secondaryLabelColor` and `systemOrange` under the panel's `NSAppearance` (alpha blended onto each background), as spec 012's `resolvedSystemFillsReachContrast` does. Increased-contrast system variants cannot be resolved without changing the system setting; the walkthrough covers them (as in spec 012).

**Band model**: the tests blend pure white (dark) or pure black (light) at the band factor, while the app draws bands with `Color.primary`, which carries some alpha (label color is about 85% opaque). The modeled bands are therefore slightly stronger than the drawn ones, which makes the FR-007 text checks conservative; FR-011's "light no stronger than dark" holds for both models because the same share applies to both panels.

## R4: Bands, hover and selection on the light panel

**Decision**: Keep `Color.primary.opacity(BandStyle.opacity(...))` for bands and `Color.primary.opacity(0.06)` for the hover, unchanged. Under the light color scheme `Color.primary` is black-ish, so the same factors darken the light panel by the same share as they lighten the dark one.

**Rationale**: FR-011 asks for the same factors on the light foreground. With the measured backgrounds, a tinted band on the light panel has a contrast ratio of about 1.09 to the plain panel (dark: 1.12), the footer 1.16 (dark 1.23), and with Increase Contrast 1.19 and 1.30 (dark 1.27 and 1.45): visible, and no stronger than on the dark panel. The test asserts ratio > 1.0 and light ≤ dark for each band style and contrast setting.

**Alternatives considered**: separate light factors (more numbers to tune and test, no gain over FR-011).

## R5: Bar fills and track

**Decision**: Keep `Color.orange`/`Color.red` fills and the `Color.secondary.opacity(0.25)` track in `RowBarView` unchanged in both panels (FR-010).

**Rationale**: Clarification: the percentage text and the note carry the same information, so the fills are exempt from a non-text target, and they keep matching the menu bar's levels. The track is a graphic, not governed by FR-007.

## R6: Demo build and screenshots

**Decision**: No scenario change and no capture script change. The demo configuration has no `dropdownTheme`, so Auto applies and the capture's system appearance switch decides the panel. The default scenario already has orange rows (`attentionRows`, the Claude Max 7-day pace note) and threshold-driven red (`thresholdCriticalRows`, the Side project budget); a coverage test pins both so the light shots keep showing them.

**Rationale**: FR-014; the capture already runs once per appearance.

**Revision 2026-10-21 (walkthrough)**: the first light background, #F5F5F7, looked whiter than the system's light menus, which sampled at about #BEC0C3 to #C6C8CB over a dark desktop (their material is translucent). The maintainer chose #D5D6D9. The darker panel needed darker text: secondary #545458 to #48484A, warning #9A3A00 to #7A2E00, critical #B0000E to #8A000A; the table above shows the new worst cases.
