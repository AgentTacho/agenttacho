---
runbook_version: 1
feature: 045-claude-automode-classifier-usage
status: drafted
mode: full
steps_total: 9
step_results: pending,pending,pending,pending,pending,pending,pending,pending,pending
drafted_at: 12fc1ca
drafted_fingerprint: 99a52eb8453dff9aa511eccf5561fd2a377a5911cfed3064569d395f52f8aa1d
tested_at:
tested_fingerprint:
updated: 2026-11-13
---

# Try it: Claude Code Auto-mode classifier usage

<!-- runbook-status -->
> **Status:** drafted · 0 of 9 steps · Mode: full · Drafted at 12fc1ca · 2026-11-13
<!-- /runbook-status -->

## What you're testing

AgentTacho now counts the tokens of Claude Code's Auto-mode classifier calls, which the session transcript leaves out. It reads them from `.automode_decisions.jsonl`, which Claude Code writes into the session's working directory when `AUTOMODE_DECISION_LOG=1` is set.

The journey: build this branch, note an account's total, run a small Auto-mode session with the decision log enabled in a scratch directory, check the log has usage rows, start the branch build, and see the total grow by the main requests plus the classifier rows, under the same model row. Then delete the log and see the classifier share go away again.

This uses real model usage on one of your Claude Code profiles (a few cents or a few free-model requests). aprofile's `features` command does not exist yet (aprofile brainstorm 007), so the variable is set on the command line.

## Test environment

No fixtures are started by the agent. Step 1 builds the branch app; step 4 is a Claude Code session you run yourself on a profile of your choice.

## Steps

### Step 1 of 9: Build the branch app (US1)

**Why this step:** The installed AgentTacho does not have the feature; the branch build does.

**Run:**

```
cd /Users/rhuss/Work/projects/agentmeter/.claude/worktrees/045-claude-automode-classifier-usage && make app
```

**What you should see:** The build ends without errors and names the built `AgentTacho.app` under the build directory.

**If you see something else:** A signing or SDK error points at the build setup, not at this feature; `make test` passing tells you the code itself compiles.

**Result:**

### Step 2 of 9: Note the account's total before the session (US1)

**Why this step:** You need a baseline to see the classifier share arrive.

**Do:**

1. Open the installed AgentTacho dropdown.
2. Pick the account the profile of step 4 bills (for example the GLM token account) and note its token total and the model row the session will use.

**What you should see:** A token total for the account; write it down.

**If you see something else:** If the account shows no usage at all, choose another profile in step 4 whose account AgentTacho tracks.

**Result:**

### Step 3 of 9: Create a scratch working directory (US1)

**Why this step:** The decision log lands in the session's working directory; a scratch directory keeps it out of your repositories.

**Run:**

```
mkdir -p "$HOME/Work/experiments/agenttacho-045-walkthrough" && ls -la "$HOME/Work/experiments/agenttacho-045-walkthrough"
```

**What you should see:** An empty directory listing (only `.` and `..`).

**If you see something else:** Leftover files from an earlier try: remove `.automode_decisions.jsonl` there before step 4.

**Result:**

### Step 4 of 9: Run a short Auto-mode session with the decision log on (US1)

**Why this step:** This produces real classifier calls and their usage rows.

**Do:**

1. In a terminal: `cd "$HOME/Work/experiments/agenttacho-045-walkthrough"`.
2. Start the Claude Code profile you chose in step 2 with `AUTOMODE_DECISION_LOG=1` in front of its command (for example `AUTOMODE_DECISION_LOG=1 claude`, or the aprofile wrapper of that profile).
3. Switch to Auto mode (Shift+Tab until the mode line says auto).
4. Ask for two harmless shell commands, for example: "Run `date` and then `ls -la` in this directory and tell me the results."
5. When both ran, exit Claude Code.

**What you should see:** Both commands run without an approval prompt (the classifier allowed them).

**If you see something else:** An approval prompt means Auto mode was not on, or the classifier denied the call; rerun with Auto mode active.

**Result:**

### Step 5 of 9: Check the decision log has usage rows (US1)

**Why this step:** Confirms Claude Code wrote usage-bearing rows, so AgentTacho has something to read.

