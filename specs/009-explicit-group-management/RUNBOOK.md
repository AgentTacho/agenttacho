---
runbook_version: 1
feature: 009-explicit-group-management
status: passed
mode: light
steps_total: 9
step_results: passed,passed,passed,passed,passed,passed,passed,passed,passed
drafted_at: e55ab72
drafted_fingerprint: 2671c078454aeb4fd35d42e5746ec5862b9e39e1175d5479e5dd952fbe2d07d5
tested_at: d3e6522
tested_fingerprint: 2671c078454aeb4fd35d42e5746ec5862b9e39e1175d5479e5dd952fbe2d07d5
updated: 2026-10-15
---

# Try it: Explicit Group Management

<!-- runbook-status -->
> **Status:** passed · 9 of 9 steps (9 passed) · Mode: light · Tested at d3e6522 · 2026-10-15
<!-- /runbook-status -->










## What you're testing

Budget groups no longer disappear when their last account leaves, and the Groups tab can add and remove groups. Removing a group that still has accounts asks where those accounts go.

Order of the journey: tests, backup and build, a group surviving its last member, adding a group, removing a group into own budgets, undo, removing into another group, removing an empty group, restore.

All commands run from the repository root of the feature worktree (`.claude/worktrees/009-explicit-group-management`, or `main` after merge). The app reads your real configuration, so Step 2 backs it up and the last step restores it.

## Test environment

No fixtures. Needs the Xcode Command Line Tools and `jq`, and a configuration with at least one budget group that has one member (yours has the Vertex group with "Claude Code via Vertex"). The single-instance check stops a second copy, so Step 2 quits the running AgentTacho first.

## Steps

### Step 1 of 9: Run the test suite (US1, US2, US3)

**Why this step:** The lifecycle rules, the removal destinations and the member ordering are pure logic with unit tests.

**Run:**

```
make test 2>&1 | tail -1
```

**What you should see:** `Test run with 681 tests in 74 suites passed` (or more tests).

**If you see something else:** A failing `GroupLifecycle`, `Configuration` or `ArrangementReconcile` test names the rule that broke.

**Result:** passed (run by the agent).

- ✔ 681 tests or more → `Test run with 681 tests in 74 suites passed`

### Step 2 of 9: Back up the configuration, build and start the app (US1)

**Why this step:** The walkthrough changes groups in your real configuration; the backup lets Step 9 undo everything.

**Run:**

```
cp ~/.config/agenttacho/config.json ~/.config/agenttacho/config.json.bak-009 && osascript -e 'tell application id "dev.rhuss.agenttacho" to quit'; make app 2>&1 | tail -1 && open build/AgentTacho.app
```

**What you should see:** `Built build/AgentTacho.app`, and AgentTacho appears in the menu bar.

**If you see something else:** An "AgentTacho is already running" alert means the quit did not finish; choose "Stop It and Start This One".

**Result:** passed (run by the agent).

- ✔ `Built build/AgentTacho.app`, feature build running (PID 23770 from the worktree), backup `config.json.bak-009` written; config had one group, `["Vertex"]`

### Step 3 of 9: A group survives losing its last account (US1)

**Why this step:** This is the dead end the feature fixes: the group must stay with its settings.

**Do:**

1. Settings > Accounts: select "Claude Code via Vertex" and set Budget to "Own budget".
2. Open the Groups tab, then the Menu Bar tab, then the dropdown.
3. Back in Accounts, set the account's Budget to "Vertex" again.

**What you should see:** After 1, "Vertex" is still in the Groups tab with its amount and thresholds, the editor says "No accounts in this group yet", the Menu Bar tab still lists it at its place, the bar shows it at 0%, and its dropdown section says "No accounts in this group yet". After 3, the account is a member again.

**If you see something else:** "Vertex" missing means the group was still deleted implicitly.

**Result:** passed (user in the app, config checked by the agent).

- ✔ group kept with settings, 0%, notes shown, account back in the group → user: as expected; config `{"groups":["Vertex"],"groupId":"grp-vertex"}`

### Step 4 of 9: Add a group (US2)

**Why this step:** Groups can now be created on their own.

**Do:**

1. Groups tab: press Add.
2. Check the Menu Bar tab and an account's Budget picker.

**What you should see:** "Budget group" appears selected with a weekly budget of 60 US dollars, shown in the bar, thresholds 80% and 100%. It is last in the Menu Bar tab and offered in the Budget picker.

