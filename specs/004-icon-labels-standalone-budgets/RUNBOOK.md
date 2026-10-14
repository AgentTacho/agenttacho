---
runbook_version: 1
feature: 004-icon-labels-standalone-budgets
status: passed
mode: light
steps_total: 11
step_results: passed,passed,passed,passed,passed,passed,passed,passed,passed,passed,passed
drafted_at: 41680cc
drafted_fingerprint: 860dcc7baabb74c6c04004a92ff0ce0ef14425241d1f229a9d894bb54d095780
tested_at: 1adba32
tested_fingerprint: 860dcc7baabb74c6c04004a92ff0ce0ef14425241d1f229a9d894bb54d095780
updated: 2026-10-14
---

# Try it: Icon Labels and Standalone Budgets

<!-- runbook-status -->
> **Status:** passed · 11 of 11 steps (11 passed) · Mode: light · Tested at 1adba32 · 2026-10-14
<!-- /runbook-status -->












## What you're testing

Accounts and groups now carry exactly one icon and no text label, and icons may repeat. A token-based account can have its own budget instead of a group. A group member can also show its share of the group budget in the menu bar.

The journey goes like this:

1. Build and test, with your real configuration backed up.
2. Check that the legacy file still loads.
3. Give two entries the same icon.
4. Switch the Vertex account to its own budget and look at it in the dropdown and the bar.
5. Put it back into a group with its share shown in the bar.
6. Confirm that a contradictory hand edit is rejected.
7. Restore the configuration.

## Test environment

No fixtures. The journey uses your own `~/.config/llm-usage-menubar/config.json`, which is backed up in step 2 and restored in the last step, and your existing session logs (read only). Your configuration has one subscription account ("Claude Max"), one Vertex token-based account, and one group ("Vertex weekly") that contains it.

## Steps

### Step 1 of 11: Run the test suite (US1, US2, US3, US4)

**Why this step:** It proves the decoding rules, the budget owners, the threshold baselines, and the bar layout before you touch the app.

**Run:**

```
make test 2>&1 | tail -3
```

**What you should see:** A final line saying the test run passed, with about 344 tests in 36 suites and no failures.

**If you see something else:** A failing suite name points at the area. `ConfigurationTests` covers decoding and validation, `BarLayoutTests` covers bar order and member shares, and `ThresholdTrackerTests` covers the baselines.

**Result:** passed (agent). Expected vs actual: ✔ "about 344 tests in 36 suites, no failures" → `✔ Test run with 344 tests in 36 suites passed after 0.172 seconds.`

### Step 2 of 11: Back up your configuration (US4)

**Why this step:** Later steps edit the real file, so you need a copy to restore. The listing also shows the legacy text labels.

**Run:**

```
cp ~/.config/llm-usage-menubar/config.json ~/.config/llm-usage-menubar/config.json.bak-004 && jq -c '(.accounts[] | {displayName, label, icon, groupId}), (.groups[] | {name, label, icon})' ~/.config/llm-usage-menubar/config.json
```

**What you should see:** Three lines, each still with a `label` value ("M", "VC", "V") and an icon (`brands:claude`, `solid:v`, `brands:google`). The Vertex account has `groupId` set.

**If you see something else:** "No such file" means there is no configuration yet. Launch the app once and come back.

**Result:** passed (agent). Expected vs actual: ✔ three entries with labels "M", "VC", "V" and icons `brands:claude`, `solid:v`, `brands:google`; ✔ Vertex account `"groupId":"grp-vertex"`. Backup written to `config.json.bak-004`.

### Step 3 of 11: Build and launch the app (US4, US1)

**Why this step:** The legacy file must load without being rewritten, and the bar and dropdown must show icons only.

**Needs:** Step 2

**Run:**

```
pkill -x LLMUsageMenuBar; make run 2>&1 | tail -1 && sleep 5 && jq '[.accounts[], .groups[]] | map(has("label")) | all' ~/.config/llm-usage-menubar/config.json
```

**What you should see:** `open "build/AgentMeter.app"`, then `true`: every entry still has its label key, because loading does not rewrite the file. In the menu bar, entries show icons with percents and no letters. The dropdown shows each entry as its icon followed by its name, with no configuration error.

**If you see something else:** A configuration error in the dropdown means the legacy file was rejected (FR-006).

**Result:** passed (agent ran the command, user checked the UI). Expected vs actual: ✔ `open "build/AgentMeter.app"`, app running; ✔ `true` (labels still in the file after load); ✔ user confirmed icons only in the bar, icon plus name in the dropdown, no configuration error.

### Step 4 of 11: Use the same icon twice (US1)

