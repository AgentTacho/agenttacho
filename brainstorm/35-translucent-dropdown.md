# Brainstorm: Translucent Dropdown

**Date:** 2026-10-23
**Status:** parked (spec 036 on branch `036-translucent-dropdown`, waits for brainstorm 36, the dropdown in a real NSMenu)

Seeded from the idea inbox entry `translucent-dropdown-panel` (walkthrough of spec 032, 2026-10-21).

## Problem Framing

The dropdown panel is opaque in both themes (spec 032 FR-007). The system's own menus and menu bar extras use a translucent material, so the dropdown is the one surface near the menu bar that does not let the desktop through, and it reads as a foreign window rather than a system menu. The spec 032 walkthrough noted it when comparing the light panel against the system's menus.

Opacity is deliberate: spec 025 made the panel opaque because the fully translucent panel before it left the orange and red status lines unreadable over a light desktop, and brainstorm 31 ruled the native material out again for the same reason. Any translucency has to keep that fix: every text color must still reach 4.5:1, whatever the desktop behind the panel.

The idea is an optional, bounded translucency: a blurred desktop under the panel with the panel color drawn over it so that only a small, fixed share of the background shows through. Off by default, switched on in Settings > General > Appearance. The bound is what makes it testable: the worst cases are the panel blended with pure black and with pure white at the leak share, and the contrast tests from spec 032 can check the text colors against exactly those.

## Approaches Considered

### A: Blur plus capped tint (chosen)
- A system blur behind the content (the window's material, blending what is behind the window), and the panel's fixed background color on top at a fixed opacity, so a known share (about 10 to 15%) of the blurred desktop shows through.
- Pros: looks like a system menu at a glance; the leak is bounded, so contrast stays provable with the existing test approach (text against the panel blended with black and with white at the leak share, on every band and hover fill); the blur removes sharp desktop detail behind text.
- Cons: a second palette pair to tune and test; a new amendment to spec 032 FR-007; a small amount of platform code around the window's effect view.

### B: The native menu material
- Pros: exactly what the system menus look like.
- Cons: the material's tint is not under the app's control, so the contrast is unbounded and untestable. This is the state spec 025 fixed. Ruled out, as in brainstorm 31.

### C: Plain alpha on the panel, no blur
- Pros: the simplest change, a single opacity value.
- Cons: sharp desktop detail (text, icons, window edges) shows behind the dropdown's text, which hurts readability more than the same leak share through a blur. Ruled out.

### Control alternatives
- A slider from opaque to a maximum, or Off / Subtle / Strong steps: rejected for now. One toggle with one tested share keeps the UI small and the test matrix at two palettes; a slider can follow if the fixed share proves wrong for some desktops.

### Palette alternatives
- Tune today's palettes so they pass on both the opaque and the translucent panel: rejected, because the opaque panel's text would shift for everyone who never turns the option on.
- Pick the leak share so that today's palettes still pass unchanged: rejected, because the share that passes is likely too small to notice.
- Separate translucent palettes (chosen): the opaque palettes of spec 032 stay exactly as they are; translucency switches to its own light and dark palette, each tested at the leak share.

## Decision

Approach A with one toggle and separate translucent palettes.

- New toggle in Settings > General > Appearance, below "Dropdown theme", off by default for new installs and upgrades alike. The setting is stored in the configuration and absent when off.
- On: a blurred view of what is behind the window, with the panel's background color drawn over it so that a fixed share (10 to 15%, set in the spec) shows through. Works with both the light and the dark panel; Auto, Dark and Light keep their meaning.
- Off: today's opaque panel, unchanged, with today's palettes.
- The system's "Reduce transparency" accessibility setting wins: with it on, the panel is opaque even when the toggle is on (Apple's guidance for translucent materials).
- Settings and the menu bar item are not affected.

## Key Requirements

- The toggle lives in Appearance next to the theme picker, is off by default, and is absent from the configuration file when off.
- With the toggle on, the leak share is fixed and the same on both panels; nothing else about the layout changes (width, bands, scroll, footer).
- Two new translucent palettes (light, dark). Every text color (primary, secondary, warning, critical, link) reaches at least 4.5:1 against the least favorable background it can sit on: the panel, a band, a hover fill over a band, each blended with pure black and with pure white at the leak share, with and without Increase Contrast where it can be resolved. Tests resolve the real colors, as spec 032 does.
- The opaque palettes of spec 032 do not change.
- "Reduce transparency" on makes the panel opaque regardless of the toggle, and a change of that setting reaches an open dropdown.
- A toggle change in Settings reaches an open dropdown without closing it, like the theme change (spec 032 FR-004).
- Spec 032 FR-007 ("opaque in every theme") gets a dated amendment, and the related comment in the dropdown view changes with it.
- Screenshots and website (constitution V): the default is off, so the existing dropdown shots stay as they are. No landing page card for this feature. Check whether site copy or the README describes the panel as opaque.

## Open Questions

- The exact leak share within 10 to 15%, and which system material the blur uses (the menu material, the popover material, or a plain behind-window blur).
- Whether the translucent palettes need shades beyond warning, critical and secondary (for example the link blue on the footer band).
- Toggle label and caption wording ("Translucent background", "Let the desktop show through").
- Whether the blur stays active while the dropdown is not the key window (the effect view's state), and whether the panel's shadow or corner radius needs to change with it.
- Whether the demo scenario and the capture script need a translucent variant for review (not for the site), or a manual check in the walkthrough is enough.
- Whether the tooltip and other AppKit-drawn parts over the panel keep their look under the effect view.

---

## Revisit: 2026-10-23

### Updated Problem Framing

Spec 036 was implemented on branch `036-translucent-dropdown` and failed its walkthrough at step 4, in three designs:

- **12% panel color share:** invisible. The system's menu material tints the desktop strongly before the panel color covers it. Measured with the panel color at opacity 0 on macOS 26: light #ACACAC over a black and #E5E5E5 over a white desktop, dark #232222 and #676766.
- **Design B (light 30%, dark 60% panel color):** barely visible.
- **Design C (the system's glass, no panel color, the system's text colors, contrast target relaxed):** `NSGlassEffectView` in the clear `MenuBarExtra` window works. The regular style gives #1A1A1A over black and #414141 over white on the dark panel; the clear style gives #2F2F2F and #AAAAAA, with shapes but no text detail behind it.

CodexBar, which the maintainer pointed to, uses a real `NSMenu` with custom item views. macOS 26 gives `NSMenu` windows its menu glass, which keeps visibly more detail. A custom window cannot request that look.

### Updated Decision

Parked. The dropdown first moves into a real `NSMenu` (brainstorm 36). Then this feature is revisited on top of it, where the translucency may come for free from the menu itself.

### Open Threads

- Whether the NSMenu-hosted dropdown keeps an opaque look at all, or whether the menu's own glass becomes the only look (with Reduce transparency handled by the system).
- The theme mismatch seen in the walkthrough: the demo configuration said `dropdownTheme: light`, and the panel showed dark.
- Branch `036-translucent-dropdown` (13 commits, unmerged) holds the spec, the walkthrough results and the design C code. Its opacity restore (`WindowOpacityRestore`) and panel mode logic may be reusable.
