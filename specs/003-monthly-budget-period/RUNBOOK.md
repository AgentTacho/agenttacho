---
runbook_version: 1
feature: 003-monthly-budget-period
status: passed
mode: light
steps_total: 9
step_results: passed,passed,passed,passed,passed,passed,passed,passed,passed
drafted_at: 971136c
drafted_fingerprint: 34fd825667c3f45327355ac7eefdbb00169d59f92f08039ffce67208851fc33b
tested_at: 7723f65
tested_fingerprint: a20f0ecc16528e7e5d5ce18e7fe29a2ec17e8328d07d6546d0d4e3e7a47b2579
updated: 2026-10-14
---

# Try it: Monthly Budget Period

<!-- runbook-status -->
> **Status:** passed · 9 of 9 steps (9 passed) · Mode: light · Tested at 7723f65 · 2026-10-14
<!-- /runbook-status -->










## What you're testing

Budget groups can now track a monthly budget (from the 1st at local midnight to the end of the month) instead of a weekly one. The journey goes like this:

1. Build the app and run the test suite, with your real configuration backed up.
2. Switch a group to Monthly in Settings.
3. Check that the saved file uses the new form.
4. Check the dropdown and the diagnostic log.
5. Confirm that a bad hand edit is rejected.
6. Restore your configuration.

## Test environment

No fixtures. The journey uses your own `~/.config/agentmeter/config.json`, which is backed up in step 2 and restored in the last step, and your existing Claude Code session logs (read only). You need at least one budget group with a token-based account.

## Steps

### Step 1 of 9: Run the test suite (US1, US3, US4)

**Why this step:** It proves the month window, the decoding rules, and the threshold behaviour on the current build before you touch the app.

**Run:**

```
make test 2>&1 | tail -5
```

**What you should see:** A final line saying the test run passed, with about 306 tests in 27 suites and no failures.

**If you see something else:** A failing suite name points at the area (for example `ConfigurationTests` means legacy decoding, `AggregatorTests` means monthly windows).

**Result:** passed (agent). Expected vs actual: ✔ "about 306 tests in 27 suites, no failures" → `✔ Test run with 306 tests in 27 suites passed after 0.153 seconds.`

### Step 2 of 9: Back up your configuration (US4)

**Why this step:** Later steps edit the real configuration file, so you need a copy to restore.

**Run:**

```
cp ~/.config/agentmeter/config.json ~/.config/agentmeter/config.json.bak-003 && jq '.groups[] | {name, period, budgetUSD, weeklyBudgetUSD}' ~/.config/agentmeter/config.json
```

**What you should see:** One object per group. A file from the previous version shows `"period": null`, `"budgetUSD": null`, and a number in `weeklyBudgetUSD`.

**If you see something else:** "No such file" means the app has never saved a configuration. Launch it once (step 3) and come back.

**Result:** passed (agent). Expected vs actual: ✔ "previous-version form" → one group `"Vertex weekly"` with `"period": null`, `"budgetUSD": null`, `"weeklyBudgetUSD": 1000`; backup written to `config.json.bak-003`.

### Step 3 of 9: Build and launch the app (US2, US4)

**Why this step:** The legacy file must load unchanged in the new build.

**Needs:** Step 2

**Run:**

```
pkill -x AgentMeter; make run && sleep 5 && jq '.groups[] | {name, weeklyBudgetUSD}' ~/.config/agentmeter/config.json
```

**What you should see:** `Built build/AgentMeter.app`, then the app appears in the menu bar. The groups still show their old `weeklyBudgetUSD` values, because loading must not rewrite the file. The dropdown lists every group as before, reading "per week".

**If you see something else:** A configuration error in the dropdown means the legacy file was rejected (US4 failure).

