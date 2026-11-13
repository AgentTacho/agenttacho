# Data Model: Claude Code Auto-mode Classifier Usage

## UsageRecord (changed)

| Field | Type | Notes |
|---|---|---|
| `sessionKey` | `String?` | NEW. Claude session id, or the session file's canonical path when the record has none (clarification Q1). Nil for other harnesses and for classifier records |
| `cwd` | `String?` | NEW. Raw working directory of the record |
| `origin` | `RecordOrigin` | NEW. `.session` (default) or `.classifier` (FR-010). Not read by totals, pricing, limits, groups or UI |

All three default in both initializers; `UsageRecord(raw:...)` copies `cwd` from the raw record. `LogIndex` passes `sessionKey`.

## ClassifierRow

One usage-bearing line of a decision log (FR-004, FR-008, FR-009).

| Field | Type | Notes |
|---|---|---|
| `id` | `String` | `<canonical log path>#<line start offset>` (FR-008a) |
| `timestamp` | `Date` | From `ts` epoch milliseconds |
| `model` | `String` | `classifierModel` without a trailing `[...]` |
| `inputTokens` | `Int` | `inputTokens`, absent = 0 |
| `cacheReadTokens` | `Int` | `cacheReadInputTokens`, absent = 0 |
| `cacheWrite5mTokens` | `Int` | `cacheCreationInputTokens`, absent = 0 |
| `outputTokens` | `Int` | `outputTokens`, absent = 0 |

Validation: `ts` numeric; model non-empty after normalization; each present counter a non-negative integer; at least one counter above zero. A valid row with all counters zero or absent is "without usage"; anything else invalid is "malformed".

## ClassifierLineResult

`.row(ClassifierRow)` | `.withoutUsage` | `.malformed`. Rows before the window start are dropped by the index, not counted as malformed.

## DecisionLogEntry (per decision log file)

| Field | Type | Notes |
|---|---|---|
| `canonicalPath` | `String` | Key |
| `directory` | `String` | Canonical working directory |
| `size` | `Int` | Size at last read |
| `modificationDate` | `Date` | At last read |
| `parsedOffset` | `Int` | End of the last complete line read |
| `rows` | `[ClassifierRow]` | In-window rows, in file order |

Lifecycle: created on first `.found`; grown files read from `parsedOffset`; shorter than `parsedOffset` → rows cleared and read from 0; `.absent`, `.notRegular`, `.tooLarge`, modification date before window start, or `directory` no longer among the report's canonical values → removed; `.timedOut`/`.busy` → kept as is. Rows before the window start are pruned each refresh. When `window.start` moves earlier than the previous update's, all entries are dropped (as in `LogIndex`).

## ProbeResult and ProbeReport (per refresh)

`ProbeResult`: `.found(path, size, modificationDate)` | `.absent` | `.notRegular` | `.tooLarge(size)` | `.timedOut` | `.busy`.

`ProbeReport`: `results: [rawCwd: ProbeResult]`, `canonical: [rawCwd: canonicalDirectory]` (from this check, or for `.timedOut`/`.busy` the last finished check of that raw directory; absent when no check of it ever finished), `newlyTimedOut: [rawCwd]` (to log once until a check of it finishes again).

## SessionSpan (rebuilt every refresh)

| Field | Type | Notes |
|---|---|---|
| `directory` | `String` | Canonical cwd |
| `sessionKey` | `String` | |
| `start` | `Date` | Earliest in-window record |
| `end` | `Date` | Latest in-window record + 300 s (FR-005) |
| `accounts` | `Set<String?>` | Account ids of the span's records; nil = Unassigned |

Covering and decision (FR-006): union of `accounts` of all spans in the row's directory with `start <= t <= end`; exactly one element and it is non-nil → that account, else unassigned.

## ClassifierIndexStats (per update of ClassifierLogIndex)

`checked`, `logsRead`, `timedOut`, `busy`, `skipped` (not regular or too large, with the paths of too-large files), `withoutUsage`, `malformed`, `bytesRead`.

## ClassifierAttributionResult (per refresh)

`records: [UsageRecord]` (origin `.classifier`), `assigned: Int`, `unassigned: Int`, `doubleRecordingSessions: Set<String>` (session keys with a session record whose input, output, cache read and `cacheWrite5m + cacheWrite1h` equal a covered row's four counters). Rows counted = `records.count`.
