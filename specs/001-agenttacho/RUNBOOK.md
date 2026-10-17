---
runbook_version: 1
feature: 001-llm-usage-menubar
status: failed
mode: light
steps_total: 12
step_results: passed,passed,passed,passed,passed,passed,passed,passed,passed,failed,passed,passed
drafted_at: 270905e
drafted_fingerprint: 614370defea59e4c6b06b6805f3ac140c7af79cc5f3a71b49dd5e43eb7ffa4a1
tested_at: 8e71689
tested_fingerprint: 700bae0d075c5f4102ea558b565611ede09e8f7e2a491237300b3e35c21f0e59
updated: 2026-10-13
---

# Try it: LLM Usage Menu Bar

<!-- runbook-status -->
> **Status:** failed · 12 of 12 steps (11 passed, 1 failed) · Mode: light · Tested at 8e71689 · 2026-10-13
<!-- /runbook-status -->













## What you're testing

A macOS menu bar app that shows, per account, how much of a usage limit is used. The journey builds and launches the app, reads the subscription limits that Anthropic reports for your Claude Max account (US1), checks the Vertex spend against the weekly budget and cross-checks the amount with an independent script (US2), exercises configuration validation in the settings window and by hand-editing the config file (US3), triggers exactly one threshold notification (US4), and opens the per-model and per-day breakdown (US5). The last step quits the app and restores your configuration.

The journey uses your existing configuration at `~/.config/llm-usage-menubar/config.json` (accounts `M` and `VC`, group `V` with a 60 USD weekly budget). Steps that change it restore it at the end.

Everything the app does is also written to `~/Library/Logs/llm-usage-menubar/usage.log`, so most expectations can be checked from the terminal even when the menu bar is hard to read.

## Test environment

No fixtures. The app itself is started in Step 2 and quit in Step 12. Nothing else needs to run.

## Steps

### Step 1 of 12: Build and run the test suite (US1)

**Why this step:** Confirms the toolchain works on this machine before anything is launched. The suite covers parsing, pricing, windows, attribution, thresholds, and configuration validation.

**Needs:** Xcode command line tools with Swift 5.10 or newer.

**Run:**

```
cd /Users/rhuss/Work/projects/llm-usage-menubar/.claude/worktrees/001-llm-usage-menubar && make test
```

**What you should see:** The build finishes without errors and the last line reads `Test run with 128 tests in 15 suites passed` followed by a duration.

**If you see something else:** A failure mentioning `XCTest` or a plugin path means the Makefile could not find the Swift Testing plugin under the active toolchain; check `xcode-select -p`. A failure mentioning `@State` as a macro means the macOS 26 SDK is missing next to the macOS 27 one.

**Result:** passed, run by the agent. Output: 320 lines, saved to specs/001-llm-usage-menubar/.walkthrough/step-1.log.
- ✔ "Test run with 128 tests in 15 suites passed" -> last line: `✔ Test run with 128 tests in 15 suites passed after 0.157 seconds.`

### Step 2 of 12: Back up the config and launch the app (US1)

**Why this step:** Later steps edit the configuration. Keeping a copy makes the final restore trivial. The app is assembled into a bundle and opened the way a user would open it.

**Needs:** Step 1.

**Run:**

```
cp ~/.config/llm-usage-menubar/config.json ~/.config/llm-usage-menubar/config.json.runbook-backup && cd /Users/rhuss/Work/projects/llm-usage-menubar/.claude/worktrees/001-llm-usage-menubar && make run
```

**What you should see:** `Built build/LLM Usage.app`, then a macOS dialog asking whether "LLM Usage" may use the "Claude Code-credentials" item in your keychain. Click **Always Allow**. No Dock icon appears. Within a few seconds the menu bar shows an item such as `M 42% V 557%` (your numbers will differ).

**If you see something else:** If the dialog does not appear and the bar shows `M --`, the keychain item name does not match the credential directory in the config; Step 4 shows the exact error. The dialog reappears after every rebuild because the ad-hoc signature changes; that is expected.

