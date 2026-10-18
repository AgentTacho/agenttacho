---
runbook_version: 1
feature: 024-demo-mode-screenshots
status: passed
mode: light
steps_total: 12
step_results: passed,passed,passed,passed,passed,passed,passed,passed,passed,passed,passed,passed
drafted_at: 4563f86
drafted_fingerprint: 299aac454d09976707fd4f009a33a6feb2752b98a42768f133d872c174f30053
tested_at: f94bfc9
tested_fingerprint: 5ac0fbb6d69e4e2363fa16605761471afc5a7806bc35a7492ef1d05897cea0df
updated: 2026-10-18
---

# Try it: Demo build and screenshot capture

<!-- runbook-status -->
> **Status:** passed · 12 of 12 steps (12 passed) · Mode: light · Tested at f94bfc9 · 2026-10-18
<!-- /runbook-status -->















## What you're testing

AgentTacho Demo is a separate build that plays a made-up scenario instead of your real usage, and `scripts/screenshots/capture.sh` turns it into the 22 landing page screenshots. The journey goes the way you would use it: build the demo app and confirm releases stay clean, take a fingerprint of your installed AgentTacho, watch the demo story play (including the real alert), give the demo app its notification permission once, run the full capture, look at the images, and finally confirm that your own AgentTacho was never touched and that a Ctrl-C leaves everything as it was.

## Test environment

No fixtures. Everything runs on this Mac from the worktree. The installed AgentTacho is quit by the steps that need it quiet and started again at the end.

## Steps

### Step 1 of 12: Build the demo app (US1)

**Why this step:** Every later step uses `build/AgentTacho Demo.app`; its identity must differ from AgentTacho's so the two never meet.

**Run:**

```
make app-demo && /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "build/AgentTacho Demo.app/Contents/Info.plist" && ls "build/AgentTacho Demo.app/Contents/Resources/demo"
```

**What you should see:** The build ends with `build: demo build, bundle id dev.rhuss.agenttacho.demo` and `Built build/AgentTacho Demo.app`, then `dev.rhuss.agenttacho.demo`, then `default.json` and `litellm-prices.json`.

**If you see something else:** A compile error under `#if AGENTTACHO_DEMO` means the demo branch broke; a missing `demo` folder means `build-app.sh` did not copy `Resources/demo`.

**Result:** passed (agent). `build: demo build, bundle id dev.rhuss.agenttacho.demo`, `Built build/AgentTacho Demo.app`, `dev.rhuss.agenttacho.demo`, `default.json`, `litellm-prices.json`.

### Step 2 of 12: The regular build has no demo code (US4)

**Why this step:** Release builds must never carry the demo source, scenarios or identity (FR-003, SC-006).

**Run:**

```
make app && echo "DemoMode symbols: $(nm -U build/AgentTacho.app/Contents/MacOS/AgentTacho | grep -c DemoMode)" && (ls build/AgentTacho.app/Contents/Resources | grep demo || echo "no demo folder")
```

**What you should see:** `Built build/AgentTacho.app`, then `DemoMode symbols: 0` and `no demo folder`.

**If you see something else:** A non-zero count would already have stopped `make app` with `error: the app links DemoMode symbols`; check that `DEMO` is not set and that Package.swift adds DemoMode only with `DEMO=1`.

**Result:** passed (agent). `Built build/AgentTacho.app`, `DemoMode symbols: 0`, `no demo folder`.

### Step 3 of 12: Releases refuse the demo flag (US4)

**Why this step:** A stray `DEMO=1` in the environment must stop `make dmg` and `make release` before anything is built (FR-002).

**Run:**

```
DEMO=1 make -s dmg; echo "exit $?"
```

**What you should see:** `error: DEMO is set; release builds never carry the demo flag` and a non-zero exit (`make: *** [dmg] Error 1`, then `exit 2`).

**If you see something else:** If a build starts, `release.sh` lost its `DEMO` guard.

