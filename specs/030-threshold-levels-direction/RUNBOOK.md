---
runbook_version: 1
feature: 030-threshold-levels-direction
status: passed
mode: light
steps_total: 9
step_results: passed,passed,passed,passed,passed,passed,passed,passed,passed
drafted_at: 92ca272
drafted_fingerprint: f46127393bb842f19d0e01d8bf8276cb3c0a4f2f55cbe5d8585a6ad620b10486
tested_at: 581d755
tested_fingerprint: 06069053272e14d23d87e5c19bf6fb2bd0406c1b71c8f4c540c9c1d204438c32
updated: 2026-10-20
---

# Try it: Threshold Levels and Budget Direction

<!-- runbook-status -->
> **Status:** passed · 9 of 9 steps (9 passed) · Mode: light · Tested at 581d755 · 2026-10-20
<!-- /runbook-status -->










## What you're testing

The notification thresholds now set the orange (warning) and red (critical) levels in both the menu bar and the dropdown. A new General setting, "Show usage as", shows every limit and budget as used or remaining. The journey: run the tests, build the demo app, see a threshold-driven red, raise a warning by editing a threshold, switch to Remaining, check an over-budget value in the variants scenario, check the thresholds editor in Remaining, and switch back.

## Test environment

No fixtures. The demo app (`build/AgentTacho Demo.app`) plays a made-up scenario and uses its own folders (`~/.config/agenttacho-demo`), so it runs next to a real AgentTacho without touching it. Quit the demo app at the end.

## Steps

### Step 1 of 9: Run the test suites (US1)

**Why this step:** proves the level rule, the direction values, the texts and the demo coverage before looking at the UI.

**Run:**

```
make test && make test-release
```

**What you should see:** both targets finish without failures; the Swift summary reports all UsageCore and DemoMode tests passed, and the release tests end with 0 failed.

**If you see something else:** a failing DemoMode test points at the demo scenario; a failing UsageCore test at the level or direction logic.

**Result:** passed (agent ran it). Exit 0; output 4797 lines in `.walkthrough/step-1.log`.
- ✔ all UsageCore tests passed: line 4351 `Test run with 1731 tests in 169 suites passed`
- ✔ all DemoMode tests passed: line 4542 `Test run with 66 tests in 7 suites passed`
- ✔ release tests 0 failed: line 4797 `253 passed, 0 failed`

### Step 2 of 9: Build and open the demo app (US1)

**Why this step:** the demo build is the only allowed way to see the UI with made-up data.

**Run:**

```
make app-demo && open "build/AgentTacho Demo.app"
```

**What you should see:** the build ends without errors and the demo app's entries appear in the menu bar (Claude Max with the `5h` tag at 58%, ChatGPT Plus, Company budget, Side project).

**If you see something else:** no entries means the app did not start; check Console for AgentTacho Demo.

**Result:** passed (agent ran the command, user checked the menu bar). Log in `.walkthrough/step-2.log`.
- ✔ build without errors: `Built build/AgentTacho Demo.app`, exit 0
- ✔ entries in the menu bar: confirmed by the user (Claude Max `5h` 58%, ChatGPT Plus, Company budget, Side project)

### Step 3 of 9: See a threshold-driven red (US1)

**Why this step:** the Side project budget has thresholds 75 and 85 and sits at about 87%, so it must be red below 100%.

**Do:**

1. Look at the Side project entry in the menu bar.
2. Click the menu bar item to open the dropdown and find the Side project section and the Claude Max 7-day row.

**What you should see:** the Side project value is red in the menu bar; in the dropdown its header percent is red and its bar is red. Claude Max's 7-day row shows 70% in the primary color with an orange bar and an orange pace note.

**If you see something else:** an orange or neutral Side project entry means the critical threshold is not applied.

**Result:** passed (user ran it in the demo app).
- ✔ Side project red in the menu bar, red header percent and red bar in the dropdown: confirmed by the user
- ✔ Claude Max 7-day row at 70% in the primary color with orange bar and pace note: confirmed by the user

### Step 4 of 9: Raise a warning by editing a threshold (US1)

**Why this step:** the first threshold must turn the dropdown percent orange while the bar keeps its pace meaning.

**Do:**

1. Open Settings from the dropdown, select Claude Max, set "First notification at" to 60.
2. Open the dropdown again and look at the Claude Max rows.

**What you should see:** the 7-day percent (70%) is orange, its bar stays orange only for pace; the 5-hour percent (58%) stays in the primary color. The explanation under the threshold fields names both levels.

**If you see something else:** a red 7-day percent means the second threshold was changed instead.

**Result:** passed (user ran it in the demo app).
- ✔ 7-day percent orange, bar orange only for pace: confirmed by the user
- ✔ 5-hour percent (58%) primary: confirmed by the user
- ✔ explanation names both levels: confirmed by the user

### Step 5 of 9: Switch to Remaining (US2)

**Why this step:** every level value must show 100 minus its used value, with flipped markers and unchanged colors.

**Do:**

1. Settings, General, section "Display": set "Show usage as" to Remaining.
2. Look at the menu bar and open the dropdown.

