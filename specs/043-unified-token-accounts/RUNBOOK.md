---
runbook_version: 1
feature: 043-unified-token-accounts
status: passed
mode: light
steps_total: 13
step_results: passed,passed,passed,passed,passed,passed,passed,passed,passed,passed,passed,passed,passed
drafted_at: 61f7f17
drafted_fingerprint: ef25533ac1cb78b0fb9b11ca8797e0a8e9acd5df58465ca928476b9600fefc66
tested_at: 08ca959
tested_fingerprint: 3abd0f6ebb258b3674605adc25b4f296cc5485f24e8d845447d2540052aba65e
updated: 2026-11-03
---

# Try it: Unified Token Accounts

<!-- runbook-status -->
> **Status:** passed · 13 of 13 steps (13 passed) · Mode: light · Tested at 08ca959 · 2026-11-03
<!-- /runbook-status -->














## What you're testing

A token-based account now has one budget choice besides the groups: an own budget whose amount is optional. An empty amount means no limit (what spec 041 called "No limit"). Without an amount the dropdown shows real spend when the account's models have prices, and tokens (plus the optional "Value as" line) when they do not. A per-account "Dropdown shows" pop-up (Automatic, Percent, Tokens, Money) can override the headline. Existing spec 041 configurations load unchanged.

The journey: run the tests, build and open the demo app, look at the "Free models" and "API key" sections and the menu bar, then use Settings to inspect "API key", give it an amount, change its headline, take the amount away again and check the Menu Bar tab. An optional last part loads your real configuration (with a backup first) to see the migration.

## Test environment

No fixtures. The demo app writes its own configuration from `Resources/demo/default.json` on every launch and never reads or changes your real AgentTacho configuration or agent data. Steps 11 to 13 use your real configuration and make a backup first.

## Steps

### Step 1 of 13: Run the test suites (US1, US2, US3, US4, US5)

**Why this step:** the core logic (configuration form and migration, headline choice, money texts, Value as on unpriced models, threshold rules) is covered by tests; this proves the branch is green before you look at the UI.

**Run:**

```
make test
```

**What you should see:** both test targets pass with no failures, among them `NoLimitConfigurationTests`, `DropdownShowTests`, `OwnBudgetFormTests`, `HeadlineTextTests` and `NoLimitPresentationTests`.

**If you see something else:** a failure in `MatchRuntimeTests.tenThousandLinesStayFast` under load is a known timing flake; rerun. Any other failure is a real regression.

**Result:** passed (agent, 2026-11-03). Log: `specs/043-unified-token-accounts/.walkthrough/step-1.log`.

```text
✔ Test run with 2635 tests in 286 suites passed after 4.238 seconds.
✔ Test run with 78 tests in 7 suites passed after 0.095 seconds.
```

Expected vs actual: ✔ both targets pass; ✔ suites `NoLimitConfigurationTests`, `DropdownShowTests`, `OwnBudgetFormTests`, `HeadlineTextTests`, `NoLimitPresentationTests` passed.

### Step 2 of 13: Build the demo app (US1)

**Why this step:** the demo app plays a scenario with two accounts without an amount ("Free models" and "API key"), so you can see the UI without real accounts.

**Run:**

```
make app-demo
```

**What you should see:** the build ends without errors and `build/AgentTacho Demo.app` exists.

**If you see something else:** a compile error means the branch does not build; stop here.

**Result:** passed (agent, 2026-11-03). Log: `specs/043-unified-token-accounts/.walkthrough/step-2.log`.

```text
Built build/AgentTacho Demo.app
```

Expected vs actual: ✔ build without errors; ✔ `build/AgentTacho Demo.app` exists.

### Step 3 of 13: Open the demo app (US1)

**Why this step:** the dropdown and Settings are only visible in the running app.

**Needs:** step 2.

**Run:**

```
open "build/AgentTacho Demo.app"
```

**What you should see:** the AgentTacho Demo icon appears in the menu bar with the demo's bar entries.

**If you see something else:** if a real AgentTacho is running too, both icons appear; that is fine, use the demo one.

**Result:** passed (agent started it with `open`, process running from the worktree build; maintainer confirmed the icon and bar entries, 2026-11-03).

### Step 4 of 13: Free models looks as before (US1, US4)

**Why this step:** an account of free models without an amount must look exactly like spec 041's No limit section.

**Needs:** step 3.

**Do:**

1. Click the AgentTacho Demo icon to open the dropdown.
2. Find the "Free models" section and hover its headline and its second line.

**What you should see:** a compact token headline (for example `48.2M`), the line `≈ $… at claude-opus-5-5 prices` left of the reset text, no bar, no percent, no pace. The headline tooltip reads `48.2 million tokens this month`.

**If you see something else:** a `$` headline here would mean Automatic picked Money for an account with only unpriced records (FR-011).

**Result:** passed on the second try (maintainer, 2026-11-03). First try: everything as expected, but the maintainer asked for the tooltip to say "48.2 million" instead of the exact 8-digit count. Fixed in `9151994` (spec 043 FR-013 amended), demo rebuilt and relaunched; the retry showed `48.2 million tokens this month`. The expectation above was corrected to the new tooltip.