**Result:** passed (agent). `error: DEMO is set; release builds never carry the demo flag`, `make: *** [dmg] Error 1`, `exit 2`.

### Step 4 of 12: Quit AgentTacho and fingerprint its files (US1)

**Why this step:** The demo app must leave AgentTacho's configuration, imported prices, last good values and preferences byte for byte unchanged (SC-003). AgentTacho must be quit first, because it writes `last-good.json` on its own refreshes.

**Run:**

```
build/screenshots/uihelper quit dev.rhuss.agenttacho; shasum ~/.config/agenttacho/config.json ~/.config/agenttacho/imported-prices.json ~/Library/Application\ Support/agenttacho/last-good.json ~/Library/Preferences/dev.rhuss.agenttacho.plist | tee specs/024-demo-mode-screenshots/.walkthrough/before.sha
```

**What you should see:** `quit=done` (or `quit=none` if AgentTacho was not running), then four `shasum` lines.

**If you see something else:** `error: dev.rhuss.agenttacho did not quit within 10 s` means a dialog is open in AgentTacho; close it and run the step again. A "No such file" line just means that file does not exist on this Mac.

**Result:** passed (agent). `quit=done`; four checksums saved to `.walkthrough/before.sha`.

### Step 5 of 12: Allow notifications for the demo app (US2)

**Why this step:** The alert shot needs a real banner. macOS asks once per app, and the capture script refuses to run until AgentTacho Demo may show Banners (FR-018).

**Run:**

```
scripts/screenshots/capture.sh --first-run "$PWD/build/shots"
```

**What you should see:** `Waiting for the answer to the notification prompt of AgentTacho Demo...`, a macOS prompt or nothing (when already decided), then `notification permission: authorization granted` and `notification style: Banners`. If notifications are off (as they were on 2026-10-18), the script names System Settings > Notifications > AgentTacho Demo: allow them there with the Banners style and run the step again.

**If you see something else:** `missing tool:` names a tool to install; `Accessibility`, `Screen Recording` or `Automation` names a permission for your terminal; `Appearance is set to Auto` asks you to choose Light or Dark first.

**Result:** passed on retry (agent). First run: `notification permission for AgentTacho Demo was not granted: authorization error: Notifications are not allowed for this application` (denied earlier on this Mac). The user allowed notifications with Banners in System Settings; the rerun printed `notification permission: authorization granted` and `notification style: Banners`, exit 0. Log: `.walkthrough/step-5.log`.

### Step 6 of 12: Watch the demo story play, with the alert (US1, US2)

**Why this step:** The scenario must start at 76% for the Company budget, apply its frame about 12 s after launch and fire exactly one real notification (FR-012, FR-014).

**Run:**

```
open -n "build/AgentTacho Demo.app" --args -AppleLanguages '(en)' -AppleLocale en_US; sleep 20; tail -n 40 ~/Library/Logs/agenttacho-demo/usage.log | grep -E 'demo|crossing|Company budget|authorization|alert style|sent:'
```

**What you should see:** `demo build, scenario default`, a group line for Company budget at `(76%)`, then about 12 s later one at `(86%)`, one `crossing: Company budget monthly 80% (now 86%)`, `sent: Company budget ...` and `demo: last frame applied`. A macOS banner "Company budget reached 80%" appears.

**If you see something else:** No `sent:` line but a crossing means notifications are still blocked (see Step 5). A second crossing line would mean the scenario values cross another threshold.

**Result:** passed (agent). Launch 08:11:23Z at `(76%)`, refresh 08:11:37Z at `(86%)`, one `crossing: Company budget monthly 80% (now 86%)`, `sent: Company budget (grp-company) monthly crossed 80% at 86%`, `demo: last frame applied`, `alert style banner`.

### Step 7 of 12: Look at the bar, the dropdown and Settings (US1)

**Why this step:** This is what the screenshots will show; only the About tab may say "Demo" (FR-004, FR-007).