**What you should see:** the menu bar reads `5h 42%` for Claude Max; rows read 100 minus their used percent; bars fill to the remaining share with the tick at the expected remaining share; run-out markers read `↘` or `↓`; budget lines read "$X left of $Y/week" or "/month". Every color stays as it was in Used. The Menu Bar tab's checkbox label and preview show `↘`/`↓`.

**If you see something else:** a value that did not change, or a color that did, is a bug.

**Result:** passed (user ran it in the demo app).
- ✔ remaining values in the bar and the dropdown, bars filled to the remaining share: confirmed by the user
- ✔ markers `↘`/`↓`, Menu Bar tab label and preview flipped: confirmed by the user
- ✔ budget lines "$X left of $Y/period", colors unchanged: confirmed by the user

### Step 6 of 9: Check the thresholds editor in Remaining (US4)

**Why this step:** thresholds read in the chosen direction while the stored value stays used percent.

**Do:**

1. Settings, select ChatGPT Plus: the fields should read 20 and 0 with "% left".
2. Enter 30 in the first field.

**What you should see:** fields show 20 and 0 with "% left" and placeholders 20 and 0; after entering 30 the next step shows the stored value.

**If you see something else:** fields still reading 80 and 100 mean the editor ignores the direction.

**Result:** passed (user ran it in the demo app).
- ✔ ChatGPT Plus fields read 20 and 0 with "% left": confirmed by the user
- ✔ 30 entered in the first field (stored value checked in step 7)

### Step 7 of 9: Confirm the stored threshold (US4)

**Why this step:** the configuration must store 70 for an entered 30 left.

**Run:**

```
jq '{thresholds: (.accounts[] | select(.id == "acc-codex") | .thresholds), displayDirection}' ~/.config/agenttacho-demo/config.json
```

**What you should see:** the thresholds array starts with 70 and keeps 100; the top-level `displayDirection` is `"remaining"`.

**If you see something else:** 30 stored means the conversion is missing; a missing file means the demo stores its configuration elsewhere (check `docs/development.md`).

**Result:** passed (agent ran it).
- ✔ thresholds start with 70 and keep 100 → `"thresholds": [70, 100]`
- ✔ top-level direction is remaining → `"displayDirection": "remaining"`

### Step 8 of 9: Over budget in Remaining (US3)

**Why this step:** a budget above 100% must read negative and red with an empty bar.

**Do:**

1. Quit the demo app.
2. Run `open "build/AgentTacho Demo.app" --args -demoScenario variants` and make sure the direction is still Remaining (set it again if the scenario resets the configuration).
3. Open the dropdown and find the Team budget.

**What you should see:** the Team budget reads a negative value such as "−9%" in red, its bar is empty and red, and its line reads "$N over $80/week" (or "/month").

**If you see something else:** "0%" or a positive value means the negative format is missing.

**Result:** passed (agent restarted the demo with `-demoScenario variants`, user checked the dropdown).
- Note: loading the scenario reset `displayDirection` to `"used"` (scenario configuration has no direction), so the user set Remaining again, as the step allows.
- ✔ Team budget negative and red, empty red bar, "$N over $80/period": confirmed by the user

### Step 9 of 9: Switch back to Used (US2)

**Why this step:** the switch must restore today's look at once.

**Do:**

1. Settings, General, Display: set "Show usage as" to Used.
2. Look at the menu bar and the dropdown, then quit the demo app.

**What you should see:** values, bars, `↗`/`↑` markers and "$X of $Y" lines return at once, without a refresh; the Team budget reads above 100% in red.

**If you see something else:** values that only change after a refresh mean the views do not observe the setting.

**Result:** passed (user ran it in the demo app; agent quit the demo afterwards).
- ✔ values, bars, `↗`/`↑` and "$X of $Y" back at once without a refresh: confirmed by the user
- ✔ Team budget above 100% in red: confirmed by the user

## Not covered here

- Notification wording in Remaining: the demo build fires threshold notifications only when a value crosses a threshold during the run, which the scenarios do not guarantee; the texts are covered by `ThresholdNotificationTextTests`.
- VoiceOver wording ("30% left", "critical" vs "over limit"): covered by unit tests; checking it by hand needs VoiceOver.
- Screenshots and website copy: need the maintainer's go for the capture (AGENTS.md step 4).

## Coverage

- US1 (red at my own limit): steps 1, 3, 4.
- US2 (watch the budget empty): steps 5, 9.
- US3 (over budget in Remaining): step 8.
- US4 (thresholds in the chosen direction): steps 6, 7.

## Results

9 steps: 9 passed, 0 failed, 0 skipped (2026-10-20, at 581d755). The agent ran steps 1, 2 (build and launch), 7 and the restart in step 8; the user checked every GUI step in the demo app.

What this shows: the second threshold turns an entry red below 100% in the menu bar and the dropdown, the first threshold turns the dropdown percent orange while the bar keeps its pace meaning, "Show usage as" flips every level value, bar and marker at once without changing a color, a budget above 100% reads negative with "over", the thresholds editor speaks the chosen direction while the configuration keeps used percent (30 left stored as 70), and switching back restores the used view immediately.

Observation: loading a demo scenario resets the direction to used, because scenario configurations carry no `displayDirection`. Expected for the demo; no effect on real configurations.
