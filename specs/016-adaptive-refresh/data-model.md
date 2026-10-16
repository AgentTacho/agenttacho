# Data Model: Adaptive Refresh

All types live in `UsageCore` unless noted. None is persisted except the configuration key.

## Configuration (changed)

| Field | Type | Default | Notes |
|---|---|---|---|
| `adaptiveRefresh` | `Bool` | `true` | JSON key `adaptiveRefresh`. Missing: `true`. Non-boolean: `true` plus a load note (FR-001, research R10). Not data-relevant (no refresh on change). |

## PacedEndpoint (new)

`enum PacedEndpoint: String { case claude, codex }`

- `harnesses`: `.claude` takes `[.claudeCode, .openCode]`, `.codex` takes `[.codex, .openCode]` (FR-004).
- `isInUse(configuration)`: `.claude` when `configuration.subscriptionAccounts` (the Claude ones) is not empty, `.codex` when any `configuration.codexSubscriptionAccounts` has `liveLimits` on (FR-003a).

## SystemConditions (new)

| Field | Type | Meaning |
|---|---|---|
| `idle` | `Bool` | No input for 600 s, screen locked, or displays asleep (FR-008) |
| `lowPowerMode` | `Bool` | Low Power Mode is on (FR-009) |
| `thermalPressure` | `Bool` | Thermal state is serious or critical (FR-009) |

The app reads them (research R8) and passes them to the coordinator. The default is all `false`.

## TimerReason / PaceReason (new)

`enum PaceReason: Int, Comparable { case idle, lowPowerMode, highTemperature, noAgentActivity }`, ranked in that order through the raw value (FR-016). `timerReason` is nil while disabled or when no condition holds.

## AdaptivePace (new)

| Field | Type | Notes |
|---|---|---|
| `enabled` | `Bool` | From `adaptiveRefresh` |
| `base` | `TimeInterval` | `refreshIntervalSeconds` |
| `conditions` | `SystemConditions` | Last values from the app |
| `endpoints` | `[PacedEndpoint: EndpointPace]` | One per endpoint |
| `inUse` | `Set<PacedEndpoint>` | Updated from the configuration each refresh |
| `lastRefreshAt` | `Date?` | Start of the last completed refresh of any trigger (FR-003a) |
| `lastScheduledAt` | `Date?` | Start of the last completed `.scheduled` refresh |

Constants: `cap = 1800 s`, `tickTolerance = 5 s`, `openSpacing = 60 s`.

`EndpointPace`: `lastCallAt: Date?` (last call that reached the service), `interval: TimeInterval` (starts at `base`).

Derived values, all pure functions of the fields plus `now`:

- `bound = max(base, cap)`, so a base above 30 minutes is never stretched (FR-003).
- `timerInterval`:
  - disabled: `base`;
  - idle: `max(base, cap)`;
  - Low Power Mode or high temperature: `min(2 * base, bound)`, never below `base`;
  - none: `base`.
  - With several conditions the largest wins (FR-008 to FR-010). The reason is the highest-ranked condition that holds.
- `dueAt(endpoint)`: `lastCallAt + max(interval, timerInterval)` (FR-010a); `nil` when `lastCallAt` is `nil` (due now).
- `shouldCall(endpoint, newestActivity, now)` for a scheduled refresh: true when disabled, or when there is no last call, or when `now >= dueAt - tickTolerance`, or when there is activity (`newestActivity > lastCallAt`) and `now - lastCallAt >= timerInterval - tickTolerance` (FR-006).
- `nextScheduledRefresh(now)`: `max(now, min(lastRefreshAt + timerInterval, d))`, where `d` is the minimum `dueAt` over the endpoints in use that is later than `lastScheduledAt + tickTolerance` (FR-010a); with `lastScheduledAt` nil every due time counts, so a past due time gives at most one immediate tick. A due time that a scheduled refresh already handled (it counted as due within the tolerance) is ignored, so an endpoint whose last call cannot move (transport failures, rate-limit block, no request, never called) never makes the timer spin, while a reprice or spaced refresh just before a due time does not hide it. When `lastRefreshAt` is nil (no refresh completed yet, the launch refresh still running) it returns `now + timerInterval`, so the adaptive loop never adds a request at launch. When disabled, `lastRefreshAt + base`.
- `shouldRefreshOnOpen(now)`: false when disabled. Otherwise true when some endpoint in use has no last call or a last call at least 60 s old, or, with no endpoint in use, when `lastRefreshAt` is nil or at least 60 s old (FR-012). The coordinator additionally returns false while a refresh runs.
- **Clock moved backwards**: `mutating func normalize(now:)`, called by the coordinator at the start of every refresh and before every timer and status query, stores `now` into any `lastCallAt`, `lastRefreshAt` or `lastScheduledAt` later than `now` (as `EndpointPolicy` drops a block when the clock moved back). A backwards clock therefore delays a call by at most `max(interval, timerInterval)`.
- `status(now)`: a `RefreshPaceStatus`, or nil when every pace equals the base (FR-016). Its time is never in the past: an endpoint time is `max(dueAt, nextScheduledRefresh(now))`.

Mutations:

- `recordCall(endpoint, at, scheduled, newestActivity) -> IntervalChange?`: only called when the call reached the service and the result was not reused. `IntervalChange` is `struct { endpoint: PacedEndpoint; from: TimeInterval; to: TimeInterval; reason: PaceReason? }` (`reason` is `.noAgentActivity` when it grew, nil when it returned to the base).
  - If `newestActivity > previous lastCallAt` (or there was no previous call), the interval returns to `base`.
  - Else, if `scheduled`, the interval becomes `min(interval * 2, bound)`.
  - Else it stays.
  - Then `lastCallAt = at`. Returns the change, for the log (FR-005, FR-013).
- `update(configuration:)`: sets `enabled`, `base` and `inUse`. A changed base or toggle resets every interval to `base` (edge case "Toggle switched while slowed").
- `update(conditions:)`: returns whether the timer interval or its reason changed (for the log and for re-arming).
- `refreshCompleted(at:scheduled:)`: sets `lastRefreshAt`, and `lastScheduledAt` when `scheduled`.

## RefreshPaceStatus (new)

| Field | Type |
|---|---|
| `reason` | `PaceReason` |
| `nextAt` | `Date` |
| `kind` | `.planLimits` (an endpoint is in use) or `.refresh` (no endpoint in use) |

`text(now:calendar:)` gives the line from research R11. Time format: time only for today, otherwise abbreviated weekday plus time.

## RefreshTrigger (changed)

New cases `.dropdownOpen` and `.idleReturn`, rank 1. `EndpointPolicy` spaces them like `.wake` (60 s). `CodexLimitsSource` treats them like `.wake`.

## RefreshContext (changed)

New field `codexPaceDue: Bool = true`. It is only read by `CodexLimitsSource.decide` for `.scheduled`.

## SubscriptionEntry, CodexLimitsEntry (changed)

New transient field `reachedService: Bool = false`. It is true when this refresh sent a request for the entry and the answer was a success or a failure whose `FailureCategory` is not `.transport`. It is not written to `last-good.json` and is reset on reuse.

## State transitions (endpoint interval, base 5 min, no activity)

```text
launch call (unscheduled)      -> interval 5 (unchanged)
scheduled call, quiet          -> 10
scheduled call, quiet          -> 20
scheduled call, quiet          -> 30 (cap)
any call that saw activity     -> 5
dropdown-open call, quiet      -> unchanged
transport failure / no request -> unchanged, lastCallAt unchanged (activity carries over)
```
