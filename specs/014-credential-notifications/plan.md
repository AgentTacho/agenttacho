# Implementation Plan: Credential Notifications

**Branch**: `014-credential-notifications` | **Date**: 2026-10-16 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/014-credential-notifications/spec.md`

## Summary

Deliver one macOS notification when a working Claude or Codex sign-in starts failing (rejected or removed at once, expired after 24 hours), withdraw it when the sign-in works again, and let one switch in Settings turn this off. A new pure `CredentialAlertTracker` in UsageCore derives a credential health per account from each snapshot (spec 010's failure states plus two small additions that carry the token's expiry time) and emits deliver and withdraw events; the existing `NotificationPresenter` posts them under a stable per-account identifier. Clicking any AgentMeter notification opens the dropdown.

## Technical Context

**Language/Version**: Swift 5.10 toolchain (Package.swift tools version), Swift 6 language features as used in the repo

**Primary Dependencies**: Foundation, SwiftUI (`MenuBarExtra`, Settings), AppKit, UserNotifications; no new dependencies

**Storage**: One new key `notifySignInProblems` in the existing configuration JSON; no new files; tracker state in memory only

**Testing**: Swift Testing via `make test` (UsageCore tests); UI behavior through the quickstart walkthrough

**Target Platform**: macOS 14+

**Project Type**: desktop menu bar app (UsageCore library plus thin SwiftUI app target)

**Performance Goals**: Tracker work is O(accounts) per snapshot; negligible

**Constraints**: No network requests, no writes to agents' files, no token material in notifications or logs (spec FR-010, FR-015)

**Scale/Scope**: A handful of accounts; about 6 source files touched, 3 new UsageCore files, 1 new app file

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The constitution file is an unfilled template. The project rules in `AGENTS.md` serve as gates:

| Gate | Status |
|---|---|
| Logic in UsageCore with tests, app target stays thin | Pass: health derivation, tracker and notification texts are in UsageCore; the app only wires events to `UNUserNotificationCenter` and the status button |
| Tests first | Pass: tasks put each test before its implementation |
| Doc comments cite spec requirements (`spec 014 FR-xxx`) | Planned in every new type |
| No em or en dash characters | Applies to code, comments, docs, commits |
| Read-only toward agents' files; README "Security and privacy" kept true | Pass: no new reads or writes; README sentence added (research R9) |
| Build and test only through the Makefile | Pass |

Post-design re-check: unchanged, pass.

## Design

### UsageCore

1. **Expiry and problem on entries** (research R1)
   - `SubscriptionEntry.credentialExpiresAt: Date?`, set by `SubscriptionSource` for `.credentialsExpired` (the `Attempt.credentialsExpired` case carries the date).
   - `CodexCredentialProblem` enum and `CodexLimitsEntry.credentialProblem`, carried through `CodexLimitsSource.Failure` from `live()` for a missing sign-in (keychain or not) and an expired credential, and kept by `markedStale` and the fallback builders.
2. **`CredentialHealth`** (`Notifications/CredentialHealth.swift`): enum plus `static func claude(_ entry:)` and `static func codex(_ entry:)` (the latter returns nil when `entry.state.impliedLiveLimits == false`), nil meaning unchanged (data-model table).
3. **`CredentialAlert` and `CredentialAlertEvent`** (`Notifications/CredentialAlert.swift`): value types. `CredentialAlert` formats `identifier`, `title`, `body` per `contracts/notification-texts.md` from its `directory` field (nil means default); it does no path comparison. `CredentialAlertEvent` has `.deliver`, `.suppressed` (due while the switch is off, only logged) and `.withdraw`, and a `logMessage` with the contract's log text, so every user-visible and logged string is built and tested in UsageCore.
4. **`CredentialAlertTracker`** (`Notifications/CredentialAlertTracker.swift`): pure struct created with `Paths`; it owns the default-directory decision (expanded comparison with `paths.defaultClaudeDirectoryPath` and the existing `Paths.defaultCodexHome`) and the canonical identities. Transitions as in `data-model.md`, `expiryDelay = 24 h`, preliminary snapshots skipped.
5. **`PendingNotificationQueue`** (`Notifications/PendingNotificationQueue.swift`): value type holding queued threshold crossings and credential alerts while authorization is pending: newest crossing per entity, window and threshold (as today), one credential alert per account (newest wins), `removeCredential(accountId:)`, `drain()`. Tested in UsageCore (AGENTS.md: logic in UsageCore).
6. **Configuration**: `notifySignInProblems` (decode `?? true`, always encoded like `showsRunOutMarker`), reset to true in `dataRelevant()` so it is presentation only.

### Interfaces

```text
public enum CredentialHealth: Equatable, Sendable
    static func claude(_ entry: SubscriptionEntry) -> CredentialHealth?
    static func codex(_ entry: CodexLimitsEntry) -> CredentialHealth?

