---

description: "Task list for credential notifications"
---

# Tasks: Credential Notifications

**Input**: Design documents from `specs/014-credential-notifications/`

**Prerequisites**: plan.md (see its Interfaces block and Global constraints), spec.md, research.md, data-model.md, contracts/notification-texts.md, quickstart.md

**Tests**: Included. AGENTS.md requires tests first for logic in UsageCore (Swift Testing, run with `make test`).

**Organization**: Tasks are grouped by user story so each story can be implemented and tested on its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

## Conventions for every task

- Signatures follow the Interfaces block in plan.md exactly.
- New and changed doc comments cite the requirements they implement (for example `spec 014 FR-005`).
- No em dash or en dash characters anywhere.
- Build and test only through the Makefile (`make test`, `make app`).

---

## Phase 1: Setup

**Purpose**: Confirm a green baseline before changing anything.

- [x] T001 Run `make test` on the branch and confirm all existing tests pass before any change (no file changes)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The snapshot entries carry what the tracker needs, and the health derivation exists (research R1, data-model "CredentialHealth" and "Additions to existing types").

- [x] T002 [P] Add tests in Tests/UsageCoreTests/SubscriptionSourceTests.swift: an expired Claude credential yields `.credentialsExpired` with `credentialExpiresAt` equal to the credential's `expiresAt`; `.ok`, `.notSignedIn`, `.signInRejected` and `.stale` entries have `credentialExpiresAt == nil`; a credential whose expiry lies in the future (clock moved backwards) is not expired
- [x] T003 [P] Add tests in Tests/UsageCoreTests/CodexLimitsSourceTests.swift: a missing sign-in yields `credentialProblem == .notSignedIn`, a sign-in kept in the keychain (`config.toml` with keychain storage) yields `.keychain`, an expired token yields `.expired(at:)` with the token's expiry; a rejected token, a live success, a transport failure and a credential reader that throws yield nil; `markedStale(reason:)` keeps `credentialProblem`; a later `.notDue` refresh after the failure keeps it
- [x] T004 Add `credentialExpiresAt: Date?` to `SubscriptionEntry` in Sources/UsageCore/Snapshot/UsageSnapshot.swift (init parameter defaulting to nil) and set it in Sources/UsageCore/Subscription/SubscriptionSource.swift by carrying the expiry date in the `credentialsExpired` attempt case and passing it where the `.credentialsExpired` entry is built (spec 014 FR-005); make T002 pass
- [x] T005 Add `public enum CodexCredentialProblem: Equatable, Sendable { case expired(at: Date), notSignedIn, keychain }` and `credentialProblem: CodexCredentialProblem?` (init parameter defaulting to nil) on `CodexLimitsEntry` in Sources/UsageCore/Subscription/CodexLimits.swift; add `credentialProblem` to `CodexLimitsSource.Failure` in Sources/UsageCore/Subscription/CodexLimitsSource.swift, set it in `live()` (`.missing` with the `CodexCredentialLookup.keychain` reason gives `.keychain`, other `.missing` gives `.notSignedIn`, an expired credential gives `.expired(at: expiresAt)`), and pass it into every entry built from a failure (`fallback`, `graceEntry` and the `.noRequest` path); make T003 pass
- [x] T006 [P] Add Tests/UsageCoreTests/CredentialHealthTests.swift covering every row of the derivation table in specs/014-credential-notifications/data-model.md for Claude and Codex, including nil for `.stale`, `.retrying`, Codex `.localOnly`, `.unavailable` without a problem, and a Codex entry whose `state.impliedLiveLimits == false`
- [x] T007 Implement `CredentialHealth` with `static func claude(_ entry: SubscriptionEntry) -> CredentialHealth?` and `static func codex(_ entry: CodexLimitsEntry) -> CredentialHealth?` (nil when `entry.state.impliedLiveLimits == false`) in Sources/UsageCore/Notifications/CredentialHealth.swift (spec 014 FR-001); make T006 pass

**Checkpoint**: `make test` green; entries carry expiry and problem; health derivation done.

---

## Phase 3: User Story 1 - A rejected or removed sign-in notifies once (Priority: P1) MVP

