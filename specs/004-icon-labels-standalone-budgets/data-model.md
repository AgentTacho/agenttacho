# Data Model: Icon Labels and Standalone Budgets

These are changes relative to `specs/001-agentmeter/data-model.md` and `specs/003-monthly-budget-period/data-model.md`.

## IconDefaults (new)

| Entry | Default icon |
|-------|--------------|
| Subscription account | `brands:claude` |
| Token-based account, provider `vertex` | `brands:google` |
| Budget group | `solid:wallet` |

## Account (changed)

| Field | Change | Rules |
|-------|--------|-------|
| label | **removed** | Ignored when decoding, never encoded (FR-001, FR-006, FR-007) |
| icon | `String?` becomes **`String`** | Required. If missing, `null` or `""` in the file, the type default is used (FR-002, FR-006). Must exist in the catalog (FR-005). May repeat (FR-003). |
| displayName, harness, customMarker, kind | unchanged | |

## TokenBasedSettings (changed)

| Field | Type | Rules |
|-------|------|-------|
| provider | Provider | unchanged |
| membership | TokenMembership | **new**: exactly one of `group(id, shownInBar)` and `ownBudget(BudgetSettings)` (FR-008) |
| groupId | `String?` (computed) | `id` for `.group`, `nil` for `.ownBudget` |

## TokenMembership (new)

| Case | Payload | JSON |
|------|---------|------|
| group | `id: String`, `shownInBar: Bool` (default false, FR-016) | `"groupId": "...", "shownInBar": false` |
| ownBudget | `BudgetSettings` | `"budget": { ... }` |

## BudgetSettings (new, shared)

| Field | Type | Rules |
|-------|------|-------|
| period | BudgetPeriod | Absent means weekly. `null` or an unknown value is a decode error (spec 003 FR-004a) |
| budgetUSD | Decimal | Required, > 0 (validated, message names the period) |
| shownInBar | Bool | Defaults to `true` when absent |
| thresholds | [Int] | Defaults to `[]` when absent. Whole numbers > 0 |

## BudgetGroup (changed)

| Field | Change |
|-------|--------|
| label | **removed** |
| icon | becomes a required `String`. Default `solid:wallet` when missing, `null` or empty |
| budget | **new** computed get/set view over `period`, `budgetUSD`, `shownInBar`, `thresholds`. The JSON keys stay flat |

## BudgetOwner (new, derived)

`Configuration.budgetOwners` lists groups in groups-list order, then standalone token-based accounts in accounts-list order.

| Field | Type | Group | Standalone account |
|-------|------|-------|--------------------|
| id | String | group id | account id |
| name | String | group name | account displayName |
| icon | String | group icon | account icon |
| budget | BudgetSettings | group's | account's own |
| memberIds | [String] | member account ids | `[account id]` |
| kind | `.group` / `.account` | `.group` | `.account` |

## GroupEntry (snapshot, changed)

| Field | Change |
|-------|--------|
| memberSpendUSD | **new** `[String: Decimal]`: each member's spend in the owner's window |
| memberPercent(_ id) | **new** helper. Rounded and uncapped, relative to `budgetUSD` (FR-017, FR-018a) |

## UsageSnapshot (changed)

| Field | Change |
|-------|--------|
| accountBudgets | **new** `[String: GroupEntry]`, keyed by standalone account id (FR-010) |
| groups | unchanged (group entries only) |

## BarItem (new, UsageCore)

| Field | Type | Notes |
|-------|------|-------|
| id | String | entry id. For a member: `"<groupId>/<accountId>"` |
| icon | String | catalog reference |
| name | String | used for accessibility and logs (FR-004) |
| value | String | `"42%"`, `"--"`, or `"…"` |
| level | normal / warning / critical | from the owner's warning threshold (members: the group's, FR-018) |
| stale | Bool | members copy the group's stale flag (FR-018) |

## Threshold state (changed)

| Field | Change |
|-------|--------|
| memberIds | **new**. If it differs from the owner's current members, the state resets and the next observation is a baseline (FR-015) |

## Validation (changed)

| Rule | Status |
|------|--------|
| Label length, label uniqueness (spec 001 FR-032) | **removed** |
| Icon in catalog | kept (FR-005) |
| Token-based account has exactly one of group and own budget | **new** (decode error, FR-008) |
| `groupId` references an existing group | kept |
| Own budget: amount > 0, thresholds > 0 | **new**, same messages as groups (FR-009) |
| Group has at least one member | kept |
