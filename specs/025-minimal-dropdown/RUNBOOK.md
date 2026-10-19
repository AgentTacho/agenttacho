---
runbook_version: 1
feature: 025-minimal-dropdown
status: passed
mode: light
steps_total: 9
step_results: passed,passed,passed,passed,passed,passed,passed,passed,passed
drafted_at: 46cd7e5
drafted_fingerprint: 1024e5b9a07094ebbb49e6f7dc9dc6c4e5f59c883f5d66a605f2a5ea06dc92c1
tested_at: d70d5cb
tested_fingerprint: 8a7193edb03af9a9883096c36681dec12373559740fcb9803665ec6eb18b4313
updated: 2026-10-19
---

# Try it: Minimal Dropdown

<!-- runbook-status -->
> **Status:** passed · 9 of 9 steps (9 passed) · Mode: light · Tested at d70d5cb · 2026-10-19
<!-- /runbook-status -->












## What you're testing

The dropdown's calmer layout from spec 025: every limit window and budget shows one text line and a bar with a pace tick, an orange note appears only when a row will run out or burns fast, times read relative by default and absolute per account or group, the Codex section drops its plan and token lines, a one-member group drops its member line, dividers separate sections, and the footer is "Last refreshed" above three icons (refresh, Settings, Quit) with no gear menu.

The journey: run the core tests, build the demo app, open the default scenario and read the dropdown top to bottom (rows, budget, Codex, footer), switch the Claude account to absolute times in Settings and undo it, then open the `variants` scenario for absolute times and the one-member group.

## Test environment

No fixtures. The demo build (`build/AgentTacho Demo.app`) uses its own configuration folder `~/.config/agenttacho-demo/` and never touches the real AgentTacho's files, keychain or network. A running real AgentTacho can stay open; it shows its own menu bar item next to the demo's.

## Steps

### Step 1 of 9: Core tests pass (US1, US4)

**Why this step:** the bar, note, time and footer texts are decided by tested core logic; this proves those rules (relative and absolute formats, rounding, notes) hold before looking at the UI.

**Needs:** nothing.

**Run:**

```
make test
```

**What you should see:** both suites pass, the UsageCore suite with about 1530 tests and the DemoMode suite with about 64, and no failure lines.

**If you see something else:** a failing `TimeTextTests` case points at a locale or time zone assumption on this Mac; a build error means the worktree is not on branch `025-minimal-dropdown`.

**Result:** passed (agent ran `make test`, 2026-10-19).

Expected vs actual:
- ✔ UsageCore suite passes (about 1530): "Test run with 1530 tests in 145 suites passed after 0.618 seconds."
- ✔ DemoMode suite passes (about 64): "Test run with 64 tests in 7 suites passed after 0.037 seconds."
- ✔ no failure lines; exit 0. Full output: specs/025-minimal-dropdown/.walkthrough/step-1.log

### Step 2 of 9: Build the demo app (US1)

**Why this step:** the demo build shows made-up accounts, so the dropdown can be checked without real credentials.

**Needs:** Step 1.

**Run:**

```
make app-demo
```

**What you should see:** the build ends without errors and `build/AgentTacho Demo.app` is updated.

**If you see something else:** a signing timestamp error is a temporary Apple service problem; run the command again.

**Result:** passed (agent ran `make app-demo`).

Expected vs actual:
- ✔ build ends without errors: "Build complete! (0,50 secs)", exit 0
- ✔ demo app updated: "Built build/AgentTacho Demo.app" (modified Oct 19 07:20)
Output: specs/025-minimal-dropdown/.walkthrough/step-2.log

### Step 3 of 9: Open the default scenario (US1)

**Why this step:** the default scenario is the story the screenshots show: a Claude Max plan ahead of pace on its 7-day window, a ChatGPT Plus plan, and a two-member "Company budget".

**Needs:** Step 2.

**Run:**

```
open -n "build/AgentTacho Demo.app" --args -AppleLanguages "(en)" -AppleLocale en_US -demoScenario default
```

**What you should see:** a second AgentTacho item appears in the menu bar within a few seconds.

**If you see something else:** no item: check `~/Library/Logs/agenttacho-demo/` for a "scenario default not played" line.

**Result:** passed (agent ran the command; user confirmed with screenshots).

- ✔ a second AgentTacho item appeared; log shows a clean start (pid 25370)

### Step 4 of 9: Read the window rows (US1, US6)

