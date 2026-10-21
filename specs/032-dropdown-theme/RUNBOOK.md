---
runbook_version: 1
feature: 032-dropdown-theme
status: drafted
mode: light
steps_total: 11
step_results: pending,pending,pending,pending,pending,pending,pending,pending,pending,pending,pending
drafted_at: 1aefdd6
drafted_fingerprint: 4afc338ca47b5f0c68423fb27f9516c5f2371d35164ddcb9ce1f177471caebca
tested_at:
tested_fingerprint:
updated: 2026-10-21
---

# Try it: Dropdown Theme

<!-- runbook-status -->
> **Status:** drafted · 0 of 11 steps · Mode: light · Drafted at 1aefdd6 · 2026-10-21
<!-- /runbook-status -->

## What you're testing

Spec 032 lets the dropdown follow the system appearance instead of being always dark, and adds a "Dropdown theme" picker (Auto, Dark, Light) in Settings > General > Display. The light panel is an opaque gray (#D5D6D9) with darker orange, red, secondary and link colors so every text reaches 4.5:1; the dark panel is unchanged apart from a lighter red and a lighter link blue.

The journey: run the tests, open the demo in light appearance and look at the light panel, switch the system to dark while the dropdown is open, check Increase Contrast, pick Dark and Light in Settings against the system, look at what the configuration file stores, feed it an unknown value, check that Settings and the menu bar item did not change, and put the system appearance back.

## Test environment

No fixtures. The demo build (`build/AgentTacho Demo.app`) uses its own folders (`~/.config/agenttacho-demo`, `~/Library/Logs/agenttacho-demo`) and never touches the real AgentTacho; it rewrites its configuration from the scenario at every launch. Steps 2, 4 and 11 switch the system appearance; step 11 restores dark.

## Steps

### Step 1 of 11: Core tests pass (US1, US2, US3)

**Why this step:** theme resolution, the configuration key, the palette contrast rules and the demo coverage are tested core logic.

**Needs:** nothing.

**Run:**

```
make test
```

**What you should see:** both suites pass, UsageCore with about 1758 tests and DemoMode with about 69, and no failure lines.

**If you see something else:** a failing `DropdownPaletteTests` case names the role and the background that misses 4.5:1; a failing `ConfigurationTests` case about `dropdownTheme` means the key is written for Auto or a note is wrong.

**Result:**

### Step 2 of 11: Build the demo and switch the system to light (US1)

**Why this step:** the light panel shows with the default theme (Auto) only while the system is in light appearance.

**Needs:** step 1.

**Run:**

```
make app-demo && osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to false' && open -n "build/AgentTacho Demo.app" --args -AppleLanguages "(en)" -AppleLocale en_US -demoScenario default
```

**What you should see:** "Built build/AgentTacho Demo.app", the system turns light, and a second tacho item appears in the menu bar (the demo's, starting with "5h 58%").

**If you see something else:** no second item means the demo did not start; check `~/Library/Logs/agenttacho-demo/usage.log`.

**Result:**

### Step 3 of 11: Look at the light panel (US1)

**Why this step:** the core of the feature: with Auto in light appearance the dropdown is light, opaque and readable.

**Needs:** step 2.

**Do:**

1. Click the demo's menu bar item.
2. Look at the panel, the bands between sections, the footer, the orange pace notes and the red "Side project" percent.
3. Hover a row on a tinted band.

**What you should see:** an opaque mid-light gray panel, no desktop showing through; every second section on a slightly darker band and the footer a bit darker still; orange notes in a dark brownish orange and the Side project percent in dark red, both easy to read; bar fills still bright system orange and red; the hover highlight visible on the band; no dark strip at the footer or the scroll area.

**If you see something else:** a dark panel means the theme did not resolve to light (check that the system is light); a white strip or a dark strip means one part of the panel did not follow the style (FR-012).

**Result:**

### Step 4 of 11: Switch to dark with the dropdown open (US1)

**Why this step:** with Auto the open dropdown follows a system switch within one second, without closing (FR-006, SC-002).

**Needs:** step 3, dropdown still open.

**Run:**

```
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true'
```

**What you should see:** within about a second the open dropdown turns into the dark panel you know, without closing; red text is a lighter, salmon-like red; the bands are faintly lighter than the panel.

**If you see something else:** a dropdown that stays light until reopened means the appearance watcher did not fire; a closed dropdown is acceptable only if the click into the terminal closed it (reopen and check it is dark).

**Result:**

### Step 5 of 11: Increase Contrast in both panels (US1)

**Why this step:** the system's higher-contrast colors cannot be resolved in tests, so they are checked by eye (FR-007, edge case "Increase Contrast").

**Needs:** step 4.

**Do:**

1. System Settings > Accessibility > Display: turn on "Increase contrast".
2. Open the demo dropdown in dark appearance and look at the footer and a hovered row on a tinted band.
3. Run step 2's appearance command with `false` again to go light, open the dropdown, look at the same places.
4. Turn "Increase contrast" off.

**What you should see:** in both panels the bands get stronger and all text (secondary, orange, red, the "Last refreshed" line, links) stays readable on the footer and on a hovered band.

**If you see something else:** a text that blurs into the footer band names a role whose color needs adjusting.

**Result:**

### Step 6 of 11: Pick Dark while the system is light (US2)

**Why this step:** a fixed theme ignores the system appearance (FR-006, US2 scenario 1).

**Needs:** system light (step 5 ends light), demo running.

**Do:**

1. Open the demo dropdown, click the gear icon to open Settings.
2. General > Display: set "Dropdown theme" to Dark.
3. Open the demo dropdown again.

**What you should see:** the picker shows Auto, Dark, Light under "Show usage as" with the caption "Auto follows the system appearance. Settings and the menu bar always do."; the Settings window itself stays light; the dropdown is dark.

**If you see something else:** a light dropdown means the setting did not reach the dropdown (FR-004).

**Result:**

### Step 7 of 11: Pick Light while the system is dark (US2)

**Why this step:** the other direction of a fixed theme (US2 scenario 2), and the switch back to Auto (US2 scenario 3).

**Needs:** step 6.

**Do:**

1. Set "Dropdown theme" to Light in the demo's Settings.
2. Run step 4's command to switch the system to dark.
3. Open the demo dropdown: it should stay light.
4. Set "Dropdown theme" back to Auto and open the dropdown again.

**What you should see:** with Light, the dropdown is light while the system and Settings are dark; with Auto, it is dark again.

**If you see something else:** a dark dropdown under Light means the panel style ignores the theme.

**Result:**

### Step 8 of 11: What the configuration stores (US3)

**Why this step:** Auto writes no key; Dark and Light write their value (FR-003).

**Needs:** step 7 (theme back at Auto).

**Run:**

```
grep -c dropdownTheme ~/.config/agenttacho-demo/config.json; true
```

**What you should see:** `0` (no `dropdownTheme` key while the theme is Auto). Then set the theme to Dark in Settings, wait two seconds and run the command again: `1`. Set it back to Auto.

**If you see something else:** `1` under Auto means Auto is written to the file.

**Result:**

### Step 9 of 11: An unknown value falls back to Auto with a note (US3)

**Why this step:** a hand-edited configuration with a value AgentTacho does not know must not break loading (US3 scenario 2).

**Needs:** step 8, theme at Auto, system dark.

**Run:**

```
jq '.dropdownTheme = "sepia"' ~/.config/agenttacho-demo/config.json > /tmp/agenttacho-demo-config.json && mv /tmp/agenttacho-demo-config.json ~/.config/agenttacho-demo/config.json && sleep 3 && grep -n 'dropdownTheme' ~/Library/Logs/agenttacho-demo/usage.log | tail -2
```

**What you should see:** a log line containing `dropdownTheme "sepia" is not known, using auto`; the dropdown still opens dark (Auto in dark appearance) and the Settings picker shows Auto.

**If you see something else:** no log line means the reload did not pick up the file or the note is missing; a configuration error line in the dropdown means the value broke loading.

**Result:**

### Step 10 of 11: Settings, menu bar item and preview unchanged (US2)

**Why this step:** the theme applies to the dropdown only (FR-005).

**Needs:** demo running.

**Do:**

1. Set "Dropdown theme" to Light, then look at the menu bar item, the Settings window, and the bar preview in Settings > Menu Bar.
2. Set it back to Auto.

**What you should see:** the menu bar item follows the menu bar as before, Settings follows the system (dark), and the Menu Bar preview keeps its dark capsule; the About tab's update buttons (if shown) keep the system link style.

**If you see something else:** anything other than the dropdown changing with the theme is a FR-005 violation.

**Result:**

### Step 11 of 11: Quit the demo and restore dark appearance

**Why this step:** leaves the Mac as it was before the walkthrough.

**Needs:** nothing.

**Run:**

```
osascript -e 'tell application "AgentTacho Demo" to quit'; osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true'
```

**What you should see:** the demo's menu bar item disappears and the system is dark.

**If you see something else:** run the second command again.

**Result:**

## Not covered here

- Screenshots and site copy (FR-015): the capture run (`scripts/screenshots/capture.sh`) takes over the Mac and needs the maintainer's go; it is tracked as T021.

## Coverage

- US1 (follow the system): steps 1, 2, 3, 4, 5.
- US2 (fixed theme in Settings): steps 6, 7, 10.
- US3 (hand-edited configuration): steps 1, 8, 9.

## Results
