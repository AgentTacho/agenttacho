---
runbook_version: 1
feature: 028-section-bands
status: passed
mode: light
steps_total: 7
step_results: passed,passed,passed,passed,passed,passed,passed
drafted_at: 3b8d911
drafted_fingerprint: 3000ed29ee7a5eb431ae5ee15d8fd9da2a02e4cfc261f931d5216b3c0bdf7d8a
tested_at: a1b657e
tested_fingerprint: 2ff588d0cdc7f81e6dd438a3ceadb5d3b4d8684b5a79d9f8135f567355f64276
updated: 2026-10-19
---

# Try it: Section Bands

<!-- runbook-status -->
> **Status:** passed · 7 of 7 steps (7 passed) · Mode: light · Tested at a1b657e · 2026-10-19
<!-- /runbook-status -->








## What you're testing

Spec 028 removes every horizontal line from the dropdown. Sections now alternate between the plain panel and a very faint full-width band (plain, tinted, plain, ...), and the pinned footer sits on its own, slightly stronger band. The row hover highlight of spec 027 must stay visible on a tinted band, and "Increase contrast" makes the bands stronger.

The journey: run the tests, open the demo (four sections: Claude Max, Codex, Company budget, Side), look at the bands and the footer, hover a row on a tinted band, scroll with expanded Details, and toggle "Increase contrast".

## Test environment

No fixtures. The demo build (`build/AgentTacho Demo.app`) uses its own configuration folder and never touches the real AgentTacho; it rewrites its configuration from the scenario at every launch.

## Steps

### Step 1 of 7: Core tests pass (US1, US2, US3)

**Why this step:** the stripe rule, the Unassigned rule, the band strengths and the demo's stripe sequence are tested core logic.

**Needs:** nothing.

**Run:**

```
make test
```

**What you should see:** both suites pass, UsageCore with about 1654 tests and DemoMode with about 65, and no failure lines.

**If you see something else:** a failing `SectionBandsTests` case means the stripe order or the strength order broke; a failing `DefaultScenarioTests` case means the demo no longer shows plain, tinted, plain, tinted.

**Result:** passed (agent ran `make test`).

- ✔ "both suites pass" → "Test run with 1654 tests in 157 suites passed" and "Test run with 65 tests in 7 suites passed"; no ✘ lines; output: specs/028-section-bands/.walkthrough/step-1.log

### Step 2 of 7: Build and open the demo (US1)

**Why this step:** the demo has four sections with fixed values and no real credentials.

**Needs:** Step 1.

**Run:**

```
make app-demo && open -n "build/AgentTacho Demo.app" --args -AppleLanguages "(en)" -AppleLocale en_US -demoScenario default
```

**What you should see:** the build ends without errors and a second AgentTacho item appears in the menu bar.

**If you see something else:** no second item means the demo app did not start; check `make app-demo` output for errors.

**Result:** passed (agent ran the build and `open`).

- ✔ "build ends without errors" → "Built build/AgentTacho Demo.app"
- ✔ "a second AgentTacho item appears" → demo process running (`AgentTacho -demoScenario default`); output: specs/028-section-bands/.walkthrough/step-2.log

### Step 3 of 7: Sections without lines (US1)

**Why this step:** this is the feature: sections stay apart without any divider.

**Needs:** Step 2.

**Do:**

1. Click the demo's menu bar item to open the dropdown.
2. Look at the boundaries between Claude Max, Codex, Company budget and Side.

**What you should see:** no horizontal line anywhere. Claude Max and Company budget sit on the plain dark panel; Codex and Side sit on a faintly lighter band that runs from the panel's left edge to its right edge. Bands meet the plain sections without a gap, and no text or bar touches a band edge. The first line of Claude Max is as far from the top edge as before.

**If you see something else:** a line means a `Divider` survived; a band that stops short of the edges means the horizontal inset is still on the container; text touching a band edge means the vertical band padding is missing.

**Result:** passed (user checked): no lines; plain, tinted, plain, tinted bands edge to edge; text clear of band edges.