**Why this step:** the core of the feature: the pace is visible without hovering, and text appears only where it calls for action.

**Needs:** Step 3.

**Do:**

1. Click the demo's menu bar item.
2. Read the Claude Max section: the 5-hour and 7-day rows, each with a text line and a bar below it.
3. Hover the "resets in …" text of the 7-day row.
4. Count the dividers between the sections.

**What you should see:** each row reads like "7-day  70%  resets in 3d 12h" with a full-width bar; the 7-day bar fill lies right of its tick, is orange, and has an orange line like "20% ahead · runs out in 1d 12h" under it; the 5-hour row has no extra line; hovering the reset shows the absolute date and time; no pace tooltip appears anywhere; one thin divider sits between each pair of sections and one above the footer.

**If you see something else:** an orange note on an on-pace row, or a missing note on the 7-day row, means the attention rule (run-out or fast burn) is wrong; a bar without a tick on the 7-day row means the pace reading is missing.

**Result:** passed on the screenshots, with two open points (user ran it).

Expected vs actual:
- ✔ rows read name, percent, reset on one line with a full-width bar and tick
- ✔ 7-day bar orange with "20% ahead · burning fast · runs out in 1d 12h"; 5-hour row has no note
- ✔ dividers between sections and before the footer
- not reported: the reset-time tooltip, and that no pace tooltip appears
- finding 1: expanding Details shifted the content a few pixels left (a scrollbar took width); fixed in 5892e19 (indicator hidden), user confirmed no shift after relaunch
- finding 2 (change request): the budget section has three Details; the user wants one, with the member accounts inside

### Step 5 of 9: Read the Codex section and Details (US5)

**Why this step:** the Codex section lost two lines; their information must still be reachable.

**Needs:** Step 4 (dropdown open).

**Do:**

1. Look at the ChatGPT Plus section below Claude.
2. Expand "Details" of the Claude section, then of the Codex section.

**What you should see:** no "ChatGPT Plus plan" line and no "Tokens this week" line in the section; the name has no tooltip; each expanded Details starts with a line like "This week: 45.1M tokens" above the Models / Projects / Harnesses picker.

**If you see something else:** a Details without the total line means the subscription section does not pass it.

**Result:** passed (user ran it).

Expected vs actual:
- ✔ no "ChatGPT Plus plan" line and no "Tokens this week" line in the Codex section
- ✔ the name has no tooltip (the Codex tooltip was removed after this step showed Claude had none and the header names the plan; commit 534de3c)
- ✔ Claude Details start with "This week: 188.7M tokens" (screenshot); the Codex Details also start with a "This week: …" line (user confirmed)

### Step 6 of 9: Read the budget and the footer (US2, US3)

**Why this step:** budgets use the same row pattern, and the footer must keep a fixed order with one-click Settings and Quit.

**Needs:** Step 4 (dropdown open).

**Do:**

1. Find "Company budget": header with percent, the "<spent> of <budget>/month" line with "resets in …", and its bar.
2. Check the two member lines (Claude via Vertex, OpenAI API) below it.
3. Look at the bottom: "Last refreshed <time>" as the last text line, then three icons.
4. Hover each icon, then hover "Last refreshed".
5. Press ⌘, while the dropdown is open.

**What you should see:** the budget has a bar with a tick (red and full if it is over 100%); both member lines are there; the icons show the tooltips "Refresh now", "Settings…" and "Quit AgentTacho"; there is no gear menu; "Last refreshed" shows the time only (today) and its tooltip is either empty or names the next limit check when a pace is slowed; ⌘, opens the Settings window.

**If you see something else:** any line below "Last refreshed" other than the icons breaks FR-023; a gear menu means the old footer is still compiled in.

**Result:** passed (user ran it; "the rest is fine").

Expected vs actual:
- ✔ budget with bar and tick, two member lines, "Last refreshed" as the last text line, three icons, no gear menu (screenshots)
- ✔ user reported the remaining checks (icon tooltips, ⌘,) fine; individual tooltip texts were not itemized
- follow-ups for a later brainstorm (idea inbox `minimal-dropdown-round-2`): pin the footer so it never scrolls out; put "Last refreshed" beside the refresh button; the sum of the week's tokens at the end of the calendar view instead of a "This week" line

### Step 7 of 9: Switch the Claude account to absolute times and undo (US4)

