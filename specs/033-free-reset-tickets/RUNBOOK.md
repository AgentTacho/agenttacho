---
runbook_version: 1
feature: 033-free-reset-tickets
status: passed
mode: light
steps_total: 8
step_results: passed,passed,passed,passed,passed,passed,passed,passed
drafted_at: 6c00c48
drafted_fingerprint: 9e0e053aaf56dd1091e575229e1e71dff74c5ad0612ba59e9967574866109750
tested_at: 2117f64
tested_fingerprint: fdce6f35ed33c4e1071a6902bd43b8b47a0507cbb23474d335a46d8ff0169094
updated: 2026-10-21
---

# Try it: Free Reset Tickets

<!-- runbook-status -->
> **Status:** passed · 8 of 8 steps (8 passed) · Mode: light · Tested at 2117f64 · 2026-10-21
<!-- /runbook-status -->









## What you're testing

AgentTacho now reads free limit-reset tickets for Claude and Codex subscription accounts, shows up to three dimmed gift glyphs (plus `+N`) next to the account name in the dropdown, explains each ticket's expiry in a tooltip, opens the provider's usage page on a click, and reminds you before a ticket expires (with a switch in Settings).

The journey: run the test suite, build and open the demo app, look at the glyphs and their tooltips, click one to open Claude's usage page, check the new Settings switch, then try the real app with your own accounts and read the diagnostic log.

## Test environment

No fixtures. Everything runs on this Mac: the Makefile builds the apps, the demo app plays its bundled scenario, and the real app reads your existing Claude Code and Codex sign-ins (read only).

## Steps

### Step 1 of 8: Run the test suite (US1, US2, US3)

**Why this step:** The ticket decoders, the flag fallback, the expiry tracker, the texts and the demo coverage are all tested in UsageCore and DemoMode; a green run is the baseline for the manual steps.

**Needs:** nothing

**Run:**

```
make test 2>&1 | grep "Test run with"
```

**What you should see:** Two lines starting with "✔ Test run with", one for about 1878 UsageCore tests and one for 70 DemoMode tests, both "passed".

**If you see something else:** A "✘" line names the failing test; the feature is not ready to try.

**Result:** passed (agent). Expected two passing runs; got `✔ Test run with 1878 tests in 193 suites passed` and `✔ Test run with 70 tests in 7 suites passed`.

### Step 2 of 8: Build and open the demo app (US1)

**Why this step:** The demo build shows invented accounts from `Resources/demo/default.json`, where the first Claude Max account holds two tickets, so you can see the glyphs without a real ticket.

**Needs:** Step 1. Quit a running "AgentTacho Demo" first.

**Run:**

```
make app-demo && open "build/AgentTacho Demo.app"
```

**What you should see:** The build ends without errors and the demo's menu bar item appears.

**If you see something else:** A build error points at the changed sources; a missing app path means the build script wrote somewhere else (check the last lines of its output).

**Result:** passed (agent). Expected a clean build and a running demo; got `Built build/AgentTacho Demo.app` and the demo process running. The menu bar item was confirmed by the maintainer in Step 3.

### Step 3 of 8: See the gift glyphs (US1)

**Why this step:** This is the core of the feature: tickets visible next to the account name, dimmed and monochrome.

**Needs:** Step 2

**Do:**

1. Click the demo's menu bar item to open the dropdown.
2. Look at the header of the first Claude Max section.

**What you should see:** Two small gift glyphs right after the account name, in the same dimmed gray as the secondary text, no color. Other accounts show none. The headline percentage on the right is unchanged.

**If you see something else:** No glyphs means the demo tickets did not reach the entry; colored or bright glyphs mean the secondary color is not applied.

**Result:** passed (maintainer). Two dimmed, monochrome gift glyphs after "Claude Max · Work", none on other accounts.

### Step 4 of 8: Read the tooltips (US1)

**Why this step:** The tooltip is how you learn how long a ticket stays valid.

**Needs:** Step 3

**Do:**

1. Hover over the first gift glyph and wait for the tooltip.
2. Hover over the second one.

**What you should see:** First: "Free limit reset, expires in 2d 4h (<weekday and time>)" and a second line "Click to open the usage page" (the relative time counts down from the scenario start). Second: "Free limit reset, no expiry" and the same second line.

**If you see something else:** Swapped order means the display sort is wrong (soonest expiry must come first); a missing second line means the link hint is missing.