**Result:** passed (agent ran the command, user checked the dropdown). Expected vs actual: ✔ `Built build/AgentMeter.app`, app running; ✔ `"weeklyBudgetUSD": 1000` unchanged after load; ✔ user confirmed "Vertex weekly" shows "of $1,000.00 per week" with a weekly reset and no configuration error.

### Step 4 of 9: Switch a group to Monthly (US2)

**Why this step:** This is the main user action: choosing the period in Settings.

**Needs:** Step 3

**Do:**

1. Open the dropdown and choose Settings, then the Accounts tab.
2. Select a budget group. Set **Period** to **Monthly** and enter a monthly amount (for example 400).
3. Save, then look at the group list summary.

**What you should see:** The amount field is labelled "Monthly budget", the summary reads "$400.00 per month, N member(s)", and the thresholds editor talks about "the monthly budget".

**If you see something else:** A label still saying "weekly" means a FR-014 wording gap.

**Result:** passed (user). User confirmed the period picker exists, and after switching to Monthly the amount label, group summary ("per month"), and thresholds text are all period-aware.

### Step 5 of 9: Check the saved file (US2, US4)

**Why this step:** Saving must write the new form and drop the legacy key.

**Needs:** Step 4

**Run:**

```
jq '.groups[] | {name, period, budgetUSD, has_legacy: has("weeklyBudgetUSD")}' ~/.config/agentmeter/config.json
```

**What you should see:** Every group has a `period` and a `budgetUSD`, and `has_legacy` is `false`. The group you switched has `"period": "monthly"` and your amount.

**If you see something else:** `has_legacy: true` means the writer still emits the old key (FR-004).

**Result:** passed (agent). Expected vs actual: ✔ "period and budgetUSD, no legacy key" → `"period": "monthly"`, `"budgetUSD": 300`, `"has_legacy": false` for group "Vertex weekly".

### Step 6 of 9: Read the month-to-date numbers in the dropdown (US1)

**Why this step:** The group must measure spend over the calendar month, not the week.

**Needs:** Step 5

**Do:**

1. Choose Refresh in the dropdown and wait for it to finish.
2. Look at the monthly group's line, then expand its Details.

**What you should see:** "$X of $400.00 per month (P%)" and "resets" on the 1st of next month at 00:00. Details shows a day row starting on the 1st and ending today, wrapped in rows of 7 with day-of-month numbers. If you also have a weekly group, it keeps its weekly reset and single-row weekday trend.

**If you see something else:** A reset date within the next 7 days means the group still uses the weekly window.

**Result:** passed after fix and retry (user). First run: day row showed Oct 1 to 14 in two rows of 7 as specified, but every cost cell wrapped "US$" onto a second line. Fix: day cells now show compact whole dollars without the currency suffix ("409", "1.5K", "<1"), with the exact amount on hover. Retry: user confirmed one-line cells, exact value on hover, "of $300.00 per month" and a reset on Nov 1 00:00.

### Step 7 of 9: Confirm the window in the diagnostic log (US1)

**Why this step:** The log shows the exact window boundaries and the refresh time.

**Needs:** Step 6

**Run:**

```
rg "monthly|record\(s\) since|done in" ~/Library/Logs/agentmeter/usage.log | tail -4
```

**What you should see:** A `group ... (monthly, <1st 00:00 local as UTC> to <next 1st>, <your time zone>)` line, a `record(s) since` line whose start is no later than the 1st, and a `done in N s` line under 10 seconds.

**If you see something else:** A `record(s) since` start after the 1st means the collection window misses early-month usage.

**Result:** passed (agent). Expected vs actual:
- ✔ "monthly group line with local month bounds" → `group Google (monthly, 2026-09-30T22:00:00Z to 2026-10-31T23:00:00Z, Europe/Berlin): 1545.09949045 of 300 USD (515%)`. The end offset differs from the start (CEST to CET on Oct 25), confirming DST-aware boundaries.
- ✔ "record(s) since no later than the 1st" → `ok: 36971 record(s) since 2026-09-30T22:00:00Z`
- ✔ "done in under 10 s" → `done in 3.358 s` (launch refresh, full read)
- Note: the first run of the command went through an output filter that truncated lines; re-run unfiltered with the same command.

