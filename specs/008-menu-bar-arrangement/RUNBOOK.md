---
runbook_version: 1
feature: 008-menu-bar-arrangement
status: passed
mode: light
steps_total: 11
step_results: passed,passed,passed,passed,passed,passed,passed,passed,passed,passed,passed
drafted_at: b754ec7
drafted_fingerprint: a60b47e4e0e55f33482dc9618356fb8564bc33a0c2a42e46f8afb52f08819913
tested_at: 8524535
tested_fingerprint: 10197175096dfaba9121b4fa718ecf7e60c5bc1404bbc21899dfe14f37ca861c
updated: 2026-10-15
---

# Try it: Menu Bar Arrangement

<!-- runbook-status -->
> **Status:** passed · 11 of 11 steps (11 passed) · Mode: light · Tested at 8524535 · 2026-10-15
<!-- /runbook-status -->












## What you're testing

The bar and the dropdown now follow one order, and the new Settings tab "Menu Bar" lets you arrange it by dragging or with Option-Command-Up/Down, and show or hide each entry with a checkbox. Existing configurations keep their bar order until you change it.

Order of the journey: tests, backup and build, unchanged order after the update, bar and dropdown agree, reorder by drag, members stay with their group, keyboard moves, checkboxes in sync with the editors, undo, relaunch, restore the backup.

All commands run from the repository root of the feature worktree (`.claude/worktrees/008-menu-bar-arrangement`, or `main` after merge). The app reads your real configuration, so Step 2 backs it up and the last step restores it.

## Test environment

No fixtures. The steps need the Xcode Command Line Tools, `jq`, and a configuration with at least one account and one budget group (yours has Claude Max, Codex and the Vertex group). Quit any other running AgentMeter before Step 3 so only this build runs.

## Steps

### Step 1 of 11: Run the test suite (US1, US2, US3)

**Why this step:** Resolution, reconciliation and the editor moves are pure logic with unit tests; a green run shows the rules work before touching the app.

**Run:**

```
make test 2>&1 | tail -3
```

**What you should see:** A final line like `Test run with 628 tests in 68 suites passed` (or more tests), and no failing test.

**If you see something else:** A failing `Arrangement...` test names the rule that broke; a macro or SDK error means the build ran outside the Makefile.

**Result:** passed (run by the agent).

- ✔ final `Test run with ... passed`, 628 or more → `Test run with 629 tests in 68 suites passed`
- ✔ no failing test → no failure lines

### Step 2 of 11: Back up your configuration and build the app (US1)

**Why this step:** The app reads and writes `~/.config/agentmeter/config.json`; the backup lets the last step undo everything this walkthrough changes.

**Run:**

```
cp ~/.config/agentmeter/config.json ~/.config/agentmeter/config.json.bak-008 && make app 2>&1 | tail -2 && jq 'has("arrangement")' ~/.config/agentmeter/config.json
```

**What you should see:** `Built build/AgentMeter.app`, then `false` (no stored arrangement yet).

**If you see something else:** `true` means an earlier build of this feature already stored an order; the walkthrough still works, but Step 3 then shows that stored order.

**Result:** passed (run by the agent).

- ✔ `Built build/AgentMeter.app` → line 2: `Built build/AgentMeter.app`
- ✔ `false` → line 3: `false`
- ✔ backup `config.json.bak-008` written by the `cp` that starts the chain

### Step 3 of 11: See the bar order unchanged after the update (US1)

**Why this step:** Existing configurations must keep their bar order (SC-003), and loading must not rewrite the file (FR-004).

**Needs:** Step 2.

**Do:**

1. Quit any running AgentMeter, then run `open build/AgentMeter.app`.
2. Look at the menu bar entry.
3. In Terminal, run `jq 'has("arrangement")' ~/.config/agentmeter/config.json`.

**What you should see:** The same order as before the update: accounts first (Claude, Codex), then the Vertex group. The `jq` command still prints `false`.

**If you see something else:** A different order means the default order differs from spec 004 FR-020; `true` means loading wrote an arrangement.

**Result:** passed (the user quit AgentMeter 0.1.1, the agent started the test build and ran the `jq` check; the user read the bar).

- ✔ previous order, accounts first then the group → user: `Claude, Codex, Vertex`
- ✔ `jq` still prints `false` after launch → `false` (test build PID 54500 from the worktree `build/`)

### Step 4 of 11: Check that bar and dropdown agree (US1)

**Why this step:** The dropdown used its own fixed order before; now its sections follow the bar (FR-003, SC-001).

