---
runbook_version: 1
feature: 041-no-limit-accounts
status: passed
mode: light
steps_total: 11
step_results: passed,passed,passed,passed,passed,passed,passed,passed,passed,passed,passed
drafted_at: d7d9d29
drafted_fingerprint: b016a029cd4d2f4d3ba8990b0d4447cda4ee205c84783717eb126a8a1bd1e833
tested_at: 74dd376
tested_fingerprint: f58b4eaa27102717db4854d4ef312c8d793958ff21252ef9d7d368dd25bc14df
updated: 2026-11-02
---

# Try it: Accounts without a Limit

<!-- runbook-status -->
> **Status:** passed · 11 of 11 steps (11 passed) · Mode: light · Tested at 74dd376 · 2026-11-02
<!-- /runbook-status -->












## What you're testing

A token-based account can now have **No limit** instead of an own budget or a group. It counts its period's tokens, shows them in its own dropdown section without a percent, bar, thresholds or pace, never appears in the menu bar, and can show what its tokens would have cost at a reference model's prices ("Value as").

The journey: run the core tests (all four user stories, including the gateway split of story 4), build and open the demo app, look at the "Free models" section and the menu bar, then use Settings to inspect the account, remove and restore its Value as model, switch it to an own budget and back, and check the Menu Bar tab.

## Test environment

No fixtures. The demo app writes its own configuration from `Resources/demo/default.json` on every launch and never reads or changes your real AgentTacho configuration or agent data.

## Steps

### Step 1 of 11: Run the test suites (US1, US2, US3, US4)

**Why this step:** the core logic (configuration, counting, value, texts, switches, attribution) is covered by tests; this proves the branch is green before you look at the UI.

**Run:**

```
make test
```

**What you should see:** both test targets pass with no failures, among them the suites `NoLimitConfigurationTests`, `NoLimitTransitionTests`, `NoLimitPresentationTests` and `AttributionTests` (with `eachGatewayRecordCountsForExactlyOneAccount`, story 4).

**If you see something else:** a failure in `MatchRuntimeTests.tenThousandLinesStayFast` under load is a known timing flake; rerun. Any other failure is a real regression.

**Result:** passed (agent, during finish verification, 2026-11-02).

```text
✔ Test run with 2446 tests in 265 suites passed after 3.663 seconds.
✔ Test run with 76 tests in 7 suites passed after 0.089 seconds.
✔ Test eachGatewayRecordCountsForExactlyOneAccount() passed after 0.895 seconds.
```

Expected vs actual: ✔ both targets pass; ✔ `NoLimitConfigurationTests`, `NoLimitTransitionTests`, `NoLimitPresentationTests` passed; ✔ `eachGatewayRecordCountsForExactlyOneAccount` passed. Correction: that test lives in the suite `NoLimitAttributionTests`, not `AttributionTests` (the step text said `AttributionTests`).

### Step 2 of 11: Build the demo app (US1)

**Why this step:** the demo app plays a scenario that includes a No limit account, so you can see the UI without real accounts.

**Run:**

```
make app-demo
```

**What you should see:** the build ends without errors and `build/AgentTacho Demo.app` exists.

**If you see something else:** a signing error means the local signing identity is missing; the Makefile prints which variable to set.

**Result:** passed (agent). Output: 212 lines, saved to `specs/041-no-limit-accounts/.walkthrough/step-2.log`.

```text
build: demo build, bundle id dev.rhuss.agenttacho.demo
Built build/AgentTacho Demo.app
```

Expected vs actual: ✔ no errors (exit 0); ✔ `build/AgentTacho Demo.app` exists.

### Step 3 of 11: Open the demo app (US1)

**Why this step:** starts the demo with the default scenario.

**Needs:** step 2.

**Run:**

```
open "build/AgentTacho Demo.app"
```

**What you should see:** the AgentTacho Demo item appears in the menu bar within a few seconds.

**If you see something else:** if a regular AgentTacho is running, both items show; the demo is the one that opens a dropdown with "Free models".

**Result:** passed (agent). `open` exited 0 and the demo process is running (`AgentTacho Demo.app`, pid 46642), next to the regular AgentTacho.

### Step 4 of 11: Look at the "Free models" section (US1, US2)

**Why this step:** this is the feature's main surface: tokens without a made-up limit, and the reference value.

**Needs:** step 3.

**Do:**

1. Click the demo's menu bar item to open the dropdown.
2. Scroll to "Free models", after "Side project" and before Unassigned.

**What you should see:** a header with a gift icon, "Free models" and a bold token count (for example "48.2M") where other sections show a percent, with the exact count, unit and period in its tooltip; one line below with "≈ $<n> at claude-opus-5-5 prices" on the left (its tooltip says what the tokens would have cost and that nothing was spent) and the reset text on the right. No bar, no pace note, no "incomplete, unpriced" note.

**If you see something else:** a percent or bar means the account was treated as a budget; a missing value line means the Value as model was not found in the price table.

**Result:** passed after a fix (maintainer, 2026-11-02). First run: the separate line "tokens this month" sat oddly below the header and added nothing, so the maintainer asked for better use of the space. Fix (commit "feat(dropdown): No limit section on two lines"): the headline keeps the bare count with the exact count in its tooltip, and the value line (or "this week"/"this month" without one) sits left of the reset text. Retry: as expected. Step text corrected to the new layout. Side finding: on the maintainer's en_DE locale numbers read "48,2M" and "108 US$"; recorded as idea inbox `english-number-format` for a separate change (numbers en_US, times regional).

### Step 5 of 11: Check the menu bar (US1)