**Result:** passed. Command run by the agent, dialog and bar checked by the user. Output saved to specs/001-llm-usage-menubar/.walkthrough/step-2.log.
- ✔ "Built build/LLM Usage.app" -> `Built build/LLM Usage.app`, then `open "build/LLM Usage.app"`; process LLMUsageMenuBar running 4 s later
- ✔ keychain dialog, Always Allow, bar shows M and V percents, no Dock icon -> confirmed by the user

### Step 3 of 12: Confirm the first refresh in the log (US1)

**Why this step:** The log records what the subscription source fetched, independent of how the bar renders it.

**Needs:** Step 2, dialog answered.

**Run:**

```
rg -n "\[subscription\] ok|\[refresh\] done" ~/Library/Logs/llm-usage-menubar/usage.log | tail -n 2
```

**What you should see:** One line like `[subscription] ok: 1 account(s) <id>=ok(5h 24%, 7d 55%)` and one `[refresh] done in 0.3 s, 0 source error(s), window <start> to <end> (aligned)`. The window spans exactly seven days.

**If you see something else:** `credentialsExpired` means Claude Code's token has lapsed; run any Claude Code command to refresh it, then click "Refresh now". `notSignedIn` means no keychain item exists for the configured credential directory. `(fallback)` instead of `(aligned ...)` means the subscription fetch has not succeeded yet.

**Result:** passed, run by the agent.
```
2026-10-13T11:22:15Z [subscription] ok: 1 account(s) DD73C467-E970-44DE-9342-263613EFA73A=ok(5h 8%, 7d 81%)
2026-10-13T11:22:15Z [refresh] done in 12.584 s, 0 source error(s), window 2026-10-09T07:00:00Z to 2026-10-16T07:00:00Z (aligned)
```
- ✔ subscription ok line with 5h and 7d percents -> `ok(5h 8%, 7d 81%)`
- ✔ refresh done, 0 source errors, 7-day window -> 2026-10-09T07:00Z to 2026-10-16T07:00Z, aligned
- Runbook correction: the log prints `(aligned)` without the account id; the expectation text above said `(aligned <id>)`. The 12.6 s refresh time includes waiting for the keychain dialog.

### Step 4 of 12: Compare the dropdown with Claude Code's own numbers (US1)

**Why this step:** The spec requires the shown percent to match Anthropic's real limit within one point.

**Needs:** Step 3.

**Do:**

1. Click the menu bar item. The dropdown shows the account `M` with a `5-hour` row and a `7-day` row, each with a percent and a `resets ...` time, and a `Last refreshed` line at the bottom.
2. In a terminal, run `claude` and type `/usage`.
3. Compare the two percents for the current session (5-hour) and the weekly limit (7-day).

**What you should see:** Both pairs agree within one percentage point, and the reset times match.

**If you see something else:** A difference of more than one point after a fresh refresh means the two tools read different windows; note both values and the time, then click "Refresh now" and compare again.

**Result:** passed, done by the user. Dropdown rows and `/usage` in Claude Code agree within one point (log at the time: 5h 8%, 7d 81%); reset times match.

### Step 5 of 12: Read the Vertex group total (US2)

**Why this step:** The group line in the dropdown and in the log is the spend inferred from the local session logs, priced with the built-in table, against the weekly budget.

**Needs:** Step 3.

**Run:**

```
rg -n "\[refresh\] group V" ~/Library/Logs/llm-usage-menubar/usage.log | tail -n 1
```

**What you should see:** A line like `[refresh] group V: 334.2003185 of 60 USD (557%)`. The dropdown shows the same group `V` with `$334.20 of $60.00 (557%)` and `resets <window end>`. Percents above 100 are shown as is.

**If you see something else:** `0 of 60 USD (0%)` with Vertex sessions in the current week means the records are not attributed; check the `[sessionLogs]` lines above it for an `error:` entry or a missing log directory.

