# Implementation Plan: Free Reset Tickets

**Branch**: `033-free-reset-tickets` | **Date**: 2026-10-21 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/033-free-reset-tickets/spec.md`

## Summary

Read free limit-reset tickets for Claude (a query flag on the existing usage request) and Codex (one extra read-only request after a successful plan-limit request), keep them in memory on the snapshot entries, show up to three dimmed `solid:gift` glyphs plus `+N` in each account's dropdown header with expiry tooltips and a click that opens the provider's usage page, and deliver two expiry notifications per account and expiry time (3 days, 24 hours), de-duplicated across relaunches by a small record in the macOS defaults. Parsing, ticket state, flag handling, texts and the expiry tracker live in UsageCore; the app adds a header view, the presenter wiring and one Settings switch.

## Technical Context

**Language/Version**: Swift 5.10 toolchain, Swift 6 language features as used in the repo

**Primary Dependencies**: Foundation, SwiftUI, AppKit, UserNotifications; no new dependencies

**Storage**: New configuration key `notifyFreeResetExpiry`; new defaults key `freeResetNotices` (notification record); tickets in memory only, `last-good.json` unchanged

**Testing**: Swift Testing through `make test` (UsageCoreTests, DemoModeTests) with `StubURLProtocol`; UI through quickstart and walkthrough

**Target Platform**: macOS 14+

**Project Type**: desktop menu bar app (UsageCore library, DemoMode, thin SwiftUI app target)

**Performance Goals**: no extra Claude request (except FR-004's single repeat); at most one extra Codex request per refresh, 10 s timeout

**Constraints**: read-only toward services and agents' files; no identifiers or tokens in logs, notifications or storage (FR-006, FR-015, FR-019)

**Scale/Scope**: a handful of accounts; about 12 source files touched, 4 new UsageCore files, 1 new app view

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status |
|---|---|
| I. Issue first, AI welcome, specs recommended | Pass: maintainer-initiated, full spec pipeline |
| II. Test-first, logic in UsageCore | Pass: parsing, flag state, ticket list, texts, tracker, record store and configuration are UsageCore with tests first; the app maps events and renders |
| III. Read-only, privacy | Pass: two read requests documented in `contracts/external-sources.md`; nothing redeemed; no identifiers stored; README and site privacy sections updated in the same pull request (FR-020) |
| IV. Makefile only | Pass |
| V. Screenshots and website | Pass: table below; no new card or stem under constitution 2.1.0 (spec FR-022, FR-023) |
| No em or en dashes, Conventional Commits, doc comments cite `spec 033 FR-xxx` | Planned |

Post-design re-check: unchanged, pass.

## Screenshots and website

| | |
|---|---|
| Shots that change | glance, same-provider (both show the first Claude Max section); one capture run rewrites all 14 files |
| New shots | none (no new card or stem; constitution 2.1.0, card candidates list) |
| Demo scenario | `acc-max` gets two tickets, one expiring in 2d 4h and one without expiry (coverage test: `defaultScenarioShowsResetTickets`) |
| Website copy | `src/components/agenttacho/Privacy.astro` (mirror of README FR-020); `docs/card-candidates.md` entry: spec, pull request, status `ready` after merge; feature strip and cards unchanged |
| README image | unchanged |

## Design

### UsageCore

1. **`Subscription/ResetTickets.swift`** (new): `ResetTicket`, `ResetTicketRead` (with `kind` labels), list helpers (`usable(at:)`, `sortedForDisplay`, `glyphs(at:)`, `groupedByExpiry`), and the two decoders: `ResetTicketDecoding.claude(cedarEmber: Any?, now:) -> ResetTicketRead` and `ResetTicketDecoding.codex(data: Data, now:) -> ResetTicketRead` with the plausibility caps (research R1, R3).
2. **`UsageEndpointClient`**: `fetch(token:includeTickets:) -> (status: SubscriptionStatus, tickets: ResetTicketRead?)`; adds the query item when asked; decodes `cedar_ember` leniently so a bad block never fails the windows. Existing `fetch(token:)` stays as a wrapper for callers and tests.
3. **`SubscriptionSource`**: per-account `TicketFlag` and `lastTickets`; `attempt` performs the FR-004 repeat and returns the ticket read with the attempt; `apply` sets `SubscriptionEntry.resetTickets` per FR-003; per-run log-once set (research R9); pruning with the other per-account state; a credential directory change clears `lastTickets` and resets the flag, like `lastGood`.
4. **`CodexUsageClient.fetchResetCredits(_:) -> ResetTicketRead`**: request per `contracts/external-sources.md`, 10 s timeout, never throws.
5. **`CodexLimitsSource`**: `live` calls `fetchResetCredits` only after `fetch` succeeded and returns the read with `.success`; a failed or skipped plan-limit request yields `.temporaryFailure(skipped)`; `lastTickets` per canonical home, mapped to accounts through `plan.home` (live limits on only); entries built without a request (`notDue`, `blocked`, `noRequest`, `fallback`, `graceEntry`) attach `lastTickets` minus expired; live limits off gives none.
6. **Snapshot entries**: `resetTickets` on `SubscriptionEntry` and `CodexLimitsEntry`, copied by `reused`, `endingGrace`, `markedStale`; not passed to `LastGoodStore`.
7. **`Dropdown/ResetTicketText.swift`** (new): glyph tooltip, overflow tooltip, VoiceOver label (contracts/texts.md), using new `TimeText.expiry(_:)` and `TimeText.absolute(_:)`.
8. **`Notifications/ResetTicketExpiry.swift`** (new): `ResetTicketExpiryStep`, `ResetTicketExpiryAlert` (identifier, title, body, logMessage), `ResetTicketExpiryEvent` (`.deliver`, `.suppressed`).
9. **`Notifications/ResetTicketExpiryTracker.swift`** (new): pure struct over a `ResetTicketNoticeStore`; `observe(snapshot:configuration:now:) -> [ResetTicketExpiryEvent]` per data model; skips preliminary snapshots.
10. **`Notifications/ResetTicketNoticeStore.swift`** (new): protocol, `UserDefaultsResetTicketNoticeStore(defaults:)`, `InMemoryResetTicketNoticeStore`.
11. **`PendingNotificationQueue`**: third list for expiry alerts.
12. **`Configuration`**: `notifyFreeResetExpiry` (as `notifySignInProblems`).
13. **`AppLinks`**: `claudeUsagePage`, `codexUsagePage`.

### Interfaces

```text
public struct ResetTicket: Equatable, Sendable { public var expiresAt: Date? }
public enum ResetTicketRead: Equatable, Sendable { case tickets([ResetTicket]), temporaryFailure(String), clearingFailure(String) }
extension Array where Element == ResetTicket
    func usable(at: Date) -> [ResetTicket]; var sortedForDisplay: [ResetTicket]
    func glyphs(at: Date) -> (shown: [ResetTicket], overflow: [ResetTicket]); func groupedByExpiry(at: Date) -> [Date: Int]
