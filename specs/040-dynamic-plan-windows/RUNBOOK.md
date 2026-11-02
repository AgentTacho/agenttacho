---
runbook_version: 1
feature: 040-dynamic-plan-windows
status: passed
mode: light
steps_total: 6
step_results: passed,passed,passed,passed,passed,passed
drafted_at: c970c44
drafted_fingerprint: 983f898394479f935b3e75946c7c0dcbebb31e0f184c7055e913bfd0635b526e
tested_at: 6f703ec
tested_fingerprint: 72d34bd5328e469adf281d2c06ee6960522ef6735e9397b83c7db9abee1b6ec7
updated: 2026-11-02
---

# Try it: Dynamic Claude Plan Windows

<!-- runbook-status -->
> **Status:** passed · 6 of 6 steps (6 passed) · Mode: light · Tested at 6f703ec · 2026-11-02
<!-- /runbook-status -->







## What you're testing

Claude plan windows now come from the usage endpoint's `limits` list instead of a fixed 5-hour and 7-day pair. You will first run the tests, then build the demo app and look at the dropdown: the Claude section shows "7-day" and "Fable" rows and no dead "5-hour" row, while Codex still shows its own 5-hour window. Then you play the `variants` scenario to see a window of an unknown group ("daily") appear without a pace note. Finally, with the real app, you check the new log line and the saved values file, which also covers compatibility with your existing configuration.

Order: tests, demo build, default scenario dropdown, variants scenario, real app log and saved values.

## Test environment

No fixtures. The steps build the apps with the Makefile and read files AgentTacho writes in your home folder. The demo app keeps its own folders (`~/.config/agenttacho-demo` and friends) and reads no keychain item.

## Steps

### Step 1 of 6: Run the test suites (US1, US2, US3, US4)

**Why this step:** the parser, identities, headline fallback, thresholds, saved-values compatibility and the older answer shape are all decided by tested UsageCore logic.

**Run:**

```
make test 2>&1 | tail -5
```

**What you should see:** both test runs end without failures, about 2450 UsageCore tests and 74 DemoMode tests passed.

**If you see something else:** a failing test names the requirement area (ClaudeLimitsTests, UsageEndpointClientTests, LastGoodStoreTests); the branch is not ready.

**Result:**
Passed (agent run, on retry). Expected vs actual: ✔ `Test run with 2452 tests in 255 suites passed`; ✔ `Test run with 74 tests in 7 suites passed`; exit 0. The first two runs, right after the app builds and the screenshot capture, each failed one load-sensitive spec 038 test in MatchRuntimeTests (`tenThousandLinesStayFast`: 1.2 s against a 1 s limit; `tenThousandLinesThroughTheKindFirstStep`: fewer than 5000 matches, because a 50 ms per-record regex limit hit under load switches the rule off). This branch does not touch that code; recorded in the idea inbox as `load-sensitive-match-tests`. Log: `.walkthrough/step-1.log`.

### Step 2 of 6: Build the demo app (US1)

**Why this step:** the demo app plays a made-up scenario, so you can see the dropdown without real accounts.

**Run:**

```
make app-demo 2>&1 | tail -3 && ls -d "build/AgentTacho Demo.app"
```

**What you should see:** the build finishes and the last line prints `build/AgentTacho Demo.app`.

**If you see something else:** a build error means the branch does not compile outside the test build; report the first error line.

**Result:**
Passed (agent run). Expected vs actual: ✔ `Built build/AgentTacho Demo.app`; ✔ `build/AgentTacho Demo.app/` listed.

### Step 3 of 6: Look at the Claude section in the default scenario (US1, US2)

**Why this step:** this is the visible bug: the Claude section must not show a "5-hour" row that reads "unavailable".

**Needs:** Step 2.

**Do:**

1. Quit any running "AgentTacho Demo" instance.
2. Run `open "build/AgentTacho Demo.app"`.
3. Click the AgentTacho Demo item in the menu bar to open the dropdown.

**What you should see:** both Claude Max sections ("Work" and "Personal") list "7-day" and "Fable" rows and no "5-hour" row; the ● sits on the "Fable" row and the menu bar entry for Claude Max shows the tag "Fable" before its percent. The Codex section still lists "5-hour" and "weekly". Clicking the "7-day" row moves the ● there and the tag disappears from the bar.

**If you see something else:** a "5-hour" row in the Claude section means the scenario or the dropdown still uses the fixed pair; a missing tag means the `model:Fable` headline did not resolve.

**Result:**
Passed (user checked in the demo app, started by the agent after quitting the regular AgentTacho): both Claude Max sections show "7-day" and "Fable" with no 5-hour row, the bar shows the Fable tag, the 7-day click moves the ●, Codex still shows 5-hour and weekly.

