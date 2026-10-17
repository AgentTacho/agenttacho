---
runbook_version: 1
feature: 012-colored-bar-levels
status: passed
mode: light
steps_total: 11
step_results: passed,passed,passed,passed,passed,passed,passed,passed,passed,passed,passed
drafted_at: b9735d9
drafted_fingerprint: 0165bab0947099a1752fb75677c4f82c2ddeb5d0a174da3be9fcf0702224b123
tested_at: 64adae3
tested_fingerprint: 91d2cfc1e3fcbe26db6e173e851c6465df1eb76233f36ffc1dbeeddf6f6a69e2
updated: 2026-10-16
---

# Try it: Colored Bar Levels

<!-- runbook-status -->
> **Status:** passed · 11 of 11 steps (11 passed) · Mode: light · Tested at 64adae3 · 2026-10-16
<!-- /runbook-status -->












## What you're testing

The menu bar now shows levels by color instead of the `⚠` and `‼` glyphs: by default an entry's value turns orange at its warning threshold and red at 100% or above, while the icon stays in the normal menu bar color. The Menu Bar tab adds "Level color" (Text, Pill, Off) and "Mark levels with ⚠ / ‼"; with Off and no symbols a note says levels no longer appear in the bar. A bar without any level must look exactly as before, and the colors must follow the menu bar's appearance.

Order of the journey: tests, backup and build, the default red and orange values, appearance and highlight checks (the main technical risk), the pill style, the symbols checkbox, hiding levels, accessibility text, an unknown config value, restore.

All commands run from the repository root of the feature worktree (`.claude/worktrees/012-colored-bar-levels`, or `main` after merge). The app reads your real configuration, so Step 2 backs it up and the last step restores it.

## Test environment

No fixtures. Needs the Xcode Command Line Tools, `jq`, and a configuration with at least one entry in the bar. Your "Vertex" group is far over its budget, which gives an over-limit entry without changes. The single-instance check stops a second copy, so Step 2 quits any running AgentTacho first (including a build from another worktree).

## Steps

### Step 1 of 11: Run the test suite (US1, US2, US3, US4)

**Why this step:** Which part gets which color, glyphs, pills, accessibility text, pill contrast and the config decoding are pure logic with unit tests.

**Run:**

```
make test 2>&1 | tail -1
```

**What you should see:** `Test run with 760 tests in 82 suites passed` (or more tests).

**If you see something else:** A failing `BarPresentationTests`, `PillContrastTests` or `LevelDisplayConfigurationTests` test names the rule that broke.

**Result:** passed (run by the agent).

- ✔ 760 tests or more → `Test run with 760 tests in 82 suites passed after 0.551 seconds.`

### Step 2 of 11: Back up the configuration, build and start the app (US1)

**Why this step:** Later steps change thresholds, the level settings and a config value; the backup lets the last step undo everything.

**Run:**

```
cp ~/.config/agenttacho/config.json ~/.config/agenttacho/config.json.bak-012 && osascript -e 'tell application id "dev.rhuss.agenttacho" to quit'; make app 2>&1 | tail -1 && open build/AgentTacho.app
```

**What you should see:** `Built build/AgentTacho.app`, and AgentTacho appears in the menu bar.

**If you see something else:** An "AgentTacho is already running" alert means the quit did not finish; choose "Stop It and Start This One".

**Result:** passed (run by the agent).

- ✔ `Built build/AgentTacho.app`, feature build running from the worktree, backup `config.json.bak-012` written

### Step 3 of 11: Over-limit value in red, icon neutral (US1)

**Why this step:** The default style: a value over 100% is red, without `‼`, and the bar is no wider than a normal entry.

**Do:**

1. Wait for the first refresh.
2. Look at the Vertex entry in the menu bar, then at the other entries.

**What you should see:** The Vertex value (over 100%) is red; its wallet icon stays in the menu bar's normal text color; there is no `‼`. Entries below their warning threshold look exactly as before. An entry with `↗` (run-out marker from spec 011) shows the arrow in the normal color.

**If you see something else:** A `‼` means the symbols setting is on or the old build is running; an all-monochrome bar with Vertex over 100% means the colored path is not used.

**Result:** passed (user in the app).

- ✔ Vertex value red, icon neutral, no `‼`, other entries unchanged → user: as expected

