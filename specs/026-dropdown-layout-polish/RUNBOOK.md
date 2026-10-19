---
runbook_version: 1
feature: 026-dropdown-layout-polish
status: passed
mode: light
steps_total: 7
step_results: passed,passed,passed,passed,passed,passed,passed
drafted_at: 21e2277
drafted_fingerprint: a2bdd07a5dd3b7d4fd729be0b459827317a4d56b0c6584c7bdae154a752f5e7d
tested_at: 1572e98
tested_fingerprint: a9345dbc1a37fdae0b49cd978700c8200b9e4aed375330dbdd70a6e5f47533d2
updated: 2026-10-19
---

# Try it: Dropdown Layout Polish

<!-- runbook-status -->
> **Status:** passed · 7 of 7 steps (7 passed) · Mode: light · Tested at 1572e98 · 2026-10-19
<!-- /runbook-status -->








## What you're testing

Spec 026 polishes the spec 025 dropdown: a budget group has one Details with a "Show account details" button for its members' tables, every day row ends with a Σ column instead of a "This week" line, the footer (errors, update line, status row) stays pinned while the sections scroll, "Last refreshed" sits beside the refresh icon, and the panel never grows past the visible screen.

The journey: run the tests, build the demo, open the budget Details and show the accounts, read the Σ columns, overfill the panel to see the pinned footer, then check the one-member group in the variants scenario.

## Test environment

No fixtures. The demo build (`build/AgentTacho Demo.app`) uses its own configuration folder and never touches the real AgentTacho.

## Steps

### Step 1 of 7: Core tests pass (US1, US2, US3)

**Why this step:** the member rules, the Σ value and tooltip, the footer error list, the status tooltip and the height cap are tested core logic.

**Needs:** nothing.

**Run:**

```
make test
```

**What you should see:** both suites pass, UsageCore with about 1568 tests and DemoMode with about 64, and no failure lines.

**If you see something else:** a failing `CompactFormatTests` case on a non-US Mac points at a locale assumption.

**Result:** passed (agent ran `make test`).

- ✔ "Test run with 1568 tests in 150 suites passed" and "Test run with 64 tests in 7 suites passed"; output: specs/026-dropdown-layout-polish/.walkthrough/step-1.log

### Step 2 of 7: Build and open the demo (US1)

**Why this step:** the demo shows a two-member "Company budget" without real credentials.

**Needs:** Step 1.

**Run:**

```
make app-demo && open -n "build/AgentTacho Demo.app" --args -AppleLanguages "(en)" -AppleLocale en_US -demoScenario default
```

**What you should see:** the build ends without errors and a second AgentTacho item appears in the menu bar.

**If you see something else:** a signing timestamp error is temporary; run it again.

**Result:** passed (agent ran the command).

- ✔ "Built build/AgentTacho Demo.app", exit 0; the demo runs (pid 10632); output: specs/026-dropdown-layout-polish/.walkthrough/step-2.log

### Step 3 of 7: One Details per budget (US1)

**Why this step:** the core change: one disclosure per budget, members one click deeper.

**Needs:** Step 2.

**Do:**

1. Open the demo's dropdown and find "Company budget".
2. Count the "Details" disclosures in that section.
3. Expand its Details, press "Show account details", switch the view picker to Projects, then press "Hide account details".

**What you should see:** two member lines without Details of their own and exactly one "Details"; after "Show account details" both members' tables and day rows appear under their names, the button reads "Hide account details", switching the picker changes the group's and the members' tables together, and "Hide account details" removes the member tables.

**If you see something else:** a member line with its own Details means the old member disclosures are still rendered.

**Result:** passed after fixes (user ran it; "works").

- ✔ one Details per budget; member lines without Details; the button reveals and hides the member tables; one picker for all tables
- finding: the picker and tables moved horizontally between views; fixed in 8e77d5a (Details left-aligned at full width, FR-005a)
- change: the button reads "Show account details" / "Hide account details" (8e77d5a)
- change: the orange note's tooltip shows only the run-out time in the other form (8e77d5a, FR-019b)
- change: Settings closes the dropdown first, so they never overlap (50e8951, FR-012a)

