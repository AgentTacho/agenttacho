# Data Model: Burn Rate Escalation

All types live in `UsageCore` and are in memory only. Nothing is encoded or written (FR-003, FR-013).

## BurnWindowKey (enum, Hashable, Sendable)

Identifies one window or budget across refreshes (spec Key Entities, research R2).

| Case | Payload | Source |
|------|---------|--------|
| `.claude(_, _)` | account id, `ClaudeWindow` (`.fiveHour`, `.sevenDay`, `.model(name)`) | `UsageSnapshot.subscriptions` |
| `.codex(_, _)` | account id, `CodexLimitWindow.name` | `UsageSnapshot.codexLimits` |
| `.group(_)` | group id | `UsageSnapshot.groups` |
| `.accountBudget(_)` | account id with its own budget | `UsageSnapshot.accountBudgets` |

A group and an account may share an id (spec 008), so the two budget owners are separate cases.

## RateObservation (struct, Equatable, Sendable)

| Field | Type | Rule |
|-------|------|------|
| `observedAt` | `Date` | spec 011 FR-002 observation time |
| `usedPercent` | `Double` | unrounded |
| `resetsAt` | `Date` | reset time, unchanged when within 60 s; budget window end |

## ObservationLog (struct, Equatable, Sendable)

| Field | Type | Notes |
|-------|------|-------|
| `entries` | `[BurnWindowKey: [RateObservation]]` | oldest first, at most 60 minutes old |
| `budgetFingerprints` | `[BurnWindowKey: BudgetFingerprint]` | private `BudgetFingerprint` (`budgetUSD: Decimal`, `period: BudgetPeriod`, sorted `members: [String]`) per budget key |

Operations:
- `updated(with: UsageSnapshot, budgetPricesChanged: Bool) -> ObservationLog`: records every window with a pace, applies the discard rules (research R4), removes keys without a pace, prunes by `generatedAt - lookback`.
- `recentRate(for: BurnWindowKey, now: Date) -> RecentRate?`: research R6.

State transitions per key: empty → one observation → several (span grows) → discarded (reset change, lower percent, budget fingerprint or price change) → one observation; any key → removed when its window has no pace.

## RecentRate (struct, Equatable, Sendable)

| Field | Type |
|-------|------|
| `perHour` | `Double` (percentage points per hour, > 0) |
| `observedAt` | `Date` (newest observation) |
| `usedPercent` | `Double` (newest observation) |

## BurnRate (struct, Equatable, Sendable)

| Field | Type | Rule |
|-------|------|------|
| `sustainablePerHour` | `Double` | FR-001 |
| `averagePerHour` | `Double?` | FR-002; nil at zero or negative elapsed time |
| `recentPerHour` | `Double?` | FR-004 |
| `fastRunOut` | `Date?` | FR-005 to FR-007; set iff the entry burns fast |
| `burnsFast` | `Bool` (computed) | `fastRunOut != nil` |

Constants: `factor = 2`, `lookback = 3600 s`, `minimumSpan = 900 s`, `minimumChange = 2` points.

## Changes to existing types

- `UsageSnapshot.observations: ObservationLog` (default empty) and `UsageSnapshot.burnRate(for:) -> BurnRate?`.
- `BarItem.burnsFast: Bool` (default false); `accessibilitySuffix` covers the fast wording.
- `Pace.summary(runOutText:fastRunOut:)` with `fastRunOut` defaulting to nil.
