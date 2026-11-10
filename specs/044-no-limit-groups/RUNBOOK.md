---
runbook_version: 1
feature: 044-no-limit-groups
status: passed
mode: light
steps_total: 10
step_results: passed,passed,passed,passed,passed,passed,passed,passed,passed,passed
drafted_at: 443865d
drafted_fingerprint: d66db9a061e4aa5f338b717c00469a12107fb210993f1de013027b9d5aa48239
tested_at: eed8b15
tested_fingerprint: e731b12066b396eaa317f29567b95d96c9b24581a3de1e95158015657358c26f
updated: 2026-11-10
---

# Try it: Budget Groups Without an Amount

<!-- runbook-status -->
> **Status:** passed · 10 of 10 steps (10 passed) · Mode: light · Tested at eed8b15 · 2026-11-10
<!-- /runbook-status -->












## What you're testing

A budget group can now leave its amount empty. Such a group adds up its members' spend (or tokens) in one dropdown section, lists each member without a share percent, and never shows a percent, bar or menu bar entry. Groups also get "Price tokens as" and "Dropdown shows", like an account without an amount.

The journey: run the tests, build and open the demo app, look at the new "Open models" group in the dropdown and the menu bar, edit it in Settings (headline choice, adding and clearing an amount, the saved file), check the Menu Bar tab, and finally combine your own two free-model accounts into one group in the real app.

## Test environment

No fixtures. The demo app (`build/AgentTacho Demo.app`) runs next to an installed AgentTacho with its own configuration (`~/.config/agenttacho-demo`) and plays a made-up scenario; it reads no agent files, no keychain item and makes no network request. Step 10 uses your real AgentTacho and its configuration.

## Steps

### Step 1 of 10: Run the test suites (US1)

**Why this step:** the core rules (configuration, aggregation, headlines, member lines, Settings rules) are covered by tests; a green run is the baseline before looking at the UI.

**Run:**

```
make test && make test-release
```

**What you should see:** both targets finish without failures; the UsageCore summary reports about 2720 passing tests, DemoMode 79, and the release tests "266 passed, 0 failed".

**If you see something else:** a failure names the test and file; a failure in `GroupNoLimit*`, `MemberLineText*` or `DefaultScenarioTests` points at this feature.

**Result:** passed (agent). `make test`: 2720 tests in 297 suites passed, 79 tests in 7 suites passed; `make test-release`: 266 passed, 0 failed. Output: `.walkthrough/step-1.log` (7518 lines).

### Step 2 of 10: Build the demo app (US1)

**Why this step:** the demo build shows the new group with made-up data, so nothing real is needed to look at the UI.

**Needs:** Step 1

**Run:**

```
make app-demo && ls -d "build/AgentTacho Demo.app"
```

**What you should see:** the build ends without errors and the last line prints `build/AgentTacho Demo.app`.

**If you see something else:** a compile error in `Sources/AgentTacho` means the SwiftUI wiring broke; rerun `make test` first.

**Result:** passed (agent). `Built build/AgentTacho Demo.app`, last line `build/AgentTacho Demo.app`.

### Step 3 of 10: Open the demo app (US1)

**Why this step:** the following steps look at the running demo.

**Needs:** Step 2

**Run:**

```
open "build/AgentTacho Demo.app"
```

**What you should see:** a second AgentTacho item appears in the menu bar (the demo), next to your installed one if it runs.

**If you see something else:** if nothing appears, check `~/Library/Logs/agenttacho-demo/usage.log` for a startup error.

**Result:** passed (agent ran `open`, user confirmed). The demo process started (`build/AgentTacho Demo.app/Contents/MacOS/AgentTacho`); the user saw its menu bar item in step 4.

### Step 4 of 10: Look at the "Open models" section (US1)

**Why this step:** this is the feature's main promise: one section for free models from two harnesses, without a limit.

**Needs:** Step 3

**Do:**

1. Click the demo's menu bar item to open the dropdown.
2. Scroll to the last section before "Unassigned", "Open models".
3. Hover the headline amount and each member line amount.
4. Expand "Details", then press "Show account details".