**Do:**

1. In the menu bar, find the demo item: Claude `70% ↑`, Codex `60% ↗`, Company budget orange `86%`, Side project red `104%`.
2. Open its dropdown: the Claude 5-hour meter is on pace, the Codex 5-hour meter behind, the Claude 7-day meter ahead; hover the 7-day meter for its tooltip.
3. Expand Details under Company budget and switch to Harnesses: Claude Code, Codex and OpenCode are listed, and there is no "incomplete" note.
4. Gear menu > "Check for Updates…": the line says "Demo build: updates are off".
5. Settings > About shows "Build: Demo"; Settings > Prices > Import > "OpenAI prices (LiteLLM, direct and Vertex)" opens a preview at once.
6. Quit the demo app (gear menu > Quit).

**What you should see:** Exactly the values above, English text and US number formats, and no "Demo" anywhere except the About row.

**If you see something else:** German formats mean the launch arguments were dropped; a red error line at the top of the dropdown names a scenario problem.

**Result:** passed (user, screenshot of bar and dropdown). Bar `70%↑ 60%↗ 86% 104%` with orange and red; Claude 5-hour on pace, 7-day ahead, ChatGPT 5-hour behind, weekly ahead; Company budget `430 of $500/month` 86% with both members priced; Side project 104% without a meter; US formats. Details > Harnesses, Settings, About and the Prices preview were not in the screenshot; Step 9 and 10 show them.

### Step 8 of 12: A missing scenario shows its error and stays empty (US1)

**Why this step:** A wrong `-demoScenario` must never fall back to real data (FR-013).

**Run:**

```
build/screenshots/uihelper quit dev.rhuss.agenttacho.demo; open -n "build/AgentTacho Demo.app" --args -demoScenario missing; sleep 5; grep 'scenario missing' ~/Library/Logs/agenttacho-demo/usage.log | tail -n 1; build/screenshots/uihelper quit dev.rhuss.agenttacho.demo
```

**What you should see:** `quit=done` or `quit=none` (an open demo app would make the new launch exit at the single-instance check), `demo build, scenario missing not played: no scenario named "missing" in the app bundle`, then `quit=done`. If you open the dropdown before the quit, it shows "Demo scenario error" and "No accounts configured".

**If you see something else:** Accounts in the dropdown would mean an earlier run's configuration survived.

**Result:** passed (agent). `demo build, scenario missing not played: no scenario named "missing" in the app bundle`; `quit=done`.

### Step 9 of 12: Run the full capture (US3)

**Why this step:** One command must produce all 22 files in under 5 minutes without a manual step (SC-001), restoring the appearance afterwards. Leave the Mac alone while it runs: it moves the mouse.

**Run:**

```
time scripts/screenshots/capture.sh "$PWD/build/shots"
```

**What you should see:** The build, a short demo launch for the notification check, then two passes (the system switches to dark for the second), and finally 22 lines such as `dropdown-light.webp 720x1200` with the `time` total under 5 minutes. The appearance is what it was before.

**If you see something else:** `could not capture <stem> (<appearance>): <reason>; not captured: ...` names what failed; the target folder is unchanged and the appearance restored. Common reasons: a banner still on screen, another app's window over the region, the tooltip not appearing.

**Result:** passed on the fifth try (agent). The first four runs stopped with `could not capture ...` and left the target empty and the appearance restored; each exposed a real defect fixed in the script (tooltip window height, Details disclosure press, Settings opened from the hidden main menu, hover into the meter). Final run: exit 0, 22 files, 1:39 total, appearance back to dark as before. Logs: `.walkthrough/step-9*.log`.

### Step 10 of 12: Review the 22 images (US3)

**Why this step:** The images go to a public site: no real name, no German formats, no clipped UI (SC-007).

**Run:**

```
ls build/shots | wc -l && open build/shots
```

**What you should see:** `22`, and a Finder window. Check each image: light and dark variants, the banner reads "Company budget reached 80%", the menu bar item has a transparent background, crops show whole cards.