### Step 4 of 7: The footer band (US2)

**Why this step:** without the divider the footer must still stand apart, even below a tinted section.

**Needs:** Step 3 (dropdown open).

**Do:**

1. Look at the bottom of the dropdown, below the Side section (tinted).

**What you should see:** the status row (refresh icon, "Last refreshed", Settings and Quit) sits on its own band, a little lighter than the Side band, reaching the panel's left, right and bottom edges, with no line above it.

**If you see something else:** a footer that blends into Side means the footer strength is not above the tinted strength; a gap at the bottom or sides means the band is inside the inset.

**Result:** passed (user checked): the footer band stands apart from the tinted Side project band, edge to edge, no line above.

### Step 5 of 7: Hover on a tinted band (US3)

**Why this step:** the headline switch of spec 027 relies on the hover highlight; a band must not swallow it.

**Needs:** Step 3 (dropdown open).

**Do:**

1. Hover the Codex section's 5-hour row (on the tinted band), then the Claude Max 7-day row (plain).
2. Look at the bar tracks and the pace ticks in the Codex section.

**What you should see:** both rows show the rounded hover highlight and `○`, clearly visible on the tinted band too; the bar tracks and ticks in the Codex section read as well as in Claude Max.

**If you see something else:** an invisible highlight on Codex means the hover is drawn below the band or is weaker than it.

**Result:** passed (user checked): hover highlight and ○ visible on the tinted ChatGPT Plus band and the plain Claude Max band; bar tracks and ticks readable.

### Step 6 of 7: Scroll under the pinned footer (US2)

**Why this step:** section bands scroll, the footer band stays.

**Needs:** Step 3 (dropdown open).

**Do:**

1. Expand the Details of Claude Max and of Company budget (press "Show accounts" too) until the dropdown reaches its height and scrolls.
2. Scroll the sections up and down.

**What you should see:** the section bands move with their sections; the footer band stays at the bottom, and a section scrolling under it is cut at the footer band's top edge. The stripes do not change while Details open or close.

**If you see something else:** a footer that scrolls away or sections drawn over the footer means the scroll structure of spec 026 changed.

**Result:** passed (user checked): section bands scroll, the footer band stays pinned, sections clip at its top edge, stripes stable.

### Step 7 of 7: Increase contrast, then quit the demo (US1)

**Why this step:** with "Increase contrast" the bands must get stronger (FR-006).

**Needs:** Step 3.

**Do:**

1. Open System Settings > Accessibility > Display and turn on "Increase contrast".
2. Open the demo dropdown again and compare the Codex band and the footer band with before.
3. Turn "Increase contrast" off again.
4. Quit the demo with its Quit button in the dropdown footer.

**What you should see:** with "Increase contrast" on, the tinted bands and the footer band are clearly stronger, the footer still lighter than the tinted bands; turned off, they return to the faint look. The demo quits and its menu bar item disappears.

**If you see something else:** unchanged bands mean the contrast setting is not read.

**Result:** passed (user checked): bands stronger with Increase contrast and faint again without; the demo quit.

## Not covered here

- The screenshot recapture (`plan-limits`, `pace`, `budget`, `groups`, `details`, `harnesses`, `dropdown`) and the README image: they need the maintainer's go for `scripts/screenshots/capture.sh` (AGENTS.md step 4); check the bottom edge of the `details` and `harnesses` crops for a sliver of the footer band.
- VoiceOver reading order: the bands add no accessibility elements; not walked through here.

## Coverage

- US1 (sections apart without lines): Steps 1, 2, 3, 7.
- US2 (a footer that stands apart): Steps 1, 4, 6.
- US3 (hover and markers on a band): Steps 1, 5.

## Results

7 steps: 7 passed, 0 failed, 0 skipped. The dropdown separates its sections with alternating full-width bands instead of dividers, the pinned footer has its own stronger band, the hover highlight stays visible on tinted bands, the bands scroll under the pinned footer, and Increase contrast strengthens them. The recaptured shots (site PR #4) show the same.
