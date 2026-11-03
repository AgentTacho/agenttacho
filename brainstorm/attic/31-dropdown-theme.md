# Brainstorm: Dropdown Theme

**Date:** 2026-10-21
**Status:** spec-created (specs/032-dropdown-theme)

## Problem Framing

The dropdown is always dark (`DropdownView.swift` forces `.colorScheme(.dark)` and `NSAppearance(named: .darkAqua)` on its panel). With the system in light appearance, the menu bar, Settings and every other app are light, and the dark dropdown looks out of place.

The dark panel came from spec 025: the translucent panel it replaced made the orange and red status lines unreadable over a light desktop. The fix that mattered was making the panel opaque; dark was a side choice. An opaque light panel keeps the fix.

Users who prefer the dark look, whatever the system does, should be able to keep it. So the dropdown gets a theme setting: Auto, Dark, Light.

## Approaches Considered

### A: Opaque light panel with adjusted warning colors (chosen)
- In light appearance the panel uses the system's light window background, still opaque. Dark appearance stays exactly as today.
- The section bands (spec 028) use `Color.primary` opacity and adapt without changes.
- Orange and red text switch to darker shades in light appearance so they reach 4.5:1 on the light panel (the contrast bar spec 012 set). Bar fills and other graphics keep the system colors (3:1 suffices for non-text).
- Pros: matches macOS expectations, keeps spec 025's readability fix, dark users see no change.
- Cons: light-only text colors are a small new palette to test; all light screenshots of the dropdown change.

### B: Native translucent material in light appearance
- Pros: looks like a system menu.
- Cons: reintroduces the readability problem spec 025 fixed. Ruled out.

### C: Opaque light panel, system colors unchanged
- Pros: least work.
- Cons: system orange on a light background is about 2.2:1, below the project's 4.5:1 text contrast bar.

### Scope alternatives
- Theme for the whole app (dropdown and Settings, via `NSApp.appearance`): rejected. A Settings window that ignores the system is unusual on macOS, and the Settings bar preview stays a dark capsule anyway (spec 008 FR-013).
- No setting, only follow the system: rejected. Users who like the dark dropdown would lose it.

## Decision

Approach A, with the theme setting scoped to the dropdown only.

- New picker "Theme" (or similar) with Auto, Dark, Light in Settings > General > Display, next to "Show usage as".
- Default Auto for everyone, new installs and upgrades alike. No migration: an upgrader in light appearance sees a light dropdown after the update and can pick Dark to get the old look back.
- Settings keeps following the system. The menu bar item keeps following the menu bar (the system decides its look). The Settings bar preview keeps its dark capsule.

## Key Requirements

- Auto: the dropdown follows the system appearance, including a switch while AgentTacho runs (and, ideally, while the dropdown is open).
- Dark: today's panel, unchanged, regardless of system appearance.
- Light: an opaque light panel regardless of system appearance.
- The panel is opaque in every theme.
- In the light panel, every text color (warning, error, secondary) reaches at least 4.5:1 against the panel background, with tests that resolve the real colors, as spec 012 did. Increase Contrast stays supported in both themes.
- The setting is stored in the configuration and absent when left at Auto.
- A change in Settings takes effect on the next opening of the dropdown at the latest.
- Screenshots and website (constitution V): the light-appearance shots of the dropdown now show a light panel. One capture run, review of every changed shot in both appearances, and a check whether site copy mentions a dark dropdown. The capture script runs the demo app with the default (Auto), so light and dark shots differ as intended. The Settings General shot (if captured) shows the new picker.

## Open Questions

- Picker label and placement: "Theme" vs "Dropdown appearance", and whether it sits under Display or a new section.
- Exact light shades for orange and red text, and whether secondary text needs adjusting.
- Whether the light panel uses `windowBackgroundColor` or a fixed color, and how the bands' tint reads on it (also open from #27).
- Does the change apply while the dropdown is open, or on the next opening (Settings uses a draft that is applied on save)?
- The demo scenario's coverage test: does it need a check that the light panel renders the warning and error lines?
- Whether the demo app should accept a theme override for captures, or Auto is enough.