### Step 4 of 7: The Σ column (US2)

**Why this step:** the week's total moves from its own line into the day row.

**Needs:** Step 2.

**Do:**

1. Expand the Claude Max Details.
2. Look at the top of the Details and at the end of the day row; hover the Σ value.
3. Look at the Company budget's day row.

**What you should see:** the Details start with the view picker (no "This week" line); the day row ends with "Σ" and a total, hovering shows "Total: … tokens"; the budget's row ends with a dollar Σ; nothing is clipped or scrolls sideways.

**If you see something else:** a clipped Σ column means the day columns are too wide for the Details.

**Result:** passed after changes (user ran it; "works").

- ✔ no "This week" line; day rows end with Σ; nothing clipped
- change: tooltips give tokens in millions ("Total: 188.7M tokens"), 561f285, FR-009c
- change: every day row starts with a header column "Day" over "Tok" (tokens) or "$" (budgets), 561f285 and 1572e98, FR-009b; columns 28 pt with 4 pt spacing (FR-009a)

### Step 5 of 7: Pinned footer and status row (US3)

**Why this step:** the icons and errors must stay reachable however long the dropdown gets.

**Needs:** Step 2.

**Do:**

1. Expand every Details and "Show account details" until the dropdown reaches its full height.
2. Scroll the sections with the trackpad or wheel.
3. Look at the bottom row and hover the "Last refreshed" text.

**What you should see:** only the sections scroll; the bottom row stays in place and reads, from left, the refresh icon, "Last refreshed …", then the Settings and Quit icons; no visible scrollbar; the panel ends above the Dock and the screen bottom.

**If you see something else:** the footer moving with the sections means it is still inside the scroll view; a panel running under the Dock means the screen-aware cap is not applied.

**Result:** passed (user ran it; "works").

- ✔ only the sections scroll; the status row with refresh, "Last refreshed", Settings and Quit stays; no scrollbar; the panel ends above the screen bottom

### Step 6 of 7: Quit and open the variants scenario (US1)

**Why this step:** the variants scenario has a group with a single member.

**Needs:** Step 2; quit the demo with ⌘Q in its dropdown first.

**Run:**

```
open -n "build/AgentTacho Demo.app" --args -AppleLanguages "(en)" -AppleLocale en_US -demoScenario variants
```

**What you should see:** the demo's menu bar item appears again.

**If you see something else:** check `~/Library/Logs/agenttacho-demo/` for "scenario variants not played".

**Result:** passed (agent quit the default demo and ran the command).

- ✔ the demo runs (pid 15401); log: "demo build, scenario variants"

### Step 7 of 7: One-member group (US1)

**Why this step:** a one-member group must not show member lines or a "Show account details" button.

**Needs:** Step 6.

**Do:**

1. Open the dropdown and find "Team budget".
2. Expand its Details.

**What you should see:** no member line and no "Show account details" button; its Details show the group's tables and day row with Σ.

**If you see something else:** a "Show account details" button means the member rule is not applied.

**Result:** passed (user ran it; "works").

- ✔ "Team budget" has no member line and no "Show account details"; its Details show the group's tables and the day row with header and Σ

## Not covered here

- A short screen (for example a 13-inch display with larger text) for the screen-aware cap: needs that display setup; the cap rule is covered by core tests.
- More than three source errors in the footer ("+N more"): the demo has no failing sources; covered by core tests.

## Coverage

- US1 (one Details per budget): Steps 2, 3, 6, 7.
- US2 (Σ column): Step 4.
- US3 (pinned footer, status row): Step 5.

## Results

7 steps: 7 passed, 0 failed, 0 skipped (2026-10-19).

The polished dropdown works in the demo build: a budget group has one Details with a "Show account details" button for its members, day rows start with a "Day" / "Tok" or "$" header and end with Σ, the footer stays pinned with "Last refreshed" beside the refresh icon, and a one-member group shows no member line or button.

Changed during the walkthrough: the orange note's tooltip shows only the run-out time in the other form, the button reads "Show account details", the Details are left-aligned so the picker and tables no longer move (8e77d5a); Settings closes the dropdown first (50e8951); the day row header and token tooltips in millions (561f285, 1572e98).
