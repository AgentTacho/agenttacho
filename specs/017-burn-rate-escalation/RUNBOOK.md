---
runbook_version: 1
feature: 017-burn-rate-escalation
status: passed
mode: light
steps_total: 9
step_results: passed,passed,passed,skipped,passed,passed,passed,passed,passed
drafted_at: 1cef226
drafted_fingerprint: 2f0c1594e516d337dd1d39d7d252b20e715cf88bf0610d42b94c425dcab68f2b
tested_at: 27429b2
tested_fingerprint: 2f0c1594e516d337dd1d39d7d252b20e715cf88bf0610d42b94c425dcab68f2b
updated: 2026-10-16
---

# Try it: Burn Rate Escalation

<!-- runbook-status -->
> **Status:** passed · 9 of 9 steps (8 passed, 1 skipped) · Mode: light · Tested at 27429b2 · 2026-10-16
<!-- /runbook-status -->










## What you're testing

An entry that burns at least twice as fast as its remaining time allows (it would run out in half the time left or less) now shows `↑` in the menu bar instead of `↗`. Two rates can trigger it: the average since the window started, and the recent rate over the last 60 minutes, measured from observations AgentMeter keeps in memory. The dropdown pace meter's tooltip then reads "<delta> · burning fast · runs out <time>", and VoiceOver reads "burning fast, projected to run out well before reset". The Menu Bar tab toggle now reads "Show ↗ or ↑ when an entry will run out before it resets".

Order of the journey: tests, backup and build, the average-rate escalation (forced with a temporary budget amount), the recent-rate escalation (a real burst), the toggle, accessibility text, no new files or requests, restore.

All commands run from the repository root of the feature worktree (`.claude/worktrees/017-burn-rate-escalation`, or `main` after merge). The app reads your real configuration, so Step 2 backs it up and the last step restores it.

## Test environment

No fixtures. Needs the Xcode Command Line Tools, `jq`, and a configuration with at least one budget (for example the monthly "Vertex" group). The single-instance check stops a second copy, so Step 2 quits the running AgentMeter first. Step 4 needs an agent session that spends against that budget for about 20 to 40 minutes.

## Steps

### Step 1 of 9: Run the test suite (US1, US2, US3)

**Why this step:** The rates, the observation rules (lookback, minimum span and change, discards) and the marker decision are pure logic with unit tests, including the spec's worked numbers.

**Run:**

```
make test 2>&1 | tail -1
```

**What you should see:** `Test run with 1031 tests in 105 suites passed` (or more tests).

**If you see something else:** A failing `BurnRateTests`, `ObservationLogTests` or `BarLayoutTests` test names the rule that broke.

**Result:** passed (run by the agent).

- ✔ 1031 tests or more → `Test run with 1031 tests in 105 suites passed after 0.435 seconds.`

### Step 2 of 9: Back up the configuration, build and start the app (US2)

**Why this step:** Steps 3 to 5 change a budget amount and the marker setting in your real configuration; the backup lets Step 9 undo everything.

**Run:**

```
mkdir -p specs/017-burn-rate-escalation/.walkthrough && cp ~/.config/agentmeter/config.json ~/.config/agentmeter/config.json.bak-017 && ls ~/.config/agentmeter > specs/017-burn-rate-escalation/.walkthrough/files-before.txt && osascript -e 'tell application id "dev.rhuss.agentmeter" to quit'; make app 2>&1 | tail -1 && open build/AgentMeter.app
```

**What you should see:** `Built build/AgentMeter.app`, and AgentMeter appears in the menu bar.

**If you see something else:** An "AgentMeter is already running" alert means the quit did not finish; choose "Stop It and Start This One".

**Result:** passed (run by the agent).

- ✔ `Built build/AgentMeter.app` → `Built build/AgentMeter.app`
- ✔ AgentMeter in the menu bar → process running; its status item reads "Claude Code (Max) 6%  Codex (Plus) 4%  Vertex over limit 528%".

### Step 3 of 9: Escalate through the average rate (US2, US3)

**Why this step:** An entry far enough ahead of even use burns fast at its average rate; this needs no observations, so it works right after launch.

**Do:**

1. Open the dropdown and hover the budget's pace meter. Note the expected share E: the shown percent minus the tooltip's delta (for example 48% at "19% ahead" gives E = 29).
2. Settings > Groups: change the budget amount so its percent is at or above 200 x E / (100 + E) (for E = 49 that is 66%), still below its 80% warning threshold, and at least 10% of the window has elapsed.
3. Look at the menu bar and hover the budget's pace meter.
4. Change the amount so the percent lies between E + 6 and that limit (for E = 49, for example 58%).

