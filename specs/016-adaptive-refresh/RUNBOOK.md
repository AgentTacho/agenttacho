---
runbook_version: 1
feature: 016-adaptive-refresh
status: passed
mode: light
steps_total: 12
step_results: passed,passed,passed,passed,passed,skipped,skipped,skipped,passed,passed,passed,passed
drafted_at: 66ce9f5
drafted_fingerprint: 4a8a118f8617afdaaf857a6fc3059d1178c8edaacb3d2487a962dd2308a934a7
tested_at: d027671
tested_fingerprint: c530193b83a71115ea37ca70eea87e3ac3767f7d52533d609fdf11950d90eb22
updated: 2026-10-16
---

# Try it: Adaptive Refresh

<!-- runbook-status -->
> **Status:** passed · 12 of 12 steps (9 passed, 3 skipped) · Mode: light · Tested at d027671 · 2026-10-16
<!-- /runbook-status -->













## What you're testing

AgentMeter no longer refreshes on a blind fixed timer. With "Adapt refresh" on (the default), it refreshes when you open the menu, calls the Claude and Codex usage endpoints less often while no agent writes new usage, slows the whole timer while you are away or the Mac is in Low Power Mode, and says so in one line of the dropdown. Turning the toggle off restores the old fixed timer.

The journey: run the tests, start the build from this branch and watch its log, check the new setting, open the menu to see the refresh on open, let the agents rest so the endpoint pace stretches, read the pace line, wake an agent to see the pace snap back, try Low Power Mode and a screen lock, then turn the feature off and restore your normal app.

Important: this feature watches your own agent activity. While you follow the runbook, a running Claude Code or Codex session that keeps working (including an agent helping you with this walkthrough) counts as activity and keeps the pace at the base. For steps 6 and 7, make sure no agent is working.

## Test environment

No fixtures. The steps build the app from this branch with `make app` and run it in place of the installed AgentMeter; the last step restores the installed app. The diagnostic log is AgentMeter's own file `~/Library/Logs/agentmeter/usage.log`.

## Steps

### Step 1 of 12: Run the test suite (US1, US2, US3, US4)

**Why this step:** The pace decisions are pure, tested values; a green suite shows the core rules hold before you look at the app.

**Needs:** Xcode command line tools, run from the worktree root.

**Run:**

```
make test 2>&1 | tail -5
```

**What you should see:** A final line saying the test run passed, with no failures (about 978 tests).

**If you see something else:** A compile error means the branch is not complete; a failing test names the broken rule (look for `AdaptivePace`, `RefreshPaceStatus` or `RefreshCoordinator` in the name).

**Result:** passed (agent). `✔ Test run with 978 tests in 99 suites passed`.

### Step 2 of 12: Start the branch build instead of the installed app (US1)

**Why this step:** AgentMeter runs only once, so the installed copy has to quit before the branch build can start.

**Needs:** Step 1.

**Run:**

```
osascript -e 'quit app "AgentMeter"'; sleep 2; make app && open build/AgentMeter.app && sleep 5 && tail -n 5 ~/Library/Logs/agentmeter/usage.log
```

**What you should see:** The build finishes, the AgentMeter item appears in the menu bar, and the log tail shows a `launch` line followed by a refresh summary line containing `trigger launch`.

**If you see something else:** No new `launch` line means the old instance was still running (quit it from its menu and retry); a build error points to the toolchain.

**Result:** passed (agent). Built 0.3.1-dev build 121; `07:31:57Z [app] launch, AgentMeter 0.3.1-dev (build 121)`, `07:32:03Z [refresh] done ... trigger launch, endpoint fetched`.

### Step 3 of 12: Find the new setting (US4)

**Why this step:** The feature is on by default and has exactly one control.

**Needs:** Step 2.

**Do:**

1. Open the AgentMeter menu, click the gear, choose "Settings…".
2. Open the General tab.

**What you should see:** Directly below the refresh interval, a checked toggle "Adapt refresh" with the caption "Refresh when the menu opens; check plan limits less often while no agent runs, while you are away or while the Mac saves power (still at least every 30 minutes)."

**If you see something else:** A missing toggle means the running app is not the branch build (repeat step 2).

**Result:** passed (user). Checked toggle with the caption shown directly below the interval.

### Step 4 of 12: Open the menu after a minute (US1)

**Why this step:** Opening the dropdown should fetch current values when the last endpoint call is at least 60 seconds old.

**Needs:** Step 2, at least one Claude subscription account or Codex account with live limits, and at least 60 seconds since the launch refresh.

**Do:**

1. Wait until at least one minute has passed since step 2.
2. Close Settings, then click the AgentMeter menu bar item once.
3. Run the command below.

**Run:**

```
rg "trigger dropdownOpen" ~/Library/Logs/agentmeter/usage.log | tail -n 1
```

**What you should see:** One refresh summary line with `trigger dropdownOpen, endpoint fetched`, stamped at the moment you opened the menu.

