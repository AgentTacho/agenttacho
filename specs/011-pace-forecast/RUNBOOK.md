---
runbook_version: 1
feature: 011-pace-forecast
status: passed
mode: light
steps_total: 9
step_results: passed,passed,passed,passed,passed,passed,passed,passed,passed
drafted_at: 342bfb5
drafted_fingerprint: 1e08c6b587b1aa394ff02147f97680f4d8686d548b8b99bb9b7200e6fa3c930a
tested_at: 8ac7049
tested_fingerprint: a3e11aec209cc20967ee861678c5aae4a72b565088ccd63b76504a9b94a68967
updated: 2026-10-16
---

# Try it: Pace Forecast

<!-- runbook-status -->
> **Status:** passed · 9 of 9 steps (9 passed) · Mode: light · Tested at 8ac7049 · 2026-10-16
<!-- /runbook-status -->










## What you're testing

Every window and budget in the dropdown gets a pace meter at the end of its row (a tick for even use, a bar left of it when behind, right of it when ahead, orange when it runs out before the reset; hovering shows "on pace", "N% ahead" or "N% behind", plus "· runs out <time>"), and the menu bar marks an entry that will run out before its reset with `↗`. A toggle in the Menu Bar tab turns the marker off.

Order of the journey: tests, backup and build, the pace meters in the dropdown, a hand check of the budget's numbers, the bar marker (forced with a temporary lower budget), the toggle and Undo, accessibility text, no new files or requests, restore.

All commands run from the repository root of the feature worktree (`.claude/worktrees/011-pace-forecast`, or `main` after merge). The app reads your real configuration, so Step 2 backs it up and the last step restores it.

## Test environment

No fixtures. Needs the Xcode Command Line Tools, `jq` and `python3`, and a configuration with at least one subscription account and one budget (yours has the monthly "Vertex" group with 300 US dollars). The single-instance check stops a second copy, so Step 2 quits the running AgentMeter first.

## Steps

### Step 1 of 9: Run the test suite (US1, US2, US3)

**Why this step:** The pace rules (expected share, band, hold back, exclusions, run-out) and the marker decision are pure logic with unit tests.

**Run:**

```
make test 2>&1 | tail -1
```

**What you should see:** `Test run with 729 tests in 79 suites passed` (or more tests).

**If you see something else:** A failing `PaceTests` or `BarLayoutTests` test names the rule that broke.

**Result:** passed (run by the agent).

- ✔ 729 tests or more → `Test run with 729 tests in 79 suites passed after 0.496 seconds.`

### Step 2 of 9: Back up the configuration, build and start the app (US1)

**Why this step:** Step 5 changes a budget amount and Step 6 the marker setting in your real configuration; the backup lets Step 9 undo everything.

**Run:**

```
cp ~/.config/agentmeter/config.json ~/.config/agentmeter/config.json.bak-011 && ls ~/.config/agentmeter > specs/011-pace-forecast/.walkthrough/files-before.txt && osascript -e 'tell application id "dev.rhuss.agentmeter" to quit'; make app 2>&1 | tail -1 && open build/AgentMeter.app
```

**What you should see:** `Built build/AgentMeter.app`, and AgentMeter appears in the menu bar.

**If you see something else:** An "AgentMeter is already running" alert means the quit did not finish; choose "Stop It and Start This One".

**Result:** passed (run by the agent).

- ✔ `Built build/AgentMeter.app`, feature build running (PID 10392 from the worktree), backup `config.json.bak-011` written

### Step 3 of 9: Pace meters in the dropdown (US1, US2)

**Why this step:** The core of the feature: each window and budget says whether it will last until its reset.

**Do:**

1. Wait for the first refresh, then open the dropdown.
2. Look at the end of the Claude "5-hour" and "7-day" rows (and a model limit row, if shown), each Codex window row and the Vertex amount line, and hover over a meter.

