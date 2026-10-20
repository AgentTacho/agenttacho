---
runbook_version: 1
feature: 030-threshold-levels-direction
status: drafted
mode: light
steps_total: 9
step_results: pending,pending,pending,pending,pending,pending,pending,pending,pending
drafted_at: 92ca272
drafted_fingerprint: f46127393bb842f19d0e01d8bf8276cb3c0a4f2f55cbe5d8585a6ad620b10486
tested_at:
tested_fingerprint:
updated: 2026-10-20
---

# Try it: Threshold Levels and Budget Direction

<!-- runbook-status -->
> **Status:** drafted · 0 of 9 steps · Mode: light · Drafted at 92ca272 · 2026-10-20
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

**Result:**

### Step 2 of 9: Build and open the demo app (US1)

**Why this step:** the demo build is the only allowed way to see the UI with made-up data.

**Run:**

```
make app-demo && open "build/AgentTacho Demo.app"
```

**What you should see:** the build ends without errors and the demo app's entries appear in the menu bar (Claude Max with the `5h` tag at 58%, ChatGPT Plus, Company budget, Side project).

**If you see something else:** no entries means the app did not start; check Console for AgentTacho Demo.

**Result:**

### Step 3 of 9: See a threshold-driven red (US1)

**Why this step:** the Side project budget has thresholds 75 and 85 and sits at about 87%, so it must be red below 100%.

**Do:**

1. Look at the Side project entry in the menu bar.
2. Click the menu bar item to open the dropdown and find the Side project section and the Claude Max 7-day row.

**What you should see:** the Side project value is red in the menu bar; in the dropdown its header percent is red and its bar is red. Claude Max's 7-day row shows 70% in the primary color with an orange bar and an orange pace note.

**If you see something else:** an orange or neutral Side project entry means the critical threshold is not applied.

**Result:**

### Step 4 of 9: Raise a warning by editing a threshold (US1)

**Why this step:** the first threshold must turn the dropdown percent orange while the bar keeps its pace meaning.

**Do:**

1. Open Settings from the dropdown, select Claude Max, set "First notification at" to 60.
2. Open the dropdown again and look at the Claude Max rows.

**What you should see:** the 7-day percent (70%) is orange, its bar stays orange only for pace; the 5-hour percent (58%) stays in the primary color. The explanation under the threshold fields names both levels.

**If you see something else:** a red 7-day percent means the second threshold was changed instead.

**Result:**

### Step 5 of 9: Switch to Remaining (US2)

**Why this step:** every level value must show 100 minus its used value, with flipped markers and unchanged colors.

**Do:**

1. Settings, General, section "Display": set "Show usage as" to Remaining.
2. Look at the menu bar and open the dropdown.

**What you should see:** the menu bar reads `5h 42%` for Claude Max; rows read 100 minus their used percent; bars fill to the remaining share with the tick at the expected remaining share; run-out markers read `↘` or `↓`; budget lines read "$X left of $Y/week" or "/month". Every color stays as it was in Used. The Menu Bar tab's checkbox label and preview show `↘`/`↓`.

**If you see something else:** a value that did not change, or a color that did, is a bug.

**Result:**

### Step 6 of 9: Check the thresholds editor in Remaining (US4)

**Why this step:** thresholds read in the chosen direction while the stored value stays used percent.

**Do:**

1. Settings, select ChatGPT Plus: the fields should read 20 and 0 with "% left".
2. Enter 30 in the first field.

**What you should see:** fields show 20 and 0 with "% left" and placeholders 20 and 0; after entering 30 the next step shows the stored value.

**If you see something else:** fields still reading 80 and 100 mean the editor ignores the direction.

**Result:**

### Step 7 of 9: Confirm the stored threshold (US4)

**Why this step:** the configuration must store 70 for an entered 30 left.

**Run:**

```
jq '{thresholds: (.accounts[] | select(.id == "acc-codex") | .thresholds), displayDirection}' ~/.config/agenttacho-demo/config.json
```

**What you should see:** the thresholds array starts with 70 and keeps 100; the top-level `displayDirection` is `"remaining"`.

**If you see something else:** 30 stored means the conversion is missing; a missing file means the demo stores its configuration elsewhere (check `docs/development.md`).

**Result:**

### Step 8 of 9: Over budget in Remaining (US3)

**Why this step:** a budget above 100% must read negative and red with an empty bar.

**Do:**

1. Quit the demo app.
2. Run `open "build/AgentTacho Demo.app" --args -demoScenario variants` and make sure the direction is still Remaining (set it again if the scenario resets the configuration).
3. Open the dropdown and find the Team budget.

**What you should see:** the Team budget reads a negative value such as "−9%" in red, its bar is empty and red, and its line reads "$N over $80/week" (or "/month").

**If you see something else:** "0%" or a positive value means the negative format is missing.

**Result:**

### Step 9 of 9: Switch back to Used (US2)

**Why this step:** the switch must restore today's look at once.

**Do:**

1. Settings, General, Display: set "Show usage as" to Used.
2. Look at the menu bar and the dropdown, then quit the demo app.

**What you should see:** values, bars, `↗`/`↑` markers and "$X of $Y" lines return at once, without a refresh; the Team budget reads above 100% in red.

**If you see something else:** values that only change after a refresh mean the views do not observe the setting.

**Result:**

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