public enum ResetTicketText
    static func glyphTooltip(_: ResetTicket, times: TimeText) -> String
    static func overflowTooltip(_: [ResetTicket], times: TimeText) -> String
    static func accessibilityLabel(_: [ResetTicket], times: TimeText) -> String
public struct ResetTicketNoticeKey: Hashable, Sendable { accountId: String; expiresAt: Date; step: ResetTicketExpiryStep }
public enum ResetTicketExpiryStep: String, Sendable { case threeDays = "3d", oneDay = "24h" }
public protocol ResetTicketNoticeStore: Sendable { func load() -> Set<ResetTicketNoticeKey>; func save(_: Set<ResetTicketNoticeKey>) }
public struct ResetTicketExpiryAlert: Equatable, Sendable
    accountId, accountName: String; step: ResetTicketExpiryStep; expiresAt: Date; count: Int
    func identifier() -> String; func title() -> String; func body(times: TimeText) -> String; func logMessage(suppressed: Bool) -> String
public enum ResetTicketExpiryEvent: Equatable, Sendable { case deliver(ResetTicketExpiryAlert), suppressed(ResetTicketExpiryAlert) }
public struct ResetTicketExpiryTracker
    init(store: ResetTicketNoticeStore)
    mutating func observe(snapshot: UsageSnapshot, configuration: Configuration, now: Date) -> [ResetTicketExpiryEvent]