**If you see something else:** No line at all means `.onAppear` did not fire on opening (the plan's fallback is a window notification, research R9); `endpoint reused (last fetch ... s ago)` means less than 60 s had passed.

**Result:** passed (agent, after a fix). First run failed: only the first opening refreshed (`07:33:08Z ... trigger dropdownOpen`), later openings well past 60 s did not, because the MenuBarExtra keeps its content alive and `.onAppear` fires once. Fixed with the research R9 fallback (`NSWindow.didBecomeKeyNotification` on the panel, commit d027671). Retry: `07:37:59Z` and `07:40:39Z ... trigger dropdownOpen, endpoint fetched` for two openings.

### Step 5 of 12: Reopen right away (US1)

**Why this step:** Opening again within a minute must not call the endpoints a second time.

**Needs:** Step 4.

**Do:**

1. Close the menu and open it again within a few seconds.
2. Run the command below.

**Run:**

```
rg "trigger dropdownOpen" ~/Library/Logs/agentmeter/usage.log | tail -n 2
```

**What you should see:** Still only the line from step 4 (no new `trigger dropdownOpen` line), because the last call is under 60 seconds old.

**If you see something else:** A second line with `endpoint fetched` means the 60-second spacing is not applied on opening.

**Result:** passed (user and agent). Reopened within seconds; newest dropdownOpen line still 07:40:39, no new refresh.

### Step 6 of 12: Let the agents rest (US2)

**Why this step:** Without new local usage, the endpoint interval should double after each quiet scheduled call (5, 10, 20, 30 minutes at the default 5-minute base) while the local scan keeps running every 5 minutes.

**Needs:** Step 2, no Claude Code, Codex or OpenCode session doing work for about 20 minutes.

**Do:**

1. Stop or pause every agent session.
2. Wait about 20 minutes.
3. Run the command below.

**Run:**

```
rg "pace: |endpoint reused \(adaptive pace" ~/Library/Logs/agentmeter/usage.log | tail -n 8
```

**What you should see:** `pace: claude interval 600 s (no agent activity)` and later `pace: claude interval 1200 s (no agent activity)`, with refresh summary lines between them that say `endpoint reused (adaptive pace, next call ...)`. Codex accounts with live limits show matching `pace: codex interval ...` and `pace: codex reused (adaptive pace, next call ...)` lines.

**If you see something else:** `pace: claude interval back to base (activity)` means an agent wrote usage during the wait (check for a busy session).

**Result:** skipped. Needs about 20 minutes without any agent activity, not possible while other sessions were working on the project; covered by the P1 and SC-001 tests.

### Step 7 of 12: Read the pace line (US4)

**Why this step:** The dropdown should explain why plan limits are older than the last refresh and when they are checked next.

**Needs:** Step 6 (a stretched pace).

**Do:**

1. Open the AgentMeter menu and look at the footer under "Last refreshed".
2. If the opening started a refresh (the last call was more than a minute ago), close and reopen the menu after a few seconds to see the updated line.

**What you should see:** One line `Plan limits next checked at HH:MM (no agent activity)`, with a time in the future. A refresh on opening calls the endpoints but keeps the stretched interval, so the line moves to the new call time plus that interval; it never shows a past time.

**If you see something else:** No line means every pace is at the base again (an agent ran); a past time is a bug (contract row L6).

**Result:** skipped. Depends on the stretched pace of step 6; the pace line text is covered by RefreshPaceStatusTests L1 to L6.

### Step 8 of 12: Wake an agent (US2)

**Why this step:** One new usage record should bring the endpoint pace back to the base at the next scheduled refresh.

**Needs:** Step 6, the `claude` command signed in to a subscription account that AgentMeter shows.

**Run:**

```
claude -p "Reply with the single word ok" && sleep 330 && rg "pace: claude interval back to base|trigger scheduled, endpoint fetched" ~/Library/Logs/agentmeter/usage.log | tail -n 2
```

**What you should see:** After about five and a half minutes, `pace: claude interval back to base (activity)` and a refresh summary line with `trigger scheduled, endpoint fetched`.

**If you see something else:** Only `endpoint reused (adaptive pace ...)` lines mean the new record was not seen as activity (check that the prompt wrote to a Claude Code directory AgentMeter scans).

**Result:** skipped. Depends on step 6; covered by the P2 and SC-002 tests.

### Step 9 of 12: Turn on Low Power Mode (US3)

**Why this step:** While the Mac saves power, the whole timer should run at twice the base.

**Needs:** Step 2.

**Do:**

1. Open System Settings > Battery and set Low Power Mode to "Always".
2. Run the command below, then open the AgentMeter menu and read the footer.
3. Set Low Power Mode back to your usual setting.

**Run:**

```
rg "conditions: |pace: timer" ~/Library/Logs/agentmeter/usage.log | tail -n 3
```

**What you should see:** `conditions: idle=false, lowPower=true, thermal=false` followed by `pace: timer 600 s (Low Power Mode)`; the dropdown line names Low Power Mode. After switching it back, `pace: timer back to base 300 s`.

**If you see something else:** No `conditions:` line means the power state notification was not observed.

**Result:** passed (user and agent). `07:43:49Z [app] conditions: idle=false, lowPower=true, thermal=false`, `07:43:49Z [refresh] pace: timer 600 s (Low Power Mode)`; dropdown line ended in `(Low Power Mode)`; switched back: `07:44:30Z [refresh] pace: timer back to base 300 s`.

### Step 10 of 12: Lock the screen and come back (US3)

**Why this step:** A locked screen counts as idle (timer 30 minutes); unlocking should trigger one refresh within a minute.

**Needs:** Step 2, at least one minute since the last endpoint call.

**Do:**

1. Press Control-Command-Q to lock the screen and wait about a minute.
2. Unlock, wait one more minute, then run the command below.

**Run:**

```
rg "conditions: |pace: timer|trigger idleReturn" ~/Library/Logs/agentmeter/usage.log | tail -n 5
```

**What you should see:** `conditions: idle=true, ...` and `pace: timer 1800 s (idle)` at the lock, then `conditions: idle=false, ...`, `pace: timer back to base 300 s` and a refresh summary line with `trigger idleReturn` after unlocking.

**If you see something else:** A missing `trigger idleReturn` with `pace: return from idle right after wake, no extra refresh` is correct when the Mac also slept and woke (the wake refresh covered it).

**Result:** passed (user and agent). Lock: `07:45:11Z conditions: idle=true`, `pace: timer 1800 s (idle)`; unlock: `07:49:19Z conditions: idle=false`, `pace: timer back to base 300 s`, `07:49:22Z ... trigger idleReturn, endpoint fetched`.

### Step 11 of 12: Turn the feature off (US4)

**Why this step:** With the toggle off, AgentMeter must behave exactly as before: fixed timer, no refresh on opening, no pace line.

**Needs:** Step 3.

**Do:**

1. In Settings > General, uncheck "Adapt refresh".
2. Wait a minute, open the AgentMeter menu, and check that the footer has no pace line.
3. Run the command below.

**Run:**

```
rg "pace: adaptive refresh|trigger dropdownOpen|conditions: " ~/Library/Logs/agentmeter/usage.log | tail -n 3
```

**What you should see:** `pace: adaptive refresh off` as the newest of these lines: no `trigger dropdownOpen` and no `conditions:` line after it, because the system state is no longer read while the toggle is off.

**If you see something else:** A `trigger dropdownOpen` line after the switch means the toggle does not reach the app; a `conditions:` line after it means the system state monitor kept running.

**Result:** passed (user and agent). `07:50:58Z [refresh] pace: adaptive refresh off`, then no dropdownOpen refresh and no `conditions:` line; no pace line in the footer.

### Step 12 of 12: Restore your normal setup

**Why this step:** Leave the toggle as you want it and go back to the installed app.

**Needs:** Step 11.

**Do:**

1. In Settings > General, turn "Adapt refresh" back on if you want to keep it (the setting is in your shared configuration file).
2. Run the command below.

**Run:**

```
osascript -e 'quit app "AgentMeter"'; sleep 2; open -a AgentMeter
```

**What you should see:** The installed AgentMeter starts again in the menu bar. It ignores the `adaptiveRefresh` key until it is updated to a version with this feature.

**If you see something else:** If `open -a AgentMeter` cannot find the app, start it from the Applications folder.

**Result:** passed (agent). Installed `/Applications/AgentMeter.app` running again: `07:54:57Z [app] launch, AgentMeter 0.3.1 (build 74)`.

## Not covered here

- High thermal pressure (FR-009): it cannot be triggered on demand without stressing the machine; the rule shares its code path with Low Power Mode (step 9) and is covered by `AdaptivePaceTests`.
- Rate-limit interaction (FR-014) and the backwards clock edge case: not reproducible by hand without forcing the usage service to answer 429 or changing the system clock; covered by `RefreshCoordinatorTests` and `AdaptivePaceTests`.
- The full 30-minute cap and the 2-hour call count (SC-001): would need two hours of waiting; covered by the P1 test.

## Coverage

- US1 (current numbers when I look): steps 4 and 5.
- US2 (fewer endpoint calls while no agent works): steps 6 and 8.
- US3 (slower timer while away or saving power): steps 9 and 10; thermal pressure only in tests.
- US4 (know what the refresh is doing, turn it off): steps 3, 7 and 11.

## Results

12 steps: 9 passed (step 4 after a fix during the run), 0 failed, 3 skipped (steps 6 to 8 need 20 idle minutes without any agent). The walkthrough found one real bug: the refresh on opening the menu ran only on the first opening per launch (step 4), fixed in commit d027671 and confirmed by the retry. Opening the menu refreshes with 60 s spacing, Low Power Mode and a screen lock slow the timer and log it, unlocking refreshes within seconds, the dropdown names the reason, and turning the toggle off stops the open refresh and the system state reads. The endpoint pace stretching (US2) was not tried by hand and rests on the automated tests.
