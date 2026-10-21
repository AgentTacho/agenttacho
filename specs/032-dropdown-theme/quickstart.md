# Quickstart: Dropdown Theme

## Prerequisites

- macOS 14 or later, the repository checked out, `make` available.
- For the screenshot run: the capture prerequisites in `docs/website.md` and a site checkout.

## Automated checks

```bash
make test           # UsageCore and DemoMode tests, including DropdownThemeTests and DropdownPaletteTests
make test-release   # release and screenshot script tests
```

Expected: both pass. The palette tests print no failures for any background (see data-model.md, Invariants).

## Manual validation with the demo build

```bash
make app-demo
```

1. System in light appearance, theme Auto (fresh demo settings): open the dropdown. Expect a light, opaque panel; the Claude Max 7-day pace note in dark orange and the Side project budget percent in dark red, both easy to read; bands faintly darker than the panel.
2. Switch the system to dark appearance with the dropdown open. Expect the dark panel within a second, without closing; red text is the lighter red.
3. Settings > General > Display: pick Dark while the system is light. Expect the dropdown dark at once (or at the next opening if Settings closed it). Pick Light while the system is dark: light panel.
4. Pick Auto again; quit and relaunch; the setting is kept and the panel follows the system.
5. With "Increase contrast" on (System Settings > Accessibility > Display), repeat 1 and 2: bands are stronger, all text still readable.
6. Check that the menu bar item, the Settings window and the Settings bar preview look as before in every theme.

## Configuration file

- With Auto, the configuration has no `dropdownTheme` key.
- Write `"dropdownTheme": "sepia"` by hand: the dropdown uses Auto and the diagnostic log (Settings > Log) shows `dropdownTheme "sepia" is not known, using auto`.

## Screenshots

Follow AGENTS.md steps 4 to 7 (ask the maintainer before capturing). Expected: the light variants of glance, budget, harnesses and same-provider show the light panel; dark variants differ only in the red text.
