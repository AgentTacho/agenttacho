---
runbook_version: 1
feature: 021-recover-stuck-offline
status: drafted
mode: light
steps_total: 7
step_results: pending,pending,pending,pending,pending,pending,pending
drafted_at: 5af20e6
drafted_fingerprint: 7a290d9c780fdaa98df952621bf7c18176bb352eacb5f2f6edbcf96ebb8d7bff
tested_at:
tested_fingerprint:
updated: 2026-10-16
---

# Try it: Recover From a Stuck Offline State

<!-- runbook-status -->
> **Status:** drafted · 0 of 7 steps · Mode: light · Drafted at 5af20e6 · 2026-10-16
<!-- /runbook-status -->

## What you're testing

AgentTacho now uses a fresh connection for every usage request, so a network change can no longer leave it stuck "offline" until a restart. "Refresh now" sends a real request again within a minute after a request that got no answer, and the diagnostic log names the technical error behind "The Internet connection appears to be offline".

Order of the journey: tests, start this build, make a request fail by going offline, read the log detail, come back online and click "Refresh now", toggle the VPN as a smoke test, back to the installed app.

All commands run from the root of the feature worktree (`.claude/worktrees/021-recover-stuck-offline`, or `main` after merge). Steps 3 to 5 take your Mac offline for a few seconds; keep it short, because the coding agent you are talking to needs the network too.

## Test environment

No fixtures. Needs a Claude subscription account and a Codex subscription account with live limits, Wi-Fi as the only network (unplug Ethernet if present), and the WireGuard VPN profile "Hofwiesen 9" for Step 6.

## Steps

### Step 1 of 7: Run the test suite (US1, US2, US3)

**Why this step:** The per-request session, the no-answer classification, the manual bypass (including merged clicks and rate-limit waits) and the log detail are `UsageCore` logic with tests.

**Run:**

```
make test 2>&1 | tail -1
```

**What you should see:** `Test run with 1431 tests in ... suites passed` (or more tests).

**If you see something else:** a failing `EndpointPolicyTests`, `SubscriptionSourceTests`, `CodexLimitsSourceTests`, `RefreshCoordinatorTests` or `NetworkFailureDetailTests` test names the rule that broke.

**Result:**

### Step 2 of 7: Start this build instead of the installed app (US1)

**Why this step:** The installed 0.4.1 does not have the fix; only one AgentTacho can run at a time.

**Run:**

```
osascript -e 'quit app "AgentTacho"'; make run 2>&1 | tail -2
```

**What you should see:** `Built build/AgentTacho.app` and `open "build/AgentTacho.app"`, then the AgentTacho icon in the menu bar with current values.

**If you see something else:** a build error means the branch does not compile; stop here.

**Result:**

### Step 3 of 7: Make a request fail while offline (US3)

**Why this step:** Produces a no-answer failure, the kind that got stuck on 2026-10-16.

**Do:**

1. Turn Wi-Fi off (Control Center > Wi-Fi).
2. Open the AgentTacho dropdown and click "Refresh now".
3. Wait about 5 seconds, then turn Wi-Fi back on. Do not click "Refresh now" yet.

**What you should see:** the Claude and Codex rows turn stale with the usual "usage endpoint unreachable: The Internet connection appears to be offline." text, as today.

**If you see something else:** fresh values mean the refresh ran before Wi-Fi went off; repeat steps 1 and 2.

**Result:**

### Step 4 of 7: Read the error detail in the log (US3)

**Why this step:** The log line now names the technical error, so the next stuck state leaves evidence (spec FR-007); the dropdown text stays as before.

**Run:**

```
rg -n "fetch failed \(transport\)|request failed" ~/Library/Logs/agenttacho/usage.log | tail -2 | cut -c1-260
```

**What you should see:** a recent line ending with a bracket such as `[NSURLErrorDomain -1009; underlying kCFErrorDomainCFNetwork -1009; stream error 50]`, and no token, URL or account email in it.

**If you see something else:** a line without the bracket means the log detail is missing; a `-1001` code means a timeout instead of offline, which is also a no-answer failure.

**Result:**

### Step 5 of 7: Come back online and click "Refresh now" (US2)

**Why this step:** Within a minute of a no-answer failure, a click must send a real request instead of reusing the failure (spec FR-003).

**Do:**

1. With Wi-Fi back on, open the dropdown and click "Refresh now" within a minute of Step 3.
2. Watch the Claude and Codex rows.

**What you should see:** both rows show fresh values without `~` and the stale notes disappear. The log (Step 4's command with `endpoint fetched` instead) shows `endpoint fetched for no-answer accounts (Refresh now)`.

**If you see something else:** `endpoint reused (last fetch N s ago)` means the bypass did not apply; check whether the Step 3 failure was logged as transport.

**Result:**

### Step 6 of 7: Toggle the VPN while AgentTacho runs (US1, SC-004 smoke test)

**Why this step:** The original incident probably followed a network change such as a VPN going up or down; with a fresh connection per request, AgentTacho recovers at the next request.

**Do:**

1. Connect the WireGuard profile "Hofwiesen 9", wait a few seconds, then disconnect it.
2. Wait about 10 seconds, then click "Refresh now" in the dropdown.

**What you should see:** fresh values for Claude and Codex, no "offline" note.

**If you see something else:** a lasting "offline" note after the VPN is down again means a request still fails; copy the bracketed log detail of the newest failure.

**Result:**

### Step 7 of 7: Return to the installed app (US1)

**Why this step:** Leaves your Mac running the installed AgentTacho again.

**Run:**

```
osascript -e 'quit app "AgentTacho"'; sleep 2; open -a /Applications/AgentTacho.app && sleep 3 && pgrep -lf "AgentTacho.app/Contents/MacOS"
```

**What you should see:** one process line with `/Applications/AgentTacho.app/Contents/MacOS/AgentTacho`.

**If you see something else:** a path under `build/` means the build is still running; quit it from the dropdown's gear menu.

**Result:**

## Not covered here

- **The exact 2026-10-16 failure:** its cause is unproven; Step 6 only shows recovery from a VPN toggle. If it happens again, Step 4's log detail is the evidence.
- **Merged clicks, several Claude accounts, rate-limit waits (FR-003a to FR-006):** need timing control; covered by `RefreshCoordinatorTests`, `SubscriptionSourceTests` and `CodexLimitsSourceTests`.

## Coverage

- **US1 (recovers by itself):** Steps 1, 2 and 6.
- **US2 ("Refresh now" really retries):** Steps 1 and 5.
- **US3 (the log shows why):** Steps 1, 3 and 4.

## Results