**Why this step:** a No limit account must never appear in the menu bar.

**Needs:** step 3.

**Do:**

1. Look at the demo's menu bar item.

**What you should see:** the same four entries as before this feature (Claude, Codex, company budget, side project); none for "Free models".

**If you see something else:** an extra entry for "Free models" means the bar layout counts No limit accounts.

**Result:** passed (maintainer): only the four existing entries, none for "Free models".

### Step 6 of 11: Inspect the account in Settings (US3)

**Why this step:** shows the subtitle and the editor fields of a No limit account.

**Needs:** step 3.

**Do:**

1. Open Settings from the dropdown's footer, then the Accounts tab.
2. Find "Free models" in the list and select it.

**What you should see:** the subtitle reads "Other provider · no limit / month". The editor's budget choice shows "No limit", followed by Period (Monthly), a "Value as" menu showing "claude-opus-5-5" with its caption, and Times. No amount, no thresholds, no "Show in menu bar".

**If you see something else:** amount or threshold fields mean the editor did not switch its layout for No limit.

**Result:** passed (maintainer): subtitle and editor as described.

### Step 7 of 11: Remove and restore the Value as model (US2)

**Why this step:** the value line depends only on the Value as model.

**Needs:** step 6.

**Do:**

1. In the "Value as" menu choose "None", apply, and open the dropdown.
2. Back in Settings, choose "claude-opus-5-5" again (it is in the main list; imported models are under "More"), apply, and open the dropdown.

**What you should see:** after 1 the "Free models" section shows tokens only, no value line and no note; after 2 the value line is back with the same amount as in step 4.

**If you see something else:** a value line after choosing "None" means the setting is not applied.

**Result:** passed (maintainer): "None" removes the value line and shows the period; re-selecting claude-opus-5-5 brings the value back.

The period text in this step's expectation follows the new two-line layout of step 4.

### Step 8 of 11: Switch to an own budget (US3)

**Why this step:** switching must ask for an amount and then make the account a normal budget.

**Needs:** step 6.

**Do:**

1. Set the budget choice to "Own budget".
2. Try to apply without entering an amount.
3. Enter 50 and apply; look at the menu bar.

**What you should see:** after 1 the editor shows an empty amount field, thresholds 80% and 100%, "Show in menu bar" on, and the period Monthly; after 2 the change is not applied and the problem line asks for an amount above 0 per month; after 3 the menu bar gains an entry for "Free models" with a percent.

**If you see something else:** an amount of "0" prefilled, or a save that goes through without an amount, is a defect.

**Result:** passed (maintainer): empty amount, save refused without one, bar entry with a percent after 50.

### Step 9 of 11: Switch back to No limit (US3)

**Why this step:** the switch back must drop the budget and restore the Value as model.

**Needs:** step 8.

**Do:**

1. Set the budget choice to "No limit" and apply.
2. Look at the menu bar and the dropdown.

**What you should see:** the menu bar entry for "Free models" is gone; the editor shows Period Monthly and "Value as" claude-opus-5-5 again; the dropdown section shows tokens and the value line as in step 4.

**If you see something else:** a lost Value as model means it was not kept across the switch.

**Result:** passed (maintainer): bar entry gone, Monthly and Value as claude-opus-5-5 restored.

### Step 10 of 11: Check the Menu Bar tab (US3)

**Why this step:** the Menu Bar tab lists every entry for ordering; a No limit row has no "Show in bar" choice.

**Needs:** step 6.

**Do:**

1. Open the Menu Bar tab in Settings.
2. Find the "Free models" row in the entry list.

**What you should see:** the row's caption says "No limit" and it has no "Show in bar" checkbox; it can still be reordered. It is drawn in normal text like a shown entry.

**If you see something else:** a "Show in bar" checkbox on the row is a defect.

**Result:** passed after a fix (maintainer). First run: caption "No limit" and no checkbox as expected, but the row was grey like a hidden entry; the maintainer chose normal text. Fix (commit "fix(settings): draw No limit rows like shown entries in the Menu Bar tab"); retry as expected. The step text's note about the grey row is obsolete.

### Step 11 of 11: Quit the demo app

**Why this step:** leaves the machine as it was.

**Run:**

```
osascript -e 'quit app "AgentTacho Demo"'
```

**What you should see:** the demo's menu bar item disappears.

**If you see something else:** quit it from the dropdown's footer.

**Result:** passed (agent): `osascript` exited 0 and no demo process is left.

## Not covered here

- Hand-edited configuration checks (invalid `noLimit` combinations, a Value as model without a price): the demo rewrites its configuration on every launch, so these are covered by `NoLimitConfigurationTests` and `NoLimitPresentationTests` in step 1 instead.
- Real gateway records (story 4 with a real EnMaaS profile): no paid gateway records exist yet; step 1 covers the split with invented records.

## Coverage

- US1: steps 1, 3, 4, 5.
- US2: steps 1, 4, 7.
- US3: steps 1, 6, 8, 9, 10.
- US4: step 1 only (tests), see "Not covered here".

## Results

11 steps: 11 passed, 0 failed, 0 skipped (2026-11-02). Two steps passed after fixes made during the walkthrough: the No limit section now uses two lines (headline with the bare count, value or period left of the reset text; step 4), and No limit rows in the Menu Bar tab are drawn like shown entries (step 10). The feature does what the spec says: tokens without a made-up limit, a reference value, no menu bar entry, and clean switches between No limit, an own budget and back. Follow-up outside this feature: English number formatting on non-English regions (idea inbox `english-number-format`).