**Run:**

```
jq -s '{rows: length, model: (map(.classifierModel) | unique), input: (map(.inputTokens // 0) | add), cacheRead: (map(.cacheReadInputTokens // 0) | add), cacheWrite: (map(.cacheCreationInputTokens // 0) | add), output: (map(.outputTokens // 0) | add)}' "$HOME/Work/experiments/agenttacho-045-walkthrough/.automode_decisions.jsonl"
```

**What you should see:** At least one row (usually one per tool call), a model name ending in a bracket marker such as `[1m]`, and token sums above zero. Note the sum of the four counters: that is the classifier share.

**If you see something else:** "No such file" means the variable did not reach Claude Code (check step 4's command); rows with all counters zero mean decisions without a classifier call.

**Result:**

### Step 6 of 9: Start the branch build instead of the installed app (US1)

**Why this step:** Only one AgentTacho should read the logs, and it must be the branch build.

**Run:**

```
osascript -e 'quit app "AgentTacho"'; sleep 2; cd /Users/rhuss/Work/projects/agentmeter/.claude/worktrees/045-claude-automode-classifier-usage && make run
```

**What you should see:** The installed app quits and the branch build opens in the menu bar.

**If you see something else:** If two menu bar items appear, quit the one from `/Applications`.

**Result:**

### Step 7 of 9: Read the diagnostic log line (US1, US4)

**Why this step:** The log line shows what the classifier step read and assigned, without opening the UI.

**Run:**

```
sleep 20; rg "decision logs read" "$HOME/Library/Logs/agenttacho/usage.log" | tail -1
```

**What you should see:** A `sessionLogs` line with `decision logs read 1`, `rows counted` equal to the row count of step 5, `assigned` equal to that count, `unassigned 0`, `malformed 0`.

**If you see something else:** No line yet means no refresh ran: click refresh in the dropdown and run the command again. `unassigned` above 0 means the rows fell outside the session's time span or the session's records are not on one account; compare with the account matching in Settings.

**Result:**

### Step 8 of 9: See the total include the classifier share (US1)

**Why this step:** This is the user-visible outcome: totals that include the classifier calls.

**Do:**

1. Open the branch build's dropdown and pick the account from step 2.
2. Compare its token total with the value from step 2.
3. Look at the model rows.

**What you should see:** The total grew by the session's main requests plus the classifier share from step 5. The classifier tokens sit in the same model row as the session (no extra row ending in `[1m]`).

**If you see something else:** A separate `[1m]` model row means the model name was not normalized; a growth of only the main requests means the decision log was not read (check step 7).

**Result:**

### Step 9 of 9: Delete the log and see the share leave (US2)

**Why this step:** Shows that rows count only while the log exists, and that nothing is counted twice across refreshes.

**Run:**

```
rm "$HOME/Work/experiments/agenttacho-045-walkthrough/.automode_decisions.jsonl" && sleep 20 && rg "decision logs read" "$HOME/Library/Logs/agenttacho/usage.log" | tail -1
```

**What you should see:** After the next refresh, the dropdown total drops by exactly the classifier share from step 5, and no new `decision logs read` line appears for a refresh with no log found (the last line stays the one from step 7).

**If you see something else:** A total that does not drop means the entry was not removed; a total that drops by more means session records were affected, which must not happen.

**Result:**

## Not covered here

- Hung or unmounted volumes (FR-012), FIFOs, symbolic links and oversized logs (FR-001): they need a broken file system to try by hand; covered by `DecisionLogProbeTests` and `ClassifierLogIndexTests`.
- Two overlapping sessions on different accounts in one directory (US3): needs two billed accounts used at the same time; covered by `ClassifierAttributionTests` and `SessionLogSourceClassifierTests`.
- Malformed rows from a future Claude Code format (US4 scenarios 1 to 4): covered by `ClassifierRowParserTests`.

## Coverage

- US1: steps 1 to 8.
- US2: step 9 (removal); repeated refreshes without double counting run between steps 7 and 9.
- US3: not covered by hand (see above).
- US4: step 7 shows the counters; malformed input is covered by tests only.

## Results
