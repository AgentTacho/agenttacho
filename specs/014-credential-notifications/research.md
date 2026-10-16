# Research: Credential Notifications

## R1. Where the credential health comes from

- **Decision**: Derive the health from the snapshot entries the refresh already produces, with two small additions so the expiry time is known:
  - Claude: `SubscriptionEntry` gains `credentialExpiresAt: Date?`, set by `SubscriptionSource` when it produces `.credentialsExpired` (the expiry time of the `OAuthCredential` it read). States map as `.ok` to working, `.signInRejected` to rejected, `.notSignedIn` to not signed in, `.credentialsExpired` to expired; `.stale` (transport, rate limit, service changed, unreadable credentials) and `.retrying` are unchanged.
  - Codex: `CodexLimitsEntry` gains `credentialProblem: CodexCredentialProblem?` (`.expired(at:)`, `.notSignedIn`, `.keychain`), carried in the source's `Failure` from `live()` (missing lookup, expired credential) into every entry built from that failure. `signInRejected == true` maps to rejected (it already covers a 401/403 and a token already rejected, spec 007 FR-003). `.live` and `.newerSnapshot` (the last request did not fail) map to working. Everything else is unchanged.
- **Rationale**: The tracker stays a pure function of `(snapshot, configuration)`, like `ThresholdTracker`, and the sources keep their existing state machines. Matching Codex reason strings would be fragile, so the problem is carried as a typed value.
- **Alternatives considered**: Reading credentials a second time in the tracker (rejected: extra reads, breaks the pure core and FR-015); a new snapshot section with per-account health (rejected: duplicates information the entries already hold).

## R2. Tracker shape

- **Decision**: A new pure struct `CredentialAlertTracker` in `Sources/UsageCore/Notifications/`, separate from `ThresholdTracker` (brainstorm approach A). `observe(snapshot:configuration:)` returns `[CredentialAlertEvent]` (`.deliver(CredentialAlert)` or `.withdraw(accountId:)`). `configurationChanged(_:)` returns the withdraw events for a switch turned off, so the app can act without waiting for a snapshot (see R5). The clock is `snapshot.generatedAt`.
- **Rationale**: Testable without UI or `UNUserNotificationCenter`; mirrors the existing tracker so reviewers recognize the pattern.
- **Alternatives considered**: Extending `ThresholdTracker` (rejected in the brainstorm: different baseline and reset rules).

## R3. Account identity and baseline

- **Decision**: State is keyed by account id and holds an identity string: `claude|<canonical credential directory>` or `codex|<canonical Codex home>|live`. A different identity, an account no longer in the configuration, or a Codex account with live limits off drops the state and emits a withdraw if a notification was delivered (FR-004, FR-008). Preliminary snapshots (saved values at launch, spec 010 FR-015) are skipped entirely. The baseline is the first health other than unchanged (clarification Q2).
- **Rationale**: Matches the spec's baseline triggers, including "after live limits are turned on" (the state was dropped while off).

## R4. Notification identifiers and queue (spec review F9)

- **Decision**: Credential notifications use the stable identifier `credential-<accountId>`. Posting with the same identifier replaces a delivered one (FR-011); withdrawing calls `removeDeliveredNotifications(withIdentifiers:)` and `removePendingNotificationRequests(withIdentifiers:)`. The queue moves into UsageCore as `PendingNotificationQueue` (threshold crossings and credential alerts); a withdraw removes the queued alert for that account (FR-014). Threshold identifiers keep their timestamp. At launch the presenter removes delivered `credential-` notifications left from an earlier run, since the new run starts from a baseline and would never withdraw them (SC-005).
- **Rationale**: One presenter keeps a single authorization flow and log source (`notifications`).

## R5. Switch changes and configuration edits

- **Decision**: The configuration key `notifySignInProblems` (Bool, absent means true) is presentation only: it is excluded from `Configuration.dataRelevant()`, so toggling it does not refresh. `AppModel.saveConfiguration` calls `credentialTracker.configurationChanged(config)` and hands the resulting withdraw events to the presenter at once. The tracker still sees the switch in every `observe` call, so a hand-edited file takes effect on the next refresh. Account removal and directory changes already trigger a refresh (`needsRefresh`), so `observe` handles them.
- **Rationale**: FR-012 requires removing delivered notifications when the switch goes off; waiting for the next scheduled refresh could take up to the refresh interval.

## R6. Opening the dropdown from a notification click (spec review N1, FR-013)

- **Decision**: Set a `UNUserNotificationCenterDelegate` (an `NSObject` helper owned by the presenter) in the presenter's `init`, which `AppModel` runs at launch, so a click that arrives before the first refresh is handled. On `didReceive`, call `MenuBarOpener.open()`: it looks through `NSApp.windows` for the status bar window that holds the `MenuBarExtra` button (an `NSStatusBarButton`, found by walking the content view's subviews), and calls `performClick(nil)` on it unless the `MenuBarExtra` window is already visible. If no button is found, it calls `NSApp.activate()` and nothing else. The outcome is written to the diagnostic log. `willPresent` returns `[.banner, .list, .sound]`, so notifications also appear while the dropdown is open (the app counts as active then).
- **Rationale**: SwiftUI's `MenuBarExtra` has no public API to open its window. Clicking its status button uses only public AppKit types and is what a user click does. The fallback satisfies FR-013's recorded alternative. The acceptance test (quickstart step 6) checks that the click opens the dropdown and, if the lookup ever fails, that the app comes to the front.
- **Alternatives considered**: Key-value access to private `statusItem` properties (rejected: private API); third-party `MenuBarExtraAccess` (rejected: new dependency for one call); replacing `MenuBarExtra` with an `NSStatusItem` and `NSPopover` (rejected: far larger change).

## R7. Expiry delay

- **Decision**: `CredentialAlertTracker.expiryDelay = 24 * 3600`, a constant. Due when `now >= expiresAt + expiryDelay`, checked on every refresh while the account stays expired.
- **Rationale**: Spec assumption; measured from the credential's own expiry, so a relaunch does not restart it (FR-005), although a relaunch does reset the baseline (FR-004).

## R8. Notification text

- **Decision**: Built in UsageCore by `CredentialAlert.title` and `.body` (contract `contracts/notification-texts.md`), so the texts and the "no token" guarantee (SC-006) are unit tested. Commands name a non-default directory as `CLAUDE_CONFIG_DIR=<dir as configured> claude` (same rule as `SignInRejectedNote`) or `CODEX_HOME=<home as configured> codex` (default `~/.codex`, compared after expansion).

## R9. README

- **Decision**: The "Security and privacy" section already states that tokens never reach notifications. Add one sentence under "What you should know" that AgentMeter notifies once when a working sign-in stops working (switch in Settings, General), and that the notification names the account and the command to run, never a token (FR-015).