**Result:** passed (maintainer). Expiring ticket first with "expires in ...", then "no expiry", each with "Click to open the usage page".

### Step 5 of 8: Open the usage page with a click (US1)

**Why this step:** The glyph leads to the page where the reset can be redeemed.

**Needs:** Step 3

**Do:**

1. Click one of the gift glyphs.

**What you should see:** The dropdown closes and your default browser opens `https://claude.ai/settings/usage`.

**If you see something else:** A dropdown that stays open means the close closure is not wired; a different page means the wrong link.

**Result:** passed (maintainer). The dropdown closed and the browser opened `https://claude.ai/settings/usage`.

### Step 6 of 8: Find the reminder switch (US3)

**Why this step:** Reminders can be turned off without hiding the glyphs.

**Needs:** Step 2

**Do:**

1. Open the demo's Settings and go to General.
2. Look at the Notifications section.

**What you should see:** Two switches: "Notify when a sign-in stops working" and below it "Notify before a free limit reset expires", both on.

**If you see something else:** A missing second switch means the Settings change did not land in this build.

**Result:** passed (maintainer). Both switches present and on in Settings > General > Notifications.

### Step 7 of 8: Try the real app with your accounts (US1)

**Why this step:** The sources are undocumented; only a real account shows whether Claude and ChatGPT answer as expected.

**Needs:** Step 1. Quit the demo app and a running AgentTacho first.

**Run:**

```
make app && open build/AgentTacho.app
```

**What you should see:** AgentTacho starts as usual. In the dropdown, a Claude Pro or Max account shows gift glyphs only if Claude Settings > Usage offers "Reset for free"; a Codex account with live limits on shows glyphs only if ChatGPT lists reset credits. Without tickets the headers look as before, and the usage figures are the same as in your previous version.

**If you see something else:** Changed or missing usage figures mean the ticket read affected the usage request (it must not); glyphs that do not match the provider's page mean the decoding differs from the live answer.

**Result:** passed (agent built and launched, maintainer compared). First try: the maintainer asked for slightly smaller glyphs; fixed in `2117f64` (glyphs and `+N` at the small system font size, spec FR-009 updated), rebuilt, relaunched, then confirmed: glyphs match the accounts and the usage figures are unchanged.

### Step 8 of 8: Check the diagnostic log (US1, US2)

**Why this step:** Failed ticket reads and reminders are logged without tokens or service identifiers.

**Needs:** Step 7 (wait for one refresh)

**Run:**

```
grep -i "free reset" ~/Library/Logs/agenttacho/usage.log | tail -20
```

**What you should see:** Either no lines (all ticket reads succeeded and no reminder fell due) or lines like "acc-...: free reset tickets not read (http-404)" or "free reset expiry 3d for acc-..., expires 2026-...". No token, no long identifier.

**If you see something else:** Anything that looks like a token or a credit or grant id is a privacy bug.

**Result:** passed (agent). Expected no lines or harmless ones; `grep -i "free reset"` found no lines, so every ticket read succeeded and no reminder fell due. Latest refresh: `codexLimits ok: 1 account(s)`, `0 source error(s)`.

## Not covered here

- **Expiry notifications on screen (US2):** they need a real ticket within 3 days of its expiry, and the demo build delivers none by design. The tracker tests in Step 1 cover the 3-day and 24-hour steps, relaunches and grouping.
- **Codex glyphs and the Codex usage link in the demo:** the demo scenario gives tickets to a Claude account only; a Codex account with real reset credits shows them in Step 7.
- **Screenshots:** the capture takes over the Mac and runs only with the maintainer's go (task T037).

## Coverage

- US1 (see tickets): Steps 1 to 5, 7, 8.
- US2 (reminders): Step 1 (tests) and Step 8 (log); on-screen delivery not covered, see above.
- US3 (switch): Steps 1 and 6.

## Results

8 steps: 8 passed, 0 failed, 0 skipped.

The test suite and the demo build are green. In the demo, the first Claude Max account shows two dimmed gift glyphs with expiry tooltips, a click opens Claude's usage page and closes the dropdown, and Settings > General has the new reminder switch. The real app with the maintainer's accounts shows glyphs that match the providers' usage pages, unchanged usage figures, and no ticket read failures in the log. One change came out of the walkthrough: the glyphs are now a little smaller (small system font size). On-screen expiry notifications were not tried (no real ticket within 3 days); the tracker tests cover them.
