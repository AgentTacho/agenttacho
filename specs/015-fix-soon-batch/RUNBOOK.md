---
runbook_version: 1
feature: 015-fix-soon-batch
status: passed
mode: light
steps_total: 10
step_results: passed,passed,passed,passed,passed,passed,passed,passed,passed,passed
drafted_at: 03c3dbb
drafted_fingerprint: 77ff7151f52634053c5af17beed981986472b14076b40269945e9fcfb5a470fe
tested_at: 81c9bfa
tested_fingerprint: 777f5fd008049176aa34a44a8321ee7fa49d5cf5358af0e18aa521fdf0cd2d19
updated: 2026-10-16
---

# Try it: Fix-Soon Review Batch

<!-- runbook-status -->
> **Status:** passed · 10 of 10 steps (10 passed) · Mode: light · Tested at 81c9bfa · 2026-10-16
<!-- /runbook-status -->











## What you're testing

Seven small fixes from earlier code reviews. Most of them are rules that only show at rare moments: a window reset while the Mac sleeps, a period switch while the session logs cannot be read, an expired Developer ID certificate, or a failed upload during a release replacement. Those are covered by the unit and release tests, which this journey runs first. The part you can try by hand is the hardened OpenCode read: you point AgentMeter at a crafted `opencode.db` whose `message` table is a view, and the app refuses it cleanly while the rest of the dropdown keeps working.

Order of the journey: Swift tests, release script tests, a look at the README changes, config backup, a crafted OpenCode database, build and launch, the diagnostic log line, the dropdown, restore.

All commands run from the root of the feature worktree (`.claude/worktrees/015-fix-soon-batch`, or `main` after merge). The app reads your real configuration, so Step 4 backs it up and the last step restores it.

## Test environment

No fixtures. Needs the Xcode Command Line Tools, `jq`, `sqlite3` (part of macOS) and `rg`. The crafted database lives in this feature's scratch folder `specs/015-fix-soon-batch/.walkthrough/crafted-opencode/`, which ignores itself in git.

## Steps

### Step 1 of 10: Run the Swift test suite (US1, US2)

**Why this step:** The threshold reset rule, the period-mismatch filter, the credential directory scan set, the OpenCode hardening and the Claude request time limit are all `UsageCore` logic with tests.

**Run:**

```
make test 2>&1 | tail -1
```

**What you should see:** `Test run with 914 tests in ... suites passed` (or more tests).

**If you see something else:** A failing `ThresholdTrackerTests`, `BudgetPeriodFilterTests`, `LogIndexTests`, `OpenCodeSourceTests` or `UsageEndpointClientTests` test names the rule that broke.

**Result:** passed (run by the agent). Expected `Test run with 914 tests ... passed` or more; got `Test run with 1351 tests in 132 suites passed` (the rebase on main added the tests of specs 013, 014, 016 and 017).

### Step 2 of 10: Run the release script tests (US3)

**Why this step:** The signing tier guard and the draft-first replacement are tested with stubbed `security` and `gh` tools, because an expired certificate or a real GitHub release cannot be staged safely by hand.

**Run:**

```
make test-release 2>&1 | tail -3
```

**What you should see:** a summary with 200 (or more) passed tests and 0 failures.

**If you see something else:** the failing test name starts with the file it comes from (`test_preflight`, `test_signing`, `test_release_flow`, `test_build_scripts`, `test_makefile`).

**Result:** passed (run by the agent). Expected 200 or more passed and 0 failures; got `208 passed, 0 failed`.

### Step 3 of 10: Check the README statements (US2, US3)

**Why this step:** AGENTS.md requires the "Security and privacy" section to stay true; it now names the time limit, the hardened OpenCode read and the extra scanned directories, and the maintainer section names `ALLOW_TIER_DOWNGRADE`.

**Run:**

```
rg -n "45 seconds|trusted_schema|subscription account's Claude Code directory|ALLOW_TIER_DOWNGRADE=1" README.md
```

**What you should see:** at least four matching lines: one with "give up after 45 seconds", one with `trusted_schema=OFF`, the "Agent session data" table row naming each Claude subscription account's Claude Code directory, and the release paragraph or variable table with `ALLOW_TIER_DOWNGRADE=1`.

**If you see something else:** a missing line means the README was not updated for that requirement (spec 015 FR-011 or FR-013).

