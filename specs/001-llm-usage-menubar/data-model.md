# Data Model: LLM Usage Menu Bar

All types live in the `UsageCore` library. Configuration types are `Codable` and define the on-disk JSON format. Snapshot types are value types produced by a refresh and consumed by the UI.

## Configuration (persisted)

### Configuration
| Field | Type | Rules |
|---|---|---|
| version | Int | Format version, 1 |
| refreshIntervalSeconds | Int | Default 300, minimum 60 (FR-024) |
| logDirectories | [String] | Extra Claude Code config directories; `~/.claude` is always included (FR-012) |
| weekFallback | WeekFallback | Default Monday 00:00 local (FR-022) |
| alignmentAccountId | String? | Id of the subscription account whose 7-day reset defines group windows; nil means first subscription account in order (FR-021, edge case) |
| startAtLogin | Bool | Default false (FR-035) |
| accounts | [Account] | Ordered; order defines bar order (FR-002) |
| groups | [BudgetGroup] | Ordered |
| priceOverrides | [PriceEntry] | User entries, take precedence over built-in (FR-015) |

Validation (on save and on load):
- Labels of accounts and groups are 1 to 3 characters and unique across both lists (FR-032).
- Every token-based account's `groupId` references an existing group; every group has at least one member (FR-019).
- Two subscription accounts never share a `credentialDirectory` (FR-011).
- `alignmentAccountId`, when set, references a subscription account.
- Thresholds are whole numbers greater than 0 (FR-027).
- `weeklyBudgetUSD` is greater than 0; `weekFallback.weekday` is 1 to 7 and `hour` is 0 to 23.
- Label uniqueness is an exact, case-sensitive comparison.
- A field of the wrong JSON type is a decode error and rejects the file like invalid JSON (FR-033).

### Account
| Field | Type | Rules |
|---|---|---|
| id | String | Stable UUID string |
| label | String | 1 to 3 characters |
| displayName | String | Free text |
| harness | Harness | `claudeCode` in this version; enum is open for later harnesses (FR-017) |
| kind | AccountKind | `.subscription(SubscriptionSettings)` or `.tokenBased(TokenBasedSettings)` |
| customMarker | String? | Substring matched against the raw assistant record (FR-013) |

Encoded as a flat JSON object with a `type` discriminator (`"subscription"` or `"tokenBased"`) so adding a new kind later does not change existing entries.

### SubscriptionSettings
| Field | Type | Rules |
|---|---|---|
| credentialDirectory | String | Claude Code config directory; default `~/.claude` |
| shownInBar | Bool | |
| thresholds | [Int] | Percent, applied to both windows independently (FR-027) |

### TokenBasedSettings
| Field | Type | Rules |
|---|---|---|
| groupId | String | Required (FR-019) |
| provider | Provider | `.vertex` in this version; selects the built-in detection rule |

### BudgetGroup
| Field | Type | Rules |
|---|---|---|
| id | String | |
| name | String | |
| label | String | 1 to 3 characters |
| weeklyBudgetUSD | Decimal | > 0 |
| shownInBar | Bool | |
| thresholds | [Int] | |

### WeekFallback
| Field | Type |
|---|---|
| weekday | Int (1 = Sunday ... 7 = Saturday, Calendar convention) |
| hour | Int (0 to 23) |

### PriceEntry
| Field | Type |
|---|---|
| model | String | Canonical model id (matching rule in research R5) |
| inputPerMTok | Decimal |
| outputPerMTok | Decimal |
| cacheWrite5mPerMTok | Decimal |
| cacheWrite1hPerMTok | Decimal |
| cacheReadPerMTok | Decimal |
| source | PriceSource | `builtIn` or `override` (not persisted for overrides) |

## Detection (built-in, not persisted)

### DetectionRule
Per provider: `requestIdPrefix` (`req_vrtx_` for Vertex). The subscription rule is `directRequestId`: the request id starts with `req_` and carries no provider infix (`req_011...` matches, `req_vrtx_...` and `req_bdrk_...` do not) and matches no token-based rule. A custom marker on an account replaces that account's built-in rule with a `rawContains` rule (the raw assistant record must contain the marker). Resolution per record: collect matching accounts; when at least one account matched through its custom marker, only marker matches are considered (a marker is more specific than a built-in rule, which is what separates two Vertex accounts); if exactly one remains, attribute; if several and all are subscription accounts, apply the credential-directory tie-breaker (the config directory whose `projects` tree contains the file, after symlink resolution); otherwise Unassigned.

## Session log ingestion (in memory)

