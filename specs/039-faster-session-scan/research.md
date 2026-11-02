# Research: Faster Session Scan

Every decision below was checked against the code on the branch or measured on the maintainer's Mac (M4 Pro, 14 cores, macOS 26 SDK) on 2026-10-28. Figures are from the brainstorm's stage benchmark (one 352 MB project folder, 93,036 lines, 17,084 assistant lines, warm cache, single-threaded) unless a check is named.

## R1: Where the bench lives

**Decision**: A SwiftPM executable target `ScanBench` (product `scan-bench`, `Sources/ScanBench/main.swift`) that depends on `UsageCore` and holds only argument parsing and printing. The measurement, the report, the digest and the comparison live in `UsageCore/Bench/` so the test suite can call them (constitution II). Three Makefile targets wrap it (constitution IV): `make bench-scan`, `make bench-compare`, `make bench-digests`.

**Rationale**: The bench must run over the real corpus outside `swift test` and must run the same code path as a refresh, so it has to link `UsageCore` as the app does. `swift build -c release` builds the new target with the rest; `scripts/release/build-app.sh` only bundles the `AgentTacho` product, so the bench never ships in the app. A hidden flag of the app would need the bundle, LaunchServices and the menu bar; a test marked as a benchmark cannot take a directory argument from the maintainer.

**Alternatives considered**: hidden app flag (rejected: GUI process, no stdout); benchmark test (rejected: no arguments, runs inside `swift test` with its own overhead); shell script with `/usr/bin/time` (rejected: cannot read disk bytes or run the digest, and logic outside UsageCore is untestable).

## R2: Reading CPU, memory and disk figures

**Decision**: `UsageCore/Diagnostics/ProcessResources.swift` takes a snapshot from two calls (checked in a scratch program on 2026-10-28, both callable from Swift with `import Darwin`, no shim):

- `getrusage(RUSAGE_SELF)`: `ru_utime` and `ru_stime` (user and system CPU as timevals), `ru_maxrss` (peak resident set, in bytes on macOS).
- `proc_pid_rusage(getpid(), RUSAGE_INFO_V4, ...)` into `rusage_info_v4`: `ri_diskio_bytesread` (physical bytes read; a 49 MB file read raised it by 49,086,464) and `ri_lifetime_max_phys_footprint` (peak physical footprint, the figure Activity Monitor shows). `ri_user_time` is in Mach time units (timebase 125/3 on Apple silicon), so CPU comes from `getrusage` instead.
- Wall time from `ContinuousClock`.

The report states both peak figures (max RSS and max physical footprint); SC-003 is judged on the physical footprint. The diagnostic log line (FR-007) uses the `getrusage` CPU delta only: one call at the start and one at the end of `collect`, process-wide, as the clarification says.

**Rationale**: Both calls are in the platform's libraries (FR-019), cost microseconds, and give exactly the figures FR-002 asks for. `/usr/bin/time -l` remains a cross-check in the quickstart.

**Alternatives considered**: `task_info(MACH_TASK_BASIC_INFO)` (resident size only, no disk); `fs_usage` (needs root, per-call trace); `host_statistics` (machine-wide, not the process).

## R3: Visiting lines in place

**Decision**: `LogIndex.readCompleteLines` (one `Data` per line, `for i in complete.indices where complete[i] == 0x0A`, 932 ms per 352 MB) is replaced by `readUnreadBytes(path:from:)`, which returns the unread tail of the file as one `Data` plus the byte count up to the last newline, and a `SessionLineReader.forEachLine(in: UnsafeRawBufferPointer, body:)` that finds line ends with `memchr` (7 ms per 352 MB), trims a trailing CR, skips empty lines and hands each line to `body` as an `UnsafeRawBufferPointer` slice of the same buffer. Only lines classified as candidates (R4) are copied into a `Data` for `JSONDecoder` and attribution (FR-012); the shape lines (62 of 93,036) are copied too, since `SessionProfile.detect(line: Data, ...)` keeps its signature.

