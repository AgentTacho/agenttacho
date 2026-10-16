# Quickstart: Credential Notifications

## Automated checks

```bash
make test
```

Covers, in `Tests/UsageCoreTests`:

- `CredentialHealthTests`: every row of the derivation table in `data-model.md`.
- `CredentialAlertTrackerTests`: baseline at launch and while offline, working to rejected or not signed in notifies once, repeated failures stay silent, recovery withdraws, re-arm, expiry delay measured from the expiry time, expired to rejected inside the delay notifies, kind change after notifying is silent, switch off suppresses and withdraws, switch on later does not notify an episode that fell due while off, identity change and account removal withdraw, Codex live limits off, preliminary snapshots skipped, accounts hidden from the bar still notify.
- `CredentialAlertTests`: titles and bodies per `contracts/notification-texts.md`, default and non-default directories, and a sentinel test that no text contains the token strings used in a refresh (SC-006).
- `ConfigurationTests`: `notifySignInProblems` defaults to true when absent, round trips, and is not data relevant.
- `SubscriptionSourceTests` and `CodexLimitsSourceTests`: `credentialExpiresAt` and `credentialProblem` are set for the expired, missing and keychain cases.

## Manual walkthrough (app bundle required: `make app`)

1. Launch AgentMeter with a working Claude subscription account. Settings, General shows "Notify when a sign-in stops working" switched on.
2. Rejected sign-in: sign in to Claude Code with the same account on another machine (or invalidate the token). After the next refresh one notification "<account>: sign-in rejected" appears. Further refreshes add nothing.
3. Recovery: run `claude` to sign in again and refresh. The notification disappears from Notification Center.
4. Not signed in: move the credential away (for a non-default directory, rename its `.credentials.json`; for the default, use a test account directory). One notification "<account>: no sign-in found" appears.
5. Switch: turn the switch off while a credential notification is shown. It disappears at once. Cause another failure: nothing is delivered. Threshold notifications still arrive.
6. Click: click a credential or threshold notification. The dropdown opens. If the diagnostic log says `activated app`, the fallback ran and AgentMeter comes to the front.
7. Launch while failing: quit, break the sign-in, launch. No credential notification appears.
8. Leftovers: with a credential notification shown, quit AgentMeter and fix the sign-in, then launch. The old notification is gone from Notification Center.
9. Log: Settings, Log shows the `credential ...` lines from `contracts/notification-texts.md` and no token.