public struct CredentialAlert: Equatable, Sendable
    accountId, accountName: String; provider: Provider (.claude, .codex); kind: Kind (.rejected, .notSignedIn, .notReadable, .expired); directory: String?
    var identifier: String; var title: String; var body: String

public enum CredentialAlertEvent: Equatable, Sendable
    case deliver(CredentialAlert), suppressed(CredentialAlert), withdraw(accountId: String)
    var logMessage: String

public struct CredentialAlertTracker: Sendable
    static let expiryDelay: TimeInterval
    init(paths: Paths = Paths())
    mutating func observe(snapshot: UsageSnapshot, configuration: Configuration) -> [CredentialAlertEvent]
    mutating func configurationChanged(_ configuration: Configuration) -> [CredentialAlertEvent]

public struct PendingNotificationQueue: Sendable
    mutating func add(_ crossing: ThresholdCrossing); mutating func add(_ alert: CredentialAlert)
    mutating func removeCredential(accountId: String); mutating func drain() -> (crossings: [ThresholdCrossing], alerts: [CredentialAlert])
```

### Global constraints

- No em or en dash characters; doc comments cite `spec 014 FR-xxx`.
- No credential data enters any type above; the only inputs are snapshot entries and configuration.
- The app target only maps events to `UNUserNotificationCenter` calls and logs `logMessage`.

### App target (thin)

7. **`NotificationPresenter`**: uses `PendingNotificationQueue`; `handle(_ events: [CredentialAlertEvent])` posts with identifier `credential-<accountId>`, logs `.suppressed`, and withdraws (delivered notification, pending request and queued item). It keeps the set of identifiers it actually posted and logs a withdraw only for those. In its `init`, when an app bundle exists, it sets a `NotificationClickHandler` (`NSObject`, `UNUserNotificationCenterDelegate`) as delegate and removes every delivered notification whose identifier starts with `credential-` (left over from an earlier run, which the new run's baseline would never withdraw; SC-005, FR-007, FR-008). `didReceive` calls `MenuBarOpener.open(log:)`; `willPresent` returns banner, list and sound.
8. **`MenuBarOpener`** (new file): finds the `NSStatusBarButton` of the app's status item in `NSApp.windows` and clicks it unless the `MenuBarExtra` window is visible; otherwise `NSApp.activate()` (research R6).
9. **`AppModel`**: `credentialTracker = CredentialAlertTracker(paths: paths)` next to `thresholdTracker`; the presenter is created eagerly at the end of `init` (no longer lazy) so the click delegate exists before any click; `apply(_:)` passes `observe` events to the presenter; `saveConfiguration` passes `configurationChanged` events.
10. **Settings, General**: new `Section("Notifications")` with `Toggle("Notify when a sign-in stops working", isOn: $draft.notifySignInProblems)`.
11. **README**: one sentence under "Security and privacy", "What you should know" (research R9).

### Changes to earlier behavior

Clicking a threshold notification now opens the dropdown, and notifications also show while the dropdown is open (spec "Changes to earlier specs").

## Project Structure

### Documentation (this feature)

```text
specs/014-credential-notifications/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/notification-texts.md
├── checklists/requirements.md
└── tasks.md            # from /speckit-tasks
```

### Source Code (repository root)

```text
Sources/UsageCore/
├── Config/Configuration.swift                 # notifySignInProblems
├── Snapshot/UsageSnapshot.swift               # SubscriptionEntry.credentialExpiresAt
├── Subscription/CodexLimits.swift             # CodexCredentialProblem, CodexLimitsEntry.credentialProblem
├── Subscription/CodexLimitsSource.swift       # Failure.credentialProblem
├── Subscription/SubscriptionSource.swift      # expiry date on .credentialsExpired
└── Notifications/
    ├── CredentialHealth.swift                 # new
    ├── CredentialAlert.swift                  # new
    ├── CredentialAlertTracker.swift           # new
    └── PendingNotificationQueue.swift         # new

Sources/AgentMeter/
├── App.swift                                  # tracker wiring
├── NotificationPresenter.swift                # queue, identifiers, withdraw, click delegate
├── MenuBarOpener.swift                        # new
└── SettingsView.swift                         # switch in General

Tests/UsageCoreTests/
├── CredentialHealthTests.swift                # new
├── CredentialAlertTests.swift                 # new
├── CredentialAlertTrackerTests.swift          # new
├── PendingNotificationQueueTests.swift        # new
├── CredentialNoTokenTests.swift               # new, SC-006 sentinel through source and tracker
├── ConfigurationTests.swift
├── SubscriptionSourceTests.swift
└── CodexLimitsSourceTests.swift

README.md                                      # Security and privacy sentence
```

**Structure Decision**: Existing two-target layout; new logic in `Sources/UsageCore/Notifications/` next to `ThresholdTracker`.

## Complexity Tracking

No gate violations.