### Step 8 of 9: Reject an invalid hand edit (US4)

**Why this step:** A monthly group carrying only the legacy amount must be refused, and the last valid configuration must stay in effect.

**Needs:** Step 5

**Run:**

```
jq '(.groups[0] | .period) = "monthly" | (.groups[0]) |= (del(.budgetUSD) | .weeklyBudgetUSD = 50)' ~/.config/agentmeter/config.json > /tmp/agentmeter-bad.json && cp /tmp/agentmeter-bad.json ~/.config/agentmeter/config.json
```

Then choose Refresh in the dropdown.

**What you should see:** The dropdown shows a configuration error, and the groups keep showing the values from step 6.

**If you see something else:** If the group now shows a $50 monthly budget, the legacy amount was silently accepted for a monthly group (FR-004a).

**Result:** passed (agent wrote the file, user checked the dropdown). Expected vs actual: ✔ file now has `{"period":"monthly","budgetUSD":null,"weeklyBudgetUSD":50}`; ✔ user confirmed a configuration error in the dropdown with the group still on its $300 monthly budget.

### Step 9 of 9: Restore your configuration (US4)

**Why this step:** It puts back the file you started with.

**Needs:** Step 2

**Run:**

```
cp ~/.config/agentmeter/config.json.bak-003 ~/.config/agentmeter/config.json && rm /tmp/agentmeter-bad.json && jq '.groups | length' ~/.config/agentmeter/config.json
```

**What you should see:** The number of groups you had at the start. After the next refresh, the dropdown shows your original setup with no error.

**If you see something else:** If the copy fails, the backup is still at `~/.config/agentmeter/config.json.bak-003`.

**Result:** passed (agent ran, user checked), with a user-chosen variant: instead of restoring the weekly backup, the broken group was repaired to the monthly $300 setup from step 4 with `jq '(.groups[0]) |= (del(.weeklyBudgetUSD) | .period = "monthly" | .budgetUSD = 300)'`; the backup file was kept. Expected vs actual: ✔ `"period": "monthly"`, `"budgetUSD": 300`, `"has_legacy": false`; ✔ user confirmed the configuration error disappeared after refresh.

## Not covered here

- **Month rollover and threshold re-arming (US3):** this needs the clock to cross midnight on the 1st. It is covered by `ThresholdTrackerTests` and `WindowResolverTests` in step 1.
- **Time zone change while running:** changing the system time zone mid-test is disruptive. It is covered by `WindowResolverTests`.
- **Threshold notifications (US3) end to end:** this needs real spend to cross a threshold. It is covered by unit tests in step 1.

## Coverage

- **US1 (track monthly):** steps 1, 6 and 7.
- **US2 (choose in settings):** steps 3, 4 and 5.
- **US3 (notifications):** step 1 only (unit tests), see Not covered here.
- **US4 (legacy configs):** steps 2, 3, 5, 8 and 9.

## Results

All 9 steps passed (2026-10-14), one after a fix. The full suite passed (306 tests). The legacy weekly configuration loaded without being rewritten. In Settings the group switched to Monthly with period-aware labels, and saving wrote `period`/`budgetUSD` without the legacy key. The dropdown showed month-to-date spend with a Nov 1 reset and a day row from Oct 1 to today wrapped in rows of 7. The diagnostic log confirmed DST-aware local month boundaries and a 3.4 s full refresh. An invalid monthly-with-legacy-amount edit was rejected while the last valid configuration stayed in effect.

Fixed during the session: day cells wrapped "US$" onto a second line. They now show compact whole dollars with the exact amount on hover. Not tried by hand: month rollover, a live time zone change, and notifications end to end; the unit tests cover these.