**Why this step:** the time format is a per-account setting that Settings applies by itself and ⌘Z undoes.

**Needs:** Step 6 (Settings open).

**Do:**

1. In Settings, open Accounts and select "Claude Max".
2. Set "Times" to Absolute and wait a moment.
3. Open the dropdown and read the Claude rows and the Codex rows.
4. Back in Settings, press ⌘Z.
5. Open the dropdown again.

**What you should see:** after step 2 the Claude rows read like "resets 17:20" or "resets Thu 09:00" and hovering shows the relative form, while the Codex rows still read "resets in …"; after ⌘Z the Claude rows read relative again.

**If you see something else:** times that do not change after the pause mean the section does not read its account's format; ⌘Z that leaves Absolute means the undo does not cover the field.

**Result:** passed (user ran it).

Expected vs actual:
- ✔ Absolute applied by itself; Claude rows read clock times, Codex rows stayed relative; ⌘Z restored Relative (user: "works")
- finding: the account detail pane was cropped on both sides by the Times picker's fixed size; fixed in d70d5cb (frame maxWidth 240 like PeriodPicker), user confirmed

### Step 8 of 9: Check the stored value (US4)

**Why this step:** the choice must be stored in the configuration file and survive a restart.

**Needs:** Step 7 (repeat its step 2 so Absolute is set again, then quit the demo with ⌘Q in the dropdown).

**Run:**

```
rg -n '"timeFormat"' ~/.config/agenttacho-demo/config.json
```

**What you should see:** every account and group line has a `"timeFormat"` entry, the Claude Max account with `"absolute"` and the others with `"relative"`.

**If you see something else:** no `timeFormat` keys means Settings did not write the field; note that the demo setup may reset this folder at the next demo launch, which is expected.

**Result:** passed (agent ran the command while the demo was running; the user set the values).

Expected vs actual:
- ✔ every account and the group carry `"timeFormat"` (lines 15, 31, 43, 55, 74, 122)
- ✔ Claude Max line 15 `"absolute"`; ChatGPT Plus line 31 `"absolute"` (the user set it too); all others `"relative"`
- note: a first read right after the step 7 undo showed Claude Max `"relative"`, which matched the undo

### Step 9 of 9: The variants scenario (US2, US4)

**Why this step:** the second scenario holds what the published screenshots leave out: absolute times from the configuration file and a group with one member.

**Needs:** Step 2; the demo app quit.

**Run:**

```
open -n "build/AgentTacho Demo.app" --args -AppleLanguages "(en)" -AppleLocale en_US -demoScenario variants
```

**What you should see:** after opening the dropdown, the Claude Max rows read absolute times ("resets 17:20" style) with the relative form on hover, and "Team budget" shows its header, amount line and bar but no member line for its single member "Claude via Vertex".

**If you see something else:** a member line under "Team budget" breaks FR-010; relative times under Claude Max mean the configuration's `timeFormat` is not read.

**Result:** passed (agent launched the app, pid 30644, log "demo build, scenario variants"; user confirmed the dropdown: "works").

## Not covered here

- The published screenshots and the website copy (constitution V): the capture quits AgentTacho and switches the system appearance, so it runs only on the maintainer's go, with the site pull request afterwards.
- VoiceOver reading of rows and budgets (FR-006): possible by hand with VoiceOver on, but not part of this journey.

## Coverage

- US1 (window rows): Steps 1 to 4.
- US2 (budgets): Steps 6 and 9.
- US3 (footer): Step 6.
- US4 (time format): Steps 1, 7, 8 and 9.
- US5 (Codex section): Step 5.
- US6 (dividers): Step 4.

## Results

9 steps: 9 passed, 0 failed, 0 skipped (2026-10-19).

The minimal dropdown works as specified in the demo build: window rows and budgets show a bar with a pace tick and an orange note only when a row runs out or burns fast, times are relative by default and absolute per account, Settings stores the choice and undoes it with ⌘Z, the Codex section has no plan or token line, a one-member group has no member line, and the footer is "Last refreshed" above three icons.

Fixed during the walkthrough: the dropdown content shifted left when a scrollbar appeared (5892e19), the Codex name tooltip was removed (534de3c), and the Times picker cropped the account form (d70d5cb). Follow-ups are in the idea inbox as `minimal-dropdown-round-2`: one Details per budget, a percent switch, the week's sum in the calendar row, a pinned footer, and "Last refreshed" beside the refresh button.