**If you see something else:** A clipped crop points at an accessibility frame that is off; note the stem.

**Result:** passed (user and agent). User: "Looks good to me" (the menu bar images first looked cut off in a Finder preview, the files are fine). Agent viewed 12 images: alert, plan-limits, budget, pace, details, harnesses, groups, prices, dropdown, menubar. Open point: in `pace-*` the tooltip wraps and the next heading showed beside it; fixed in the script by clipping the dropdown below the plan rows (commit f94bfc9), not yet seen on a real recapture.

### Step 11 of 12: AgentTacho's files are unchanged (US1)

**Why this step:** Proves the demo build and the capture never touched AgentTacho's own data (SC-003).

**Run:**

```
shasum -c specs/024-demo-mode-screenshots/.walkthrough/before.sha
```

**What you should see:** `OK` for every file listed in Step 4.

**If you see something else:** A `FAILED` line for `last-good.json` usually means AgentTacho was running in between (the capture restarts it at the end only if it ran before Step 9).

**Result:** passed (agent). `shasum -c`: all four files OK.

### Step 12 of 12: Ctrl-C leaves everything as it was (US3)

**Why this step:** An interrupted capture must restore the appearance, quit the demo app and leave the target folder untouched (FR-021, FR-022, SC-004).

**Do:**

1. Run `scripts/screenshots/capture.sh "$PWD/build/shots-interrupt"` in a terminal.
2. When the system switches to dark appearance (the second pass), press Ctrl-C once.
3. Run `ls build/shots-interrupt; pgrep -fl "AgentTacho Demo.app"; echo "exit done"`.

**What you should see:** The script exits right away (status 130), the appearance is back to what it was, `build/shots-interrupt` is empty or missing, and no AgentTacho Demo process is listed.

**If you see something else:** Dark appearance left on would break SC-004; note what the script printed.

**Result:** passed (agent, with a signal instead of the keyboard). Started in dark appearance; the capture switched to light, then back to dark for its second pass. About 8 s into that pass the agent sent SIGTERM and the script exited with 130, the appearance was dark again, no AgentTacho Demo process was left and `build/shots-interrupt` was never created. A first attempt with SIGINT had no effect because background jobs of a non-interactive shell ignore SIGINT; the script traps INT and TERM with the same handler (`trap 'exit 130' INT TERM`), and the stub test `test_screenshots_interrupt_cleans_up` covers the INT path. A real Ctrl-C was not pressed by hand.

## Not covered here

- Quickstart Q5 (`nettop` and `sudo fs_usage` during a capture, `secd` log stream) needs sudo and a second terminal watching the demo process. It is described in quickstart.md.
- A Focus mode that hides the banner (quickstart Q7.2) depends on your Focus setup.

## Coverage

- US1 (demo story in a separate app): Steps 1, 4, 6, 7, 8, 11.
- US2 (scripted alert): Steps 5, 6.
- US3 (one command captures every screenshot): Steps 5, 9, 10, 12.
- US4 (release builds stay clean): Steps 2, 3.

## Results

12 steps: 12 passed, 0 failed, 0 skipped.

What a reader now knows: the demo app builds with its own identity, plays the default scenario with exactly one real alert, never touches AgentTacho's files, and `capture.sh` produces all 22 files in about 1.5 minutes while restoring the appearance, also when interrupted. Releases refuse the demo flag and a regular build links no demo code.

The walkthrough found real defects that the stub tests could not: the tooltip window is wider than assumed, the Details disclosure has no press of its own, Settings was opened through the hidden main menu, a hover onto the cursor's own position shows no tooltip, and an open import sheet holds up quitting. All are fixed and committed.

Not verified: the pace crop fix after the last change (clipping the dropdown below the plan rows) was tested with stubs only, not on a real recapture; quickstart Q5 (`nettop`, `fs_usage`) needs sudo.
