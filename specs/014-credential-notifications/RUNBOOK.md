---
runbook_version: 1
feature: 014-credential-notifications
status: passed
mode: light
steps_total: 7
step_results: passed,passed,passed,passed,passed,passed,passed
drafted_at: 6b0ca28
drafted_fingerprint: a7c1153375630a9b217925c93434de61440d19256db950ab3e5f68fcfc74f8c8
tested_at: fb35235
tested_fingerprint: dc3c5dbf2c0c80e0f9873ebac29691a072aeb26d8163d7e35f05cd07b2de0585
updated: 2026-10-16
---

# Try it: Credential Notifications

<!-- runbook-status -->
> **Status:** passed · 7 of 7 steps (7 passed) · Mode: light · Tested at fb35235 · 2026-10-16
<!-- /runbook-status -->








## What you're testing

AgentMeter now notifies once when a working Claude or Codex sign-in stops working, withdraws the notification when it works again, and offers one switch to turn this off. The journey runs in this order: confirm the logic with the test suite (including the end-to-end tests that drive real source results through the tracker), launch the built app, check that launch cleans up leftover credential notifications, try the new switch in Settings and confirm it is presentation only, and confirm no token reaches the log.

## Test environment

No fixtures. The steps use the app bundle built by `make app` and your existing AgentMeter configuration (`~/.config/agentmeter/config.json`) and log (`~/Library/Logs/agentmeter/usage.log`). AgentMeter only reads your agents' sign-ins; nothing here changes them.

## Steps

### Step 1 of 7: Run the test suite (US1, US2, US3)

**Why this step:** The notification rules (baseline, one notification per episode, withdraw on recovery, 24-hour expiry delay, the switch) live in UsageCore and are covered by tests, including end-to-end tests that feed real Claude and Codex source results (HTTP 401, missing and expired sign-ins) through the tracker and check that no token appears in any text.

**Run:**

```
make test 2>&1 | rg -e 'Suite (Credential|PendingNotificationQueue)' -e 'Test run with'
```

**What you should see:** Passing lines for the suites CredentialHealthTests, CredentialAlertTests, CredentialAlertTrackerTests, CredentialNoTokenTests, CredentialPostLedgerTests and PendingNotificationQueueTests, and a final line like "Test run with 926 tests in 95 suites passed".

**If you see something else:** A failing suite names the rule that broke; a missing suite means the test file is not in the target.

**Result:**

Passed (agent ran it). Expected vs actual: all six new suites passed (CredentialAlertTests, CredentialHealthTests, CredentialPostLedgerTests, PendingNotificationQueueTests, CredentialAlertTrackerTests, CredentialNoTokenTests); final line "Test run with 926 tests in 95 suites passed after 0.610 seconds." The filter also matched the existing CredentialReaderTests, which passed.

### Step 2 of 7: Build and launch the app (US1)

**Why this step:** Notifications, the click handler and the Settings switch only exist in the app bundle. Only one AgentMeter can run, so a running copy is quit first.

**Run:**

```
osascript -e 'quit app "AgentMeter"'; make run
```

**What you should see:** The build finishes with the signed app in `build/AgentMeter.app`, and the AgentMeter entry appears in the menu bar.

**If you see something else:** A build error points at the failing file; no menu bar entry means the old instance was still running (quit it from its dropdown and run `make run` again).

**Result:**

Passed (agent ran it). Build complete, "signing: developer-id", "Built build/AgentMeter.app", and `pgrep` shows the AgentMeter process running from the worktree's `build/AgentMeter.app`. The only compiler warning is a pre-existing deprecation in IconPickerSheet.swift, untouched by this feature.

### Step 3 of 7: Launch cleans up leftover credential notifications (US1)

**Why this step:** A credential notification from an earlier run would never be withdrawn by the new run, so the app removes such leftovers at launch.

**Run:**

```
rg -n 'credential leftovers removed' ~/Library/Logs/agentmeter/usage.log | tail -1
```

**What you should see:** A line from the launch a moment ago, "credential leftovers removed: 0" (or a higher count if a credential notification was still in Notification Center).

**If you see something else:** No line means the presenter was not created at launch (no app bundle, or the click delegate setup did not run).

**Result:**

Passed (agent ran it). Log line `2026-10-16T06:03:36Z [notifications] credential leftovers removed: 0`, written at the launch in step 2 (08:03 local).