**What you should see:** the section headline is a whole dollar amount ("$59") with "spent this month" and the reset time; no percent, no bar, no pace tick. Two member lines, "Open models (Claude Code)" and "Open models (Codex)", show a dollar amount each ("$46", "$12") and no "(NN%)". Tooltips give exact amounts with cents and "spent this month". Details show cost tables, and the member tables appear under each member's name.

**If you see something else:** a percent or bar means the group is still treated as a budget owner; member lines with "%" mean `MemberLineText` used the amount rule.

**Result:** passed (user). Section as expected: dollar headline with "spent this month", member lines with dollar amounts and no share, cost Details. The user asked where the "what it would cost at Opus 5.5" comparison shows: only through "Price tokens as", which values records of models without a price; the demo's open models have a price, so their spend is real and no value line appears. Step 10 was adjusted accordingly (no price overrides, group Price tokens as).

### Step 5 of 10: Check the menu bar (US1)

**Why this step:** a group without an amount must never take a menu bar entry, neither for itself nor as member shares.

**Needs:** Step 3

**Do:**

1. Look at the demo's menu bar item.

**What you should see:** the same entries as before this feature (subscriptions and the company budget); no entry for "Open models" or its two members.

**If you see something else:** an extra entry or a "…" placeholder means the bar layout did not skip the group.

**Result:** passed (user). No menu bar entry for "Open models" or its members.

### Step 6 of 10: Open the group editor (US2)

**Why this step:** the group must be editable in Settings with an empty amount.

**Needs:** Step 3

**Do:**

1. In the demo dropdown, click Settings (or press ⌘,).
2. Open the Groups tab and select "Open models".
3. Read the caption below the disabled thresholds and "Show in menu bar".

**What you should see:** the Groups list subtitle reads "no limit / month, 2 member(s)". The Amount field is empty with the placeholder "No limit". Thresholds and "Show in menu bar" are visible but disabled, "Show in menu bar" unchecked, with the caption "Set a monthly budget to use thresholds and the menu bar." below them. "Price tokens as" and "Dropdown shows" (Automatic) are enabled; in "Dropdown shows" the entry Percent is disabled.

**If you see something else:** an amount of 0 or an error under the field means the editor still requires an amount.

**Result:** passed (user) after a fix. First run: the help "Set a monthly budget to use thresholds and the menu bar." did not appear, because macOS shows no tooltip on a disabled control (also true for the spec 043 own budget editor). Fix: a visible caption below the disabled controls (`DisabledReason`), also for the member share toggle, and the Menu Bar tab row carries its help on the whole row. Retried with a rebuilt demo: captions visible. Runbook correction: "Hover the disabled thresholds" now reads as the visible caption.

### Step 7 of 10: Switch the headline to tokens (US3)

**Why this step:** "Dropdown shows" decides the measure of the section, its member lines and Details for a group without an amount, without a refresh.

**Needs:** Step 6

**Do:**

1. Set "Dropdown shows" to Tokens.
2. Open the dropdown and look at "Open models", then expand Details.

**What you should see:** the headline is a token count ("12.4M" style) with "this month"; both member lines show token counts without "%" and without "$"; Details show token tables. "Last refreshed" does not change.

**If you see something else:** dollar amounts in member lines mean they do not follow the group's measure.

**Result:** passed (user). Tokens in headline, member lines and Details.

### Step 8 of 10: Add an amount, then clear it again, and check the saved file (US4)

**Why this step:** switching between an amount and none must keep the group's settings and write the right configuration.

**Needs:** Step 6

**Do:**

1. Set "Dropdown shows" back to Automatic.
2. Enter 100 in the Amount field. Open the dropdown.
3. Back in Settings, clear the Amount field. Open the dropdown again.
4. Run the command below.

**Run:**

```
jq '.groups[] | select(.name == "Open models")' ~/.config/agenttacho-demo/config.json
```

