# Brainstorm: Dropdown in a Real NSMenu

**Date:** 2026-10-23
**Status:** active

Seeded from brainstorm 35 (translucent dropdown, parked) and from the idea inbox entry `own-status-item` (deep review of spec 014, 2026-10-16).

## Problem Framing

The dropdown is a SwiftUI `MenuBarExtra` window (`.menuBarExtraStyle(.window)`). The walkthrough of spec 036 showed that such a window cannot get the look of the system's menus. It tried three designs:

- **12% panel color share:** invisible, because the system's menu material tints the desktop before the panel color covers it.
- **Design B (30% and 60% panel color):** barely visible.
- **Design C (the system's glass):** works in the clear window (regular style #1A1A1A over black and #414141 over white on the dark panel; clear style #2F2F2F and #AAAAAA). It shows shapes but no detail.

CodexBar, which the maintainer pointed to, uses an `NSStatusItem` with a real `NSMenu` of custom `NSMenuItem` views (`NSHostingView` with `allowsVibrancy`, the system's text colors). macOS 26 gives `NSMenu` windows its menu glass, which keeps visibly more detail, and every other system menu looks the same.

A second reason comes from the inbox: opening the dropdown from a notification click (spec 014 FR-013) finds the status button in the window tree and a window whose class name contains "MenuBarExtra", both SwiftUI internals. A SwiftUI update could break it silently. Owning the `NSStatusItem` removes that dependency.

The goal: the dropdown looks and behaves like a system menu by default, with the system's glass, while users who want today's opaque, contrast-checked panel can keep it.

## Approaches Considered

### A: The whole dropdown as one custom menu row
- The current `DropdownView` (sections, scroll area, pinned footer) moves unchanged into a single `NSMenuItem` view.
- Pros: the least redesign; layout, bands, Details and screenshots stay as they are.
- Cons: not a menu in feel (no keyboard navigation, no native highlight); our own scroll area inside the menu; ⌘, and ⌘Q need care because the menu's tracking loop takes the keys.

### B: Native menu structure, as CodexBar
- One custom row per section (account, group, Unassigned), separators instead of bands, the footer actions as real menu items, Details as submenus or rows that expand in place, native menu scrolling when too tall.
- Pros: the real native look and feel (HIG).
- Cons: a redesign of the dropdown (no bands, no pinned footer), all shots and site copy change, and CodexBar's workarounds for row sizing and for live updates in an open menu.

### C: Hybrid (chosen)
- One custom content row with today's sections, layout, scroll area and Details; the footer actions as native menu items below it, with their shortcuts.
- Pros: native shortcuts and footer, content nearly unchanged, a moderate change to the shots.
- Cons: two kinds of rows; the scroll area stays our own; the footer is no longer a band.

### Scope alternatives
- NSMenu only for the translucent look, the window for the opaque default: rejected, two hosting paths to maintain.
- Native glass as the only look: rejected, it would drop spec 032's opaque, contrast-checked panels for users who rely on them.
- Opaque content row by default with glass only in the footer: rejected, the menu would look half native.

## Decision

Approach C, for everyone, with the system's glass as the default look.

- An own `NSStatusItem` with an `NSMenu` replaces the `MenuBarExtra` window. The Settings scene stays.
- The menu has one custom content row with today's sections (bands, Details, the headline switch rows of spec 027, the scroll area and the height cap of spec 026), then native menu items for the footer.
- Default look: the menu's own glass. The content row draws no panel color of its own and uses the system's text colors, as CodexBar and the system's menus do.
- An opt-in "Opaque background" in Settings > General > Appearance brings back the spec 032 panel and its 4.5:1 palettes in the content row. It replaces spec 036's "Translucent background" toggle; brainstorm 35 and spec 036 are then superseded rather than parked.

## Key Requirements

- **Status item and bar label:** our own status item shows today's bar label (the `BarLabel` rendering, levels, symbols, colors) and opens the menu on a click.
- **Content row:** keeps today's sections and their behavior: bands, Details expanding without animation, the headline switch rows, the height cap and scrolling past it, and time texts that update every 30 seconds while the menu is open.
- **Live updates:** a refresh that lands while the menu is open reaches the open menu, and opening the menu still triggers the opening refresh of spec 016.
- **Native footer:** the footer actions are native menu items with their shortcuts, Refresh ⌘R, Settings… ⌘, and Quit ⌘Q. The status row ("Last refreshed" with the "stale" marker and its tooltip), the update line and the source error lines get a native form; which form each takes is open.
- **Theme:** the dropdown theme of spec 032 (Auto, Dark, Light) sets the menu's appearance.
- **Opaque background:** the opt-in option draws the opaque panel with spec 032's palettes in the content row; the default draws none. The system's Reduce transparency makes the menu opaque as it does for every menu.
- **Notification click:** a notification click opens the menu through our own status item, with no dependency on SwiftUI's window classes (resolves `own-status-item`).
- **Tooling:** the screenshot capture (`scripts/screenshots/capture.sh`, `uihelper`) finds the status item and the open menu.
- **Screenshots and website (constitution V):** every dropdown shot changes in both appearances. One capture run, a review of every changed shot, a check of the site copy that describes the dropdown, and an entry in the site's card candidates list if the native look earns a card.
- **HIG:** the menu follows Apple's Human Interface Guidelines for menus and menu bar extras (item titles with an ellipsis where they open a window, standard shortcuts, separators).

## Open Questions

- Which native form each footer part takes: the status row as a disabled item with a tooltip, the update line as an item with its Install action, the source error lines as disabled items (and their color).
- Whether the content row's headline switch rows and Details keep working inside the menu's tracking loop, and whether clicks on them must not close the menu.
- How the content row measures and changes its height while the menu is open (Details expanding), and how the height cap works against the menu's own maximum height.
- Whether the orange and red text on the system's glass needs vibrancy or other shades to stay readable over light desktops (the spec 025 problem), and what the walkthrough compares it against.
- Which of spec 036's parts carry over: `PanelMode`, the Reduce transparency handling, the Settings toggle and its caption (inverted to "Opaque background"), and the configuration key (a new key such as `dropdownOpaque`, or a migration of `dropdownTranslucent`).
- The theme mismatch seen in the spec 036 walkthrough: the demo configuration said `dropdownTheme: light`, and the panel showed dark.
- How the demo build and the capture script open and crop the menu, and whether a menu window can be captured with `screencapture -l`.
- What happens to the `MenuBarOpener` and the `MenuBarExtra` mentions in the docs and comments.