**Why this step:** Duplicate icons must be allowed, and an icon can be changed but never removed.

**Needs:** Step 3

**Do:**

1. Open Settings, then the Accounts tab, and select "Claude Code via Vertex".
2. Check that there is no text label field. The icon row shows a glyph, its name, and "Choose…", with no "Remove" button.
3. Choose the Claude icon (the same one "Claude Max" uses) and save.

**What you should see:** The save succeeds with no duplicate warning. In the account list, both accounts show the Claude icon next to their names.

**If you see something else:** A message about a label already in use means the uniqueness rule is still active (FR-003).

**Result:** passed (user). User confirmed there is no text field and no Remove button, and the Claude icon on the Vertex account was saved without a duplicate warning.

### Step 5 of 11: Check the saved file (US1, US4)

**Why this step:** Saving must write icons only and drop every text label.

**Needs:** Step 4

**Run:**

```
jq -c '{labels: ([.accounts[], .groups[]] | map(has("label")) | any), icons: [.accounts[].icon, .groups[].icon]}' ~/.config/llm-usage-menubar/config.json
```

**What you should see:** `"labels":false`, and the icons `["brands:claude","brands:claude","brands:google"]`.

**If you see something else:** `"labels":true` means the writer still emits labels (FR-007).

**Result:** passed (agent). Expected vs actual: ✔ `{"labels":false,"icons":["brands:claude","brands:claude","brands:google"]}`.

### Step 6 of 11: Give the Vertex account its own budget (US2)

**Why this step:** This is the main new structure: a token-based account with its own budget and no group.

**Needs:** Step 5

**Do:**

1. In Settings, Accounts, with "Claude Code via Vertex" selected, set **Budget** to **Own budget**.
2. Check the prefilled values: Monthly, 300, shown in bar, and the group's thresholds. Keep them and save.
3. Look at the list of budget groups.

**What you should see:** The account now shows its own budget fields. The group "Vertex weekly" is gone, because its last member left (FR-014).

**If you see something else:** If the group still exists with no members, the empty-group deletion did not run.

**Result:** passed as specified (user), with a UX finding. The account switched to its own budget and "Vertex weekly" was deleted, as FR-014 requires. However, the Budget picker then offers only "Own budget". With no group left, settings has no way to attach the account to a group again, because groups can only be created from the new-account sheet. Captured as the inbox idea `explicit-group-management` (Add and Remove buttons for groups, no implicit creation or deletion). Step 9 restores the group from the backup.

### Step 7 of 11: Check the own budget in the file (US2)

**Why this step:** The file must hold the budget nested on the account, with no `groupId`.

**Needs:** Step 6

**Run:**

```
jq -c '{account: (.accounts[] | select(.type=="tokenBased") | {groupId, budget}), groups: (.groups | length)}' ~/.config/llm-usage-menubar/config.json
```

**What you should see:** `"groupId":null`, a `budget` object with `"period":"monthly"` and `"budgetUSD":300`, and `"groups":0`.

**If you see something else:** A `groupId` next to a `budget` would be a contradictory state that the app must never write (FR-008).

**Result:** passed (agent). Expected vs actual: ✔ `{"account":{"groupId":null,"budget":{"budgetUSD":300,"period":"monthly","shownInBar":true,"thresholds":[80,100]}},"groups":0}`.

### Step 8 of 11: See the own budget in the dropdown and the bar (US2)

**Why this step:** A standalone account must behave like a group everywhere.

**Needs:** Step 7

**Do:**

1. Choose Refresh in the dropdown.
2. Find "Claude Code via Vertex" as its own budget entry and expand Details.
3. Look at the menu bar.

**What you should see:** The entry shows "$X of $300.00 per month (P%)", with a reset on Nov 1 and a breakdown with a day row. The bar shows its Claude icon with the same P%, after Claude Max's entry.

**If you see something else:** If the entry has no percent or reset, the account was not treated as a budget owner (FR-010).

**Result:** passed (user). User confirmed the own budget entry ("of $300.00 per month", Nov 1 reset, breakdown) in the dropdown and the account's icon with its percent in the bar.

### Step 9 of 11: Show a group member's share in the bar (US3)

**Why this step:** A member must be able to show its share of the group budget in the bar. This step brings back your original group from the backup and turns on the member's bar toggle.

**Needs:** Step 2

**Run:**

```
jq '(.accounts[] | select(.type=="tokenBased")) |= (.shownInBar = true)' ~/.config/llm-usage-menubar/config.json.bak-004 > /tmp/agentmeter-004.json && cp /tmp/agentmeter-004.json ~/.config/llm-usage-menubar/config.json && jq -c '.accounts[] | select(.type=="tokenBased") | {groupId, shownInBar}' ~/.config/llm-usage-menubar/config.json
```