**What you should see:** After 3, the budget's bar entry shows its percent followed by `↑`, and the meter is orange with the tooltip "N% ahead · burning fast · runs out <time>". After 4, the entry shows `↗` instead, and the tooltip reads "N% ahead · runs out <time>" without "burning fast".

**If you see something else:** `↗` after 3 means the average rule did not escalate (FR-006); `↑` after 4 means the factor of 2 is not applied (FR-005).

**Result:** passed (amount changes run by the agent through `config.json` with `jq` instead of Settings, which the app reloads at its next refresh; tooltip and glyph checked by the user).

Vertex had spent 1583.26 USD in the window 30 Sep 22:00 UTC to 31 Oct 23:00 UTC; at 08:13 UTC on 16 Oct the expected share E was about 49.7%, so the `↑` limit was 200 x E / (100 + E) = 66.4%.

- ✔ Amount 2199 USD (72%): bar shows `↑` → status item read "Vertex 72%, burning fast, projected to run out well before reset"; user saw `72%↑` and the orange tooltip "N% ahead · burning fast · runs out <time>".
- ✔ Amount 2639 USD (60%): bar shows `↗` → status item read "Vertex 60%, projected to run out before reset"; user saw `60%↗` and a tooltip without "burning fast".

### Step 4 of 9: Escalate through a recent burst (US1, US3)

**Why this step:** A burst can burn fast while the overall pace is still on pace or behind, or inside the 10% hold back; only the recent rate over the last 60 minutes sees it.

**Do:**

1. Pick a window that moves with your own work and is not at a warning level. A Claude 7-day window shortly after its weekly reset works well: its sustainable rate is below one point per hour, and it is inside the hold back, so the average rate cannot escalate it. Note its percent and the time.
2. Keep working with Claude Code until the 7-day percent has risen by at least 2 points, at least 15 minutes after the first note.
3. Look at the menu bar and hover the window's pace meter in the dropdown.

**What you should see:** Once the value has risen 2 points or more over at least 15 minutes, and that rate is at least twice the sustainable rate, the Claude entry shows `↑` and its 7-day tooltip reads "on pace · burning fast · runs out <time>" (or "N% behind", "N% ahead"). About an hour after the burst ends, the `↑` disappears.

**If you see something else:** No `↑` after a 2-point rise within 15 to 60 minutes means the recent rate did not qualify; a reset in between discards the observations (FR-003).

**Result:** skipped (stopped by the user before the burst condition was reached).

The agent noted the Claude 7-day window at 6% at 08:39 UTC and polled the status item once a minute; up to 08:56:48Z ClUTC the value stayed at 6%, so no 2-point rise happened. The original Vertex variant was replaced with this Claude variant (a 2-point rise on Vertex would have needed about 80 USD of spend within an hour). The recent-rate trigger is covered by `ObservationLogTests`, `BurnRateTests` and the coordinator test in Step 1.

### Step 5 of 9: Turn both markers off and undo (US3)

**Why this step:** One toggle covers `↗` and `↑`; the dropdown keeps its text.

**Do:**

1. With an entry showing `↑` or `↗`, open Settings > Menu Bar and read the toggle's label.
2. Turn it off, apply, and look at the bar, the preview and the dropdown tooltip.
3. Run the command below, then choose Undo in Settings.

**Run:**

```
jq '.showsRunOutMarker' ~/.config/agentmeter/config.json
```

**What you should see:** The label reads "Show ↗ or ↑ when an entry will run out before it resets". After turning it off, no entry in the bar or the preview shows `↑` or `↗`, while the tooltip still says "burning fast" where it did; the command prints `false`. After Undo, the marker is back.

**If you see something else:** The old label "Show ↗ when an entry will run out before it resets" means the label change is missing (FR-010).

**Result:** passed (toggle and Undo done by the user in Settings, command and bar text read by the agent).

- ✔ Label "Show ↗ or ↑ when an entry will run out before it resets" → confirmed by the user.
- ✔ Toggle off: no marker in bar and preview, tooltip unchanged → user confirmed; `jq` printed `false`; status item read "… Vertex 60%" without "projected to run out".
- ✔ Undo brings the marker back → `jq` printed `true`; status item read "Vertex 60%, projected to run out before reset".

### Step 6 of 9: Accessibility text (US3)

