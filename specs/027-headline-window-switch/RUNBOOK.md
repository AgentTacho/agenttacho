---
runbook_version: 1
feature: 027-headline-window-switch
status: passed
mode: light
steps_total: 8
step_results: passed,passed,passed,passed,passed,passed,passed,skipped
drafted_at: 17302e4
drafted_fingerprint: 3eb43fd7a6acc7308738b704d4989ec8d4c91f4fd478c6e10c759ac476742ca5
tested_at: 846eda0
tested_fingerprint: 112aa41bf88fef4ec91fb79bd50bb5996927a330935dc71efceab2c1bcac0a0d
updated: 2026-10-19
---

# Try it: Headline Window Switch

<!-- runbook-status -->
> **Status:** passed · 8 of 8 steps (7 passed, 1 skipped) · Mode: light · Tested at 846eda0 · 2026-10-19
<!-- /runbook-status -->









## What you're testing

Spec 027 lets you pick which limit window an account's menu bar value follows. Clicking a window row in a Claude or Codex section makes it the headline: a ● marks the row, the section header and the bar entry show a short tag ("5h", "wk", "Fable") before the value, and the level and the `↗` / `↑` markers follow that window. Clicking the default row (7-day for Claude, the longest window for Codex) brings back today's look.

The journey: run the tests, open the demo (whose Claude account starts on the 5-hour window), switch Claude back and forth, switch the Codex plan, pick the Fable model limit, look at the hover state and the Settings preview, and listen to the rows with VoiceOver.

## Test environment

No fixtures. The demo build (`build/AgentTacho Demo.app`) uses its own configuration folder and never touches the real AgentTacho; it rewrites its configuration from the scenario at every launch.

## Steps

### Step 1 of 8: Core tests pass (US1, US2, US3, US4)

**Why this step:** headline resolution, fallback, tags, levels, markers, the stored field and the Settings merge are tested core logic.

**Needs:** nothing.

**Run:**

```
make test
```

**What you should see:** both suites pass, UsageCore with about 1640 tests and DemoMode with about 64, and no failure lines.

**If you see something else:** a failing `DefaultScenarioTests` case means the demo scenario no longer shows the tag or a level or marker the shots rely on.

**Result:** passed (agent ran `make test`).

- ✔ "both suites pass" → "Test run with 1640 tests in 156 suites passed" and "Test run with 64 tests in 7 suites passed"; output: specs/027-headline-window-switch/.walkthrough/step-1.log

### Step 2 of 8: Build and open the demo (US1)

**Why this step:** the demo has a Claude Max and a ChatGPT Plus subscription with fixed values and no real credentials.

**Needs:** Step 1.

**Run:**

```
make app-demo && open -n "build/AgentTacho Demo.app" --args -AppleLanguages "(en)" -AppleLocale en_US -demoScenario default
```

**What you should see:** the build ends without errors and a second AgentTacho item appears in the menu bar, whose Claude entry reads "5h 58%" followed by "↑".

**If you see something else:** a signing timestamp error is temporary; run it again. "70%" without a tag means the scenario's `headlineWindow` was not loaded.

**Result:** passed (agent ran the command, user checked the menu bar).

- ✔ "the build ends without errors" → "Built build/AgentTacho Demo.app", exit 0; the demo runs (pid 80902); output: specs/027-headline-window-switch/.walkthrough/step-2.log
- ✔ "Claude entry reads 5h 58% followed by ↑" → confirmed by the user

### Step 3 of 8: The 5-hour window as headline (US1)

**Why this step:** the chosen window must drive the header and the bar, and the tag must say which window it is.

**Needs:** Step 2.

**Do:**

1. Open the demo's dropdown and look at the Claude Max section.
2. Read the header on the right and the marker column left of the window names.

**What you should see:** the header reads "5h" in gray followed by a bold "58%"; "5-hour" carries a ●, "7-day" and "Fable" have an empty slot; the window names stay aligned.

**If you see something else:** a ● on "7-day" means the demo choice did not apply; misaligned names mean the marker slot is missing on some rows.

**Result:** passed (user).

- ✔ header "5h" in gray plus bold "58%", ● on 5-hour, empty slots on 7-day and Fable, names aligned (user confirmed)

### Step 4 of 8: Back to the default and again (US1, US4)

**Why this step:** one click switches, one click returns, and the dropdown stays open.

**Needs:** Step 3.

**Do:**

1. Rest the pointer on the "7-day" row, then on the "5-hour" row.
2. Click the "7-day" row.
3. Look at the header and the menu bar, then click "5-hour" again.

**What you should see:** on "7-day" a subtle rounded highlight and a hollow ○ appear; on "5-hour" (the headline) nothing changes. After the click the ● is on "7-day", the header reads a bold "70%" without tag, the bar entry reads "70%" without tag, and the dropdown is still open. The second click restores "5h 58%".