**Goal**: A working account that becomes rejected or not signed in gets exactly one notification; recovery withdraws it; a later failure notifies again. Clicking a notification opens the dropdown.

**Independent Test**: With a working Claude account, a 401 on the next refresh delivers one notification, later rejected refreshes deliver nothing, a success removes it (spec US1, quickstart steps 2 to 4, 6 and 8).

### Tests for User Story 1

- [x] T008 [P] [US1] Add Tests/UsageCoreTests/CredentialAlertTests.swift: title and body for every kind and provider per specs/014-credential-notifications/contracts/notification-texts.md with `directory == nil` (plain `claude`, `codex`) and with a directory (`CLAUDE_CONFIG_DIR=<dir> claude`, `CODEX_HOME=<dir> codex`); `identifier == "credential-<accountId>"`; `CredentialAlertEvent.logMessage` returns `<accountId> <kind>` for deliver and suppressed and `<accountId>` for withdraw, as in the contract
- [x] T009 [US1] Implement `CredentialAlert` and `CredentialAlertEvent` (`.deliver`, `.suppressed`, `.withdraw(accountId:)`, `logMessage`) in Sources/UsageCore/Notifications/CredentialAlert.swift per the plan's Interfaces block; formatting only, no path comparison; include the expired texts so US2 needs no text change (spec 014 FR-009 to FR-011); make T008 pass
- [x] T010 [P] [US1] Add Tests/UsageCoreTests/PendingNotificationQueueTests.swift: a newer crossing for the same entity, window and threshold replaces the older one; a newer credential alert for the same account replaces the older one; `removeCredential(accountId:)` drops only that account's alert and leaves crossings and other alerts; `drain()` returns both lists in insertion order and empties the queue
- [x] T011 [US1] Implement `PendingNotificationQueue` in Sources/UsageCore/Notifications/PendingNotificationQueue.swift per the plan's Interfaces block (spec 014 FR-014); make T010 pass
- [x] T012 [P] [US1] Add Tests/UsageCoreTests/CredentialAlertTrackerTests.swift (style of ThresholdTrackerTests) for: failing health at the first refresh after launch is a silent baseline; unchanged results (transport `.stale`) and an entry missing from the snapshot before the first health leave the baseline unset, then a rejection stays silent; working then rejected delivers once; further rejected refreshes deliver nothing; an entry missing from a later snapshot counts as unchanged; working again emits withdraw and no deliver; a second episode delivers again; working then not signed in delivers; Codex rejected and Codex missing sign-in deliver; Codex keychain delivers kind notReadable; a kind change after delivery delivers nothing; preliminary snapshots are ignored; accounts with "Show in bar" off still deliver; two accounts sharing one credential directory each deliver (FR-011); token-based accounts and groups never produce events; an account removed from the configuration, a changed credential directory or Codex home, and Codex live limits turned off each emit withdraw when delivered and drop the state; turning live limits on again starts a new baseline; transport, rate-limited and service-changed entries between working and rejected do not prevent the delivery; the alert's `directory` is nil for `~/.claude`, its expanded form and `~/.codex`, and set for other directories
- [x] T013 [US1] Implement `CredentialAlertTracker` (`init(paths:)`, `observe(snapshot:configuration:)`) in Sources/UsageCore/Notifications/CredentialAlertTracker.swift: per-account state keyed by account id with identity `claude|<canonical dir>` or `codex|<canonical home>|live` (canonical via `Attributor.canonical(paths.expand(...))`), transitions 1 to 6 and the configuration pass from specs/014-credential-notifications/data-model.md, skipping `snapshot.isPreliminary`, using `snapshot.generatedAt` as now, deciding `directory` by expanded comparison with the default; in this phase every due rejected, notSignedIn or notReadable episode delivers (expiry and switch come in US2 and US3) (spec 014 FR-001 to FR-004, FR-006 to FR-008, FR-011); make T012 pass
- [x] T014 [US1] Add Tests/UsageCoreTests/CredentialNoTokenTests.swift (written with T012, passes after T013) (SC-006): drive `SubscriptionSource` and `CodexLimitsSource` with the existing test fakes and sentinel token strings through working, rejected (HTTP 401), missing and expired outcomes, feed the snapshots to `CredentialAlertTracker`, and assert that no event's title, body, identifier or `logMessage` contains a sentinel