**Result:** passed, run by the agent.
```
2026-10-13T11:22:15Z [refresh] group V: 802.683431 of 60 USD (1338%)
```
- ✔ group V line with spend, budget and uncapped percent -> 802.683431 of 60 USD (1338%)

### Step 6 of 12: Cross-check the amount with the independent script (US2)

**Why this step:** The spec requires the app's spend to agree with an independent sum of the same records within one cent.

**Needs:** Step 5.

**Run:**

```
cd /Users/rhuss/Work/projects/llm-usage-menubar/.claude/worktrees/001-llm-usage-menubar && WINDOW=$(rg -o "window [0-9TZ:-]+ to [0-9TZ:-]+" ~/Library/Logs/llm-usage-menubar/usage.log | tail -n 1) && START=$(printf '%s' "$WINDOW" | cut -d' ' -f2) && END=$(printf '%s' "$WINDOW" | cut -d' ' -f4) && echo "$START to $END" && scripts/sum-vertex.sh "$START" "$END" ~/.claude
```

**What you should see:** The window echoed first, then the script's output ending with a `totalUSD:` value that equals the amount from Step 5 to the cent, plus the number of deduplicated records and the models involved.

**If you see something else:** A small difference with a model listed as unpriced means the script does not mirror the app's prefix fallback; the app's value is the reference. A large difference means the two read different directories; the script only scans `~/.claude` unless more directories are passed.

**Result:** passed, run by the agent. Output saved to specs/001-llm-usage-menubar/.walkthrough/step-6.log.
```
2026-10-09T07:00:00Z to 2026-10-16T07:00:00Z
  "totalUSD": 802.683431,
  "unpriced": []
```
- ✔ window echoed -> 2026-10-09T07:00:00Z to 2026-10-16T07:00:00Z (same as the log)
- ✔ totalUSD equals Step 5 to the cent -> 802.683431 on both sides, identical; 3990 deduplicated records, no unpriced models

### Step 7 of 12: Reject an invalid refresh interval in Settings (US3)

**Why this step:** Settings must validate input with the same rules as the config file, and the minimum interval is 60 seconds.

**Needs:** Step 2.

**Do:**

1. Click the menu bar item, then **Settings…**.
2. On the **General** tab, set **Refresh interval (seconds)** to `30`.
3. Click **Save**.

**What you should see:** A red message `minimum is 60 seconds` and the save is refused. Set the value back to `300` and save; the message disappears and a `Saved <time>` line appears.

**If you see something else:** If the save goes through with 30, validation is not wired to the save path; check the log for `saved from settings: ... interval 30 s`.

**Result:** passed, done by the user. Entering 30 showed the red `minimum is 60 seconds` message and the save was refused; 300 saved with a `Saved <time>` line.

### Step 8 of 12: Break the config file by hand and watch the app keep its last values (US3)

**Why this step:** A hand edit that produces invalid JSON must be reported without wiping the values already on screen.

**Needs:** Step 7.

**Run:**

```
printf '{' > ~/.config/llm-usage-menubar/config.json && echo "now click the menu bar item, then Refresh now, then press Enter" && read -r _ && rg -n "config error" ~/Library/Logs/llm-usage-menubar/usage.log | tail -n 1
```

**What you should see:** After clicking "Refresh now", the dropdown shows a configuration error line, while the `M` and `V` rows keep their previous values. The latest `[refresh] done` log line ends with `config error: ... not valid JSON`.

**If you see something else:** If the rows disappear or show `--`, the last valid configuration was not kept. If no error appears at all, the file's modification time was not checked at refresh start. Close the Settings window before this step: a Save from an open Settings window rewrites the file with a valid configuration.

