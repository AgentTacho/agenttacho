# Data Model: Faster Session Scan

Entities of this feature, as structures in `UsageCore`. Nothing is persisted by the app; the bench writes files only where the maintainer asks.

## ProcessResources.Snapshot (new, `UsageCore/Diagnostics/ProcessResources.swift`)

One reading of the process's resource counters.

| Field | Type | Source |
|---|---|---|
| `wall` | `ContinuousClock.Instant` | clock |
| `userCPU`, `systemCPU` | `Duration` | `getrusage(RUSAGE_SELF)` |
| `maxRSS` | `Int` bytes | `ru_maxrss` |
| `maxPhysicalFootprint` | `Int` bytes | `ri_lifetime_max_phys_footprint` |
| `diskBytesRead` | `Int` | `ri_diskio_bytesread` |

`ProcessResources.snapshot() -> Snapshot` takes one reading. `Snapshot.delta(since:) -> ProcessResources.Delta` with `wall: Duration`, `userCPU`, `systemCPU`, `averageCPU: Double` (CPU over wall), `diskBytesRead` (difference), and the two peaks (the later snapshot's values). `ProcessResources.cpuSeconds()` is the convenience the sources use for FR-007.

## ScanBenchOptions (new, `UsageCore/Bench/ScanBench.swift`)

| Field | Type | Meaning |
|---|---|---|
| `reader` | `.claudeCode` or `.codex` | which source runs |
| `directory` | `String?` | session directory override; nil runs over the configuration's directories |
| `configurationFile` | `URL` | default `Paths().configFileURL` |
| `windowStart` | `Date?` | nil derives the window as the app does |
| `until` | `Date?` | the digest keeps only records stamped before it |
| `workers` | `Int?` | `ScanWorkers(count:)` override (phase D on) |
| `digestPath` | `URL?` | write the digest here |
| `useImportedPrices` | `Bool` | `true` for `run` (the app's imported price file, as the app reads it); `false` for `digest`, so the fixture digests hold built-in prices plus the configuration's overrides only (research R8) |
| `commit` | `String` | from the environment (`SCAN_BENCH_COMMIT`), `unknown` when unset |

Validation: the directory must exist, be readable and hold `projects` (Claude Code) or `sessions` (Codex); the configuration file must load without error; `digestPath` must not lie under a configured session directory, `~/.claude` or `~/.codex`.

Interfaces (`UsageCore/Bench/ScanBench.swift`), called by `Sources/ScanBench/main.swift` and `ScanBenchTests`:

- `ScanBench.run(_ options: ScanBenchOptions) async throws -> ScanBenchReport`: builds the source, runs both `collect` calls, writes the digest when `digestPath` is set.
- `ScanBench.compare(_ a: URL, _ b: URL) throws -> RecordsDigest.Comparison`: loads and compares two digest files.
- `ScanBenchError.invalid(String)`: every validation failure and unreadable file, with one line of text naming the path with `~`. `main.swift` maps it to exit code 2; a `Comparison` that is not identical maps to exit code 1.

## ScanBenchReport (new)

| Field | Type |
|---|---|
| `commit`, `reader`, `directory` (with `~`), `configurationFile` (with `~`), `windowStart` | text |
| `filesSeen`, `filesRead`, `bytesRead`, `linesVisited`, `records` | `Int` |
| `resources` | `ProcessResources.Delta` |
| `workers` | `Int` (the `ScanWorkers.count` in effect) |
| `secondRefresh` | wall `Duration`, CPU seconds `Double`, `filesRead: Int` of the second `collect` (SC-005) |

`text` renders the report (contracts/bench-cli.md). It never includes a session line.

## RecordsDigest (new, `UsageCore/Bench/RecordsDigest.swift`)

A sorted list of `Entry` plus a header.

| Entry field | Source |
|---|---|
| `harness` | `UsageRecord.harness` |
| `key` | `msg:<messageId>` or `req:<requestId>` |
| `timestamp` | `UsageRecord.timestamp` rounded to the nearest millisecond, `Z` (research R5) |
| `model`, `canonicalModel` | `UsageRecord.model`, `UsageRecord.canonicalModel` |
| `input`, `output`, `cacheWrite5m`, `cacheWrite1h`, `cacheRead`, `reasoning` | token counts |
| `project` | `UsageRecord.project?.rootPath` or empty (derived from the record's working directory) |
| `accountId` | `UsageRecord.accountId` or empty |
| `cost` | `costUSD` as decimal text or empty |

The session id appears only through the key: Codex keys are `codex:<session id>:<running total>`; the app keeps no Claude Code session id per record (research R9).

Header: `digest 1`, `config <path with ~>`, `window-start <ISO>`, `directory <path with ~>`. Ordering: harness, key, timestamp, model.

`Comparison`: `identical: Bool` (record lines only), `onlyInA: [String]`, `onlyInB: [String]` (first 20 each), `countA`, `countB`, `headerNotes: [String]` (header lines that differ; informational).

## SessionLineKind (new, `UsageCore/Logs/SessionLineClassifier.swift`)

`enum SessionLineKind { case assistant, shape, undecided, other }`. `SessionLineClassifier.classify(_ line: UnsafeRawBufferPointer) -> SessionLineKind` reads the top-level `type` member with a forward head scan (256 bytes) and a backward tail scan (4,096 bytes), tracking string state and nesting depth, and falls back to today's whole-line candidate markers: a hit is `.undecided`, which `LogIndex` handles as today (parse, then detect when no record), and no hit is `.other` (research R4). `headBudget` and `tailBudget` are static constants. `SessionLineReader.forEachLine(in:body:) -> consumedBytes` visits complete lines (research R3).

## ScanWorkers (new, `UsageCore/Logs/ScanWorkers.swift`)

| Field | Default |
|---|---|
| `count` | `max(1, min(3, activeProcessorCount / 2))`; an explicit value is clamped to `1...activeProcessorCount` |
| `qos` | `.utility` |
| `beforeJob` | `nil` (test hook, called on the worker before each job) |

`offload(_:) async -> T` runs work on the global queue of `qos` and suspends the caller; `forEach(jobs:weight:body:)` runs the job indices `0..<jobs` largest weight first on at most `count` threads and returns when all are done, at once for zero jobs (research R7).

## LogIndexStats (changed)

Gains `linesVisited: Int` (non-empty complete lines handed to the classifier in this update, as today's line split counts them). `LogIndex.update(...)` stays synchronous; `LogIndex.init` gains `workers: ScanWorkers = .default`. `ReadResult.parsed` keeps `(record, rawLine: Data, profile)` for candidate lines only.

## Source scan state (changed, `SessionLogSource` and `CodexSessionSource`)

| Field | Meaning |
|---|---|
| `scanning: Bool` | true while a scan is offloaded; a `collect` that starts meanwhile waits until it ends (research R7) |
| `scanWaiters` | the continuations of the `collect` calls waiting for the scan, resumed in order when `scanning` turns false; each resumed call checks `scanning` again before it runs, so one scan runs at a time |
| `resetPending: Bool` | a `resetForEarlierWindow()` arrived during a scan; applied at the end of `collect`, after the records, stats and log line are taken |
| `lastScanFigures` | files seen, files read, bytes read, lines visited of the last `collect`, for the bench |

Initializers gain `workers: ScanWorkers = .default` and the bench seams `scanTargets:` / `homes:` (contracts/bench-cli.md).

## Codex typed lines (changed, `UsageCore/Logs/CodexSessionParser.swift`)

| Type | Fields (all optional, lenient) |
|---|---|
| `CodexLine` | `timestamp: String?`, `payload: CodexPayload?` |
| `CodexPayload` | `type`, `id`, `cwd`, `model`, the parent-session fields `parent(of:)` reads today, `info: CodexTokenInfo?`, `rate_limits: CodexRateLimits?` |
| `CodexTokenInfo` | `total_token_usage: CodexTokenUsage?` |
| `CodexTokenUsage` | `input_tokens`, `cached_input_tokens`, `cache_write_input_tokens`, `output_tokens`, `reasoning_output_tokens`, `total_tokens` as `Double?` |
| `CodexRateLimits` | `limit_id`, `plan_type`, `primary`, `secondary`, `rate_limit_reached_type` present and non-null |
| `CodexLimitWindowFields` | `window_minutes`, `used_percent`, `resets_at` as `Double?` |

`Totals.init(_ usage: CodexTokenUsage)` applies the finite, positive and `maxTokenValue` rules of today's `init(_ usage: [String: Any])`.

## ISO8601Timestamp (new, `UsageCore/Logs/Timestamp.swift`)

`static func parse(_ text: String) -> Date?` (research R5). Replaces `SessionRecordParser.parseDate` and the Codex `ISO8601Parser`.

## Benchmark record row (`specs/039-faster-session-scan/BENCHMARK.md`)

| Column | Example |
|---|---|
| date | 2026-10-28 |
| commit | `c4d556a` |
| condition | warm, cold |
| reader | claude, codex |
| directory | `~/.claude` |
| config, window start | `~/.config/agenttacho/config.json`, `2026-10-01T00:00:00Z` |
| files seen / read, bytes read, lines, records | counts |
| wall s, cpu user s, cpu sys s, avg cpu % | figures |
| peak footprint MB, disk MB read | figures |
| workers | 3 |
| note | baseline, after R3, ... |

## Fixture digests (`Tests/UsageCoreTests/Fixtures/digests/`)

`claude.digest` with `claude-config.json`; `codex.digest` with `codex-config.json`. Generated by `make bench-digests` from the unchanged code with window start `2026-10-01T00:00:00Z`; checked by `ScanBenchTests` (FR-008). The fixture configurations hold invented account names only.
