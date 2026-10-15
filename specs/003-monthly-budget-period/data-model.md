# Data Model: Monthly Budget Period

Changes relative to `specs/001-agentmeter/data-model.md`. Unchanged entities are not repeated.

## BudgetPeriod (new)

| Value | Raw value | Window | `adjective` | `perUnit` | `budgetLabel` | Tracker window kind |
|-------|-----------|--------|-------------|-----------|---------------|---------------------|
| weekly | `"weekly"` | Aligned to the designated subscription's 7-day reset, else week fallback (spec 001 FR-021, FR-022) | weekly | per week | Weekly budget | `.weekly` |
| monthly | `"monthly"` | `[1st 00:00 local, next 1st 00:00 local)` | monthly | per month | Monthly budget | `.monthly` |

Default: `weekly`.

## BudgetGroup (changed)

| Field | Type | Change | Rules |
|-------|------|--------|-------|
| id, name, label, icon, shownInBar, thresholds | unchanged | | spec 001 |
| period | BudgetPeriod | **new** | Absent in JSON → weekly. Unknown value → decode error (FR-002, FR-004a). |
| budgetUSD | Decimal | **replaces** `weeklyBudgetUSD` | Must be > 0 (FR-001, FR-019). Decoded from `budgetUSD`, else from legacy `weeklyBudgetUSD` only when period is weekly; otherwise decode error (FR-003, FR-004a). Always encoded as `budgetUSD`. |

Validation message (`ConfigurationError.kind == .budget`): `"<Budget label> of group \"<name>\" must be greater than 0."`, for example `Monthly budget of group "Vertex" must be greater than 0.`

## GroupEntry (snapshot, changed)

| Field | Type | Change |
|-------|------|--------|
| spentUSD, budgetUSD, percent, incomplete, breakdown, members, stale | unchanged | `budgetUSD` now copies `group.budgetUSD` |
| period | BudgetPeriod | **new**, copied from the group |
| window | DateInterval | **new**, the group's own window |
| resetAt | Date | unchanged meaning, equals `window.end` |

## TokenAccountEntry (snapshot, behaviour change)

The breakdown of a token-based account is computed over the window of the account's group, not always the weekly window (FR-008, FR-013).

## UsageSnapshot (behaviour clarified)

`window` and `windowSource` keep describing the **weekly** window. They drive the Unassigned entry and subscription-account breakdowns (FR-009).

## RefreshContext (behaviour change)

`window` is the **collection window**: from the earliest start of all windows needed in this refresh (weekly window, plus the monthly window when at least one monthly group exists) to the latest end. Record sources return all records with `timestamp >= window.start`, as before.

## WindowKind (changed)

New case `.monthly` with `displayName` "monthly". Group threshold state is keyed by `(groupId, period.windowKind)`.

## State transitions: group threshold state

| Event | Effect |
|-------|--------|
| First refresh observing `(group, kind)` | Baseline recorded, no notification (spec 001 FR-028) |
| Month rollover (monthly) or new 7-day reset (weekly) | `windowEnd` changes → state reset, next observation is a baseline (FR-016, spec 001 FR-029) |
| Time zone change moving the month | `windowEnd` changes → reset (FR-016) |
| Period switch | Old key no longer live → dropped; new key starts with a baseline (FR-017) |
| Group removed | Key dropped (unchanged) |

## Windows per consumer

| Consumer | Window |
|----------|--------|
| Weekly group, its member accounts | Weekly window |
| Monthly group, its member accounts | Monthly window |
| Unassigned entry | Weekly window |
| Subscription account breakdown | Weekly window |
| Subscription utilization | Provider windows (unchanged) |