**Result:** passed on the second attempt. File written by the agent, Refresh now clicked by the user, log read by the agent.
- First attempt: no error shown. Cause: the Settings window from Step 7 was still open and its Save rewrote config.json as valid JSON three times (log 11:28:33 to 11:28:36, group budget changed to 80 in passing). Runbook corrected: close Settings first.
- Second attempt (file 1 byte at 11:30:39Z), after Refresh now:
```
2026-10-13T11:30:59Z [refresh] done in 2.303 s, 0 source error(s), window 2026-10-09T07:00:00Z to 2026-10-16T07:00:00Z (aligned), config error: Configuration file could not be decoded: The given data was not valid JSON.
```
- ✔ dropdown shows a configuration error, M and V keep their values -> confirmed by the user
- ✔ log reports the invalid JSON -> `config error: Configuration file could not be decoded: The given data was not valid JSON.`
- Runbook correction: the error is appended to the `[refresh] done` line, not logged as a separate `[config]` line.

### Step 9 of 12: Restore the config file (US3)

**Why this step:** Returns the app to a valid state before the notification steps.

**Needs:** Step 8.

**Run:**

```
cp ~/.config/llm-usage-menubar/config.json.runbook-backup ~/.config/llm-usage-menubar/config.json && echo "click Refresh now in the dropdown, then press Enter" && read -r _ && rg -n "\[config\]|\[refresh\] done" ~/Library/Logs/llm-usage-menubar/usage.log | tail -n 2
```

**What you should see:** The configuration error line disappears from the dropdown and the log shows a new `[refresh] done ... 0 source error(s)` line.

**If you see something else:** A lingering error means the file still fails validation; compare it with the backup.

**Result:** passed. File restored by the agent, Refresh now clicked by the user.
```
2026-10-13T11:31:51Z [refresh] group V: 802.683431 of 60 USD (1338%)
2026-10-13T11:31:51Z [refresh] done in 2.482 s, 0 source error(s), window 2026-10-09T06:59:59Z to 2026-10-16T06:59:59Z (aligned)
```
- ✔ error line gone from the dropdown -> confirmed by the user
- ✔ new `[refresh] done` with 0 source errors and no config error -> line above (the window end still carried the one-second jitter fixed in Step 10)

### Step 10 of 12: Trigger exactly one threshold notification (US4)

**Why this step:** A notification fires when a percent crosses a threshold from below, once per threshold and window. Lowering the budget raises the percent without any new usage, which makes the crossing reproducible.

**Needs:** Step 9, and macOS notifications allowed for "LLM Usage" (System Settings, Notifications).

**Do:**

1. Note the current percent of group `V` from the dropdown (call it P).
2. Open **Settings…**, **Groups** tab, select `V`. In the thresholds field (placeholder `80, 100`) enter a whole number T that is about 10 points above P. Click **Save**. The save triggers a refresh; no notification appears because P is still below T.
3. Return to **Settings…**, **Groups**, select `V`, and set **Weekly budget (USD)** to half its current value. Click **Save**.
4. Wait for the refresh (a few seconds), then click **Refresh now** once more.

**What you should see:** After step 3 exactly one macOS notification appears, naming the group and the threshold T. After step 4 no second notification appears. The command below confirms it from the log.

**Run:**

```
rg -n "\[notifications\]" ~/Library/Logs/llm-usage-menubar/usage.log | tail -n 3
```

**What you should see:** Exactly one `crossing: Vertex weekly weekly T% (now N%)` line for this window, with N at or above T, and no second crossing line after the extra refresh.

**If you see something else:** A crossing line but no banner means notifications are not authorized for the app; check System Settings. Two crossing lines mean the baseline was not kept between refreshes.

**Result:** failed (banner), with the crossing logic verified and one app bug fixed on the way. Settings done by the user (thresholds 1350 and 1500, budget 60 to 30), log read by the agent.

First attempt, no notification and no crossing line. Cause found in the log: the 7-day reset flipped between `2026-10-16T06:59:59Z` and `2026-10-16T07:00:00Z` from one fetch to the next, because the usage endpoint computes `resets_at` relative to the request time with sub-second jitter (the fixture in the tests carries `06:59:59.706992`). Every flip changed the window end, which reset the threshold baseline (FR-029) and also made the log index re-read every file (`window start moved earlier, index reset`, 368 files, 500 MB). Fixed in commit 45b572c: reset times are rounded to the whole minute, test `resetJitterIsNormalized` added, 129 tests pass. App rebuilt and relaunched with the budget back at 60.