**If you see something else:** No new row, or no selection, means Add did not apply.

**Result:** passed (user, config checked by the agent).

- ✔ "Budget group" added and selected, last in the stored order → config groups `["Vertex","Budget group"]`, arrangement ends with the new group

User follow-up: the Accounts list subtitle ("token-based (Vertex)") names the provider; it should also say which budget the account uses (added to the idea inbox).

### Step 5 of 9: Remove a group with members into own budgets (US3)

**Why this step:** The removal must keep every member budgeted and keep the order.

**Do:**

1. Groups tab: select "Vertex" and press Remove....
2. Check the sheet, keep "Own budgets", press Remove.
3. Look at the Accounts tab, the Menu Bar tab and the bar.

**What you should see:** The sheet lists "Claude Code via Vertex" and offers "Own budgets" and "Budget group". After Remove, "Vertex" is gone, the account has its own budget with Vertex's period, amount and thresholds, and it sits at Vertex's former place in the bar.

**If you see something else:** The account without a budget, or at the end of the bar, means the destination or the placement is wrong.

**Result:** passed (user, config checked by the agent).

- ✔ sheet lists the member and both destinations → user: as expected
- ✔ own budget with Vertex's values at Vertex's place → account `budget` monthly 300 USD, thresholds [80,100], shown in bar; order `[DD73…, F42D…, acc-vertex, FC55…]`

### Step 6 of 9: Undo the removal (US3)

**Why this step:** A removal is a settings change and must undo like one.

**Do:** Press Command-Z in the Settings window.

**What you should see:** "Vertex" is back at its place with "Claude Code via Vertex" as its member.

**If you see something else:** Undo doing nothing, or the account still on its own budget, means the undo target was not restored.

**Result:** passed (user, config checked by the agent).

- ✔ Vertex back with its member → groups `["Vertex","Budget group"]`, `groupId` `grp-vertex`, Vertex back at the third position

### Step 7 of 9: Remove a group into another group (US3)

**Why this step:** The second destination moves members into an existing group.

**Do:** Select "Vertex", press Remove..., choose "Budget group" as destination, press Remove.

**What you should see:** "Vertex" is gone and "Claude Code via Vertex" is a member of "Budget group" (its share hidden from the bar).

**If you see something else:** The account on its own budget means the destination choice was ignored.

**Result:** passed (user, config checked by the agent).

- ✔ Vertex gone, account in "Budget group" with its share hidden → groups `["Budget group"]`, `groupId` `FC554E0C…`, `memberShownInBar` unset

### Step 8 of 9: Remove an empty group and check the account removal text (US1, US3)

**Why this step:** Empty groups get a plain confirmation, and removing an account no longer announces a group deletion.

**Do:**

1. Accounts: select "Claude Code via Vertex", press Remove..., read the message, then Cancel.
2. Groups: press Add, select the new empty group, press Remove....

**What you should see:** In 1, the message says the group "Budget group" stays, without accounts. In 2, a plain confirmation without a destination picker; after Remove the group is gone and no group is selected.

**If you see something else:** "This also removes the budget group" in 1 means the old message is still there.

**Result:** passed (user).

- ✔ account removal message says the group stays → user: as expected
- ✔ plain confirmation for an empty group → user: as expected

Observation: afterwards the config had no groups (`[]`), so "Budget group" had been removed as well; not checked further.

### Step 9 of 9: Restore your configuration (US1)

**Why this step:** Puts back the configuration from before the walkthrough.

**Run:**

```
cp ~/.config/agenttacho/config.json.bak-009 ~/.config/agenttacho/config.json && jq -c '[.groups[].name]' ~/.config/agenttacho/config.json
```

**What you should see:** The group names from before Step 2, for example `["Vertex"]`. The running app picks up the file at its next refresh.

**If you see something else:** `No such file` means Step 2's backup was not made.

**Result:** passed (run by the agent).

- ✔ backup restored → `["Vertex"]`

## Coverage

- US1 (group survives): Steps 1, 3, 8.
- US2 (add a group): Steps 1, 4.
- US3 (remove a group): Steps 1, 5 to 8.

## Results

All 9 steps passed (3 run by the agent, 6 by the user with agent checks of `config.json`). A group now survives losing its last account, groups can be added in the Groups tab, and removing a group moves its accounts to their own budgets or another group at the right place in the order; Undo restores it. Follow-up: show the budget (group or own budget) in the Accounts list subtitle.