**Needs:** Step 3.

**Do:**

1. Click the AgentMeter entry to open the dropdown.
2. Compare the order of the sections with the bar entries.

**What you should see:** The sections appear in the bar's order (Claude Max, Codex, Vertex). An entry hidden from the bar would still have its section at its place.

**If you see something else:** Codex before Claude or Vertex in a different place means the dropdown does not use the arrangement.

**Result:** passed (run by the user).

- ✔ sections in the bar's order → user: `Claude, Codex, Vertex`

Note: with this configuration the old fixed dropdown order gives the same sequence, so this step alone does not tell the two apart; Step 5 does (Vertex first in the dropdown after the reorder).

### Step 5 of 11: Move the group to the front by dragging (US2)

**Why this step:** This is the main request: put any entry first, and the bar, the preview and the dropdown follow (FR-010, FR-013).

**Needs:** Step 3.

**Do:**

1. Open the dropdown, choose Settings..., and select the "Menu Bar" tab (second, after General).
2. Drag the Vertex row to the top of the list.
3. Watch the preview above the list, then the menu bar, then open the dropdown.
4. In Terminal, run `jq -c '.arrangement.entries' ~/.config/agentmeter/config.json`.

**What you should see:** The preview shows Vertex first right away; within a second the bar and the dropdown show Vertex first too. The `jq` command prints a list starting with `{"kind":"group","id":"grp-vertex"}`.

**If you see something else:** The preview drawn black on black means the template tint is missing; no `arrangement` key means the order was not saved.

**Result:** passed (drag by the user, `jq` check by the agent).

- ✔ preview, then bar and dropdown show Vertex first → user: Vertex first everywhere
- ✔ `entries` starts with the Vertex group → `[{"id":"grp-vertex","kind":"group"},{"id":"DD73C467-...","kind":"account"},{"id":"F42D727A-...","kind":"account"}]` (keys sorted `id` before `kind`; same content as expected)
- ✔ member order stored → `{"grp-vertex":["acc-vertex"]}`

### Step 6 of 11: Try to drag a member out of its group (US2)

**Why this step:** Members always stay with their group (FR-010); a drop outside it must not be accepted.

**Needs:** Step 5.

**Do:**

1. In the Menu Bar tab, drag the indented "Claude Code via Vertex" row above the Vertex row, or below Codex.

**What you should see:** The row snaps back; the list, the preview and the configuration are unchanged.

**If you see something else:** The member appearing at the top level means the drop rules accept a move they should reject.

**Result:** passed (drag by the user, `jq` check by the agent).

- ✔ row snaps back, list unchanged → user: snaps back, no change
- ✔ configuration unchanged → `{"first":"grp-vertex","n":3,"members":{"grp-vertex":["acc-vertex"]}}`, and `acc-vertex` still has `groupId` `grp-vertex`

### Step 7 of 11: Move a row with the keyboard (US2)

**Why this step:** Every drag must also be possible without a pointer (FR-010a, SC-005).

**Needs:** Step 5.

**Do:**

1. Click the Codex row to select it, keeping the focus in the list.
2. Press Option-Command-Up Arrow twice.
3. Look at the Move Up and Move Down buttons.

**What you should see:** Codex moves up one position per press and stays selected, ending first. Move Up is now disabled (first row); Move Down is enabled. With the member row selected (the only member of Vertex), both buttons are disabled.

**If you see something else:** No movement means the shortcut is not attached while the list has focus; enabled buttons on the first row mean `canMoveUp` is wrong.

**Result:** passed (keyboard by the user, `jq` checks by the agent).

- ✔ Codex moves up per press, stays selected, ends first → user: as expected; list, preview and bar show Codex first
- ✔ Move Up disabled on the first row, both buttons disabled for the only member → user: as expected
- ✔ stored order → `["F42D727A-...","DD73C467-...","grp-vertex"]` (Codex first), saved 06:21:22Z

Note: a first `jq` read at 06:20:45Z still showed Codex last. The save log shows further Settings saves at 06:21:02Z and 06:21:22Z, so that read happened before the last moves were applied; the final file matches what the app shows. Runbook correction for later runs: read the configuration only after finishing the moves and waiting a second.

### Step 8 of 11: Hide and show an entry from both places (US3)

**Why this step:** The checkbox in the tab and the toggle in the editor change the same setting (FR-012).

**Needs:** Step 5.

**Do:**

