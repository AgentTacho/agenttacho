# Quickstart: Keep Last Good Values

How to check spec 010 end to end. Unit and integration tests cover every requirement (`make test`); these steps confirm the behavior in the real app.

## Prerequisites

- A build from this branch: `make app`, then start `build/AgentMeter.app` (quit any other copy first; the single-instance guard asks otherwise).
- At least one Claude subscription account with a working Claude Code login; optionally a Codex subscription account with live limits on.
- A way to drop the network for a minute: turn Wi-Fi off, or block the hosts with the macOS firewall.
- Follow the log: `tail -f ~/Library/Logs/agentmeter/usage.log`.

## 1. Blip without a stale marker (US1, SC-001)

1. Wait for a refresh with live values (bar shows percents without `~`).
2. Turn Wi-Fi off, click "Refresh now" (or wait for the next tick), then turn Wi-Fi on within 20 seconds.
3. Expected: the bar never shows `~`; the dropdown shows "Couldn't reach the usage service, retrying at HH:MM" in gray; about 30 s later the note disappears. The log shows the transport category, "quick retry scheduled" and a successful retry.
4. Repeat with Wi-Fi off for more than a minute. Expected: after the retry the bar shows `~` and the dropdown the orange stale note; no further quick retry in the log until a request succeeds.

## 2. Rejected sign-in (US2, SC-003)

Covered by tests with a stubbed 401 answer (`SubscriptionSourceTests`, `DropdownView` preview state). By hand, only if you can invalidate the token safely (for example sign in to Claude Code with the same account on another machine, which may revoke this Mac's token). Expected: `~` in the bar and the red "Sign-in rejected, run claude to sign in again" note; running `claude` and refreshing clears it.

## 3. Relaunch while offline (US3, SC-002)

1. With live values shown, quit AgentMeter.
2. Check the file: `cat ~/Library/Application\ Support/agentmeter/last-good.json` and `ls -l` on it. Expected: version 1, your accounts with percents and reset times, mode `-rw-------`, no token text (search for `sk-ant` and `eyJ`).
3. Turn Wi-Fi off and start the app. Expected: subscription entries show their values right away (token-based entries show `…`); once the first refresh fails they show `~` with "Stale, last good value <time of the quit>".
4. Turn Wi-Fi on and click "Refresh now" after a minute. Expected: fresh values without `~`.

## 4. Reset after relaunch (FR-016)

Covered by tests (`SubscriptionStatus.effective(now:)`, saved values with a past reset). By hand: edit a `resetsAt` in `last-good.json` to a past time while the app is not running, start offline. Expected: that window shows 0% without a reset time.

## 5. Security statement (FR-021)

Open README "Security and privacy". Expected: a row for `last-good.json` saying what it holds, where it lives, and that it holds no token.