**What you should see:** with 100 the section shows a percent headline, a bar, and member lines with "(NN%)", and the thresholds and "Show in menu bar" in the editor become enabled. After clearing, the section is back to step 4. The printed group has `period`, `thresholds`, `shownInBar`, no `budgetUSD` key and no `show` key.

**If you see something else:** a `"budgetUSD": null` or a `"show": "automatic"` in the file breaks the configuration contract.

**Result:** passed (user and agent). With 100: percent and bar; after clearing: back to step 4. Saved group: `"period": "monthly"`, `"thresholds": [80, 100]`, `"shownInBar": false`, no `budgetUSD`, no `show`.

### Step 9 of 10: Check the Menu Bar tab (US2)

**Why this step:** the Menu Bar tab must explain why the group and its members cannot be shown.

**Needs:** Step 3

**Do:**

1. In Settings, open the Menu Bar tab.
2. Find the "Open models" row and its two member rows; hover their checkboxes.
3. Open the Accounts tab and look at the subtitle of "Open models (Claude Code)".

**What you should see:** the group row's caption is "No limit", its checkbox disabled and unchecked, help "Set a monthly budget to show this group in the menu bar."; member rows' checkboxes are disabled and unchecked with "Set a monthly budget for the group to show this account in the menu bar."; the live preview shows none of them. The account's subtitle names "Open models, no limit / month".

**If you see something else:** an enabled checkbox means the arrangement rules do not know the group has no amount.

**Result:** passed (user). Captions, disabled checkboxes, row help, member subtitle and share toggle caption as expected.

### Step 10 of 10: Combine your free-model accounts in the real app (US1)

**Why this step:** the use case that started the feature: one section for "Free models (Claude Code)" and "Free models (Codex)". This needs the branch build installed as your AgentTacho, so do it after the merge or with `make app` from this branch.

**Needs:** the branch build of AgentTacho running with your configuration

**Do:**

1. In Settings > Groups, press Add and name the group "Free models"; clear its Amount; set the icon to the gift.
2. In Settings > Accounts, set the Budget of "Free models (Claude Code)" and "Free models (Codex)" to the group "Free models".
3. Open the dropdown, then run the command below.

**Run:**

```
tail -n 200 ~/Library/Logs/agenttacho/usage.log | rg 'no limit group Free models' | tail -n 1
```

**What you should see:** one "Free models" section whose spend equals the sum the two former sections showed (about $96 on 2026-11-10), with two member lines and no percent; no menu bar entry; the log line `[refresh] no limit group Free models (monthly, ...): <tokens> tokens, <spend> USD spent`.

**If you see something else:** a missing log line means the group still has an amount or no members.

**Result:** passed (agent, after the v0.11.0 release). The configuration got a group "Free models" without an amount and Price tokens as `claude-opus-5-5`, with `acc-free-claude` and `acc-free-codex` as members, and the GLM and DeepSeek price overrides removed (applied with jq, backup `config-before-044.json`). Log: `[refresh] no limit group Free models (monthly, ...): 285798955 tokens, 0 USD spent, unpriced: rits/deepseek-ai/DeepSeek-V4.1-Flash-1017, rits/zai-org/glm-5-3`. The models now count as free; the Opus 5.5 comparison is the value line, not spend.

## Coverage

- US1 (one section across harnesses): steps 1 to 5 and 10.
- US2 (Settings): steps 6 and 9.
- US3 (Dropdown shows, Price tokens as): step 7 covers "Dropdown shows"; "Price tokens as" is covered by tests only, because the demo group's records are priced, so no value line appears.
- US4 (adding and removing an amount): step 8; the threshold baseline after re-entering an amount is covered by tests only (it needs usage crossing a threshold over time).

## Results

10 of 10 steps passed (step 10 after the v0.11.0 release), none failed. In the demo, a group without an amount shows one section with its members' combined spend or tokens, member lines without shares, no menu bar entry, and Settings that explain why thresholds and the menu bar are unavailable. The walkthrough found one usability gap (tooltips on disabled controls never show) and fixed it with visible captions.