**What you should see:** A small meter at the end of each of those rows, no extra lines: a tick alone when on pace, a bar left of the tick when behind, right of it when ahead, longer the further off even use. Hovering shows "on pace", "N% ahead" or "N% behind". An entry more than 5 points ahead and more than 10% into its window has an orange meter whose tooltip adds "· runs out" with a time; all other meters are gray. A window that has not started, a value shown as 100% or more, group member lines and Unassigned have no meter.

**If you see something else:** No meters at all means the dropdown is not built from this branch (check the app path in Step 2).

**Result:** passed (user in the app), after three changes found during this step.

- The first version showed the pace as an extra text line under every row ("18% behind" under 7-day at 80%, 98% of the week elapsed); it took too much space, so the spec (FR-008, FR-010) moved to a meter at the end of the row with the text as tooltip (commit c9ce4e4). This step's text was corrected to match.
- The tooltip only appeared over the drawn bar; the whole meter area is now the hover target (bf79c7e).
- The Fable row's own tooltip hid the meter's; it now covers the text only (8ac7049).
- ✔ meters at the row ends, 7-day and Fable behind, Codex on pace, Vertex (526%) without meter, short pace text on hover → user: as expected

### Step 4 of 9: Check the budget's numbers by hand (US1)

**Why this step:** The pace must match a hand calculation from the shown percent and the window (SC-002).

**Run:**

```
python3 -c "import datetime as d; n=d.datetime.now(); s=n.replace(day=1,hour=0,minute=0,second=0,microsecond=0); e=s.replace(year=s.year+(s.month==12), month=s.month%12+1); print('expected share of the month:', round((n-s)/(e-s)*100,1))"
```

**What you should see:** One line with the expected share of the current month in percent. Once Vertex is below 100% (now, or after Step 5 raises its amount), the Vertex percent shown in the dropdown minus this number, rounded, equals the delta in the pace meter's tooltip within one point ("on pace" when the difference is between -5 and +5).

**If you see something else:** A difference of more than one point means the budget window or the spend share is computed differently than FR-001 and FR-003 say.

**Result:** passed (run by the agent); the comparison with the tooltip follows in Step 5, since Vertex was at 526% and had no meter.

- ✔ one line with the expected share → `expected share of the month: 49.2`
- Runbook corrected during this step: Steps 4 and 5 no longer assume Vertex is below 100%.

### Step 5 of 9: Force the bar marker with a temporary budget amount (US3)

**Why this step:** Your real usage may not be ahead right now, or already over the budget; a different amount puts the Vertex entry ahead of even use while still below its 80% warning threshold.

**Do:**

1. Settings > Groups: select "Vertex" and change the amount (raise it if Vertex is over 100%, lower it if it is far behind) until the percent in the dropdown is about 15 to 25 points above the expected share from Step 4, and still below 80%. Check the tooltip's delta against Step 4's number.
2. Look at the menu bar and the dropdown.
3. Lower the amount until the percent is at or above 80% (and below 100%).

**What you should see:** After 1 and 2, the Vertex entry in the bar shows its percent followed by `↗`, and its dropdown meter is orange with a bar right of the tick; its tooltip reads "N% ahead · runs out" with a time (if less than 10% of the month has passed, there is no run-out and no marker yet). After 3, the bar shows `⚠` before the percent and no `↗`.

**If you see something else:** `↗` together with `⚠` means the marker is not suppressed by the warning level (FR-013).

**Result:** passed (user in the app, config and log checked by the agent).

- The first amount edit was not committed (no Return), so nothing changed; after Return the log showed `1578.4309227 of 2250 USD (70%)`.
- ✔ hand check: 70.15% minus the expected 49.22% gives 21 ahead, run-out about Thu 22 Oct 18:00 → user: `70%↗`, orange meter, tooltip as expected
- ✔ at 1900 (83%): `⚠83%` without `↗` → user: as expected

### Step 6 of 9: Turn the marker off and undo (US3)

**Why this step:** The toggle keeps the bar as minimal as before, and the preview follows it.

**Do:**

1. Set the Vertex amount back to the value from Step 5, item 1 (marker visible).
2. Settings > Menu Bar: look at the preview, then turn off "Mark entries projected to run out before reset" and apply.
3. Run the command below, then choose Undo in Settings.