Then choose Refresh in the dropdown and open Settings for the Vertex account.

**What you should see:**
- The command prints `{"groupId":"grp-vertex","shownInBar":true}`.
- The bar shows the group's Google icon with its percent, then right after it the Vertex account's icon with the same percent, since it is the only member.
- The dropdown shows the member's spend followed by "(P%)".
- In Settings, the toggle "Show this account's share in the menu bar" is on.

**If you see something else:** If the member's bar entry is missing, the member toggle is not read (FR-016). If its percent differs from the group's while it is the only member, the share computation is off (FR-017).

**Result:** passed (agent wrote the file, user checked the UI). Expected vs actual: ✔ `{"groupId":"grp-vertex","shownInBar":true}`; ✔ user confirmed the bar shows the group's entry followed directly by the member's icon with the same percent, the dropdown shows "(P%)" next to the member, and the Settings toggle is on.

### Step 10 of 11: Reject a contradictory hand edit (US2)

**Why this step:** A token-based account that names a group and also carries its own budget must be refused, and the last valid configuration must stay in effect.

**Needs:** Step 9

**Run:**

```
jq '(.accounts[] | select(.type=="tokenBased")) |= (.budget = {"budgetUSD": 50})' ~/.config/llm-usage-menubar/config.json > /tmp/agentmeter-004-bad.json && cp /tmp/agentmeter-004-bad.json ~/.config/llm-usage-menubar/config.json
```

Then choose Refresh in the dropdown.

**What you should see:** The dropdown shows a configuration error, and the bar and entries keep the values from step 9.

**If you see something else:** If a $50 budget appears, the contradictory state was accepted (FR-008).

**Result:** passed (agent wrote the file, user checked the dropdown). Expected vs actual: ✔ file has `{"groupId":"grp-vertex","budget":{"budgetUSD":50}}`; ✔ user confirmed a configuration error with the step 9 values kept.

### Step 11 of 11: Restore your configuration (US4)

**Why this step:** It puts back the file you started with.

**Needs:** Step 2

**Run:**

```
cp ~/.config/llm-usage-menubar/config.json.bak-004 ~/.config/llm-usage-menubar/config.json && rm -f /tmp/agentmeter-004.json /tmp/agentmeter-004-bad.json && jq -c '[.accounts[].displayName, .groups[].name]' ~/.config/llm-usage-menubar/config.json
```

**What you should see:** `["Claude Max","Claude Code via Vertex","Vertex weekly"]`. After the next refresh the dropdown shows your original setup with no error.

**If you see something else:** If the copy fails, the backup is still at `~/.config/llm-usage-menubar/config.json.bak-004`.

**Result:** passed (agent ran, user checked). Expected vs actual: ✔ `["Claude Max","Claude Code via Vertex","Vertex weekly"]`; ✔ user confirmed the configuration error disappeared after refresh.

## Not covered here

- **Threshold notifications for an own budget, and baselines after moving an account (US2, FR-012, FR-015):** these need real spend to cross a threshold. Step 1 covers them through `ThresholdTrackerTests`.
- **Bar ordering with several members and hidden groups (FR-019, FR-020):** your configuration has only one member. Step 1 covers it through `BarLayoutTests`.

## Coverage

- **US1 (icon-only labels):** steps 1, 3, 4 and 5.
- **US2 (own budget):** steps 1, 6, 7, 8 and 10.
- **US3 (member share in the bar):** steps 1 and 9.
- **US4 (legacy configs):** steps 2, 3, 5 and 11.

## Results

All 11 steps passed (2026-10-14).

- **Tests:** the full suite passed (344 tests).
- **Legacy loading:** the legacy file with text labels loaded without being rewritten. The bar and dropdown showed icons only.
- **Duplicate icons:** two accounts saved with the same Claude icon, and the saved file contained icons but no labels.
- **Own budget:** the Vertex account switched to its own monthly $300 budget, stored as a nested `budget` without `groupId`. It appeared as its own entry in the dropdown and the bar.
- **Member share:** with the group restored and the member's bar toggle on, the bar showed the group followed by the member's share, and the dropdown showed the same percent.
- **Rejected edit:** a hand edit with both `groupId` and `budget` was rejected, and the last valid configuration stayed in effect.

**UX finding (step 6):** after the only member moved to its own budget, the implicitly deleted group could not be recreated from settings, because the Budget picker offered only "Own budget". This is captured as the inbox idea `explicit-group-management`. Notifications and multi-member bar ordering were not tried by hand; the unit tests cover them.
