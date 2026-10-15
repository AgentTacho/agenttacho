---
runbook_version: 1
feature: 007-codex-plan-limits
status: passed
mode: light
steps_total: 10
step_results: passed,passed,passed,passed,passed,passed,passed,passed,passed,passed
drafted_at: 8e5508b
drafted_fingerprint: 5936aa5c2821fdd052faaf4460235a984fdd1961b8f6beea68a6d649c418732e
tested_at: 45c3ee5
tested_fingerprint: 5936aa5c2821fdd052faaf4460235a984fdd1961b8f6beea68a6d649c418732e
updated: 2026-10-14
---

# Try it: Codex Plan Limits

<!-- runbook-status -->
> **Status:** passed · 10 of 10 steps (10 passed) · Mode: light · Tested at 45c3ee5 · 2026-10-14
<!-- /runbook-status -->











## What you're testing

A Codex subscription account (ChatGPT plan) now shows its plan limits like a Claude subscription: every plan window with percent and reset time, a bar entry, and threshold notifications. Values come live from the ChatGPT usage service with your Codex sign-in, which AgentMeter reads but never changes. When the service cannot be reached, the newest limits Codex recorded on this Mac are shown, marked stale.

The journey:
1. Run the test suite and check your Codex sign-in and local data (without printing any token).
2. Record the sign-in file's timestamp, build and start the app.
3. Look at the live windows and compare them with Codex `/status`.
4. Go offline and watch the fallback.
5. Switch the account to local data only.
6. Confirm the diagnostic log and the untouched sign-in file.

## Test environment

No fixtures. The journey uses your real Codex sign-in (`~/.codex/auth.json` in ChatGPT mode) and your real Codex session logs, both read-only.

## Steps

### Step 1 of 10: Run the test suite (US1, US2, US3, US4)

**Why this step:** The suite covers every requirement with synthetic data, including the token sentinel and the Codex home immutability checks, before anything touches your real data.

**Run:**

```
make test 2>&1 | tail -5
```

**What you should see:** A final line reporting all tests passed (about 560 tests in 63 suites), no failures.

**If you see something else:** A failing suite name points at the area (for example `CodexLimitsSourceTests` for the source logic). Do not continue until it passes.

**Result:** passed (agent). Expected all tests pass, about 560 in 63 suites; actual: `Test run with 562 tests in 63 suites passed after 0.490 seconds.`

### Step 2 of 10: Check the Codex sign-in mode (US1)

**Why this step:** Live limits need a ChatGPT plan sign-in stored as a file in the Codex home. This prints only the mode and whether a token is present, never the token.

**Run:**

```
jq -r '"auth_mode=\(.auth_mode) token_present=\(.tokens.access_token != null)"' ~/.codex/auth.json
```

**What you should see:** `auth_mode=chatgpt token_present=true`

**If you see something else:** `apikey` means Codex is signed in with an API key (no plan limits). A missing file means Codex keeps the sign-in in the keychain or is not signed in; the account will then show local snapshots only.

**Result:** passed (agent). Expected `auth_mode=chatgpt token_present=true`; actual: `auth_mode=chatgpt token_present=true`.

### Step 3 of 10: Check that local plan snapshots exist (US2)

**Why this step:** The fallback needs at least one Codex session on this Mac that recorded plan limits.

**Run:**

```
rg -l --sort modified '"plan_type":"[a-z]' ~/.codex/sessions | tail -1
```

**What you should see:** The path of a recent `rollout-*.jsonl` file.

**If you see something else:** No output means no plan session ran on this Mac yet. Run one short Codex prompt with your ChatGPT login, then retry.

**Result:** passed (agent). Expected a recent rollout path; actual: `~/.codex/sessions/2026/10/14/rollout-2026-10-14T17-35-20-01a13b0d-c626-7af1-9e8e-73d7f4360875.jsonl`.

### Step 4 of 10: Record the sign-in file's timestamp (US1)

**Why this step:** AgentMeter must never write to the Codex home. This baseline is compared in step 10.

**Run:**

```
stat -f '%m %z' ~/.codex/auth.json | tee /tmp/agentmeter-auth-stat.txt
```

**What you should see:** Two numbers: the modification time (epoch seconds) and the file size.

**If you see something else:** An error means the file is missing; see step 2.

**Result:** passed (agent). Expected two numbers; actual: `1791981704 4213` (saved to /tmp/agentmeter-auth-stat.txt).

### Step 5 of 10: Build and start the app (US1)

**Why this step:** The menu bar app is where the limits appear.

**Needs:** Step 1.

**Run:**

```
make run
```

**What you should see:** The build finishes and AgentMeter appears in the menu bar.

**If you see something else:** A signing or build error is printed by `scripts/release/build-app.sh`; check that Xcode command line tools are installed.

**Result:** passed (agent). Expected build success and a menu bar item; actual: `Built build/AgentMeter.app`, exit 0, app running (pid 39123). Log: specs/007-codex-plan-limits/.walkthrough/step-5.log. Note: an older 006 build (pid 75179) was also running.

### Step 6 of 10: See the live windows and compare with Codex (US1)

**Why this step:** This is the main promise: the plan's windows, live, matching what Codex reports.

**Needs:** Step 5 and a Codex subscription account in AgentMeter (Settings, Accounts, add, platform ChatGPT, if you do not have one yet).

