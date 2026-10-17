---
runbook_version: 1
feature: 019-pace-line-names-plan
status: drafted
mode: light
steps_total: 6
step_results: pending,pending,pending,pending,pending,pending
drafted_at: e8313f8
drafted_fingerprint: 97888687c2ec1d42646c84a6709377c2dfcec7d7e58e0ff3d2513fdf830cafc3
tested_at:
tested_fingerprint:
updated: 2026-10-16
---

# Try it: Pace Line Names the Plan

<!-- runbook-status -->
> **Status:** drafted · 0 of 6 steps · Mode: light · Drafted at e8313f8 · 2026-10-16
<!-- /runbook-status -->

## What you're testing

With adaptive refresh on, the dropdown's pace line now names the slowed plan. If you work with Claude Code while Codex is idle, it reads "Codex limits next checked at 13:57 (no Codex activity)" instead of the confusing "Plan limits next checked at 13:57 (no agent activity)".

Order of the journey: tests, start this build, wait until the Codex pace stretches, read the line, cross-check the diagnostic log, VoiceOver, back to the installed app.

All commands run from the root of the feature worktree (`.claude/worktrees/019-pace-line-names-plan`, or `main` after merge).

## Test environment

No fixtures. Needs adaptive refresh on (Settings > General), a Claude subscription account and a Codex subscription account with live limits (yours: "Claude Code (Max)" and "Codex (Plus)"), Claude Code in use and Codex idle. The pace starts at the base after launch and needs at least two quiet Codex checks to stretch, so Step 3 waits about 15 minutes.

## Steps

### Step 1 of 6: Run the test suite (US1)

**Why this step:** Every wording variant (one plan, both plans, timer reasons, other day, 12 hour time) is `UsageCore` logic with tests.

**Run:**

```
make test 2>&1 | tail -1
```

**What you should see:** `Test run with 1380 tests in ... suites passed` (or more tests).

**If you see something else:** a failing `RefreshPaceStatusTests` test names the wording rule that broke.

**Result:**

### Step 2 of 6: Start this build instead of the installed app (US1)

**Why this step:** The installed 0.4.1 still has the old wording; only one AgentTacho can run at a time.

**Run:**

```
osascript -e 'quit app "AgentTacho"'; make run 2>&1 | tail -2
```

**What you should see:** `Built build/AgentTacho.app` and `open "build/AgentTacho.app"`, then the AgentTacho icon in the menu bar.

**If you see something else:** a build error means the branch does not compile; stop here.

**Result:**

### Step 3 of 6: Wait until the Codex pace stretches (US1)

**Why this step:** The pace starts at the base after launch; it stretches only after Codex checks that see no Codex activity.

**Run:**

```
sleep 900; rg "pace: codex interval" ~/Library/Logs/agenttacho/usage.log | tail -1
```

**What you should see:** after about 15 minutes, a recent line such as `[refresh] pace: codex interval 600 s (no agent activity)` (or 1200 s), timestamped after Step 2.

**If you see something else:** no recent line means Codex was active (a Codex session file changed) or adaptive refresh is off; check Settings > General.

**Result:**

### Step 4 of 6: Read the pace line (US1)

**Why this step:** The point of the feature: the line names the slowed plan and the agent whose activity is missing (spec FR-001).

**Do:**

1. Open the AgentTacho dropdown.
2. Read the line under "Last refreshed".

**What you should see:** "Codex limits next checked at <time> (no Codex activity)"; your Claude rows keep updating. If Claude Code was also quiet long enough, "Claude and Codex limits next checked at <time> (no agent activity)". The line is never cut off with "…".

**If you see something else:** "Plan limits next checked at … (no agent activity)" means the old build is running.

**Result:**

### Step 5 of 6: Listen with VoiceOver (US1)

**Why this step:** VoiceOver reads the same text as the screen (spec FR-005).

**Do:**

1. Turn on VoiceOver (Cmd-F5, or fn-Cmd-F5 on a MacBook, or triple-press Touch ID while holding Cmd).
2. Open the dropdown and move the VoiceOver cursor to the pace line (Control-Option-arrow keys).
3. Turn VoiceOver off the same way.

**What you should see:** VoiceOver reads "Codex limits next checked at … (no Codex activity)".

**If you see something else:** a different text than the screen shows means the accessibility text diverged.

**Result:**

### Step 6 of 6: Return to the installed app (US1)

**Why this step:** Leaves your Mac running the installed AgentTacho again.

**Run:**

```
osascript -e 'quit app "AgentTacho"'; sleep 2; open -a /Applications/AgentTacho.app && sleep 3 && pgrep -lf "AgentTacho.app/Contents/MacOS"
```

**What you should see:** one process line with `/Applications/AgentTacho.app/Contents/MacOS/AgentTacho`.

**If you see something else:** a path under `build/` means the build is still running; quit it from the dropdown's gear menu.

**Result:**

## Not covered here

- **Both plans slowed with a 12 hour clock on another day (FR-007, longest line):** needs a next check after midnight; covered by `RefreshPaceStatusTests` for the text, and the wrapping can be seen whenever the line is long.
- **Timer reasons (FR-003):** away, Low Power Mode and high temperature keep today's wording; covered by tests.

## Coverage

- **US1 (the pace line says which plan is slowed):** Steps 1, 3, 4 and 5.

## Results
