# Research: Colored Bar Levels

## R1: How the bar gets colors that follow the menu bar's appearance

**Decision**: Draw the colored bar as a non-template `NSImage` built with `NSImage(size:flipped:drawingHandler:)` whose handler uses the dynamic system colors `NSColor.labelColor`, `NSColor.systemOrange` and `NSColor.systemRed`. A drawing handler runs at draw time with `NSAppearance.currentDrawing()` set to the appearance of the view that draws it (the status bar button), so the dynamic colors resolve for the menu bar's actual appearance, including wallpaper tinting, "Increase contrast" and the highlighted state. The image's `cacheMode` is set to `.never` so a cached bitmap from another appearance is never reused. `BarLabelView` reads `@Environment(\.colorScheme)` and passes it into the image identity, so SwiftUI rebuilds the label when the appearance changes (FR-014).

**Fallback inside the same design**: if the walkthrough shows that `MenuBarExtra` rasterizes the label image once (so the handler does not run again for the button's appearance), the handler resolves the colors explicitly under an `NSAppearance` derived from the label's `colorScheme` (`.darkAqua` or `.aqua`, with the accessibility high-contrast variants when `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast` is set) via `performAsCurrentDrawingAppearance`. This is the same code path with an explicit appearance argument, already needed for the Settings preview (R5).

**Open risks checked by spike and walkthrough**: the menu bar's appearance follows the wallpaper and can differ from the system `colorScheme`, which weakens the fallback; with two displays one label image may be shown on menu bars of different appearance. Task T010 runs a spike before the renderer is written and records the result here; quickstart steps 3 to 5 cover the cases the spike cannot change automatically.

**Spike result** (T010, decided without launching the app): another AgentMeter build from a parallel session was running on the development machine, and a second instance would have raised the single-instance alert, so the built app was not started during implementation. Decision: the R1 primary path. The bar passes no explicit appearance; the dynamic colors resolve under the current drawing appearance when the drawing handler runs. Reason: if `MenuBarExtra` draws the image through the status button, the colors follow the menu bar exactly; if it rasterizes the image once, the current drawing appearance at that moment is the app's effective appearance, which is what the fallback would derive from `colorScheme` anyway, and the `.id` on `colorScheme` and `colorSchemeContrast` in `BarLabelView` forces a rebuild when either changes. The runtime checks (the appearance the handler sees, a wallpaper-dependent menu bar, two displays, the highlighted state) move to the walkthrough, quickstart steps 3 to 5. If they fail there, switching to the explicit appearance is a one-line change in `BarLabelView` (pass an appearance derived from the two environment values to `BarLabelBuilder.image`).

**Rationale**: Keeps `MenuBarExtra` (brainstorm decision A) and the single renderer; dynamic system colors give the exact hues the dropdown uses (FR-011) and their increased-contrast variants for free.

**Alternatives considered**: `NSStatusItem` with an attributed title (rejected in the brainstorm: dropdown rehosting, `openSettings` outside a scene, pill still needs an image); reading the status button's `effectiveAppearance` by walking `NSApp.windows` (fragile private layout, not needed if R1 works).

## R2: Bars without a level color stay a template image

**Decision**: When no part of the bar carries a level color (no entry at a level, or "Level color" Off), the bar is drawn exactly as today: one template image in black that macOS tints (spec FR-013 MAY clause). Only when at least one part is colored is the full-color image of R1 used. Both are produced by one function with a `colored` flag; the layout code (fonts, spacing, glyph and stale marker placement) is shared.

**Rationale**: Guarantees SC-002 (no visible change for the common case) in every condition the system handles for template images, including inactive secondary displays, which a full-color image cannot imitate exactly. The remaining differences while a level is shown are accepted and documented: no inactive-display dimming, and `labelColor` neutrals that may differ slightly from template tinting in alpha and vibrancy (to be measured in the T010 spike and the walkthrough).

**Alternatives considered**: Always full color (risks SC-002 on inactive displays and tinted bars); two separate renderers (more code, layout drift).

## R3: Pill text color

**Decision**: Text and icon on a pill are black or white, whichever has the higher WCAG 2 contrast ratio against the pill fill as resolved at draw time. The luminance and contrast math and the black or white choice live in `UsageCore` (`PillContrast`), so they are tested with the resolved sRGB values of `systemOrange` and `systemRed` in the four conditions light, dark, light with increased contrast, dark with increased contrast. Approximate values for the tests:

| Condition | Orange | Red | Expected text |
|---|---|---|---|
| Light | #FF9500 | #FF3B30 | black, black |
| Dark | #FF9F0A | #FF453A | black, black |
| Light, increased contrast | #C93400 | #D70015 | white, white |
| Dark, increased contrast | #FFB340 | #FF6961 | black, black |

All chosen combinations reach at least 4.5:1 (SC-004); the tests assert the ratio, not only the choice. These values predate macOS 26, which resolves light orange and red to #FF8D28 and #FF383C and dark to #FF9230 and #FF4245; a test also resolves the real system colors under the light and dark appearance (review fix).

**Rationale**: A fixed white fails on normal orange (about 2.2:1); a fixed black fails on increased-contrast light colors (about 4:1). Choosing per resolved color is simple and testable.

**Alternatives considered**: Darkening the pill fill to fit white text (changes the hue away from FR-011); per-condition hard-coded colors (breaks when Apple adjusts the palette).

## R4: Where the two settings live in the configuration file

**Decision**: Two top-level keys in `config.json`: `levelColor` (`"text"`, `"pill"` or `"off"`) and `showLevelSymbols` (boolean). Missing keys decode to `text` and `false`. An unknown `levelColor` string decodes to `text` and adds a note to a load-notes collector passed through `JSONDecoder.userInfo`; `ConfigStore` keeps the notes of its most recent file read and hands them out once through `takeLoadNotes()`. `RefreshCoordinator`, which loads the configuration and owns the diagnostic log, writes each note with source `config`. The keys are written on every save (synthesized encoding), which also replaces an unknown value with `text` (clarification 3).

**Rationale**: Matches existing top-level settings (`startAtLogin`, `refreshIntervalSeconds`); the userInfo collector keeps `Configuration` free of transient fields that would leak into `Equatable` and the Settings draft comparisons.

**Alternatives considered**: Nested `bar` object (no other bar setting exists yet; spec 008 arrangement is already top level); a transient field on `Configuration` (pollutes equality and the dirty check); failing validation on unknown values (violates FR-003).

The two settings are presentation only: `dataRelevant()` resets them, so a change never triggers a refresh (FR-004), like `arrangement`.

## R5: Settings preview colors

**Decision**: The preview keeps its fixed dark capsule (spec 008 FR-013) and renders the image with an explicit `NSAppearance(named: .darkAqua)` (high-contrast variant when increase contrast is on; NSAppearance.h allows `NSAppearance(named:)` to return nil for the accessibility names, so plain `.darkAqua` is the fallback; review fix): neutral parts white, dark-appearance orange and red, pill text by R3. Neutral parts use pure white (a `neutralOverride`) rather than `labelColor`, which is white at about 85% alpha in dark appearance, so they do not dim when a level appears. The appearance follows `@Environment(\.colorSchemeContrast)`, so toggling "Increase contrast" updates the preview live. The `tint` parameter of `BarLabelView` is replaced by a `preview` flag; for the template case the preview still draws the template in white as today.

**Rationale**: The capsule is always dark, so dark-appearance colors are the only ones that match it (spec FR-005).

## R6: Accessibility and plain text

**Decision**: `BarPresentation.accessibilityText` produces `"<name> <level word> <stale marker><value>"`, joined by two spaces, with level words "warning" and "over limit" and no glyphs (FR-018, clarification 2). The app-side `BarItem.text` and `valueText` extensions are removed; the placeholder "AgentMeter" stays the plain text of an empty bar.

## R7: Release notes

**Decision**: Release notes are generated from Conventional Commit subjects (`scripts/release/lib.sh`, `ReleaseChanges`). The feature's squash commit uses a `feat(bar):` subject that names the change of defaults, for example "feat(bar): show levels in color, symbols now optional". No separate changelog file exists.