// SubscriptionSource (internal)
enum TicketFlag { case on, suspended, offForRun }
static func attempt(..., flag: TicketFlag) async -> (Attempt, tickets: ResetTicketRead?, flag: TicketFlag)   // apply commits both
// CodexUsageClient
init(..., resetCreditsURL: URL = CodexUsageClient.defaultResetCreditsURL)
func fetchResetCredits(_ credential: CodexCredential) async -> ResetTicketRead   // own session, 10 s request and resource timeout
// PendingNotificationQueue
mutating func add(_ alert: ResetTicketExpiryAlert); mutating func drain() -> (crossings, alerts, expiries)   // presenter call site updated
```

The presenter formats the body with a `TimeText` built from the system calendar and locale at delivery; tests pin `en_US_POSIX` and a fixed time zone.

### App target (thin)

14. **`ResetTicketGlyphs`** (new view in `Sources/AgentTacho/ResetTicketGlyphs.swift`): takes tickets, `TimeText`, colors and the usage page URL plus an `onOpen` closure; renders `labelText("solid:gift")` per shown ticket and `Text("+N")` in `colors.secondary`, `.help` per element, a plain button style that calls `NSWorkspace.shared.open` then `onOpen()` (closes the panel); one accessibility element with label and action.
15. **`DropdownView`**: `SubscriptionSection` gets `@Environment(\.dropdownColors)` and the glyphs after `Text(account.displayName)`; `CodexPlanSection` the same in its header; the name gets `.lineLimit(1)` and lower layout priority than glyphs and headline; `DropdownView` passes `{ panel?.close() }` down.
16. **`App.swift`**: `resetTicketTracker` next to `credentialTracker`, fed in `apply` inside `#if !AGENTTACHO_DEMO`.
17. **`NotificationPresenter`**: `handle(_ events: [ResetTicketExpiryEvent])` posting `.deliver` (queue while authorization pending, log without bundle), logging `.suppressed`.
18. **`SettingsView`**: second toggle in the Notifications section.

### DemoMode

19. `ScenarioTicket`, `ClaudeWindows.tickets`; `DemoSubscriptionSource` fills `resetTickets`; `Resources/demo/default.json` gives `acc-max` two tickets; coverage fields and test `defaultScenarioShowsResetTickets`.

### Docs and website

20. README "Security and privacy" (research R10).
21. Site pull request: Privacy.astro mirror, card-candidates entry; recapture after maintainer approval.

### Global constraints

- No em or en dash characters; doc comments cite `spec 033 FR-xxx`.
- No service identifier (`id`, grant ids, `usable_now`) is decoded.
- Every user-visible and logged string is built in UsageCore.

## Project Structure

### Documentation (this feature)

```text
specs/033-free-reset-tickets/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/external-sources.md
├── contracts/texts.md
├── checklists/requirements.md
└── tasks.md            # from /speckit-tasks
```

### Source Code (repository root)

```text
Sources/UsageCore/
├── AppLinks.swift                               # usage page links
├── Config/Configuration.swift                   # notifyFreeResetExpiry
├── Dropdown/TimeText.swift                      # expiry(_:), absolute(_:)
├── Dropdown/ResetTicketText.swift               # new
├── Snapshot/UsageSnapshot.swift                 # SubscriptionEntry.resetTickets
├── Subscription/ResetTickets.swift              # new: model, decoders, list helpers
├── Subscription/UsageEndpointClient.swift       # flag, cedar_ember decoding
├── Subscription/SubscriptionSource.swift        # TicketFlag, repeat, lastTickets
├── Subscription/CodexUsageClient.swift          # fetchResetCredits
├── Subscription/CodexLimits.swift               # CodexLimitsEntry.resetTickets
├── Subscription/CodexLimitsSource.swift         # credit request after success
└── Notifications/
    ├── ResetTicketExpiry.swift                  # new
    ├── ResetTicketExpiryTracker.swift           # new
    ├── ResetTicketNoticeStore.swift             # new
    └── PendingNotificationQueue.swift           # expiry list

Sources/DemoMode/ (Scenario.swift, DemoSources.swift, ScenarioCoverage.swift)
Resources/demo/default.json

Sources/AgentTacho/
├── ResetTicketGlyphs.swift                      # new
├── DropdownView.swift
├── App.swift
├── NotificationPresenter.swift
└── SettingsView.swift

Tests/UsageCoreTests/ (ResetTicketsTests, ResetTicketTextTests, ResetTicketExpiryTrackerTests, ResetTicketNoticeStoreTests, UsageEndpointClientTests, SubscriptionSourceTests, CodexUsageClientTests, CodexLimitsSourceTests, ConfigurationTests, PendingNotificationQueueTests, LastGoodStoreTests)
Tests/DemoModeTests/DefaultScenarioTests.swift

README.md
```

**Structure Decision**: Existing layout; new logic next to the Codex and credential notification code it mirrors.

## Complexity Tracking

No gate violations.