### Step 4 of 11: Warning value in orange (US1)

**Why this step:** The warning level has its own color.

**Do:**

1. Open Settings (gear in the dropdown), Accounts tab, select your Claude subscription account.
2. Set "First notification at" to a value below its current 7-day percent (for example 10), and leave Settings open.

**What you should see:** The Claude entry's value turns orange in the bar (and in the Menu Bar tab preview, on its dark capsule, with a white icon).

**If you see something else:** No change means the threshold did not apply (a red validation text) or the 7-day percent is below the new threshold.

**Result:** passed (user in the app).

- ✔ Claude value orange in the bar and in the Menu Bar tab preview → user: as expected

### Step 5 of 11: Colors follow the menu bar's appearance (US1)

**Why this step:** The main technical risk: a full-color image must use the menu bar's own text color for neutral parts and update when the appearance changes (FR-013 to FR-015, SC-002, SC-007).

**Do:**

1. System Settings > Appearance: switch between Light and Dark while watching the bar.
2. In Light mode, pick a dark desktop picture (the menu bar turns light-on-dark), then a light one.
3. Open the AgentTacho dropdown and look at the highlighted bar entry.
4. If you have a second display, look at its menu bar while the main display is active.
5. System Settings > Accessibility > Display: turn "Increase contrast" on, then off.
6. Lower the threshold back (or wait until no entry is at a level) and compare the bar with the other menu bar items.

**What you should see:** In every case the icons and normal values match the other menu bar items' text color, orange and red stay readable, and the bar updates within about a second of each change. With no entry at a level the bar is indistinguishable from the previous version (template image).

**If you see something else:** Black icons on a dark menu bar (or white on light) after a wallpaper change mean the image does not pick up the menu bar's appearance: switch `BarLabelView` to the explicit appearance (research R1 fallback).

**Result:** passed (user in the app). The research R1 primary path (no explicit appearance) holds.

- ✔ neutral parts match the other menu bar items in the conditions tried, colors readable, updates within about a second → user: as expected

### Step 6 of 11: Pill style (US2)

**Why this step:** The louder alternative: a rounded colored background with readable text.

**Do:**

1. Settings > Menu Bar tab: set "Level color" to Pill.
2. Look at the bar and the preview; if two entries are at a level next to each other, check the gap between their pills, and check a pill at the bar's left or right end.

**What you should see:** Vertex sits on a red rounded background, the Claude entry (if still at its warning level) on an orange one; icon and value on the pill are black or white and easy to read; adjacent pills do not touch; no pill is cut off at either end. Entries without a level have no pill.

**If you see something else:** White text on a light orange pill (hard to read) means the pill contrast choice is not applied.

**Result:** passed (user in the app).

- ✔ red and orange pills, readable text, separate pills, nothing clipped, preview matches → user: as expected

### Step 7 of 11: Symbols checkbox with every style (US3)

**Why this step:** Color-blind users can bring the glyphs back, combined with any color style.

**Do:**

1. Menu Bar tab: check "Mark levels with ⚠ / ‼".
2. Switch "Level color" through Pill, Text and Off.

**What you should see:** `‼` before the Vertex value (and `⚠` before a warning value) in all three styles: inside the pill and in its text color for Pill, red or orange for Text, the normal menu bar color for Off. The `~` of a stale entry stays after the glyph.

**If you see something else:** A glyph after the value, or one that keeps a level color with Off, means the presentation is wrong.

**Result:** passed (user in the app), after two label changes found during this step.

- The checkbox read "Also show ⚠ / ‼ symbols", but the symbols also work alone with Level color Off; it is now "Mark levels with ⚠ / ‼" (spec 012 FR-004 and clarification updated). This step's text was corrected to match.
- The spec 011 toggle "Mark entries projected to run out before reset" was hard to understand; it now reads "Show ↗ when an entry will run out before it resets" (spec 011 FR-014 updated). An (i) hover help was tried and removed again as not adding much.
- ✔ new labels, glyphs correct with Pill, Text and Off → user: as expected

### Step 8 of 11: Hide levels from the bar (US4)

**Why this step:** Off without symbols is allowed and explained.

**Do:**

1. Menu Bar tab: set "Level color" to Off and uncheck the symbols box.
2. Then turn either setting back on.