### Implementation for User Story 1

- [x] T015 [US1] Rework Sources/AgentMeter/NotificationPresenter.swift: use `PendingNotificationQueue`; add `handle(_ events: [CredentialAlertEvent])` that posts `.deliver` alerts with their `identifier` (default sound), logs `.suppressed`, and on `.withdraw` removes the delivered notification and pending request (`removeDeliveredNotifications(withIdentifiers:)`, `removePendingNotificationRequests(withIdentifiers:)`) and the queued alert; keep a set of identifiers posted in this run and log `credential withdrawn` only for those; log with `logMessage` plus the outcome per contracts/notification-texts.md; without an app bundle or with denied authorization only log (spec 014 FR-007, FR-010, FR-011, FR-014)
- [x] T016 [P] [US1] Add Sources/AgentMeter/MenuBarOpener.swift: `@MainActor enum MenuBarOpener { static func open(log: DiagnosticLog) }` that finds the app's `NSStatusBarButton` by walking the content views of `NSApp.windows`, returns early if the MenuBarExtra window is already visible, calls `performClick(nil)`, and otherwise calls `NSApp.activate()`; logs `notification click: opened dropdown` or `notification click: activated app` (research R6, spec 014 FR-013)
- [x] T017 [US1] In Sources/AgentMeter/NotificationPresenter.swift `init`, when an app bundle exists: set a `NotificationClickHandler: NSObject, UNUserNotificationCenterDelegate` (owned by the presenter) as `UNUserNotificationCenter.current().delegate`, whose `didReceive` calls `MenuBarOpener.open(log:)` on the main actor and completes and whose `willPresent` returns `[.banner, .list, .sound]`; and remove delivered notifications whose identifier starts with `credential-` (via `getDeliveredNotifications`), logging `credential leftovers removed: <count>` (spec 014 FR-007, FR-013, SC-005)
- [x] T018 [US1] Wire the tracker in Sources/AgentMeter/App.swift: make `notifications` a non-lazy property created at the end of `init` (so the click delegate exists before any click), add `credentialTracker = CredentialAlertTracker(paths: paths)` next to `thresholdTracker`, and in `apply(_:)` call `credentialTracker.observe(snapshot:configuration:)` and pass non-empty events to `notifications.handle(_:)`

**Checkpoint**: US1 complete and testable on its own (`make test`, quickstart steps 2 to 4, 6 to 8).

---

## Phase 4: User Story 2 - A long expiry notifies after a delay (Priority: P2)

**Goal**: An expired credential notifies only once it has been expired for 24 hours, measured from its expiry time.

**Independent Test**: A working account whose token expired 23 hours ago delivers nothing; at 24 hours one notification is delivered (spec US2).

- [x] T019 [US2] Add expiry tests to Tests/UsageCoreTests/CredentialAlertTrackerTests.swift: working then expired delivers nothing while `now < expiresAt + 24 h`; the first refresh at or after `expiresAt + 24 h` delivers once with kind expired, also when that refresh's result is unchanged; a renewal (working) before the delay delivers nothing; an app launch whose first health is expired is a silent baseline even 30 hours after expiry; expired then rejected inside the delay delivers at once; after an expired delivery a change to rejected delivers nothing; Codex expired behaves the same; a Claude `.credentialsExpired` entry without `credentialExpiresAt` is unchanged
- [x] T020 [US2] Add `static let expiryDelay: TimeInterval = 24 * 3600` and the due check for `expired(at:)` episodes (also re-checked on unchanged results) to Sources/UsageCore/Notifications/CredentialAlertTracker.swift (spec 014 FR-005, FR-006); make T019 pass

**Checkpoint**: US1 and US2 pass.

---

## Phase 5: User Story 3 - The user can turn credential notifications off (Priority: P3)

**Goal**: One global switch, on by default, stops and withdraws credential notifications without touching threshold notifications.