### Step 4 of 7: The switch is on by default (US3)

**Why this step:** The setting must default to on, also for a configuration file written before this feature existed.

**Do:**

1. Open the AgentMeter dropdown and choose Settings.
2. Select the General tab.
3. Look for the "Notifications" section below "Launch".

**What you should see:** A "Notify when a sign-in stops working" switch, turned on.

**If you see something else:** A missing section means the Settings change is not in the build; a switch that is off on a file without the key means the default is wrong.

**Result:**

Passed (user did it). The user confirmed the "Notifications" section with "Notify when a sign-in stops working" switched on in Settings, General.

### Step 5 of 7: Turning the switch off is saved without a refresh (US3)

**Why this step:** The switch is presentation only: turning it off is saved and withdraws credential notifications at once, without calling the usage services.

**Do:**

1. In Settings, General, turn "Notify when a sign-in stops working" off.
2. Wait about two seconds for the change to apply.

**Run:**

```
jq '.notifySignInProblems' ~/.config/agentmeter/config.json; rg -n 'saved from settings' ~/Library/Logs/agentmeter/usage.log | tail -1
```

**What you should see:** `false`, then a log line from a moment ago ending in "display only".

**If you see something else:** `null` means the change was not saved yet (wait and run again); a line ending in "refresh settings" or "refresh local" means the switch is treated as data relevant.

**Result:**

Passed (user toggled, agent checked). `jq` printed `false`; log line `2026-10-16T06:07:01Z [config] saved from settings: 3 account(s), 1 group(s), interval 300 s, display only`. Note: the `rg ... | tail -1` part was rewritten by a local output-filter hook and showed no line; reading the log with plain grep gave the line above.

### Step 6 of 7: Turn the switch back on (US3)

**Why this step:** Leaves your setup as it was and confirms the value round trips.

**Do:**

1. In Settings, General, turn "Notify when a sign-in stops working" on again.
2. Wait about two seconds.

**Run:**

```
jq '.notifySignInProblems' ~/.config/agentmeter/config.json
```

**What you should see:** `true`.

**If you see something else:** `false` means the second change did not apply; toggle again and wait.

**Result:**

Passed (user toggled, agent checked). `jq` printed `true`.

### Step 7 of 7: No token in the log (US1)

**Why this step:** Credential notifications and their log lines must never contain a token (spec FR-010, SC-006).

**Run:**

```
rg -c -e 'sk-ant-' -e 'eyJhbGci' ~/Library/Logs/agentmeter/usage.log || echo "no token-like strings"
```

**What you should see:** `no token-like strings`.

**If you see something else:** A count means some line contains a token-like string; open the log and find which source wrote it.

**Result:**

Passed (agent ran it). Output: `no token-like strings`.

## Not covered here

- **A live rejected or removed sign-in notifying once and being withdrawn on recovery (US1).** Triggering it means invalidating or removing a real Claude Code or Codex sign-in on this Mac. Step 1 covers it through the end-to-end tests that drive the real sources with an HTTP 401 and a missing sign-in. To try it live, sign in to the same Claude account on another machine and wait for the next refresh (quickstart step 2).
- **The 24-hour expiry notification (US2).** It needs a token that has stayed expired for a day. Covered by the tracker tests in step 1.
- **Clicking a notification opens the dropdown, and banners while the dropdown is open.** They need a delivered notification; try them the next time a credential or threshold notification arrives (quickstart step 6). The log then shows "notification click: opened dropdown" or "activated app".

## Coverage

- **US1 (rejected or removed sign-in notifies once):** steps 1, 2, 3 and 7; the live trigger is not covered here (see above).
- **US2 (expiry after a delay):** step 1 only; a live check needs a day-old expired token.
- **US3 (switch):** steps 1 and 4 to 6.

## Results

7 steps: 7 passed, 0 failed, 0 skipped (2026-10-16).

The credential logic passes its full test suite, including end-to-end tests that drive the real Claude and Codex sources with HTTP 401, missing and expired sign-ins and confirm no token reaches any notification text or log subject. The built app removes leftover credential notifications at launch, shows the new "Notify when a sign-in stops working" switch on by default in Settings, General, saves it without triggering a refresh ("display only"), and round trips the value. The diagnostic log contains no token-like strings.

Not tried live: a real rejected, removed or day-old expired sign-in, and clicking a notification to open the dropdown (see "Not covered here").