Second attempt, after the fix:
```
2026-10-13T11:38:42Z [refresh] group V: 802.683431 of 60 USD (1338%)
2026-10-13T11:39:46Z [config] saved from settings: 2 account(s), 1 group(s), interval 300 s
2026-10-13T11:39:50Z [refresh] group V: 802.683431 of 30 USD (2676%)
2026-10-13T11:39:50Z [notifications] crossing: Vertex weekly weekly 1350% (now 2676%)
2026-10-13T11:39:50Z [notifications] crossing: Vertex weekly weekly 1500% (now 2676%)
2026-10-13T11:39:50Z [notifications] authorization error: Notifications are not allowed for this application
2026-10-13T11:39:50Z [notifications] not sent (authorization denied): Vertex weekly (grp-vertex) weekly crossed 1350% at 2676%
2026-10-13T11:40:13Z [refresh] done in 0.308 s, 0 source error(s), window 2026-10-09T07:00:00Z to 2026-10-16T07:00:00Z (aligned)
```
- ✔ window end stable across all refreshes after the fix -> `2026-10-16T07:00:00Z` on every `done` line since relaunch
- ✔ one crossing per configured threshold when the percent jumped from 1338 to 2676 -> two crossing lines (1350 and 1500, both configured by the user), none on the three later refreshes
- ✔ bar marks the group above its threshold -> screenshot shows `M ⚠83%  V ‼2676%` (glyph styling, FR-005)
- ✘ a macOS notification banner -> none. macOS reports "Notifications are not allowed for this application" at launch and on send; the app has no entry under System Settings notification preferences (`com.apple.ncprefs`), and no permission prompt appears. A banner was delivered successfully at 08:55 during implementation; the first failure followed the next rebuild. The ad-hoc signature changes with every build, and macOS binds notification permission to the signature, so the earlier grant no longer matches and no new prompt is offered. Not an app logic defect; needs a stable signing identity (self-signed certificate or developer certificate) or launching one fixed build. Tracked in brainstorm/idea-inbox.md ("stable signing identity").

### Step 11 of 12: Open the per-model and per-day breakdown (US5)

**Why this step:** The dropdown must show, per group and per token-based account, one row per model with token categories and cost, and one entry per day of the window with zeros for idle days.

**Needs:** Step 9.

**Do:**

1. Click the menu bar item.
2. Under group `V`, expand **Details**.

**What you should see:** A table with columns `Model`, `In`, `Out`, `Cache w`, `Cache r`, `Cost` and a bold `Total` row whose cost equals the group amount from Step 5 (before the budget change). Below it, seven per-day entries, one per calendar day of the window, with `$0.00` on days without usage.

**If you see something else:** A model marked `unpriced` in orange means its id matched no price entry; add an override on the **Prices** tab. Fewer than seven day entries means the window is not zero-filled. Header or footer pushed out of view means the panel did not resize with the expanded content.

**Result:** passed on the fourth attempt, done by the user, with one app defect fixed on the way.
- First attempt: content correct, layout wrong. The model table (claude-opus-4-8, 802,68 US$) and eight day columns were present, but the panel kept its height, so expanding Details pushed the header and the footer buttons out of view. Cause: the MenuBarExtra window takes its size when it opens and does not follow later content changes.
- Second attempt, content wrapped in a scroll view: empty panel, because the window proposes no height to a scroll view. Reverted.
- Third attempt, fixed vertical size without animation: content visible again, panel still did not grow.
- Fourth attempt, commit 8e71689: the dropdown measures its content and resizes the hosting panel itself, anchored at the top, scrolling past a 640 point cap. User confirmed the panel grows and header, tables and footer stay visible.
- ✔ per-model table with `Model`, `In`, `Out`, `Cache w`, `Cache r`, `Cost`, total equals the group amount -> 802,68 US$ for claude-opus-4-8
- ✔ per-day entries with zeros on idle days -> F 184,80, S 163,64, S 119,41, M 306,85, T 27,98, W 0, T 0, F 0 (US$)
- Runbook correction: the window runs Friday 09:00 to the next Friday 09:00 local time, so the trend shows eight day columns, the first and last being partial days. The expectation of seven entries was wrong; the spec's "one entry per calendar day of the window" yields eight here.