### Step 5 of 13: API key shows real spend (US2)

**Why this step:** this is the pay-as-you-go case: priced models, no amount.

**Needs:** step 4.

**Do:**

1. In the same dropdown, find the "API key" section (right after "Free models").
2. Hover the headline; open its Details.
3. Look at the menu bar.

**What you should see:** a whole-dollar headline such as `$4` without `≈`; tooltip `$4.xx spent this month`; the line `spent this month` left of the reset text; no bar or percent; Details list each model with its cost. The menu bar has no entry for "API key" or "Free models".

**If you see something else:** a token headline means the records were not priced; `≈` anywhere in this section means real and notional dollars got mixed up (FR-013).

**Result:** passed (maintainer, 2026-11-03): whole-dollar headline without ≈, tooltip `$… spent this month`, `spent this month` line, no bar or percent, cost per model in Details, no menu bar entry for either account.

### Step 6 of 13: The own budget editor without an amount (US1, US3)

**Why this step:** Settings must show one budget choice with an optional amount and disabled controls that explain themselves.

**Needs:** step 3.

**Do:**

1. Open Settings from the dropdown, tab Accounts, select "API key".
2. Open the budget pop-up, then close it.
3. Look at the Amount field, the thresholds, "Show in menu bar", "Price tokens as" and "Dropdown shows"; hover the disabled controls.
4. Open the "Dropdown shows" pop-up.

**What you should see:** the budget pop-up lists `Own budget` and the groups, no `No limit`. Amount is empty with the placeholder `No limit`. Thresholds and "Show in menu bar" are disabled, the toggle unchecked, with the tooltip `Set a monthly budget to use thresholds and the menu bar.`. "Price tokens as" is enabled. "Dropdown shows" offers Automatic, Percent, Tokens, Money with Percent disabled. The list subtitle reads `Other provider · no limit / month`.

**If you see something else:** a hidden (instead of disabled) control departs from FR-018.

**Result:** passed on the third try (maintainer, 2026-11-03). Try 1: the maintainer asked for the tooltips to name the budget ("Set a monthly budget to ...") instead of "an amount", and for "Value as" to be renamed; it is now "Price tokens as" (`2c4c670`). Try 2: Percent in "Dropdown shows" was still selectable without an amount, because a SwiftUI Picker pop-up ignores `.disabled` on its items; it is now a Menu of toggles (fix commit after `2c4c670`). Try 3: everything as expected. The step text above was corrected to the new wording.

### Step 7 of 13: Give API key an amount (US5)

**Why this step:** entering an amount turns the account into a capped budget with the usual percent, thresholds and menu bar entry.

**Needs:** step 6.

**Do:**

1. Type `300` into the Amount field.
2. Look at the thresholds, "Show in menu bar" and "Price tokens as".
3. Save, then open the dropdown and look at "API key" and the menu bar.

**What you should see:** after typing, the thresholds show 80% and 100% and "Show in menu bar" is checked and enabled; "Price tokens as" becomes disabled with the tooltip `Price tokens as applies only without a monthly budget.`. After saving, the "API key" section shows a percent headline with the amount line `$… of $300/month` and a bar, and the menu bar gains an entry for it.

**If you see something else:** no menu bar entry after saving means the amount did not turn the account into a budget owner (FR-008).

**Result:** passed (maintainer, 2026-11-03): thresholds 80%/100%, toggle checked and enabled, Price tokens as disabled with its tooltip; after saving a percent headline with `$… of $300/month` and a bar, and a new menu bar entry. The step text was updated to the renamed pop-up before running.

### Step 8 of 13: Show tokens on a capped account (US3)

**Why this step:** the headline choice must change only the headline, not the rest of the section or the menu bar.

**Needs:** step 7.

**Do:**

1. In Settings, set "Dropdown shows" of "API key" to Tokens and save.
2. Open the dropdown and look at "API key" and the menu bar.
3. Set it to Money and save; look again.

**What you should see:** with Tokens the headline is a compact token count; with Money it is a whole-dollar amount. In both cases the amount line, bar and pace stay as in step 7, and the menu bar entry still shows a percent.

**If you see something else:** a changed menu bar entry would break FR-010.

**Result:** passed (maintainer, 2026-11-03): Tokens and Money changed only the headline; amount line, bar and pace unchanged; the menu bar entry kept its percent.

### Step 9 of 13: Take the amount away again (US5)

**Why this step:** clearing the amount must return the account to no limit and keep its settings for later.

**Needs:** step 8.

**Do:**

1. In Settings, set "Dropdown shows" back to Automatic, clear the Amount field and save.
2. Open the dropdown and look at "API key" and the menu bar.
3. In Settings, type `300` again and look at the thresholds and the toggle, then clear the field again and save.

**What you should see:** after clearing, the "API key" section is back to the `$…` spend headline and `spent this month`, and its menu bar entry is gone. Typing `300` again shows the thresholds and toggle as they were in step 7.

**If you see something else:** saving refused with an empty amount would mean spec 041's FR-018 refusal is still active (FR-019).