**Rationale**: The Codex parser's `relevantLines(of:)` already does this (`memchr` per line, copy only the relevant ones), so the pattern has precedent in the codebase. Keeping whole-file reads (`FileHandle.readToEnd` from the parsed offset) keeps the per-file offsets and the "complete lines only" rule untouched (FR-010): `consumed` is still the byte count through the last newline, `total` the bytes read.

**Alternatives considered**: `mmap` (ripgrep found it slower than buffered reads for many files, and a mapped file that shrinks under the reader traps); chunked 64 KB reads with a rolling buffer (the batch cap already bounds memory at 64 MB and the largest session file is 49 MB, so whole-tail reads are simpler and no larger).

## R4: Classifying a line from a bounded portion

**Measured on the largest session file (2026-10-28)**: the top-level `type` key sits in the head (first 256 bytes) for user, shape, system, `api-request-blob`, `api-request` and `file-history-snapshot` lines, and in the tail for assistant lines (406 to 1,143 bytes from the end over 4,180 lines) and attachment lines (up to 30 KB from the end). User lines with large tool results carry it up to 944 KB from the end, so a tail window alone would miss them; shape lines start with it.

**Rejected first draft (tasks stage, 2026-10-28)**: searching the head and tail windows for known `"type":"<value>"` markers and letting any known marker decide. A nested object can hold such a marker unescaped: a `tool_use` block's `input` is arbitrary JSON, so `{"type":"user"}` inside an assistant line's head would have classified a real assistant record as `.other` and lost it. A marker search alone cannot tell the line's own `type` from a nested one (spec FR-013).

**Decision**: `SessionLineClassifier.classify(_ line: UnsafeRawBufferPointer) -> SessionLineKind` (`.assistant`, `.shape`, `.undecided`, `.other`) reads the line's **top-level** `type` member with two bounded structural scans, then falls back to today's marker search:

1. **Head scan**, forward from the first byte, at most 256 bytes. It tracks only what decides nesting: inside or outside a string (a `\` escapes the next byte), and the depth of `{` and `[` outside strings. When a string at depth 1 that equals `type` is followed by optional whitespace, `:` and optional whitespace and a string value, that value decides the line, and the scan stops. A depth-1 `type` whose value is not a string (a number, `null`, an object) decides `.other`: it is the line's own member, `JSONDecoder` rejects it, and FR-013 lets no nested key decide instead. User, shape, system, `api-request-blob`, `api-request` and `file-history-snapshot` lines are decided here, within about 130 bytes.
2. **Tail scan**, backward from the last byte, at most 4,096 bytes, and only when the last non-whitespace byte is `}`. A line cut off mid-write does not end in `}`, and the backward string state of such a line cannot be known, so it goes straight to step 3. String state comes from backslash parity: a `"` is a delimiter when an even number of `\` precede it. Depth is tracked with `}`, `]` (deeper) and `{`, `[` (shallower) outside strings. A depth-1 `"type"` key with its value decides the line, with the same value rule as the head scan. Assistant lines are decided here, after scanning 406 to 1,143 bytes.
3. **Fallback**, when neither scan found a top-level `type`: the whole line is searched with `memmem` for the four candidate markers `"type":"assistant"`, `"type": "assistant"`, `"type":"api-request-shape"` and `"type": "api-request-shape"`, the markers `SessionRecordParser.parse(data:)` and `SessionProfile.detect` search today. Any hit means `.undecided`, and no hit means `.other`. `LogIndex` handles an `.undecided` line exactly as today's loop handles every line: `parser.parse(data:)` first, and when it yields no record and `profiles` is not empty, `SessionProfile.detect`. The fallback does not pick between the two markers, because today's order (parse, then detect on no record) is what decides a line that holds both.

Value decision: `assistant` → `.assistant`, `api-request-shape` → `.shape`, any other string value or a non-string value → `.other`. The scans neither decode values nor build objects. They compare one string with two constants, which makes them classification, not the field extraction FR-020 keeps out of scope.

**Equivalence with today**:

- Assistant records are found exactly as today. Today a candidate is decoded and `JSONDecoder` keeps only a top-level `type == "assistant"`. The scans read the same top-level member, and the decoder still checks it.
- A line the scans cannot decide goes through today's code path unchanged (`.undecided`), so the whole-line fallback of FR-013 classifies it "the same as today" in the literal sense. FR-014's "only assistant lines are decoded, only shape lines are searched" applies to the lines the scans decide; for an `.undecided` line the top-level type is not known, and today's predicate is the classification.
- Shape lines differ only for a non-shape line that holds an unescaped nested `"type":"api-request-shape"` object and whose own `type` the scans find. Today such a line reaches `SessionProfile.detect`; now it does not, as FR-013 requires. If the real-corpus comparison shows such a line, FR-009 applies.
- A marker inside a JSON string has escaped quotes (`\"type\":\"assistant\"`) and matches neither today nor now.
- A top-level `"type" : "assistant"` with a space before the colon is found by the scans but was missed by today's markers. Claude Code writes compact JSON, so the fixtures pin today's spelling.

**Cost estimate**: about 130 bytes per user-like line and about 600 bytes per assistant line, scanned bytewise over a raw pointer. That is roughly 0.5 GB of the 3.5 GB corpus, at least 3 times less than one `memmem` pass over every line, which measured 216 ms per 352 MB. Lines that reach the fallback (attachment lines, whose `type` sits up to 126 KB from the start and 30 KB from the end) cost a whole-line search, as every line does today, and an `.undecided` one costs today's parse and detect on top. The bench shows the share, and the window sizes are two constants.

**Rationale**: correct by construction for FR-013, a fraction of today's cost, and today's predicate stays as the anchor for anything the scans cannot decide.

**Alternatives considered**: marker search in head and tail windows (rejected above); tail window only (misses user lines with large tool results, up to 944 KB from the end); searching `"usage"` (appears in user lines' tool results); a full JSON skip of the top-level members (decodes more than needed, FR-020 territory).

## R5: One timestamp parser

**Checked (2026-10-28)**: `ISO8601DateFormatter` with `.withFractionalSeconds` accepts 2, 3 and 6 fractional digits and truncates to milliseconds (`.080123Z` gives `.08`), returns nil for no fraction (the plain formatter takes that form), and accepts offsets such as `+02:00`. Each call costs about 25 µs; 17,084 timestamps took 438 ms. A fixed-layout parse of the same strings took 1 ms with identical instants.

**Decision**: `UsageCore/Logs/Timestamp.swift` with `enum ISO8601Timestamp { static func parse(_ text: String) -> Date? }`:

- Fast path for the forms the agents write: `YYYY-MM-DDTHH:MM:SSZ` and `YYYY-MM-DDTHH:MM:SS.<1 to 9 digits>Z`, all digits ASCII, fields range-checked (month 1 to 12, day 1 to 31, hour to 23, minute and second to 59). Days from the civil date by the proleptic Gregorian formula (Howard Hinnant's `days_from_civil`); the fraction keeps the first three digits only, so the result equals the formatter's at millisecond precision (FR-015).
- Anything else (an offset, a lowercase `z`, a space, more or fewer separators) goes to the two cached `ISO8601DateFormatter` instances, fractional first, then plain, as today.
- `SessionRecordParser.parseDate` and the Codex `ISO8601Parser` are replaced by it.

**Rationale**: The fast path is 30 lines of integer arithmetic with no allocation, and a table test compares it with the formatter on every form in the fixtures plus the edge forms (no fraction, 1, 2, 3, 6 digits, offset, invalid day) at millisecond precision. Equality at the millisecond, not the raw double, is what FR-015 asks, and the digest states timestamps at the millisecond (FR-004).

"At millisecond precision" means both instants rounded to the nearest millisecond are equal, in the tests and in the digest. Both parsers put the instant on the millisecond grid, but they reach it through different floating-point arithmetic (the formatter from the 2001 reference date, the fast path from 1970), so the two `Date` values can differ by an ulp. Flooring would turn such a value just below `.080` into `.079` on one side only, a false difference in the comparison. The table holds fractions whose fourth digit is 5 or more (`.0805`, `.999999`), so the formatter's truncation, measured above on `.080123` only, is pinned against rounding.

**Alternatives considered**: `Date(_:strategy:)` with `.iso8601` (also slow, about 10 µs); `strptime` plus `timegm` (no fractions, C locale pitfalls).

## R6: Codex typed decoding

**Decision**: `CodexSessionParser` decodes each relevant line with `JSONDecoder` into `CodexLine` (`timestamp: String?`, `payload: CodexPayload?`) and `CodexPayload` (`type`, `id`, `cwd`, `model`, the parent fields `Self.parent(of:)` reads today, `info.total_token_usage` as `CodexTokenUsage` with the six counters, `rate_limits` as `CodexRateLimits` with `limit_id`, `plan_type`, `primary`, `secondary` (each `window_minutes`, `used_percent`, `resets_at` as `Double?`) and `rate_limit_reached_type` as presence only). Every field is optional and decoded leniently: a field of the wrong JSON type reads as absent, as `nonEmpty` and `as? NSNumber` make it today, through a custom `init(from:)` that uses `try?` per key. `Totals` gets an initializer from `CodexTokenUsage` with the same finite, positive and `maxTokenValue` rules. `JSONDecoder` on these lines measured 190 ms against 315 ms for `JSONSerialization`; the dictionary walks and `NSNumber` bridging go away.

**Rationale**: FR-016, and the Codex tests must pass unchanged (FR-011), which the lenient decoding guarantees for the malformed fixtures. The public `parse(data:fallbackSessionId:)` keeps its signature and result type; an internal overload also returns the number of lines visited for the bench, so `CodexSession` does not change.

The Codex reader parses its changed files sequentially inside its actor today, at the refresh's priority. FR-017 and FR-018 cover it too (research R7): the collect loop is split into deciding which files to read (on the actor, as today), reading and parsing them through `ScanWorkers` (off the actor, the file size as weight, so the largest file starts first), and applying the results in the original file order (on the actor), so the log lines, issues and per-home counts come out in the same order as today. The parent lookup in files older than the window (`lookup(_:)` in `collect`) also moves to the workers, so no file is parsed on the actor (FR-017). Before the auth modes are computed, the source resolves parents in rounds:

1. The frontier is found by walking from every session in the window: from a session without a plan marker, follow its parent when the parent differs from the session itself, through sessions in the window or already in `outsideSessions`. Each parent id the walk reaches that is in neither, and for which a path in `olderFiles` ends with `-<id>.jsonl` (the first such path, as `lookup(_:)` picks it today), joins the frontier.
2. Those files are read and parsed through `offload` plus `forEach`, with the file size as weight. Each result goes into `outsideSessions` under the parent id that named the file, as `lookup(_:)` stores it today. A file that cannot be read stores nothing, as today.
3. Step 1 runs again over the grown `outsideSessions` until the frontier is empty. A set of ids already tried in this refresh keeps a cycle or an unreadable file from being tried twice.

`lookup(_:)` then reads only the window's sessions and `outsideSessions`, never a file. The walk follows exactly the edges today's depth-first `isPlan` recursion follows (a parent only from a session without a plan marker, never a session's own id), so it reads the same parent files, and `isPlan` itself is unchanged, so the auth modes are unchanged. The walk starts from the window's sessions, not from every cached session, so a stale `outsideSessions` entry that no window session reaches never causes a read today's code would not make. Parent files read this way count neither in `parsed`, as today, nor in `lastScanFigures`, so the baseline binary and the new one report the same files read.

**Alternatives considered**: keeping `JSONSerialization` with fewer casts (FR-016 forbids it); `Codable` with synthesized conformance (a wrong-typed field fails the whole line, which changes the malformed fixtures' results).

## R7: Bounded workers at utility priority

**Decision**: `UsageCore/Logs/ScanWorkers.swift`, a `Sendable` struct with two operations:

- `offload<T>(_ work: @escaping () -> T) async -> T` runs `work` on `DispatchQueue.global(qos: qos)` and resumes a checked continuation with the result. The caller (an actor) is suspended meanwhile, so neither the actor nor a thread of the cooperative pool is held.
- `forEach(jobs: Int, weight: (Int) -> Int, body: (Int) -> Void)` is synchronous. In the app it runs inside `offload`; `LogIndexTests` call `LogIndex.update` directly, and then the calling thread's share of the jobs runs at the test's priority. It orders the job indices by weight descending (unread bytes, largest first), starts `min(count, jobs) - 1` helper blocks on the same global queue and works on the calling thread too; each takes the next index from a lock-protected cursor until none is left; a `DispatchGroup` waits for the helpers. Zero jobs return at once. Blocking a utility dispatch thread this way is allowed; blocking the cooperative pool is not. The parameter is `jobs`, not `count`, because `count` is the worker bound.

Defaults: `count = max(1, min(3, activeProcessorCount / 2))`, `qos = .utility`, in one place. An explicit `ScanWorkers(count:)` (the bench's `--workers`) is clamped to `1...activeProcessorCount`, so no setting exceeds the machine's cores (FR-017). `beforeJob: (@Sendable (Int) -> Void)?` is a test hook called on the worker before each job.

**Claude Code reader**: `LogIndex.update` stays synchronous, so `LogIndexTests` keep calling it as today; phase 2 calls `workers.forEach` instead of `DispatchQueue.concurrentPerform`, phases 1 and 3 stay as they are. `SessionLogSource.collect` runs the whole `index.update(...)` through `workers.offload`. `LogIndex` is not `Sendable`; the closure captures it through a small `UncheckedSendableBox` whose doc comment states the exclusive access: the actor touches the index only before and after the offloaded update.

**Codex reader**: the parse of changed files and the parent lookup in older files run through `offload` plus `forEach` (research R6).

**Reentrancy**: while a scan is offloaded, the actor is suspended and can take another call. In the app, `RefreshCoordinator` is the only caller of `collect` and `resetForEarlierWindow()` (checked 2026-10-28): its `running` flag allows one run loop at a time, each refresh collects every source once in a task group, and it awaits `resetForEarlierWindow()` only after that group returned. So the app never starts a second scan during the first. The bench and the tests call `collect` directly, so the sources enforce the exclusive access themselves rather than rely on the caller:

- Each source keeps `scanning`. A `collect` that starts while `scanning` is true first waits until that scan has ended (the source keeps the waiting callers' continuations in `scanWaiters` and resumes them in order when `scanning` turns false), then checks `scanning` again before it runs, so of several waiting callers only one scans at a time. Two updates never touch the `LogIndex` at once, and two Codex collects never decide the same files at once. This is what makes the `UncheckedSendableBox` claim true.
- `resetForEarlierWindow()` during a scan sets `resetPending` and logs nothing yet. `collect` applies it at its very end, after it has taken the records, the stats and the log line of the scan: this call returns the scan's records, and the next `collect` reads every file again.
- An internal `isScanning()` lets the tests observe the state.

**FR-018 test**: a `ScanWorkers` whose `beforeJob` signals that a job has started and then waits on a semaphore holds the workers. The test starts `collect`, waits for that signal, then awaits `source.isScanning()`, which must return `true` while the workers are held (today's `concurrentPerform` inside the actor would keep the actor busy and the call would not return until the scan ended). While the workers are held, a second source's `collect` over a small tree completes, which is FR-018's "a second refresh completes". Then the test releases the semaphore and checks the records. The same test runs for the Codex source.

**Rationale**: `concurrentPerform` uses every core at the caller's priority (the user-initiated refresh), which is the 400 to 450% CPU of the complaint. A utility queue lets macOS schedule the parse on efficiency cores and behind interactive work; largest-first ordering keeps the last worker from running alone on the biggest file. The count stays small on purpose: SC-002 caps the average at 200%, and the baseline will show how many CPU seconds remain after R3 to R5.

**Measurement step**: the tasks run the bench with 2, 3 and 4 workers and record each in the benchmark record; the smallest count that meets SC-001 while keeping SC-002 is kept.

**Alternatives considered**: `TaskGroup` with `Task.detached(priority: .utility)` (the cooperative pool has no bound below the core count and a long synchronous job starves other tasks on it); `OperationQueue` with `maxConcurrentOperationCount` (works, but more objects for the same result); `concurrentPerform` on a utility queue (still every core).

## R8: The bench's code path and directory override

**Decision**: `UsageCore/Bench/ScanBench.swift` builds exactly what `App.swift` builds: `Paths()`, `ConfigStore(fileURL:)` for the given or default configuration (a read error or invalid file exits with code 2 and the error text, never a default configuration), `PriceTable.builtIn()`, `ImportedPriceStore` for the app's imported prices (`run` only, see below), then `SessionLogSource` or `CodexSessionSource` with a `DiagnosticLog` that writes to a temporary file (so the FR-007 line is produced and can be shown). The window is `WindowResolver().resolve(now:alignmentReset: nil, fallback:calendar:)` widened by `collectionWindow(...)` as `RefreshCoordinator` does, or `DateInterval(start: since, end: now)` with `--since`. It calls `collect(context:)` once with a fresh index and reads `ProcessResources` before and after.

A given directory replaces the configuration's directories through one seam on each source: `SessionLogSource(..., scanTargets: [ScanTarget]? = nil)` substitutes `resolution.directories` for the scan only (the profile candidates and the attributor still come from the configuration, so attribution runs as in the app), and `CodexSessionSource(..., homes: [String]? = nil)` does the same for the Codex homes. Without the option, the bench runs over the configuration's directories, which is the app-faithful default.

Lines visited come from `LogIndexStats.linesVisited` (new: the non-empty complete lines, as `readCompleteLines` counts them today) and from the Codex parser's internal overload (research R6). The sources keep the last refresh's figures (`lastScanFigures`: files seen, files read, bytes read, lines), which the bench reads after `collect`. `--workers N` injects `ScanWorkers(count: N)` for the measurement step of R7.

**Imported prices**: imported price entries override the built-in ones (`PriceTable.effective`). `run` reads the app's imported price file as the app does, so the baseline binary and the new one price the real corpus alike. `digest` (the fixture digests of FR-008, `make bench-digests` and `ScanBenchTests`) passes no imported store: built-in prices plus the fixture configuration's overrides only. Otherwise the committed cost column would depend on the price file of the machine that generated it, and the test would fail on every other machine.

**Validation**: the directory must exist and be readable and must hold the folder the reader scans (`projects` for Claude Code, `sessions` for Codex); otherwise the bench reports the problem and exits with code 2 without a report (spec edge cases). `compare` with a missing or unreadable digest file fails the same way and gives no verdict.

**Rationale**: FR-001 asks for the refresh code path; constructing the sources as the app does is the only way to be sure. The seam is two optional initializer parameters that the app never passes.

**Alternatives considered**: a rewritten configuration with the directory as an account's directory (changes attribution); calling `LogIndex` directly (skips the source's resolution, logging and profile candidates).

## R9: The records digest and the comparison

**Checked (2026-10-28)**: `UsageRecord` keeps neither the working directory nor the session id. The parser reads both into `RawUsageRecord`; the cwd becomes `UsageRecord.project` through `ProjectResolver` (git root, or the cwd itself when no repository contains it), and the Claude Code session id is not used after parsing. The Codex record key is `codex:<session id>:<running total>`, so the Codex session id is part of the key.

**Decision**: the digest compares the record as the app keeps it, which is what the dropdown shows (User Story 2): `UsageRecord` gets no new fields, and the spec's FR-004 is adjusted to name the project instead of the working directory and the session id only through the key (spec clarification of 2026-10-28, planning). `UsageCore/Bench/RecordsDigest.swift`: one line per `UsageRecord`, tab-separated: harness, record key (`msg:<id>` or `req:<id>`, as `LogIndex.key`), timestamp as `YYYY-MM-DDTHH:MM:SS.mmmZ` rounded to the nearest millisecond (R5), model, canonical model, input, output, cache write 5m, cache write 1h, cache read, reasoning, project root (empty when nil), account id (empty when unassigned), cost (decimal text, empty when unpriced). Lines sorted by harness, key, timestamp, model. Header lines name the digest version, the configuration file (with `~`), the window start and the directory. `RecordsDigest.compare(a:b:) -> Comparison` compares the record lines; header differences are printed as notes and do not make two digests different. It reports the counts and the first 20 differing lines per side. The bench refuses a digest path under any configured session directory, `~/.claude` or `~/.codex` (FR-004).

The fixture lines use invented working directories under a top-level folder that does not exist (`/fixture/...`), so `ProjectResolver` falls back to the cwd itself on every Mac and the committed digests are machine-independent.

The fixture digests (FR-008) live in `Tests/UsageCoreTests/Fixtures/digests/`: `claude.digest` with `claude-config.json`, `codex.digest` with `codex-config.json`; `make bench-digests` regenerates them with the fixed window start `2026-10-01T00:00:00Z` named in each digest's header and without imported prices (R8). The test `ScanBenchTests` copies the fixture files into a temporary `projects` tree, runs `ScanBench.run` with the fixture configuration and window, and compares the digest text.

**Rationale**: A text digest diffs with any tool, holds no message content (FR-003), and compares at millisecond precision as FR-004 and FR-015 require. Adding cwd and session id to every `UsageRecord` would cost about 13 MB of heap over 86,000 records for a bench-only need, and the Claude Code envelope decoding that reads them does not change (R11).

**Alternatives considered**: adding `cwd` and `sessionId` to `UsageRecord` (memory in the app for a bench-only column); a second, raw-record digest path (a code path the app does not run, against FR-001).

## R10: Benchmark record and cold runs

**Decision**: `specs/039-faster-session-scan/BENCHMARK.md` holds a table with one row per run: date, commit, condition (warm or cold), directory (with `~`), configuration, window start, files seen and read, bytes read, lines, records, wall s, CPU user s, CPU system s, average CPU %, peak footprint MB, disk MB read, workers. Below it, the digest comparison result per code version. The protocol: run twice for warm and report the second; for cold, `sudo purge`, then run once; a cold run is recognized by disk MB read close to bytes read. The warm baseline and warm runs are taken in the implementation; the cold runs and the real-corpus comparison are maintainer steps in the walkthrough (spec FR-006).

## R11: What stays as it is

- `LogIndex`'s decision phase, re-read rules (specs 035, 037, 038), batching by bytes, dedupe and phase 3 merge are untouched; only the reading and the worker model change (FR-010).
- `SessionRecordParser.parse(data:)` keeps its signature and its marker pre-filter (cheap on candidate lines, and the tests call it directly); `parse(line: String)` stays for tests.
- `SessionProfile.detect` keeps its signature; it receives only shape-classified lines (FR-014).
- No UI change (constitution V): the only visible change is the diagnostic log's refresh line (`cpu <seconds> s`), which no screenshot shows.
- `OpenCodeSource` is untouched (FR-021).
