---
runbook_version: 1
feature: 020-about-tab-update-layout
status: drafted
mode: light
steps_total: 6
step_results: pending,pending,pending,pending,pending,pending
drafted_at: f53715f
drafted_fingerprint: efac69248f4e4af5ad705fe99971e876d370afec0bf3f46103e502b703e1346b
tested_at:
tested_fingerprint:
updated: 2026-10-16
---

# Try it: About Tab Update Layout

<!-- runbook-status -->
> **Status:** drafted · 0 of 6 steps · Mode: light · Drafted at f53715f · 2026-10-16
<!-- /runbook-status -->

## What you're testing

Settings > About gets quieter: no "Updates" heading, no Signing row, and no toggle. A centered "Check for Updates…" button sits under the release data, with the update status below it in secondary text. "Check for updates automatically" moves to a new "Updates" section in Settings > General, right after "Launch".

Order of the journey: tests, config backup and build, the About tab, a manual check, the toggle in General with a relaunch, restore.

All commands run from the root of the feature worktree (`.claude/worktrees/020-about-tab-update-layout`, or `main` after merge). Settings saves edits automatically, so Step 2 backs up your configuration and the last step restores it.

## Test environment

No fixtures. Needs the Xcode Command Line Tools. A build from this branch is a development build, so its status line reads "Development build: updates are not checked"; the other update states reuse unchanged views (spec SC-003) and are not covered here.

## Steps

### Step 1 of 6: Run the test suite (US1, US2)

**Why this step:** The change is a layout change, but the stored setting and the update states it shows are covered by existing `UsageCore` tests, which must stay green (spec SC-004).

**Run:**

```
make test 2>&1 | tail -1
```

**What you should see:** `Test run with 1369 tests in 133 suites passed` (or more tests).

**If you see something else:** a failing test means the branch changed more than the layout; stop here.

**Result:**

### Step 2 of 6: Back up the configuration and start this build (US1, US2)

**Why this step:** Step 5 switches a setting that saves automatically; the backup lets the last step undo it. Only one AgentMeter can run, so any other copy is quit first.

**Run:**

```
cp ~/.config/agentmeter/config.json ~/.config/agentmeter/config.json.bak-020 && osascript -e 'quit app "AgentMeter"'; make run 2>&1 | tail -2
```

**What you should see:** `Built build/AgentMeter.app` and `open "build/AgentMeter.app"`, then the AgentMeter icon in the menu bar.

**If you see something else:** a build error means the branch does not compile; stop here.

**Result:**

### Step 3 of 6: Read the About tab (US1)

**Why this step:** The main point of the feature: the About tab shows the release data and the update check without heading, signing or toggle (spec FR-001 to FR-003, FR-007).

**Do:**

1. Open the dropdown, gear menu, "About AgentMeter".
2. Read the tab from the release data down to "What's new".

**What you should see:** Version, Commit and Built rows, no Signing row; below them a centered "Check for Updates…" button and, directly under it, the status "Development build: updates are not checked" in gray (secondary) text; no "Updates" heading and no "Check for updates automatically" checkbox; then "What's new".

**If you see something else:** a Signing row or the checkbox next to the button means the old build is running (quit it and repeat Step 2).

**Result:**

### Step 4 of 6: Press "Check for Updates…" (US1)

**Why this step:** The button still starts a check from Settings and its result shows below it (spec FR-006, spec 013 FR-003).

**Do:**

1. In the About tab, click "Check for Updates…".
2. Watch the status line below the button.

**What you should see:** the button is enabled and clickable; the status line under it stays centered and in secondary text, showing the result of this development build ("Development build: updates are not checked").

**If you see something else:** a status line that jumps above the button or turns primary color means the layout did not change as specified.

**Result:**

### Step 5 of 6: Switch the automatic check off in General and relaunch (US2)

**Why this step:** The toggle now lives in General, applies like every other setting and persists (spec FR-008, FR-009, SC-002).

**Do:**

1. Switch to the General tab and scroll to "Launch".
2. Check that the next section is "Updates" with "Check for updates automatically", followed by "Notifications".
3. Turn "Check for updates automatically" off and close Settings.
4. Quit AgentMeter from the gear menu and start it again with `open build/AgentMeter.app`.
5. Open Settings > General again.

**What you should see:** after step 2, the "Updates" section sits between "Launch" and "Notifications"; after step 5, the toggle is still off, and `rg -n checksForUpdates ~/.config/agentmeter/config.json` prints `"checksForUpdates" : false`.

**If you see something else:** a toggle that is on again after the relaunch means the setting was not saved through the Settings draft.

**Result:**

### Step 6 of 6: Restore the configuration (US2)

**Why this step:** Puts your configuration back exactly as before Step 2 and leaves your usual AgentMeter running.

**Run:**

```
osascript -e 'quit app "AgentMeter"'; mv ~/.config/agentmeter/config.json.bak-020 ~/.config/agentmeter/config.json && rg -n checksForUpdates ~/.config/agentmeter/config.json; open -a AgentMeter
```

**What you should see:** the `checksForUpdates` line from before Step 2 (usually `true`, or no line at all when the default applies), then your installed AgentMeter starts.

**If you see something else:** "No such file" from `mv` means the backup from Step 2 is missing; turn the toggle back on by hand.

**Result:**

## Not covered here

- Update states other than the development build's (available with an install action, downloading, a known update next to a failed check): they need the update-test build and a test release (`make app-update-test`, spec 013 FR-025). The views showing them are unchanged.

## Coverage

- US1 (a quieter About tab): Steps 1 to 4.
- US2 (the automatic check is a General setting): Steps 1, 2, 5 and 6.

## Results