**Result:** passed (run by the agent). Four matches: line 142 (`trusted_schema=OFF` in the OpenCode paragraph), line 177 (the Agent session data row with each Claude subscription account's Claude Code directory), line 183 (both requests give up after 45 seconds), line 256 (`ALLOW_TIER_DOWNGRADE=1` in the release paragraph).

### Step 4 of 10: Back up the configuration and quit AgentMeter (US2)

**Why this step:** Step 6 adds an extra OpenCode directory to your real configuration; the backup lets the last step put everything back. Only one copy of AgentMeter can run, so any running one (also from another worktree) is quit first.

**Run:**

```
cp ~/.config/agentmeter/config.json ~/.config/agentmeter/config.json.bak-015 && osascript -e 'quit app "AgentMeter"'; ls -l ~/.config/agentmeter/config.json.bak-015
```

**What you should see:** the `ls` line of `config.json.bak-015`, and no AgentMeter icon in the menu bar.

**If you see something else:** "No such file" means the configuration lives elsewhere or the copy failed; stop here.

**Result:** passed (run by the agent). `600 ~/.config/agentmeter/config.json.bak-015 2.1K`; no AgentMeter process running afterwards.

### Step 5 of 10: Create a crafted OpenCode database (US2)

**Why this step:** A database file from an untrusted source could replace the `message` table with a view (or a virtual table) that runs code while AgentMeter reads it. This one only uses a harmless view, which is enough to see the table check refuse it.

**Run:**

```
mkdir -p specs/015-fix-soon-batch/.walkthrough/crafted-opencode && sqlite3 specs/015-fix-soon-batch/.walkthrough/crafted-opencode/opencode.db "CREATE TABLE real_message(id TEXT, session_id TEXT, time_updated INTEGER, data TEXT); CREATE VIEW message AS SELECT * FROM real_message; CREATE TABLE session(id TEXT, directory TEXT);" && sqlite3 specs/015-fix-soon-batch/.walkthrough/crafted-opencode/opencode.db "SELECT type, name FROM sqlite_schema ORDER BY name;"
```

**What you should see:** three lines in name order: `view|message`, `table|real_message`, `table|session`.

**If you see something else:** an error from `sqlite3` means the path or the SQL is wrong; nothing has changed in your configuration yet.

**Result:** passed (run by the agent). Output `view|message`, `table|real_message`, `table|session`.

### Step 6 of 10: Add the crafted directory and start the build (US2)

**Why this step:** The extra OpenCode data directory makes AgentMeter read the crafted file on its next refresh, next to your normal sources.

**Run:**

```
jq --arg d "$PWD/specs/015-fix-soon-batch/.walkthrough/crafted-opencode" '.openCodeDirectories += [$d]' ~/.config/agentmeter/config.json.bak-015 > ~/.config/agentmeter/config.json && jq '.openCodeDirectories' ~/.config/agentmeter/config.json && make run 2>&1 | tail -3
```

**What you should see:** the `openCodeDirectories` array with the absolute path ending in `.walkthrough/crafted-opencode`, then `Built build/AgentMeter.app` and `open "build/AgentMeter.app"`, and the AgentMeter icon appears in the menu bar.

**If you see something else:** a `jq` error leaves `config.json` possibly empty; restore it with Step 10 before anything else.

**Result:** passed (run by the agent). `openCodeDirectories` showed the one absolute path ending in `.walkthrough/crafted-opencode`; the build printed `Built build/AgentMeter.app` and opened it (process running from this worktree's build). Correction: the signing tier line is printed before the last three lines, so the expectation now names `Built build/AgentMeter.app` instead.

### Step 7 of 10: Find the refusal in the diagnostic log (US2)

**Why this step:** The log shows why the crafted file was not read, with the exact check that refused it (spec 015 FR-008).

**Run:**

```
sleep 10; rg -n "crafted-opencode/opencode.db: error" ~/Library/Logs/agentmeter/usage.log | tail -2
```

**What you should see:** a line ending in `crafted-opencode/opencode.db: error: message is a view, not an ordinary table (SQLite code 1), keeping 0 previous record(s)`.

**If you see something else:** no line yet means the first refresh is still running; wait a few seconds and run it again. A line saying `skipped, same database as an earlier location` means the path points at your real OpenCode data.

**Result:** passed (run by the agent). `[opencode] ~/.../crafted-opencode/opencode.db: error: message is a view, not an ordinary table (SQLite code 1), keeping 0 previous record(s)`, word for word as expected.

### Step 8 of 10: Check the dropdown still works (US2)

**Why this step:** A refused database must not affect the other sources: Claude, Codex and your normal OpenCode data keep their values (spec 015 FR-008, "without affecting other sources").

**Do:**

1. Click the AgentMeter icon in the menu bar.
2. Look at your subscription and budget rows and at the note area at the bottom.

**What you should see:** your usual rows with current values (not stale), and a note naming the OpenCode problem with the crafted path (`OpenCode: .../crafted-opencode/opencode.db: message is a view, not an ordinary table`).

**If you see something else:** stale markers on Claude or Codex rows mean the failure spread beyond OpenCode; note which rows.

**Result:** passed (checked by the user, screenshot). Claude Code (Max) 7%, Codex (Plus) 4% and Vertex 532% with current reset times and no stale marker on any row; the note reads `opencode: OpenCode: ~/.../crafted-opencode/opencode.db: message is a view, not an ordinary table (SQLite code 1)`. The footer showed an orange `stale` next to "Last refreshed", the existing harness-stale indication of spec 006 for a source with a read issue; the rows themselves were not stale.

### Step 9 of 10: Check that your normal data is unchanged (US2)

**Why this step:** The hardened read must give the same records for a normal database as before (spec 015 FR-009); your real OpenCode database, if you have one, is read in the same refresh.

**Run:**

```
rg -n "opencode.db: [0-9]+ record\(s\) in window" ~/Library/Logs/agentmeter/usage.log | tail -2
```

**What you should see:** a recent line for your real `~/.local/share/opencode/opencode.db` with a record count in the window, or no line at all if OpenCode is not installed on this Mac.

**If you see something else:** an error line for your real database means the hardening rejected a normal file; copy the line.

**Result:** passed (run by the agent). `~/.local/share/opencode/opencode.db: 0 record(s) in window, 0 row(s) read` on two refreshes, no error: the hardened reader accepts the real database (it has no messages in this window, so record contents are covered by `OpenCodeSourceTests` only).

### Step 10 of 10: Restore the configuration (US2)

**Why this step:** Puts your configuration back and removes the crafted database.

**Run:**

```
mv ~/.config/agentmeter/config.json.bak-015 ~/.config/agentmeter/config.json && rm -rf specs/015-fix-soon-batch/.walkthrough/crafted-opencode && jq '.openCodeDirectories' ~/.config/agentmeter/config.json
```

**What you should see:** your original `openCodeDirectories` value (for example `[]`). The running app picks up the restored file at its next refresh, and the OpenCode note disappears.

**If you see something else:** "No such file" for the backup means Step 4 did not run; your configuration still has the crafted directory, remove it in Settings.

**Result:** passed (run by the agent). `openCodeDirectories` back to `[]`, crafted database removed.

## Not covered here

- **Notification after a window reset (US1, FR-001 to FR-003):** needs a real 5-hour or budget window to roll over while usage is already above a threshold, which cannot be staged on demand. Covered by `ThresholdTrackerTests` (Step 1).
- **Period switch while the session logs cannot be read (US1, FR-004, FR-005):** making every Claude Code log directory unreadable would also break Claude Code itself. Covered by `BudgetPeriodFilterTests` and the coordinator test (Step 1).
- **Scanning a credential-only Claude Code directory (US1, FR-006, FR-007):** needs a second Claude Code login in its own directory. Covered by `LogIndexTests` (Step 1).
- **The 45-second limit of the Claude request (US2, FR-010):** needs a server that trickles its answer; covered by a configuration test (Step 1).
- **Signing tier guard and release replacement (US3, FR-012 to FR-017):** need an expired or revoked Developer ID certificate and a real published GitHub release. Covered by the stubbed release tests (Step 2).

## Coverage

- **US1 (correct notifications and labels):** automated only (Step 1); see "Not covered here".
- **US2 (safer reads and requests):** the OpenCode hardening by hand (Steps 4 to 10), the request time limit through tests.
- **US3 (release safety):** automated only (Step 2).

## Results

All 10 steps passed on 2026-10-16 (9 run by the agent, Step 8 checked by the user). The unit and release suites pass on the branch rebased onto main. By hand: AgentMeter refuses a crafted `opencode.db` whose `message` table is a view, logs the exact reason, shows it as an OpenCode note, keeps every other row current, and still reads the real OpenCode database. One runbook correction in Step 6 (where the signing line appears). Window resets, the period-switch display, credential-directory scanning, the request time limit and the release guard are covered by tests only (see "Not covered here").