**Run:**

```
jq '.showsRunOutMarker' ~/.config/agentmeter/config.json
```

**What you should see:** The preview shows `↗` before the toggle is turned off and loses it right after. Once applied, the bar loses `↗` while the dropdown meter stays the same. The command prints `false`. After Undo, `↗` is back in the preview and the bar.

**If you see something else:** `null` means the setting was not saved; the dropdown meter changing means the toggle affects more than the bar.

**Result:** passed (user in the app, config and log checked by the agent).

- ✔ `false` → `false`; log `saved from settings ... display only` (no usage refresh)
- ✔ preview and bar lost `↗`, dropdown meter unchanged, Undo restored `↗` → user: as expected

### Step 7 of 9: Accessibility text (US3)

**Why this step:** The marker is a glyph; VoiceOver users need it in words (FR-015).

**Do:**

1. Open Accessibility Inspector (Xcode > Open Developer Tool > Accessibility Inspector) or turn on VoiceOver.
2. Point it at the AgentMeter menu bar item while the Vertex entry shows `↗`.

**What you should see:** The label contains "Vertex", its percent and ", projected to run out before reset", without the `↗` glyph.

**If you see something else:** The arrow read as a symbol name means the accessibility text still uses the glyph.

**Result:** passed (run by the agent through System Events instead of Accessibility Inspector).

- ✔ "Vertex", its percent and ", projected to run out before reset", no `↗` → title `Claude Code (Max) ⚠81%  Codex (Plus) 14%  Vertex 70%, projected to run out before reset`

### Step 8 of 9: No new files or requests (US1, US2, US3)

**Why this step:** Pace is computed from the snapshot only; the security statement stays true (FR-016).

**Run:**

```
ls ~/.config/agentmeter | diff specs/011-pace-forecast/.walkthrough/files-before.txt - && echo "no new files"; tail -5 ~/Library/Logs/agentmeter/usage.log
```

**What you should see:** `no new files`, and the log tail shows only the usual refresh lines (no new request or file entries).

**If you see something else:** A new file in the listing or unfamiliar log lines would contradict FR-016.

**Result:** passed (run by the agent).

- ✔ `no new files` → `no new files`
- ✔ only usual log lines → tail shows `[config] saved from settings ... display only` entries from the walkthrough's edits, no new request or file categories

### Step 9 of 9: Restore your configuration (US1)

**Why this step:** Puts back the configuration from before the walkthrough.

**Run:**

```
cp ~/.config/agentmeter/config.json.bak-011 ~/.config/agentmeter/config.json && jq -c '[.groups[] | {name, budgetUSD}], .showsRunOutMarker' ~/.config/agentmeter/config.json
```

**What you should see:** `[{"name":"Vertex","budgetUSD":300}]` and `null` (the key was not in the file before). The running app picks up the file at its next refresh.

**If you see something else:** `No such file` means Step 2's backup was not made.

**Result:** passed (run by the agent).

- ✔ `[{"name":"Vertex","budgetUSD":300}]` and `null` → `[{"name":"Vertex","budgetUSD":300}]`, `null`

## Coverage

- US1 (budgets): Steps 3, 4, 5.
- US2 (subscription windows): Step 3 shows the lines; the hand check is done for the budget only, since the windows' reset times come from the providers.
- US3 (bar marker): Steps 5, 6, 7.

## Results

All 9 steps passed. The dropdown shows a pace meter at the end of every Claude, model limit, Codex and budget row; a hand check of the Vertex budget at 2250 USD matched the tooltip (21% ahead, run-out Thu 22 Oct around 18:00), and the bar marked it `70%↗`, gave way to `⚠` at 83%, followed the Menu Bar toggle and Undo, and read "projected to run out before reset" for accessibility. No new files or log categories appeared.

The walkthrough changed the feature: the first version's text line under each row took too much space and became the meter (spec FR-008 and FR-010 updated), the tooltip area was widened, and the model limit row's own tooltip no longer hides the meter's.