**What you should see:** With both off, the note "Levels will not appear in the menu bar. Notifications and the dropdown still show them." appears below the checkbox and the bar shows Vertex without color or glyph. The note disappears as soon as either setting is on again.

**If you see something else:** No note, or a note that stays, means `hidesLevels` is not wired to the tab.

**Result:** passed (user in the app).

- ✔ note only with Off and no symbols, bar without level then → user: as expected

### Step 9 of 11: Accessibility text names the level (US3)

**Why this step:** VoiceOver users must hear the level whatever the display setting, without glyph names (FR-018).

**Run:**

```
osascript -e 'tell application "System Events" to tell (first process whose bundle identifier is "dev.rhuss.agenttacho") to get name of every menu bar item of menu bar 2'
```

**What you should see:** One line with the bar's text, for example `Claude warning 34%  Vertex over limit 526%`: "warning" or "over limit" before the values at a level, no `⚠`, `‼` or `↗` characters (a run-out marker reads ", projected to run out before reset").

**If you see something else:** A permission error means the terminal needs Accessibility access (System Settings > Privacy & Security > Accessibility); glyphs in the text mean the old plain-text form is still used.

**Result:** passed (run by the agent), after correcting this step's command.

- The first command read `description`, which is `status menu`; SwiftUI puts the label on the item's `name` (AXTitle), which VoiceOver reads. The command now reads `name`.
- ✔ level words, no glyphs → `Claude Code (Max) warning 84%  Codex (Plus) 16%  Vertex over limit 526%`

### Step 10 of 11: Unknown level color in the configuration file (US1)

**Why this step:** A hand-edited unknown value must fall back to Text, be logged, and never show a problem notice (FR-003).

**Run:**

```
jq '.levelColor = "rainbow"' ~/.config/agenttacho/config.json > /tmp/agenttacho-012.json && mv /tmp/agenttacho-012.json ~/.config/agenttacho/config.json && osascript -e 'tell application id "dev.rhuss.agenttacho" to quit'; sleep 2; open build/AgentTacho.app; sleep 8; grep 'levelColor' ~/Library/Logs/agenttacho/usage.log | tail -1
```

**What you should see:** A log line with source `config` like `levelColor "rainbow" is not known, using text`; the bar shows colored values (Text style), and no "Not applied" problem notice appears in Settings.

**If you see something else:** No log line means the load notes are not passed to the log; a problem notice means the value made the configuration invalid.

**Result:** passed (run by the agent).

- ✔ `config` log line → `2026-10-16T04:57:09Z [config] levelColor "rainbow" is not known, using text`
- ✔ no configuration error after the restart; bar text still names the levels

### Step 11 of 11: Restore the configuration

**Why this step:** Undo the threshold, level settings and config edits from this walkthrough.

**Run:**

```
osascript -e 'tell application id "dev.rhuss.agenttacho" to quit'; sleep 2; mv ~/.config/agenttacho/config.json.bak-012 ~/.config/agenttacho/config.json && jq '{levelColor, showLevelSymbols}' ~/.config/agenttacho/config.json
```

**What you should see:** `{"levelColor": null, "showLevelSymbols": null}` (the backup predates the new keys), and the app is quit. Start your usual AgentTacho again afterwards.

**If you see something else:** `No such file` means the backup from Step 2 is missing; restore the settings by hand in the Menu Bar tab.

**Result:** passed (run by the agent).

- ✔ `{"levelColor": null, "showLevelSymbols": null}`, app quit

## Coverage

- US1 (levels stand out at a glance): Steps 1 to 5, 10.
- US2 (pill style): Steps 1, 6.
- US3 (symbols and accessibility): Steps 1, 7, 9.
- US4 (hide levels): Steps 1, 8; the unchanged threshold notification (US4 scenario 3) is covered by the unchanged notification code and its tests, not re-triggered here.

## Results

All 11 steps passed (Steps 3 to 8 checked by the user in the app, Steps 1, 2 and 9 to 11 run by the agent). The bar shows warning levels in orange and over-limit levels in red by default, keeps its old look without levels, follows light, dark, tinted and high-contrast menu bars, and offers the pill style, the symbols checkbox and the hidden-levels note. The walkthrough renamed two Menu Bar tab labels ("Mark levels with ⚠ / ‼", "Show ↗ when an entry will run out before it resets") and corrected the accessibility check command.
