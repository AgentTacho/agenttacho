# Brainstorm: Colored Bar Levels

**Date:** 2026-10-16
**Status:** active

## Problem Framing

The menu bar marks an entry at its warning threshold with `⚠` and at 100% and above with `‼` (spec 001 FR-003). Both glyphs are small and sit in a monochrome bar, so a level is easy to miss at a glance, and they widen the bar and add clutter when several entries are shown. Color is the natural signal for "watch this" and "over the limit" and costs no width.

The bar is drawn today as one template image (`BarLabelBuilder.image`), which macOS tints monochrome for light, dark and tinted menu bars. That is why the glyphs carry the level: a template image cannot hold color. Colored levels therefore need the bar to be drawn as a full-color image that follows the menu bar's appearance itself.

Color alone fails for color-blind users and in grayscale, so the glyphs stay available as an option.

Seeded from the idea inbox entry `colored-bar-levels` (user idea, rated 4 stars on 2026-10-15).

## Approaches Considered

Display behavior was settled through questions (see Decision). The approaches below cover how the bar gets its color.

### A: Keep `MenuBarExtra`, draw a full-color image for the current appearance (chosen)

The bar becomes a non-template image. Neutral parts (icons, values at normal level, the `~` stale marker) are drawn in the menu bar's text color for the current appearance; level parts use the level color. The image is redrawn when the appearance changes.

- Pros: smallest change; the dropdown, its window workarounds and opening Settings stay as they are; text and pill styles use the same drawing path.
- Cons: neutral parts must match the system tint by hand (light, dark, wallpaper tinting, reduced transparency, increased contrast, inactive display, highlighted while open). A short spike should confirm this early.

### B: Replace `MenuBarExtra` with an `NSStatusItem` and a colored attributed title

- Pros: macOS handles appearance and highlighting for neutral text automatically.
- Cons: the dropdown has to be rehosted in a custom panel (positioning, outside-click and Esc dismissal, button highlight, focus); `@Environment(\.openSettings)` does not work outside a SwiftUI scene, which is a known pain on macOS 14 and later; the pill style still needs a drawn image, because attributed-string backgrounds are plain rectangles. Too large a refactor to ride along with a visual feature.

### C: Template image normally, full-color image only while a level is active

- Pros: the common case stays pixel-identical to today.
- Cons: two rendering paths that switch at runtime, more to test; the colored path still has the tint-matching problem of A.

## Decision

Approach A. If `MenuBarExtra` limitations keep accumulating, a move to `NSStatusItem` becomes its own brainstorm rather than part of this feature.

Display behavior:

- A "Level color" setting with three choices: **Text** (default), **Pill**, **Off**.
  - Text: only the entry's value is colored, orange at the warning threshold, red at 100% and above.
  - Pill: a rounded colored background behind the whole entry (icon and value), text on top in a readable contrasting color.
  - Off: no color, the bar looks as it does today without glyphs.
- A separate checkbox "Also show ⚠ / ‼ symbols", off by default. It combines freely with every color choice.
- Off with the checkbox unchecked is allowed: the bar then shows no level at all. Settings shows a short note that levels will not appear in the bar; notifications and the dropdown still show them.
- Existing configurations get the new defaults (colored text, symbols off) like new ones; a missing key means the default. The release notes mention the change.

## Key Requirements

- The bar shows the warning level and the over-limit level of each entry according to the "Level color" setting and the symbol checkbox; the level computation (`BarLevel`) does not change.
- Level colors are the system orange and red, matching the orange and red already used in the dropdown, and stay legible in light and dark menu bars.
- Parts without a level look like today in light, dark and tinted menu bars, including reduced transparency and increased contrast, and follow appearance changes without a restart.
- The `~` stale marker keeps its meaning and position in every style.
- The accessibility text of the bar always names the level (for example "warning", "over limit"), whatever the display setting, so VoiceOver users lose nothing when glyphs are off.
- The Settings bar preview (spec 008) shows the chosen style and updates as the setting changes.
- Both settings live in the configuration file with defaults when absent; older configuration files load unchanged.
- Notifications, thresholds and the dropdown are unchanged.
- Spec 001 FR-003 (glyphs carry the level) is superseded by the new setting and must be updated accordingly.
- Rendering decisions that can be tested (which segment gets which color, glyph on or off, accessibility text) live in `UsageCore` with tests; the AppKit drawing stays thin.

## Open Questions

- Settings tab and wording for the two controls ("Level color", "Also show ⚠ / ‼ symbols") and the note shown when levels are hidden from the bar
- Exact pill geometry (corner radius, padding, gap between adjacent pills) and the text color on orange and red pills in light and dark menu bars
- How neutral parts get the menu bar's text color in a non-template image (appearance observation, inactive-display dimming, highlighted state while the dropdown is open); to be confirmed by a spike
- Whether a stale entry at a level keeps full color or a dimmed color, given that stale values may be old
- Whether "Off" and the pill style also need increased-contrast variants (for example a stronger red)
- How the pace-forecast bar hint (brainstorm 10) sits next to colored values and pills