**Do:**
1. Click the AgentMeter menu bar item and find the Codex account section.
2. In a terminal, start `codex` and run `/status`.
3. Compare the 5-hour and weekly percents and reset times.

**What you should see:** The dropdown shows "5-hour" and "weekly" (Plus) or "30-day" (Free) with percent and local reset time and the plan name (for example "Plus"), no stale note. The bar entry shows the longest window's percent. Both percents are within 1 point of Codex `/status`.

**If you see something else:** "Codex sign-in expired" means Codex has not run for days; run any Codex command and refresh. A stale note "usage service changed" means the service answer format changed; check the diagnostic log (step 9).

**Result:** passed (user). Live windows shown in the dropdown and bar, within 1 point of Codex `/status`, as reported by the user.

### Step 7 of 10: Go offline and watch the fallback (US2)

**Why this step:** When the service is unreachable, the account should keep plausible values instead of going blank.

**Needs:** Step 6.

**Do:**
1. Turn off Wi-Fi (and unplug any wired network).
2. Open the dropdown and click Refresh.
3. Turn the network back on and click Refresh again.

**What you should see:** While offline, the Codex account still shows its windows, marked stale with "offline" and an "as of" time; the bar entry is dimmed. After reconnecting and refreshing, the stale note disappears.

**If you see something else:** "Unavailable" while offline means no live result or snapshot was found (see step 3).

**Result:** passed (user). Offline: windows kept, marked stale with "offline" and an "as of" time, bar dimmed; after reconnecting and refreshing the stale note disappeared, as reported by the user.

### Step 8 of 10: Switch to local data only (US4)

**Why this step:** Turning off live limits must stop credential reads and requests, and show local snapshots without a failure marker.

**Needs:** Step 6.

**Do:**
1. Open Settings, Accounts, select the Codex account.
2. Turn off "Live limits from the usage service" and close Settings.
3. Open the dropdown.
4. Turn the setting back on afterwards.

**What you should see:** The dropdown shows "Local data, as of <time>" with the snapshot's windows, and the bar entry is not dimmed. After turning the setting back on, live values return at the next refresh.

**If you see something else:** A stale note while live limits are off would be a bug (spec FR-006).

**Result:** passed (user). With live limits off: "Local data, as of <time>" with snapshot windows, bar not dimmed; live values returned after re-enabling, as reported by the user.

### Step 9 of 10: Check the diagnostic log (US1, US2, US4)

**Why this step:** Each refresh logs which source supplied the Codex values and why, and must never contain credential text.

**Run:**

```
rg 'codexLimits' ~/Library/Logs/agentmeter/usage.log | tail -6
```

**What you should see:** Recent lines naming the account with "live", "stale" with a reason (from step 7, showing the newer of the last live result and the snapshot) or "local only" (from step 8), an observation time, and a reason where applicable. No token-like strings (long base64 text starting with `eyJ`).

**If you see something else:** No lines means the source did not run; check that the account exists and the app refreshed.

**Result:** passed (agent). Log lines: `live, observed 2026-10-14T19:19:03Z, fetched`; `local only, snapshot, observed 2026-10-14T15:45:29Z, live limits off`; `stale, live, observed 2026-10-14T19:14:02Z, reason: offline, request failed: usage endpoint unreachable: The Internet connection appears to be offline.` Token-like strings (`eyJ...`) in the log: 0. Runbook correction: step 7 showed the last live result as stale (it was newer than the 15:45 snapshot, FR-005), so the expectation "snapshot (from step 7)" should read "live or snapshot, whichever is newer".

### Step 10 of 10: Confirm the sign-in file is untouched (US1)

**Why this step:** AgentMeter must never refresh the token or write to the Codex home (spec FR-003, SC-004). Codex itself may legitimately update the file if it ran in between.

**Needs:** Step 4.

**Run:**

```
diff /tmp/agentmeter-auth-stat.txt <(stat -f '%m %z' ~/.codex/auth.json) && echo unchanged
```

**What you should see:** `unchanged`, unless you ran Codex in step 6, in which case Codex may have refreshed its own sign-in.

**If you see something else:** A difference without having run Codex would be a serious bug; stop and report it.

**Result:** passed (agent). Expected `unchanged`; actual: `unchanged` (mtime 1791981704, size 4213 as in step 4).

## Not covered here

- **Threshold notifications (US3):** a real crossing needs plan usage to rise across a threshold between two refreshes, which cannot be triggered reliably by hand. The `ThresholdTrackerTests` suite in step 1 covers crossings, baselines, resets and the live-limits toggle.
- **Rate limiting and rejected sign-ins:** these need the service to answer 429 or 401, covered by `CodexLimitsSourceTests` and `CodexUsageClientTests`.

## Coverage

- US1 (live utilization): steps 2, 4, 5, 6, 9, 10.
- US2 (fallback): steps 3, 7, 9.
- US3 (thresholds): automated tests only (step 1), see "Not covered here".
- US4 (local data only): steps 8, 9.

## Results

All 10 steps passed (6 run by the agent, 4 checked by the user in the app). Against a real ChatGPT Plus sign-in, the Codex subscription account showed live 5-hour and weekly windows matching Codex `/status`; offline it kept the last values marked stale with the reason; with live limits off it showed local snapshot data without stale styling; the diagnostic log records the source of every value and contains no credential text; and `~/.codex/auth.json` was not modified. Threshold notifications, rate limiting and rejected sign-ins are covered by the automated suite only (see "Not covered here"). One expectation in step 9 was corrected during the run.