**Why this step:** The arrow is a glyph; VoiceOver users need it in words (FR-011).

**Do:**

1. Make an entry show `↑` again (Step 3, item 2).
2. Open Accessibility Inspector (Xcode > Open Developer Tool > Accessibility Inspector) or turn on VoiceOver, and point it at the AgentMeter menu bar item.

**What you should see:** The label contains the entry's name, its percent and ", burning fast, projected to run out well before reset", without the `↑` glyph.

**If you see something else:** ", projected to run out before reset" alone means the fast wording is missing.

**Result:** passed (run by the agent: amount set back to 2199 USD through `config.json`, label read through System Events, the accessibility API VoiceOver uses).

- ✔ Label with name, percent and ", burning fast, projected to run out well before reset" → "Vertex 72%, burning fast, projected to run out well before reset"
- ✔ No `↑` glyph in the label → none

### Step 7 of 9: A warning level suppresses the arrow (US2)

**Why this step:** Once the warning threshold is reached, `⚠` takes over (FR-009).

**Do:**

1. Settings > Groups: lower the amount until the percent is at or above 80% and below 100%.
2. Look at the menu bar.

**What you should see:** The entry shows `⚠` before its percent (with symbols on) or the warning color, and neither `↑` nor `↗`.

**If you see something else:** `↑` together with the warning level means the suppression rule is broken.

**Result:** passed (run by the agent: amount set to 1799 USD through `config.json`, bar read through System Events).

- ✔ Warning level and no arrow → status item read "Vertex warning 88%", without a run-out suffix, so neither `↑` nor `↗` is shown.

### Step 8 of 9: No new files or requests (US1, US2, US3)

**Why this step:** Observations live in memory only; the security statement stays true (FR-013).

**Run:**

```
ls ~/.config/agentmeter | diff specs/017-burn-rate-escalation/.walkthrough/files-before.txt - && echo "no new files"; tail -5 ~/Library/Logs/agentmeter/usage.log
```

**What you should see:** `no new files` (the backup `config.json.bak-017` was listed before, so it does not count), and the log tail shows only the usual refresh lines.

**If you see something else:** A new file in the listing or unfamiliar request lines would contradict FR-013.

**Result:** passed (run by the agent).

- ✔ `no new files` → `no new files`
- ✔ Only the usual refresh lines → the tail showed `codexLimits ok`, the Vertex group line, `refresh done … endpoint fetched` and a threshold notification (Vertex crossed 80% because of the test amount from Step 7, an existing feature); no new request or file lines.

### Step 9 of 9: Restore your configuration (US2)

**Why this step:** Puts back the configuration from before the walkthrough.

**Run:**

```
cp ~/.config/agentmeter/config.json.bak-017 ~/.config/agentmeter/config.json && jq -c '[.groups[] | {name, budgetUSD}], .showsRunOutMarker' ~/.config/agentmeter/config.json
```

**What you should see:** Your original group amounts and the original marker setting (`null` when the key was not in the file). The running app picks up the file at its next refresh.

**If you see something else:** `No such file` means Step 2's backup was not made.

**Result:** passed (run by the agent).

- ✔ Original amounts and marker setting → `[{"name":"Vertex","budgetUSD":300}]` and `true` (the value before the walkthrough). The backup `config.json.bak-017` stays in `~/.config/agentmeter`.

## Not covered here

- Claude subscription windows and Codex plan windows: their percent cannot be steered by hand, so the journey uses a budget. The same rules are covered for every window kind by the unit tests in Step 1 (SC-002).
- A price import landing during a refresh: timing-dependent, covered by a coordinator test.

## Coverage

- US1 (recent burst): Steps 1 and 4.
- US2 (average escalation, suppression): Steps 1, 3 and 7.
- US3 (tooltip, toggle, accessibility): Steps 3 to 6.

## Results

9 steps: 8 passed, 0 failed, 1 skipped (Step 4, the recent burst, stopped by the user before the Claude 7-day value rose 2 points).

The walkthrough showed in the running app that an entry burning at least twice as fast as its remaining time allows gets `↑` (Vertex at 72% with about 50% of the month elapsed), that an entry ahead but below that rate keeps `↗` (60%), that the tooltip names the fast burn, that one toggle with the new label turns both markers off without touching the dropdown, that VoiceOver reads ", burning fast, projected to run out well before reset", that a warning level suppresses the arrow, and that no files or requests were added. The recent-rate trigger was verified by the test suite only.