**Result:** passed (maintainer, 2026-11-03): spend headline and `spent this month` back after clearing, menu bar entry gone; thresholds and toggle as in step 7 after typing 300 again; saving with an empty amount works.

### Step 10 of 13: The Menu Bar tab (US1)

**Why this step:** accounts without an amount stay listed in the Menu Bar tab, but cannot be put into the bar.

**Needs:** step 9.

**Do:**

1. In Settings, open the Menu Bar tab.
2. Find "Free models" and "API key"; hover their checkboxes.

**What you should see:** both rows carry the caption `No limit` and a disabled, unchecked "Show in bar" checkbox with the tooltip `Set an amount to show this account in the menu bar.`.

**If you see something else:** a missing checkbox means the spec 041 behavior (hidden) is still there (FR-020).

**Result:** passed on the second try (maintainer, 2026-11-03). Try 1: caption `No limit` and the tooltip were there, but the disabled checkbox looked like an ordinary unchecked one; it is now drawn faded (`fix(settings): fade the unavailable Show in bar checkbox`). Try 2: as expected.

### Step 11 of 13: Back up your real configuration (US4)

**Why this step:** the branch build rewrites a spec 041 configuration in the new form on its next save, which the released AgentTacho cannot read. A backup lets you go back.

**Run:**

```
osascript -e 'quit app "AgentTacho Demo"'; osascript -e 'quit app "AgentTacho"'; cp ~/.config/agenttacho/config.json ~/.config/agenttacho/config-before-043.json
```

**What you should see:** both apps quit and `~/.config/agenttacho/config-before-043.json` exists.

**If you see something else:** an error from `cp` means the configuration is elsewhere; do not continue with steps 12 and 13.

**Result:** passed (agent, 2026-11-03): both apps quit, `cp` exited 0, `~/.config/agenttacho/config-before-043.json` (3.4K) exists. The configuration has no `noLimit` key, so it holds no spec 041 No limit account.

### Step 12 of 13: Load your real configuration with the branch build (US4)

**Why this step:** your own No limit account for free gateway models must look as before and the migration must leave a note in the log.

**Needs:** step 11.

**Run:**

```
make app && open build/AgentTacho.app && sleep 20 && rg -n "No limit is now an own budget without an amount" ~/Library/Logs/AgentTacho/usage.log
```

**What you should see:** one log line per spec 041 No limit account in your configuration, worded `account "<name>": No limit is now an own budget without an amount; the next save writes the new form`. In the dropdown, that account looks as before (token headline and its value line, if it has a Value as model).

**If you see something else:** no log line can also mean your configuration has no No limit account; check with `rg -n noLimit ~/.config/agenttacho/config-before-043.json`.

**Result:** passed, partly (agent, 2026-11-03): `Built build/AgentTacho.app`, the branch build loaded the real configuration and refreshed (`[refresh] done in 3.507 s, 0 source error(s)`), no load errors. No migration log line, as expected for a configuration without a No limit account (see step 11); the migration note itself is covered by `NoLimitConfigurationTests` in step 1.

### Step 13 of 13: Restore the backup (US4)

**Why this step:** puts your released AgentTacho back on a configuration it can read.

**Needs:** step 11.

**Run:**

```
osascript -e 'quit app "AgentTacho"'; cp ~/.config/agenttacho/config-before-043.json ~/.config/agenttacho/config.json
```

**What you should see:** the branch build quits and the configuration is the backup again; your installed AgentTacho starts normally afterwards.

**If you see something else:** keep the backup file until the released version with spec 043 is installed.

**Result:** passed (agent, 2026-11-03): branch build quit; `cmp` showed the configuration unchanged by the branch build; backup copied back (`cp` exited 0); the installed `/Applications/AgentTacho.app` restarted (process running).

## Not covered here

- Hand-edited configuration cases (`budgetUSD` 0 or `null`, invalid legacy `noLimit` combinations, unknown `show` values): the demo rewrites its configuration on every launch, so `NoLimitConfigurationTests` in step 1 covers them.
- Remaining mode with a Money headline over the amount ("−$12"): the demo has no capped account over its amount with Money selected; `HeadlineTextTests` in step 1 covers it.
- Mixed accounts (priced and free models without an amount, with a Value as model): no demo account mixes both; `NoLimitPresentationTests` covers it.

## Coverage

- US1: steps 1, 3, 4, 6, 10.
- US2: steps 1, 5.
- US3: steps 1, 6, 8.
- US4: steps 1, 4, 11 to 13.
- US5: steps 1, 7, 9.

## Results

13 steps: 13 passed (step 12 partly: the real configuration has no No limit account to migrate).

The feature works as specified in the demo and on the maintainer's real configuration: an own budget without an amount shows tokens with the Price tokens as line for free models and real spend for priced ones, stays out of the menu bar, and turns into a capped budget when an amount is entered and back when it is cleared; "Dropdown shows" changes only the headline. Four changes came out of the walkthrough: the token tooltip uses "million"/"billion" (step 4), "Value as" became "Price tokens as" and the help texts name the period's budget (step 6), "Dropdown shows" became a menu so Percent is really disabled (step 6), and the Menu Bar tab's unavailable checkbox is drawn faded (step 10).