### Step 12 of 12: Quit the app and restore the configuration (US3)

**Why this step:** Leaves the machine as it was: original budget and thresholds, no running app, no backup file.

**Needs:** Step 10.

**Run:**

```
echo "click the menu bar item, then Quit, then press Enter" && read -r _ && mv ~/.config/llm-usage-menubar/config.json.runbook-backup ~/.config/llm-usage-menubar/config.json && (pgrep -fl LLMUsageMenuBar || echo "app not running") && jq -c '[.groups[] | {label, weeklyBudgetUSD, thresholds}]' ~/.config/llm-usage-menubar/config.json
```

**What you should see:** `app not running`, then the group list with budget `60` and the original thresholds.

**If you see something else:** A process id in the output means the app is still running; quit it from the dropdown. A different budget means the backup was overwritten; edit the value back by hand.

**Result:** passed, run by the agent (app quit through AppleScript instead of the dropdown).
```
app not running
[{"label":"V","weeklyBudgetUSD":60,"thresholds":[80,100]}]
```
- ✔ `app not running` -> no LLMUsageMenuBar process
- ✔ budget 60 and original thresholds -> 60, [80, 100]; interval 300 and accounts M, VC also restored; backup file gone

## Not covered here

- Start at login (FR-035) needs a logout and login to observe; the toggle on the General tab and its log line (`start at login enabled`) are the only quick checks.
- Wake from sleep refresh (FR-025) needs a real sleep cycle; the log line `wake from sleep, refreshing` records it when it happens.
- Idle resource use over an hour (SC-008) was measured during implementation (average CPU 0.23%, resident memory at most 76 MB) and is not repeated here.
- A second subscription account with its own credential directory, and the credential-directory tie-breaker, need a second signed-in Claude Code profile with a separate `projects` tree.

## Coverage

- US1 (subscription limits): Steps 1 to 4.
- US2 (Vertex spend versus budget): Steps 5 and 6.
- US3 (configuration): Steps 7, 8, 9 and 12.
- US4 (notifications): Step 10.
- US5 (breakdowns and trend): Step 11.
- Not covered: start at login, wake refresh, long idle measurement, multiple subscription accounts (see above).

## Results

11 of 12 steps passed, 1 failed. Run on 2026-10-13 against the real Claude Max account and the real Vertex session logs.

What a reader now knows the feature does:
- The bar shows `M ⚠83%  V ‼2676%`, with glyph styling for entries above a threshold, and no Dock icon.
- Subscription percents match `/usage` in Claude Code within one point, and the group window aligns with the 7-day reset.
- The Vertex spend (802.68 USD for the week) matches the independent `scripts/sum-vertex.sh` sum exactly.
- Settings validation, a broken config file, and the restore all behave as specified.
- Threshold crossing detection works: one crossing per threshold, none on later refreshes.
- The per-model table and the zero-filled per-day trend render correctly.

Two app defects were found and fixed during the walkthrough:
- **Reset-time jitter** (commit 45b572c): the usage endpoint returns `resets_at` with sub-second jitter, so the window end flipped between 06:59:59 and 07:00:00. Each flip reset the threshold baseline, so no notification could ever fire, and forced a full re-read of all session logs. Reset times are now rounded to the minute.
- **Dropdown did not grow** (commit 8e71689): expanding Details pushed the header and footer out of view. The dropdown now resizes its panel.

Still failing:
- **Notification banner (Step 10)**: macOS answers "Notifications are not allowed for this application" and shows no permission prompt. A banner was delivered once earlier in the day; failures started after the next rebuild. The likely cause is that every build gets a new ad-hoc signature. A stable signing identity should fix it, and it is listed in `brainstorm/idea-inbox.md`.