### Step 4 of 6: Play the variants scenario with an unknown window (US2)

**Why this step:** a window kind AgentTacho does not know yet must still show up, named from its group, without pace.

**Needs:** Step 2.

**Do:**

1. Quit "AgentTacho Demo".
2. Run `open "build/AgentTacho Demo.app" --args -demoScenario variants`.
3. Open the dropdown and find the Claude section.

**What you should see:** a row named "daily" with a percent, a bar and a reset time, placed after the "7-day" row and before any model limit, and no pace note under it.

**If you see something else:** no "daily" row means the variants scenario or the list ordering lost the unknown group; a pace note under it means a window without a length got a pace.

**Result:**
Passed (user checked; the agent started the demo with `-demoScenario variants`): a "daily" row with percent, bar and reset time after 7-day and before the model limits, without a pace note.

### Step 5 of 6: Check the window log line in the real app (US1)

**Why this step:** the diagnostic log must say which window kinds Anthropic reported, so the next API change can be diagnosed from the log.

**Do:**

1. Quit "AgentTacho Demo" and any installed AgentTacho.
2. Run `make run` (builds and opens the real app with your accounts).
3. Wait until the dropdown shows values, then run the command below.

**Run:**

```
rg "windows .*\((limits|fallback)\)|=ok\(" ~/Library/Logs/agenttacho/usage.log | tail -3
```

**What you should see:** a line like `[subscription] <account id>: windows weekly_all/weekly/none, weekly_scoped/weekly/model:Fable (limits)` and a summary like `<account id>=ok(7-day 11%, Fable 15%)`, with no percents in the `windows` line. The real dropdown shows no "5-hour" row for Claude.

**If you see something else:** `(fallback)` means the answer carried no usable `limits` list; no line at all means no successful fetch yet (check the state line in the dropdown).

**Result:**
Passed (agent ran `make run` and the grep; user checked the dropdown). Expected vs actual: ✔ `[subscription] <account id>: windows weekly_all/weekly/none, weekly_scoped/weekly/model:Fable (limits)`, no percents; ✔ `=ok(7-day 17%, Fable 15%)` (the old app logged `ok(5h n/a, 7d 17%)` minutes before); ✔ no 5-hour row in the real dropdown. The first grep ran before the new build's first fetch and showed only old lines.

### Step 6 of 6: Check the saved values file keeps both formats (US3)

**Why this step:** the new list must be saved, and the older fields must stay so an earlier AgentTacho still reads the file after a downgrade.

**Needs:** Step 5.

**Run:**

```
jq '.version, (.claude[] | {windows: [.windows[]?.identity], legacy7d: (.sevenDay != null), legacyModels: (.modelLimits | length)})' ~/Library/Application\ Support/agenttacho/last-good.json
```

**What you should see:** `1`, then for the Claude account `windows` listing `"sevenDay"` and `"model:Fable"`, `legacy7d: true` and `legacyModels: 1`.

**If you see something else:** no `windows` key means the file was not rewritten yet (it is written only after values change); a missing `sevenDay` means the downgrade fields were dropped.

**Result:**
Passed (agent run). Expected vs actual: ✔ `1`; ✔ `windows` `["sevenDay", "model:Fable"]`; ✔ `legacy7d: true`; ✔ `legacyModels: 1`.

## Not covered here

- Screenshots and the website copy (spec FR-021): the capture run needs the maintainer's go and changes the Mac's appearance, so it is not part of this journey.
- A real returning 5-hour window: Anthropic does not send one today; the unit tests and the variants scenario cover it.

## Coverage

- US1 (no dead 5-hour row): steps 1, 3, 5.
- US2 (new or returning window): steps 1, 3 (headline switch), 4.
- US3 (existing settings keep working): steps 1, 5 (your real configuration loads), 6.
- US4 (older answer shape): step 1 only; the endpoint does not send that shape today.

## Results

6 steps: 6 passed, 0 failed, 0 skipped (2026-11-02).

The tests pass (2452 UsageCore, 74 DemoMode; the first two runs each hit a load-sensitive spec 038 test, recorded in the idea inbox). The demo shows the Claude sections without a 5-hour row, with the Fable headline tag, and a window of an unknown group ("daily") appears without a pace note. With the real account, Anthropic's answer is read from `limits` (log: `weekly_all/weekly/none, weekly_scoped/weekly/model:Fable (limits)`, summary `ok(7-day 17%, Fable 15%)`), the dropdown has no dead 5-hour row, and `last-good.json` holds the new window list next to the legacy fields an older version reads.
