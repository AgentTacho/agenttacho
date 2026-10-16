---
runbook_version: 1
feature: 018-account-budget-subtitle
status: passed
mode: light
steps_total: 7
step_results: passed,passed,passed,passed,passed,passed,passed
drafted_at: 2cd95d6
drafted_fingerprint: 38395b99929a60200ad03510ba3ec9a584ba578f3722ec721ccc3c2b344617fa
tested_at: 69277ab
tested_fingerprint: 38395b99929a60200ad03510ba3ec9a584ba578f3722ec721ccc3c2b344617fa
updated: 2026-10-16
---

# Try it: Account Budget Subtitle

<!-- runbook-status -->
> **Status:** passed · 7 of 7 steps (7 passed) · Mode: light · Tested at 69277ab · 2026-10-16
<!-- /runbook-status -->








## What you're testing

Settings now tells you where each token-based account's spend counts. The Accounts list subtitle shows the provider, the budget (the group's icon and name, or "own budget") and its size, for example "Vertex · [icon] Vertex, $300 / month". The Groups list uses the same amount style ("$300 / month, 1 member(s)"). Subscription accounts are unchanged.

Order of the journey: tests, config backup and build, the Accounts list, the Groups list, a live change before it is saved, VoiceOver, restore.

All commands run from the root of the feature worktree (`.claude/worktrees/018-account-budget-subtitle`, or `main` after merge). Settings saves edits automatically, so Step 2 backs up your configuration and the last step restores it.

## Test environment

No fixtures. Needs the Xcode Command Line Tools and your configuration with at least one token-based account in a group (yours: "Claude Code via Vertex" in the monthly group "Vertex" of 300 USD). Amounts follow your locale, so a German locale shows "300 $" or "300 US$" where the spec examples show "$300".

## Steps

### Step 1 of 7: Run the test suite (US1, US2)

**Why this step:** The subtitle wording, amount formatting, rounding, missing-group case and VoiceOver text are `UsageCore` logic with tests.

**Run:**

```
make test 2>&1 | tail -1
```

**What you should see:** `Test run with 1369 tests in ... suites passed` (or more tests).

**If you see something else:** a failing `AccountBudgetDescriptionTests` test names the formatting rule that broke.

**Result:** passed (run by the agent). `Test run with 1369 tests in 133 suites passed`.

### Step 2 of 7: Back up the configuration and start this build (US1)

**Why this step:** Step 5 changes a budget in Settings, which saves automatically; the backup lets the last step undo it. Only one AgentMeter can run, so any other copy is quit first.

**Run:**

```
cp ~/.config/agentmeter/config.json ~/.config/agentmeter/config.json.bak-018 && osascript -e 'quit app "AgentMeter"'; make run 2>&1 | tail -2
```

**What you should see:** `Built build/AgentMeter.app` and `open "build/AgentMeter.app"`, then the AgentMeter icon in the menu bar.

**If you see something else:** a build error means the branch does not compile; stop here.

**Result:** passed (run by the agent). Config backed up to `config.json.bak-018`; `Built build/AgentMeter.app`, `open "build/AgentMeter.app"`; the app runs from the main checkout's `build/`.

### Step 3 of 7: Read the Accounts list (US1)

**Why this step:** The main point of the feature: the list shows where each account's spend counts without selecting it (spec FR-001, FR-006, FR-007).

**Do:**

1. Open the dropdown, gear menu, "Settings…", then the Accounts tab.
2. Read the subtitle under each account name.

**What you should see:** "Claude Code (Max)" with "Claude subscription", "Codex (Plus)" with "ChatGPT subscription", and "Claude Code via Vertex" with "Vertex · ", the Vertex group's icon, then "Vertex, 300 $ / month" (in your locale's currency style), all on one line.

**If you see something else:** "token-based (Vertex)" means the old build is running; a "?" instead of the icon means the group icon id is not in the catalog.

**Result:** passed (checked by the user). Subscription subtitles unchanged; "Claude Code via Vertex" shows provider, the Vertex group's icon and name, and the monthly amount on one line.

### Step 4 of 7: Read the Groups list (US2)

**Why this step:** Both Settings lists now use one amount style (spec FR-004, SC-004).

**Do:**

1. Switch to the Groups tab.
2. Read the subtitle under "Vertex".

**What you should see:** the same amount text as in Step 3, followed by ", 1 member(s)", for example "300 $ / month, 1 member(s)", instead of the old "300,00 $ per month".

**If you see something else:** two decimals or "per month" mean the Groups row was not changed.

**Result:** passed (checked by the user). The Vertex group shows the same amount text as the Accounts list, followed by ", 1 member(s)".

### Step 5 of 7: Change the budget and watch the subtitle (US1)

**Why this step:** The subtitle follows the Settings draft, so it changes before anything is saved (spec FR-005).

**Do:**

1. In the Accounts tab, select "Claude Code via Vertex".
2. In its Budget picker, choose "Own budget".
3. Look at its subtitle in the list on the left.
4. Choose the "Vertex" group in the Budget picker again.

**What you should see:** after step 2 the subtitle reads "Vertex · own budget, 300 $ / month" (the group's period and amount carried over); after step 4 it shows the group icon and "Vertex, 300 $ / month" again.

**If you see something else:** a subtitle that only changes after closing Settings means it reads the saved configuration instead of the draft.

**Result:** passed (checked by the user). Switching to "Own budget" changed the subtitle to own budget with the group's amount and period before saving; switching back restored the group icon and name.

### Step 6 of 7: Listen with VoiceOver (US1)

**Why this step:** VoiceOver reads the subtitle without the icon glyph (spec FR-007a).

**Do:**

1. Turn on VoiceOver with Cmd-F5.
2. Move the VoiceOver cursor onto the "Claude Code via Vertex" row in the Accounts list.
3. Turn VoiceOver off with Cmd-F5.

**What you should see:** VoiceOver says something like "Vertex, group Vertex, 300 dollars per month", with no strange character name for the icon.

**If you see something else:** a spoken private-use character or "question mark" means the accessibility label is missing.

**Result:** passed (checked by the user). VoiceOver read provider, group name and amount per month without an icon character.

### Step 7 of 7: Restore the configuration (US1)

**Why this step:** Puts your configuration back exactly as before Step 2.

**Run:**

```
mv ~/.config/agentmeter/config.json.bak-018 ~/.config/agentmeter/config.json && jq '[.accounts[] | {displayName, groupId}]' ~/.config/agentmeter/config.json
```

**What you should see:** "Claude Code via Vertex" with `"groupId": "grp-vertex"` again.

**If you see something else:** "No such file" means Step 2 did not run; check the account's Budget in Settings by hand.

**Result:** passed (run by the agent). Configuration restored; "Claude Code via Vertex" has `"groupId": "grp-vertex"` again.

## Not covered here

- **Missing group (FR-002):** configuration validation rejects a group id that names no group, so the Settings draft never holds one; covered by `AccountBudgetDescriptionTests` only.
- **Long group names (FR-005a):** renaming your group would change your saved configuration; truncation is a single `lineLimit` in the view and can be checked by renaming a group and undoing it with Cmd-Z if you want to.

## Coverage

- **US1 (see where an account's spend counts):** Steps 1, 3, 5 and 6.
- **US2 (one amount style):** Steps 1 and 4.

## Results

All 7 steps passed on 2026-10-16 (3 run by the agent, 4 checked by the user in Settings). The Accounts list now says where each token-based account's spend counts (provider, group icon and name or own budget, amount per period), follows unsaved edits, and reads cleanly with VoiceOver; the Groups list uses the same amount style. The missing-group case is covered by unit tests only.