**If you see something else:** a closed dropdown after the click, or a bar that only changes after the next refresh, breaks FR-001.

**Result:** passed (user).

- ✔ hover highlight and ○ on 7-day, none on 5-hour; click switched header and bar to 70% without tag with the dropdown open; the second click restored 5h 58% (user confirmed)

### Step 5 of 8: A Codex window (US2)

**Why this step:** Codex plans follow the same rule, with their own tags.

**Needs:** Step 2.

**Do:**

1. In the ChatGPT Plus section, click the "5-hour" row.
2. Read its header and its menu bar entry.
3. Click the "weekly" row.

**What you should see:** after step 1 the ● is on "5-hour" and header and bar entry read "5h 40%"; after step 3 the ● is on "weekly" and both read "60%" without tag.

**If you see something else:** a tag on "weekly" would mean the longest window is not treated as the default.

**Result:** passed (user).

- ✔ ChatGPT Plus read 5h 40% with ● on 5-hour, then 60% without tag with ● on weekly (user confirmed)

### Step 6 of 8: A model limit, and the hover after closing (US1, US4)

**Why this step:** model limits use their name as tag; the code review flagged that a hover highlight might survive closing the dropdown.

**Needs:** Step 2.

**Do:**

1. In the Claude Max section, click the "Fable" row and read the header and the bar entry.
2. Rest the pointer on the "7-day" row so it shows its highlight, then press Esc to close the dropdown without moving the pointer.
3. Open the dropdown again with the pointer away from the rows.
4. Click "5-hour" to restore the demo's start state.

**What you should see:** after step 1 header and bar read "Fable 50%" and the ● is on "Fable". After step 3 no row shows a highlight or a ○.

**If you see something else:** a highlight or ○ on "7-day" after reopening is the review's open Minor finding (hover state not reset on close); note it in the result.

**Result:** passed (user).

- ✔ header and bar read Fable 50% with ● on Fable
- ✔ no highlight or ○ after closing with Esc on a hovered row and reopening, so the review's open Minor finding (hover not reset on close) does not occur (user confirmed)

### Step 7 of 8: Settings preview (US4)

**Why this step:** the Menu Bar tab's preview must show the bar as it is, tag included.

**Needs:** Step 2.

**Do:**

1. Open Settings from the dropdown (gear icon) and choose the Menu Bar tab.
2. Read the preview capsule.

**What you should see:** the preview's Claude entry reads "5h 58%" with the same tag as the menu bar.

**If you see something else:** "70%" in the preview while the bar shows "5h 58%" means the preview uses another code path.

**Result:** passed (user).

- ✔ the Menu Bar tab preview reads 5h 58% for Claude, like the bar (user confirmed)

### Step 8 of 8: VoiceOver on the rows (US4)

**Why this step:** the switch must be usable without seeing the ●.

**Needs:** Step 2.

**Do:**

1. Turn on VoiceOver (Command F5) and open the demo's dropdown.
2. Move to the Claude "5-hour" row, then to the "7-day" row, and open the actions menu (VO Command Space) on "7-day".
3. Turn VoiceOver off again.

**What you should see:** the "5-hour" row is read as selected and ends with "shown in menu bar"; the "7-day" row offers the action "Show in menu bar".

**If you see something else:** no "Show in menu bar" action means the accessibility action is missing (FR-003).

**Result:** skipped (user chose not to try VoiceOver in this session). The action name and the selected label are covered by the `RowText` and accessibility tests in Step 1.

## Not covered here

- Persistence across a restart: the demo rewrites its configuration from the scenario at every launch, so a choice cannot survive a demo relaunch. The `ConfigStore` round trip test in Step 1 covers it; in a real build, choose a window, quit and relaunch.
- A vanished model limit or Codex window (US3): the demo values never drop a window; the fallback is covered by the UsageCore tests in Step 1.
- Choices made while Settings is open with unsaved edits: covered by the `keepingHeadlineChoices` tests; by hand it needs a 600 ms timing race.

## Coverage

- US1: Steps 2 to 4 and 6.
- US2: Step 5.
- US3: Step 1 only (unit tests); see "Not covered here".
- US4: Steps 4, 6, 7 and 8.

## Results

8 steps: 7 passed, 0 failed, 1 skipped. In the demo build a click on a window row switches the menu bar value and the section header to that window with its tag ("5h", "Fable"), for Claude and Codex, and one click on the default row brings back today's look; rows show a quiet hover state that does not survive closing the dropdown, and the Settings preview shows the same tag. VoiceOver was not tried by hand; restart persistence and the fallback for a vanished window are covered by the tests in Step 1.