1. In the Menu Bar tab, clear the "Show in bar" checkbox of Codex.
2. Check the preview and the menu bar, then open the Accounts tab and select the Codex account.
3. Turn "Show in menu bar" back on there, and return to the Menu Bar tab.

**What you should see:** After step 1, Codex leaves the preview and the bar, and its row turns secondary but keeps its place. The Accounts editor shows "Show in menu bar" off. After step 3, the checkbox is on again and Codex is back in the bar at its old position.

**If you see something else:** The editor toggle still on after step 1 means the checkbox writes a different setting.

**Result:** passed (run by the user, final state checked by the agent).

- ✔ Codex leaves preview and bar, row keeps its place, editor toggle off → user: as expected
- ✔ editor toggle on brings the checkbox and the bar entry back at its position → user: as expected
- ✔ final file → `{"order":["F42D727A","DD73C467","grp-vert"],"codexShown":true}`

### Step 9 of 11: Undo a reorder (US2)

**Why this step:** Arrangement changes undo like any other settings change (FR-014).

**Needs:** Step 7.

**Do:**

1. In the Menu Bar tab, drag Claude Max to the bottom of the list and wait a second.
2. Choose Edit > Undo (Command-Z) in the Settings window.

**What you should see:** Claude Max returns to its previous position in the list, the preview and the bar.

**If you see something else:** No change, or the drag coming back after a moment, means the undo path re-applies the reorder.

**Result:** passed (run by the user, file checked by the agent).

- ✔ Claude Max returns to its previous position everywhere → user: restored
- ✔ stored order after Undo → `["F42D727A","DD73C467","grp-vert"]`; save log shows the drag (06:24:27Z) and the undo (06:24:34Z)

### Step 10 of 11: Relaunch and keep the order (US2)

**Why this step:** The arrangement is stored in the configuration file and must survive a restart (FR-004, SC-004).

**Needs:** Step 9.

**Do:**

1. Note the current bar order, then quit AgentMeter from the dropdown.
2. Run `open build/AgentMeter.app` again.

**What you should see:** The bar shows the same order as before quitting, and the dropdown matches it.

**If you see something else:** The default order after the restart means the arrangement was not written or not read.

**Result:** passed (user quit the app and read the bar, agent restarted it).

- ✔ same order after restart in bar and dropdown → user: `Codex, Claude, Vertex`
- ✔ new process → PID 81985 (was 54500), stored order `["F42D727A","DD73C467","grp-vert"]`

### Step 11 of 11: Restore your configuration (US1)

**Why this step:** Puts back the configuration you had before the walkthrough.

**Run:**

```
cp ~/.config/agentmeter/config.json.bak-008 ~/.config/agentmeter/config.json && jq 'has("arrangement")' ~/.config/agentmeter/config.json
```

**What you should see:** `false`. Within a refresh interval the running app picks up the restored file and shows the original order.

**If you see something else:** `No such file` means Step 2's backup was not made; the arrangement can also be removed by hand with `jq 'del(.arrangement)'`.

**Result:** passed (run by the agent).

- ✔ `false` → `false`; `config.json.bak-008` copied back

## Not covered here

- Reordering members within a group: your Vertex group has one member. Adding a second token-based account to the group (Settings > Accounts > Add) makes it testable; the unit tests cover it.
- The placement rules for new accounts and for a member moving to its own budget change your account setup; they are covered by `ArrangementReconcileTests` instead of a manual step.
- A group and an account sharing an id: only reachable by editing the configuration by hand; covered by unit tests.

## Coverage

- US1 (one order for bar and dropdown): Steps 1 to 4, 10 and 11.
- US2 (rearrange in Settings): Steps 5 to 7, 9 and 10; member reordering and placement rules are covered by unit tests only (see Not covered here).
- US3 (show and hide from the same list): Step 8.

## Results

All 11 steps passed (4 run by the agent, 7 by the user with agent checks of `config.json`); none failed or were skipped.

What a reader now knows: an existing configuration keeps its bar order and is not rewritten on load. The Menu Bar tab reorders entries by drag and by Option-Command-Up/Down, the preview, the bar and the dropdown follow, and the order is stored in `config.json` and survives a restart. A member cannot be dragged out of its group. The Show in bar checkbox and the editor toggle stay in sync, and Undo restores the previous order.

One observation without a defect: in Step 7 a configuration read taken while the user was still moving rows showed an older order; the final file matched the app. Step 4 cannot tell the old and new dropdown orders apart with this configuration; Step 5 covers that. Member reordering and the placement rules remain covered by unit tests only (see Not covered here).
