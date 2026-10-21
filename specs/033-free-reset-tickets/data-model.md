# Data Model: Free Reset Tickets

## ResetTicket (UsageCore, value type)

| Field | Type | Rule |
|---|---|---|
| `expiresAt` | `Date?` | nil means no expiry (spec FR-002) |

No identifier from the services is kept (FR-006). Equality is by `expiresAt`.

## ResetTicketRead (UsageCore, enum)

| Case | Meaning | Effect on the account's tickets (FR-003) |
|---|---|---|
| `.tickets([ResetTicket])` | successful read, possibly empty | replaces them |
| `.temporaryFailure(kind)` | transport, timeout, HTTP error, skipped Codex request | keeps the last successful read, minus expired |
| `.clearingFailure(kind)` | malformed or implausible body, dropped flag | clears them |

`kind` is a short log label (`transport`, `http-<code>`, `unexpected-location`, `undecodable`, `malformed`, `implausible`, `flag-dropped-http-<code>`, `flag-suspended-http-<code>`, `skipped`).

## ResetTicketList (UsageCore, helpers on `[ResetTicket]`)

- `usable(at now: Date) -> [ResetTicket]`: drops tickets with `expiresAt <= now` (FR-012).
- `sortedForDisplay`: ascending `expiresAt`, nil last (FR-008).
- `glyphs(at:)`: `(shown: [ResetTicket], overflow: [ResetTicket])`, `shown.count <= 3`.
- `groupedByExpiry(at:)`: `[Date: Int]` for usable tickets with expiry (FR-014).

## TicketFlag (SubscriptionSource, per Claude account, in memory)

```text
on --(flagged request 4xx except 401/429, plain repeat succeeds)--> offForRun   [clears tickets, logs once]
on --(flagged request 4xx except 401/429, plain repeat fails)-----> suspended
suspended --(plain request succeeds; not a ticket read)-----------> on          [flag sent on the next refresh]
offForRun: terminal until relaunch
```

Removed accounts drop their state.

## Entries (snapshot, transient)

- `SubscriptionEntry.resetTickets: [ResetTicket]` (Claude).
- `CodexLimitsEntry.resetTickets: [ResetTicket]` (Codex; always empty with live limits off).
- Both copied by `reused(now:)`, `endingGrace`, `markedStale`; never written by `LastGoodStore`.

## ResetTicketNoticeKey (UsageCore)

| Field | Type |
|---|---|
| `accountId` | `String` (configuration id, stable across renames) |
| `expiresAt` | `Date` (whole seconds) |
| `step` | `ResetTicketExpiryStep` (`.threeDays`, `.oneDay`) |

Stored by `ResetTicketNoticeStore` as `"<accountId>|<epoch>|<step>"` strings under the defaults key `freeResetNotices`.

## ResetTicketExpiryTracker (UsageCore, struct)

Input per non-preliminary snapshot: Claude and Codex entries, configuration (`notifyFreeResetExpiry`, account names and ids), `now`.

For each account and each expiry time `t` with `count` usable tickets:

| Condition at this refresh | Key not yet recorded | Event |
|---|---|---|
| `t - now < 24 h` | `(id, t, .oneDay)` | `.deliver` or `.suppressed` for `.oneDay`; also records `.threeDays` |
| `24 h <= t - now < 3 d` | `(id, t, .threeDays)` | `.deliver` or `.suppressed` for `.threeDays` |
| `t - now >= 3 d` | | nothing |

`.suppressed` when the switch is off (recorded as delivered, FR-017). After each observation: drop keys with `t <= now` and keys of accounts no longer configured; save when changed.

## ResetTicketExpiryAlert (UsageCore, value type)

`accountId`, `accountName`, `step`, `expiresAt`, `count`; computed `identifier` (`free-reset-<accountId>-<epoch>-<step>`), `title`, `body`, `logMessage` per `contracts/texts.md`.

## Configuration

`notifyFreeResetExpiry: Bool`, default `true`, decoded `?? true`, always encoded (as `notifySignInProblems`), normalized to `true` in `dataRelevant()`.

## Demo scenario

`ClaudeWindows.tickets: [ScenarioTicket]?`, `ScenarioTicket.expiresIn: ScenarioDuration?`. Coverage report field `resetTicketsWithExpiry: Bool`, `resetTicketsWithoutExpiry: Bool`.