**Independent Test**: With the switch off, a rejection delivers nothing; turning it off removes a delivered credential notification; threshold notifications still arrive (spec US3, quickstart step 5).

- [x] T021 [P] [US3] Add tests to Tests/UsageCoreTests/ConfigurationTests.swift: `notifySignInProblems` is true when the key is absent, false round trips through encode and decode, the key is always encoded, and toggling it does not make `needsRefresh(comparedTo:)` true
- [x] T022 [US3] Add `public var notifySignInProblems: Bool` (init default true, coding key `notifySignInProblems`, decode `?? true`) to Sources/UsageCore/Config/Configuration.swift and reset it to true in `dataRelevant()` like `showsRunOutMarker` (spec 014 FR-012); make T021 pass
- [x] T023 [US3] Add switch tests to Tests/UsageCoreTests/CredentialAlertTrackerTests.swift: with the switch off a due episode emits `.suppressed` (not `.deliver`) and counts as notified (no later delivery, also not on a change of kind, also not after the switch is turned on); `configurationChanged(_:)` with the switch off emits withdraw for every delivered episode and nothing for others; an expired episode still inside its delay when the switch is turned on delivers when the delay passes; with the switch off, health and episodes are still tracked (a recovery while off ends the episode)
- [x] T024 [US3] Implement the switch in Sources/UsageCore/Notifications/CredentialAlertTracker.swift: read `configuration.notifySignInProblems` in `observe`, emit `.suppressed` when off, add `configurationChanged(_ configuration: Configuration) -> [CredentialAlertEvent]`, and set `delivered = false` after a withdraw caused by the switch (spec 014 FR-012); make T023 pass
- [x] T025 [US3] Add `Section("Notifications") { Toggle("Notify when a sign-in stops working", isOn: $draft.notifySignInProblems) }` to `GeneralSettingsTab` in Sources/AgentMeter/SettingsView.swift, after the "Launch" section (needs T022)
- [x] T026 [US3] In `saveConfiguration(_:)` in Sources/AgentMeter/App.swift, pass `credentialTracker.configurationChanged(config)` events to `notifications.handle(_:)`, so the switch takes effect without a refresh (research R5)

**Checkpoint**: All three stories pass `make test`.

---

## Phase 6: Polish and Cross-Cutting Concerns

- [x] T027 [P] Add one sentence under "Security and privacy", "What you should know" in README.md: AgentMeter notifies once when a working sign-in stops working (switch in Settings, General), naming the account and the command to run, never a token (spec 014 FR-015, research R9)
- [x] T028 [P] Run `rg -n '\x{2013}|\x{2014}' Sources Tests specs/014-credential-notifications README.md` and confirm no matches; confirm every new type's doc comment cites spec 014 requirements
- [x] T029 Run `make test` and `make app`; confirm green and that the app builds

---

## Dependencies and Execution Order

- Phase 1, then Phase 2: T002 and T003 before T004 and T005; T006 before T007 (T007 needs T004 and T005).
- US1 (Phase 3) needs Phase 2. T008 before T009, T010 before T011 (T011 needs T009), T012 before T013, T013 before T014 passes. T015 needs T011, T009. T017 needs T015 and T016. T018 needs T013, T015, T017.
- US2 and US3 need US1's tracker (T013). They both edit CredentialAlertTracker.swift and its tests, so run them one after the other. T025 needs T022.
- Polish after all stories.

### Parallel opportunities

- T002, T003 and T006 (different test files).
- T008, T010 and T012 (different test files); T016 alongside T013 and T015.
- T021 alongside T019 and T020.
- T027 and T028.

### Parallel example: User Story 1

```text
T008 CredentialAlertTests.swift  |  T012 CredentialAlertTrackerTests.swift  |  T016 MenuBarOpener.swift
```

## Implementation Strategy

1. MVP: Phases 1 to 3 (rejected and removed notifications with withdraw, leftovers cleanup and click). Validate with quickstart steps 2 to 4, 6 to 8.
2. Add US2 (expiry delay), then US3 (switch), validating each with its tests.
3. Polish: README, dash check, full `make test` and `make app`.