### FileIndexEntry
| Field | Type |
|---|---|
| canonicalPath | String |
| size | Int |
| modificationDate | Date |
| parsedOffset | Int (bytes consumed up to the last complete line) |
| configDirectory | String (the scanned root that reached this file) |
| records | [UsageRecord] (only those with `timestamp >= window.start`; the upper bound is applied by the Aggregator so a window that moves forward loses nothing) |

Index rules: a file whose size drops below `parsedOffset` is re-read from offset 0; entries whose modification date is before `window.start` are dropped; `reset()` clears the whole index (used when the window start moves earlier, see tasks T040).

### UsageRecord
| Field | Type |
|---|---|
| messageId | String (dedupe key; `requestId` fallback) |
| timestamp | Date |
| model | String (raw id from the log) |
| canonicalModel | String |
| requestId | String |
| accountId | String? (nil means Unassigned) |
| inputTokens, outputTokens, cacheWrite5mTokens, cacheWrite1hTokens, cacheReadTokens | Int |
| costUSD | Decimal? (nil when unpriced) |

## Subscription fetch result

### SubscriptionStatus
| Field | Type |
|---|---|
| fiveHour | LimitWindow? |
| sevenDay | LimitWindow? |
| subscriptionType | String? |
| fetchedAt | Date |

### LimitWindow
| Field | Type |
|---|---|
| utilizationPercent | Double |
| resetsAt | Date |

## Snapshot (output of one refresh)

### UsageSnapshot
| Field | Type |
|---|---|
| generatedAt | Date |
| window | DateInterval (group window in effect) |
| windowSource | `.aligned(accountId)` or `.fallback` |
| subscriptions | [String: SubscriptionEntry] keyed by account id |
| groups | [String: GroupEntry] keyed by group id |
| tokenAccounts | [String: TokenAccountEntry] keyed by account id |
| unassigned | TokenAccountEntry |
| sourceErrors | [SourceError] |
| configError | String? |
| lastSuccessfulRefreshAt | Date? (generatedAt of the last refresh with no source error; carried over otherwise; shown as "Last refreshed", FR-007) |

### SourceError
sourceName: String (the `UsageSource.name`, `subscription` or `sessionLogs`), message: String (never contains a credential), at: Date.

### SubscriptionEntry
status: SubscriptionStatus?, state: `.ok`, `.stale(lastGoodAt, error)`, `.notSignedIn`, `.credentialsExpired`, breakdown: UsageBreakdown (tokens only).

### GroupEntry
spentUSD: Decimal, budgetUSD: Decimal, percent: Int (rounded, uncapped), incomplete: Bool (any unpriced records), resetAt: Date (equals `window.end`), breakdown: UsageBreakdown, members: [String], stale: Bool (true when carried over from the previous snapshot because the session log source failed, FR-007).

### TokenAccountEntry
breakdown: UsageBreakdown, incomplete: Bool, stale: Bool (same rule as GroupEntry).

## Refresh plumbing (in memory)

`RefreshContext` (configuration, window, now) is handed to every `UsageSource`; `SourceOutput` is either `.subscriptions([accountId: SubscriptionEntry])` or `.records([UsageRecord])`. Exact signatures are in tasks.md under "Shared Interfaces". The coordinator resolves the window at refresh start from the last known alignment reset, re-resolves after the sources finish, and re-runs the log source when the final window starts earlier than the one the sources saw.

### UsageBreakdown
perModel: [ModelUsage] (tokens per category, cost, priced flag, unpricedModels listed), perDay: [DayUsage] (one entry per calendar day of the window, zero-filled).

## Notifications (in memory)

### ThresholdState
Keyed by `(entityId, windowKind)` where windowKind is `fiveHour`, `sevenDay`, or `weekly`. Holds `windowEnd: Date` and `lastPercent: Int?`. A crossing is detected when `lastPercent < threshold <= currentPercent`. When `windowEnd` changes, the entry resets (FR-029). On the first refresh after launch `lastPercent` is nil, so no notification fires (FR-028 baseline). Entries whose `state` is not `.ok` (stale, not signed in, expired) and groups marked `stale` do not update `lastPercent` and produce no crossing. Entries whose id is no longer in the configuration are dropped.

### ThresholdCrossing
entityId: String, entityName: String (account `displayName` or group `name`), windowKind: WindowKind, threshold: Int, percent: Int. Thresholds are deduplicated before evaluation, so a value configured twice fires once.

## State transitions

- Subscription source: `notSignedIn` (no keychain item) → `credentialsExpired` (expiresAt past) → `ok` (200) → `stale` (any error after a prior `ok`, keeping the last status).
- Group window: `fallback` until the alignment account's first successful fetch, then `aligned`; stays `aligned` with the last fetched reset while the provider is unreachable (edge case).
