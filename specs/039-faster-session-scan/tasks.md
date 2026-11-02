# Tasks: Faster Session Scan

**Input**: Design documents from `specs/039-faster-session-scan/` (plan.md, spec.md, research.md, data-model.md, contracts/bench-cli.md, quickstart.md)

**Tests**: Required. Constitution II asks for tests written before the implementation, so each story phase lists its test tasks first. They must fail before the implementation task that follows them.

**Order is binding (spec FR-006)**: Phases 1 to 4 (setup, measurement, safety net, baseline) are done and committed before any task touches line reading, classification, timestamps, workers or Codex decoding. User Story 3 has priority P2 but runs first, because without the baseline nothing can be compared.

**Maintainer steps, not tasks here**: the cold-cache runs (`sudo purge`), the walkthrough's repeat of the real-corpus comparison, the incremental check in the app's log, and the responsiveness check by hand (quickstart sections 2 to 5). Phase 6 lists them in `BENCHMARK.md` for the walkthrough.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: US1 fast and quiet, US2 same records, US3 measured number

## Common steps

**Comparison block**, run at the end of each step of Phase 5. Commands from quickstart section 3; `SINCE` is the value recorded in `BENCHMARK.md`:

1. `make test` passes. The fixture digests (T021) are unchanged and their test passes.
2. Set `UNTIL` to ten minutes ago. Then for `READER=claude` and `READER=codex`:
   - Run the saved baseline binary (`BENCH_BIN=/tmp/agenttacho-bench/scan-bench-baseline`) and the new build back to back, each with `SINCE`, `UNTIL` and a `DIGEST` under `/tmp/agenttacho-bench/`.
   - `make bench-compare` must print `identical`.
3. Run the new build twice per reader without `DIGEST` and append the second run of each to `BENCHMARK.md`. Note the step, the second-refresh line and the comparison result.
4. Commit the step, its tests and the `BENCHMARK.md` rows together.

**Stop rule** (plan): if a comparison differs, the step is not done. Find the cause and fix it. An old-code bug is handled under spec FR-009: fix it as its own commit first, then rebuild the baseline binary and the baseline rows from that fix. Never edit a committed fixture digest to make a test pass. Only `make bench-digests` regenerates them, and only when fixtures change.

---

## Phase 1: Setup

**Purpose**: The bench target, the Makefile entry points and the fixture trees the later phases share.

- [X] T001 Add the executable target `ScanBench` and product `scan-bench` to `Package.swift`:
  - `.executableTarget(name: "ScanBench", dependencies: ["UsageCore"], path: "Sources/ScanBench")` and `.executable(name: "scan-bench", targets: ["ScanBench"])`.
  - Create `Sources/ScanBench/main.swift` printing the usage of contracts/bench-cli.md to stderr and exiting with code 2.
  - Confirm that `make build` compiles it and that `scripts/release/build-app.sh` still bundles only the `AgentTacho` product.
- [X] T002 Add the targets `bench-scan`, `bench-compare` and `bench-digests` to `Makefile`, and add them to `.PHONY` (contracts/bench-cli.md):
  - Variables: `READER`, `DIR`, `CONFIG`, `SINCE`, `UNTIL`, `DIGEST`, `WORKERS`, `BENCH_BIN`, `A`, `B`.
  - Follow the Makefile's rule that a value reaches a recipe only through the environment, read as `"$$VAR"`, never pasted into shell text.
  - `bench-scan` builds with `swift build -c release --product scan-bench` unless `BENCH_BIN` is set, then calls `run` with only the options whose variables are set.
  - Set `SCAN_BENCH_COMMIT` from `git rev-parse --short HEAD`, plus `-dirty` when `git status --porcelain` is non-empty, or to `baseline-binary` for `BENCH_BIN`.
  - `bench-digests` calls `scan-bench digest` once per reader, with the fixture trees of T003 and T004, the configurations of T005, `--since 2026-10-01T00:00:00Z`, and outputs `Tests/UsageCoreTests/Fixtures/digests/claude.digest` and `codex.digest`.
- [X] T003 [P] Create the Claude Code scan fixture tree `Tests/UsageCoreTests/Fixtures/scan/claude/projects/fixture-project/`:
  - Copy `direct-session.jsonl`, `gateway-session.jsonl`, `vertex-session.jsonl`, `custom-marker.jsonl`, `unknown-model.jsonl`, `malformed-fields.jsonl` and `truncated.jsonl` from `Tests/UsageCoreTests/Fixtures/`.
  - In the copies only, rewrite every `cwd` to a path under `/fixture/` (for example `/fixture/proj-alpha`, `/fixture/proj-beta`) so `ProjectResolver` falls back to the cwd itself on every Mac (research R9).
  - Leave the originals untouched.
- [X] T004 [P] Create the Codex scan fixture tree `Tests/UsageCoreTests/Fixtures/scan/codex/sessions/2026/10/13/`:
  - Copy the files of `Tests/UsageCoreTests/Fixtures/codex/`, renamed `rollout-2026-10-13T09-00-00-<session id>.jsonl`. `CodexSessionSource.rolloutFiles` only takes `rollout-*.jsonl`, and the parent lookup matches the `-<session id>.jsonl` suffix. Take each session id from the file's first `session_meta` line: `limits-forked.jsonl` and `subagent-session.jsonl` hold a second one, copied from the parent.
  - Rewrite each `cwd` under `/fixture/`.
- [X] T005 [P] Create the fixture configurations `Tests/UsageCoreTests/Fixtures/digests/claude-config.json` and `codex-config.json` with invented data only, using the key names of `Resources/demo/default.json`:
  - Claude: subscription `acc-max` with Claude Code directory `/fixture/claude-a`; token-based Claude Code accounts `acc-vertex` (kind Vertex) and `acc-gateway` (kind Other provider) in group `grp-work`.
  - Codex: subscription `acc-plus` with home `/fixture/codex-a`; token-based Codex account `acc-codex-api`.

---

## Phase 2: User Story 3 - The gain is a measured number (Priority: P2, runs first by FR-006)

**Goal**: One bench command runs the real refresh code path and reports wall, CPU, memory, disk and counts, writes a records digest, and compares two digests. Both refresh lines in the diagnostic log gain CPU seconds.

**Independent Test**: `make bench-scan DIR=Tests/UsageCoreTests/Fixtures/scan/claude CONFIG=Tests/UsageCoreTests/Fixtures/digests/claude-config.json SINCE=2026-10-01T00:00:00Z` prints a report as in contracts/bench-cli.md. `make bench-compare` of a digest with itself prints `identical`. The error cases exit with code 2.

### Tests for User Story 3 (write first, must fail)

- [X] T006 [P] [US3] Write `Tests/UsageCoreTests/ProcessResourcesTests.swift`:
  - A snapshot has non-negative fields.
  - After a busy loop of about 50 ms, the delta shows user CPU above 0 and wall time at least the loop time.
  - `diskBytesRead` and both peaks never decrease between snapshots.
  - `averageCPU` equals the CPU time over the wall time.
  - `ProcessResources.cpuSeconds()` grows across a busy loop.
- [X] T007 [P] [US3] Write `Tests/UsageCoreTests/RecordsDigestTests.swift`:
  - The line format follows contracts/bench-cli.md "Digest file":
    - 14 tab-separated columns.
    - Timestamps rounded to the nearest millisecond with `Z` (research R5): a `Date` one ulp below `.080` and one one ulp above both print `.080`.
    - Empty text for a nil project, account or cost; cost as `Decimal` text.
    - Keys `msg:` or `req:`, and Codex message ids kept as they are.
  - Sorting is stable and header lines are as specified.
  - `until` drops records stamped at or after it.
  - The digest text round-trips through parse.
  - `compare` returns:
    - identical for equal record lines;
    - identical with `headerNotes` when only headers differ;
    - different with `onlyInA` and `onlyInB` capped at 20 lines and the counts.
- [X] T008 [P] [US3] Write the validation and report tests in `Tests/UsageCoreTests/ScanBenchTests.swift`:
  - A missing directory, a directory without `projects` (Claude Code) or `sessions` (Codex), an unreadable or invalid configuration file, and a digest path under `~/.claude`, under `~/.codex` or under the scanned directory each make `ScanBench.run` throw `ScanBenchError.invalid`, which maps to exit code 2. No report is produced. The error text names the path with `~`.
  - `ScanBench.compare` with a missing or unreadable digest file throws `ScanBenchError.invalid` and gives no verdict.
  - A run over the T003 tree reports the files seen and read, lines, records and a `second refresh` line. The test computes the expected file and line counts from the tree it copies, so the fixtures T018 adds later do not change its expectations.
  - The report and the written digest never contain a unique content string taken from the fixture lines (for example the text of an assistant `content` block).
- [X] T009 [P] [US3] Add the FR-007 log-line tests:
  - In `Tests/UsageCoreTests/LogIndexTests.swift`, a new test that `SessionLogSource.statsLine(_:directories:elapsed:cpu:)` with `cpu: 38.04` ends with `, 9.220 s, cpu 38.0 s`. `statsLineShowsLargeByteCounts` stays unchanged: without `cpu` there is no suffix.
  - In `Tests/UsageCoreTests/CodexSessionSourceTests.swift`, a new test that the Codex refresh line ends with `s, cpu <number> s`. The existing `contains` expectations stay unchanged.

### Implementation for User Story 3

- [X] T010 [P] [US3] Implement `ProcessResources` (`Snapshot`, `Delta`, `cpuSeconds()`) in `Sources/UsageCore/Diagnostics/ProcessResources.swift`:
  - CPU and `ru_maxrss` from `getrusage(RUSAGE_SELF)`.
  - `ri_diskio_bytesread` and `ri_lifetime_max_phys_footprint` from `proc_pid_rusage(getpid(), RUSAGE_INFO_V4, ...)`.
  - Wall time from `ContinuousClock`.
  - Doc comments cite spec 039 FR-002 and FR-007 and research R2.
- [X] T011 [P] [US3] Implement `RecordsDigest` (entries from `[UsageRecord]`, header, `text`, `parse`, `compare`, `until` filter) in `Sources/UsageCore/Bench/RecordsDigest.swift` per research R9 and data-model.md.
- [X] T012 [US3] Count lines without changing how they are read:
  - Add `linesVisited` to `LogIndexStats` in `Sources/UsageCore/Logs/LogIndex.swift`, summed from the existing `readCompleteLines` result per job in phase 3.
  - In `Sources/UsageCore/Logs/CodexSessionParser.swift`, add an internal overload of `parse(data:fallbackSessionId:)` that also returns the number of non-empty lines `relevantLines` walked. The public signature and `CodexSession` stay as they are.
- [X] T013 [US3] Add the bench seams and the figures (contracts/bench-cli.md "Source initializer seams"; the app passes neither seam):
  - In `Sources/UsageCore/Logs/SessionLogSource.swift`: `scanTargets: [ScanTarget]? = nil` replaces `resolution.directories` for the scan only. Keep `lastScanFigures` (files seen, files read, bytes read, lines visited) after each `collect`.
  - In `Sources/UsageCore/Logs/CodexSessionSource.swift`: `homes: [String]? = nil` replaces the locations to scan. Keep the same `lastScanFigures`.
- [X] T014 [US3] Add the CPU seconds to both refresh lines (spec FR-007):
  - Take `ProcessResources.cpuSeconds()` at the start and end of `collect` in `SessionLogSource.swift` and `CodexSessionSource.swift`.
  - Add `cpu: Double? = nil` to `SessionLogSource.statsLine` and append `, cpu %.1f s` when it is set.
  - Append the same suffix to the Codex `home(s) read` line.
  - Make T009 pass.
- [X] T015 [US3] Implement `ScanBench` in `Sources/UsageCore/Bench/ScanBench.swift` (research R8, contracts/bench-cli.md):
  - Interfaces as data-model.md "ScanBenchOptions": `ScanBench.run(_:) async throws -> ScanBenchReport`, `ScanBench.compare(_:_:) throws -> RecordsDigest.Comparison`, `ScanBenchError.invalid(String)`.
  - Options and validation, building the configuration through `ConfigStore` without falling back to a default.
  - The prices: `PriceTable.builtIn()` plus, when `useImportedPrices` is true (`run`), the imported store at `Paths().importedPricesFileURL`. The `digest` mode passes no imported store.
  - The source, built as `Sources/AgentTacho/App.swift` builds it, with a `DiagnosticLog` in a temporary file.
  - The window: `WindowResolver.resolve` plus `collectionWindow`, or `--since`.
  - The run: two `collect` calls with `ProcessResources` snapshots around each.
  - The report text, with `~` for the home directory, and digest writing with refusal of agent directories.
  - Make T008 pass.
- [X] T016 [US3] Implement the CLI in `Sources/ScanBench/main.swift`:
  - Subcommands `run`, `compare` and `digest`, and the options of contracts/bench-cli.md.
  - Exit codes 0, 1 and 2; errors as one line on stderr.
  - No logic beyond parsing and printing (constitution II).
- [X] T017 [US3] Check the Makefile entry points end to end against the T003 and T004 trees and the T005 configurations:
  - `make bench-scan` for both readers.
  - `make bench-compare` of a digest with itself.
  - The error cases of quickstart section 6.
  - Confirm that nothing was written under `~/.claude` or `~/.codex` (compare `ls -la` before and after).

**Checkpoint**: The bench works on the unchanged parsing code. Commit Phase 1 and Phase 2.

---

## Phase 3: User Story 2 - Every record stays the same (Priority: P1), safety net from unchanged code

**Goal**: Fixtures and committed digests pin today's records, including the edge cases the new reader must keep. They are recorded before any parsing change.

**Independent Test**: `make test` passes on the unchanged parsing code with the new fixture-digest and edge-case tests.

- [X] T018 [P] [US2] Add edge-case fixtures to `Tests/UsageCoreTests/Fixtures/scan/claude/projects/fixture-project/` (invented data, cwd under `/fixture/`, timestamps in October 2026). These record today's behavior, whatever it is:
  - `nested-type-key.jsonl`, four lines:
    - (a) An assistant record whose first 256 bytes hold a `tool_use` block with `"input":{"type":"user"}` and whose top-level `"type":"assistant"` sits in the last 1 KB.
    - (b) An assistant record whose top-level `type` sits more than 256 bytes from the start and more than 4,096 bytes from the end, because a top-level string field of about 5 KB follows it. This reaches the whole-line fallback.
    - (c) A user line whose content string holds the escaped text `\"type\":\"assistant\"`.
    - (d) A user line whose top-level `"type":"user"` sits in the first 256 bytes and whose later top-level `toolUseResult` object holds an unescaped nested `{"type":"assistant","message":{...usage...}}`. With its own `type` outside both windows the line would reach the fallback and be `.undecided`, not the `.other` T029 expects.
  - `crlf.jsonl`: two assistant records with CRLF line ends.
  - `incomplete-tail.jsonl`: one complete record, then a record without a trailing newline.
  - `timestamps.jsonl`: one assistant record per timestamp form, with 0, 1, 2, 3, 6 and 9 fractional digits and one `+02:00` offset.
  - `shape-line.jsonl`: an `api-request-shape` line naming `/fixture/claude-a/projects/fixture-project/memory/`, followed by two assistant records.
  - `non-utf8.jsonl`: a user line with a raw `0xFF` byte inside a string, then a valid assistant record. Write it with a byte-exact tool (`printf`), not an editor.
- [X] T019 [P] [US2] Write `Tests/UsageCoreTests/ScanEquivalenceTests.swift`. It generates its cases in a temporary directory and drives `LogIndex.update` as `LogIndexTests` does:
  - A single assistant record padded to 1.8 MB is parsed once.
  - A file whose last line lacks its newline: after one `update` the record is missing, and after appending the newline and a second `update` it is present exactly once.
  - A record split across an append boundary is counted once.
  - These pass on today's code.
- [X] T020 [US2] Add the fixture-digest tests (spec FR-008) to `Tests/UsageCoreTests/ScanBenchTests.swift`:
  - For each reader, copy the scan tree of T003 or T004 into a temporary directory. File modification times are fresh, so every file is inside the window.
  - Run `ScanBench` in digest mode (`useImportedPrices: false`, as `make bench-digests` runs it) with the T005 configuration and `--since 2026-10-01T00:00:00Z`. Compare the record lines with `Tests/UsageCoreTests/Fixtures/digests/claude.digest` or `codex.digest`.
  - On a difference, print the `onlyInA` and `onlyInB` lines.
  - The test fails until T021 generates the digests.
- [X] T021 [US2] Run `make bench-digests` on the unchanged parsing code to create `Tests/UsageCoreTests/Fixtures/digests/claude.digest` and `codex.digest`. Review them by hand:
  - one record per expected fixture record;
  - accounts as T005 intends;
  - for each line of `nested-type-key.jsonl`, the record list shows what today's code does;
  - no real path, name or model output.

  Then `make test` passes. Commit Phase 3.

**Checkpoint**: Today's records are pinned by committed digests.

---

## Phase 4: Baseline (User Story 3), the gate before any parsing change

- [X] T022 [US3] Create `specs/039-faster-session-scan/BENCHMARK.md`:
  - The protocol of research R10 and contracts/bench-cli.md: warm means run twice and keep the second; cold means `sudo purge`, then one run.
  - The comparison block above, and `SINCE=2026-10-01T00:00:00Z`.
  - The run table with the columns of data-model.md "Benchmark record row", plus a `second refresh` column holding the second-refresh wall and CPU.
  - A "Digest comparisons" section and a "Maintainer steps" section listing the cold runs, the walkthrough's comparison, the incremental check and the responsiveness check.
  - Paths with `~`, no user name.
- [X] T023 [US3] Take the warm baseline on this unchanged parsing code:
  - Run `make bench-scan SINCE=...` twice for `READER=claude` and twice for `READER=codex`. Record the second run of each as `baseline` rows with the commit.
  - Copy the release binary aside: `mkdir -p /tmp/agenttacho-bench && cp .build/release/scan-bench /tmp/agenttacho-bench/scan-bench-baseline`.
  - Run one digest pair (baseline binary against itself, same `UNTIL`) to prove the comparison works, and note it.
  - Commit `BENCHMARK.md` as "bench: record warm baseline".

**Gate**: Phase 5 starts only after T023 is committed.

---

## Phase 5: User Story 1 - The first scan is fast and quiet (Priority: P1)

**Goal**: The first scan finishes in under 3 s at no more than 200% CPU on average, with identical records. Each step ends with the comparison block.

**Independent Test**: `make bench-scan` over the maintainer's corpus with the recorded `SINCE` (SC-001, SC-002, SC-003); `make bench-compare` against the baseline binary prints `identical` (SC-004); the second-refresh line is no slower than the baseline's (SC-005); the Codex CPU is at most half the baseline's (SC-006).

### Step B: one timestamp parser (spec FR-015, research R5)

- [X] T024 [P] [US1] Write `Tests/UsageCoreTests/TimestampTests.swift`:
  - A table compares `ISO8601Timestamp.parse` with the two `ISO8601DateFormatter` instances of today: both instants rounded to the nearest millisecond are equal (research R5). Forms: no fraction, 1, 2, 3, 6 and 9 fractional digits, fractions whose fourth digit is 5 or more (`.0805`, `.999999`, `.123999999`) so the formatter's truncation is pinned against rounding, year boundaries (`2025-12-31T23:59:59.999Z`, `2026-01-01T00:00:00Z`), the leap day `2028-02-29T12:00:00Z`, and every timestamp in the fixtures (read from the files).
  - Fallback forms parse equal to the formatter: `+02:00`, `-05:30`, lowercase `z`.
  - Text that neither parses yields nil both ways: month 13, day 32, hour 24, letters in digits, an empty string, `2026-10-14 19:44:01Z`.
- [X] T025 [US1] Implement `ISO8601Timestamp.parse` in `Sources/UsageCore/Logs/Timestamp.swift`:
  - The fast path takes `YYYY-MM-DDTHH:MM:SS(.f{1,9})?Z` with range checks and `days_from_civil`, keeping three fraction digits.
  - Every other form goes to the two cached formatters, fractional first.
  - Doc comment cites spec 039 FR-015 and research R5.
- [X] T026 [US1] Use `ISO8601Timestamp.parse`:
  - In `SessionRecordParser.parseDate` (`Sources/UsageCore/Logs/SessionRecordParser.swift`), whose formatter statics go.
  - In `Sources/UsageCore/Logs/CodexSessionParser.swift`, where the private `ISO8601Parser` class goes and `dates.date` call sites call the shared parser.
  - `SessionRecordParserTests` and `CodexSessionParserTests` pass unchanged.
- [X] T027 [US1] Run the comparison block for step B and record it in `specs/039-faster-session-scan/BENCHMARK.md` (note `step B: timestamps`). Commit.

### Step C: lines in place and top-level classification (spec FR-012 to FR-014, research R3 and R4)

- [X] T028 [P] [US1] Write `Tests/UsageCoreTests/SessionLineReaderTests.swift` for `SessionLineReader.forEachLine(in:body:)`:
  - It visits LF lines, trims one trailing CR, and skips empty lines.
  - It never visits a last line without a newline and returns the consumed bytes through the last newline.
  - A buffer without any newline yields no line and 0 consumed.
  - A 1.8 MB line is visited as one slice of the buffer: its base address lies inside the buffer, so no copy was made.
  - Bytes that are not valid UTF-8 pass through.
  - A property test over random buffers: the visited lines and the consumed count equal those of today's `LogIndex.readCompleteLines` logic, inlined in the test as the reference.
- [X] T029 [P] [US1] Write `Tests/UsageCoreTests/SessionLineClassifierTests.swift` for `SessionLineClassifier.classify`:
  - Head decisions: user, shape and system lines.
  - Tail decision: an assistant line.
  - The four lines of `nested-type-key.jsonl`: (a) `.assistant`, (b) `.undecided` through the fallback, (c) `.other`, (d) `.other`.
  - The `"type": "assistant"` spelling with a space after the colon.
  - A `"type"` key inside a string value, including one ending in escaped backslashes (`"\\\\"`), so the backward parity rule is exercised.
  - An unknown top-level type: `.other`.
  - A top-level `"type":1` or `"type":null` in the head, with a nested `"type":"assistant"` later in the line: `.other`.
  - A line without any `type` key: `.other` through the fallback.
  - A line the scans cannot decide that holds both an assistant and a shape marker: `.undecided`.
  - Lines shorter than the budgets.
  - An equivalence test over every line of every fixture file under `Tests/UsageCoreTests/Fixtures/`, with `JSONSerialization` as the reference:
    - For a line that parses as a JSON object, a `.assistant` kind means its top-level `type` is `"assistant"`, `.shape` means `"api-request-shape"`, and `.other` means neither or no candidate marker at all. `.undecided` occurs only when the line holds one of the four candidate markers.
    - For a line that does not parse (truncated, non-UTF-8), `SessionRecordParser` yields no record either way, so the test asserts two things. The kind is `.shape` only when today's shape marker occurs in the line. A line whose last non-whitespace byte is not `}` skips the tail scan and is decided by the head scan or today's marker predicate (research R4).
    - Every line for which today's `SessionRecordParser().parse(data:)` returns a record is `.assistant` or `.undecided`.
    - Every line for which today's `SessionProfile.detect` returns anything but `.notShape` and whose top-level `type` is `"api-request-shape"` is `.shape` or `.undecided`.
- [X] T030 [P] [US1] Implement `SessionLineReader` in `Sources/UsageCore/Logs/SessionLineReader.swift`: a `memchr` walk over an `UnsafeRawBufferPointer`, the complete-lines rule and CR trim (research R3). Make T028 pass.
- [X] T031 [P] [US1] Implement `SessionLineKind` and `SessionLineClassifier` in `Sources/UsageCore/Logs/SessionLineClassifier.swift` (research R4):
  - The forward head scan (256 bytes) and the backward tail scan (4,096 bytes, only when the last non-whitespace byte is `}`), tracking string state, escapes and backslash parity, and depth.
  - The depth-1 `type` key and value comparison. A non-string value decides `.other`.
  - The whole-line `memmem` fallback for the four candidate markers: any hit is `.undecided`, no hit is `.other`.
  - Doc comments cite spec 039 FR-013 and research R4.
  - Make T029 pass.
- [X] T032 [US1] Rework `LogIndex` phase 2 in `Sources/UsageCore/Logs/LogIndex.swift`:
  - A new `readUnreadBytes(path:from:)` reads the unread tail once. A file that cannot be opened or seeked, or has nothing unread, yields zero bytes, as `readCompleteLines` does today.
  - `SessionLineReader` walks it. `SessionLineClassifier` decides each line.
  - Only `.assistant` lines are copied into `Data` for `parser.parse(data:)`, and only `.shape` lines go to `SessionProfile.detect`, when `profiles` is not empty.
  - An `.undecided` line is copied and handled as today's loop handles every line: `parser.parse(data:)`, and when that yields no record and `profiles` is not empty, `SessionProfile.detect` (research R4).
  - `consumed`, `total` and `linesVisited` keep their meaning.
  - Keep `readCompleteLines` only if something still calls it; otherwise remove it.
  - `LogIndexTests`, `SessionProfileTests`, `ScanEquivalenceTests` and the fixture-digest tests pass unchanged.
- [X] T033 [US1] Run the comparison block for step C and record it in `specs/039-faster-session-scan/BENCHMARK.md` (note `step C: lines in place`). Commit.

### Step D: bounded workers off the actors (spec FR-017, FR-018, research R7)

- [X] T034 [P] [US1] Write `Tests/UsageCoreTests/ScanWorkersTests.swift`:
  - `forEach(jobs:weight:body:)` runs every index exactly once, and returns at once for zero jobs.
  - The observed maximum of jobs running at once never exceeds `count`, counted with an atomic or lock-protected counter.
  - Jobs start in descending weight order when `count == 1`.
  - From a `Task(priority: .userInitiated)`, inside a job of a `forEach` that runs inside `offload`, `qos_class_self()` is `QOS_CLASS_UTILITY`, so a higher-priority caller does not lift the scan.
  - `offload` returns the work's result, and while offloaded work is held on a semaphore, an unrelated `Task` on the cooperative pool completes.
  - The default count is `max(1, min(3, activeProcessorCount / 2))`, and `ScanWorkers(count: activeProcessorCount + 4).count` equals `activeProcessorCount`.
- [X] T035 [P] [US1] Write `Tests/UsageCoreTests/ScanConcurrencyTests.swift` (spec FR-018), using the `beforeJob` hook to signal that a job started and then hold the workers on a semaphore. Each check below starts only after that signal, so it never races the start of the scan:
  - For `SessionLogSource` over a temporary tree: `collect` runs, `await source.isScanning()` returns `true` while the workers are held, and after the release the records equal those of an unheld run.
  - While those workers are held, a `CodexSessionSource.collect` over a small tree, with its own default workers, completes (FR-018's "a second refresh completes").
  - `resetForEarlierWindow()` during the scan is applied after it ends: the held `collect` still returns the scan's records, and the next `collect` reads every file again.
  - A second `collect` on the same source, started while the workers are held, waits: it returns only after the release, and both calls return the records of an unheld run.
  - Two more `collect` calls on the same source, both started while the workers are held and after a new session file was added to the tree, never scan at the same time: after the release, the `beforeJob` calls number the tree's original files plus one, so the new file was read by one of the two calls only, and its records appear once.
  - The same for `CodexSessionSource`.
- [X] T036 [US1] Implement `ScanWorkers` in `Sources/UsageCore/Logs/ScanWorkers.swift` (research R7, data-model.md):
  - `offload` with a checked continuation on `DispatchQueue.global(qos:)`.
  - `forEach(jobs:weight:body:)` with `min(count, jobs) - 1` helper blocks plus the calling thread, a lock-protected cursor over indices sorted by weight, and a `DispatchGroup` wait.
  - `init(count:qos:beforeJob:)` clamps `count` to `1...activeProcessorCount` (FR-017).
  - The `beforeJob` hook and `static let default`.
  - Make T034 pass.
- [X] T037 [US1] Wire the workers into the Claude Code reader:
  - `LogIndex.init` gains `workers: ScanWorkers = .default`, and phase 2 calls `workers.forEach(jobs:weight:body:)` with the unread bytes as weight instead of `DispatchQueue.concurrentPerform`.
  - In `Sources/UsageCore/Logs/SessionLogSource.swift`, `collect` runs `index.update(...)` through `workers.offload`, with `LogIndex` held in an `UncheckedSendableBox` whose doc comment states the exclusive access and how `scanning` enforces it.
  - Add `scanning`, `scanWaiters`, `resetPending` and an internal `isScanning()` (data-model.md "Source scan state"). A `collect` that starts while `scanning` is true waits until the running scan ends, and checks `scanning` again when it is resumed (a `while` loop, not an `if`), so of several waiting calls only one scans at a time. `resetForEarlierWindow()` during a scan only sets `resetPending`, which `collect` applies at its end, after taking the records, the stats and the log line.
  - Add the `workers:` init parameter.
  - Make T035 pass for this source.
- [X] T038 [US1] Split `CodexSessionSource.collect` (`Sources/UsageCore/Logs/CodexSessionSource.swift`) into three steps:
  - (1) On the actor, as today: walk the locations, decide which files need reading, collect read jobs in order.
  - (2) Read (`fm.contents(atPath:)`) and parse each job through `workers.offload` plus `forEach(jobs:weight:body:)`, with the file size as weight (largest first, FR-017).
  - (3) On the actor, apply the results in job order: `files` entries, `filesRead` per home, cannot-read issues and log lines in today's order. The retry and grown-retry bookkeeping is unchanged.
  - Resolve the parent lookup in older files in rounds through the workers before the auth modes are computed (research R6): the walk starts from the window's sessions, follows parents only from sessions without a plan marker, and stores each result under the parent id that named the file. `lookup(_:)` then reads only the window's sessions and `outsideSessions`, never a file, and `isPlan` stays as it is. Parent files are not counted in `parsed` or `lastScanFigures`.
  - Add a test to `Tests/UsageCoreTests/ScanConcurrencyTests.swift`, built with `CodexFixtures.install` and `setModificationDate` as the existing older-parent test in `CodexSessionSourceTests` is. A subagent session in the window has no plan marker; its parent lies in an older file without a plan marker, and its grandparent in an older file with one. `lastHints` shows the plan hint for the subagent, as today's recursion gives. The `beforeJob` calls number the window files read plus two (the parent round and the grandparent round), so no file was parsed on the actor.
  - Add `scanning`, `scanWaiters`, `resetPending`, `isScanning()` and the `workers:` init parameter, with the same waiting and reset rules as T037.
  - Make T035 pass for this source. `CodexSessionSourceTests` pass unchanged.
- [X] T039 [US1] Add `--workers <n>` to `Sources/UsageCore/Bench/ScanBench.swift` and `Sources/ScanBench/main.swift`, injecting `ScanWorkers(count: n)` into the source and the index. The report's `workers` line shows the count in effect.
- [X] T040 [US1] Run the comparison block for step D. Then run `WORKERS=2`, `3` and `4` warm for `READER=claude`, two runs each, and record the second of each.
  - Keep as default the smallest count that meets SC-001 warm (under 3 s) with SC-002 (at most 200% average). If none does, keep the one closest to both and note it.
  - Update `ScanWorkers.default` in `Sources/UsageCore/Logs/ScanWorkers.swift` if the choice differs, and adjust T034's default-count expectation with a comment citing the recorded rows.
  - Record all of it in `specs/039-faster-session-scan/BENCHMARK.md` (note `step D: workers`). Commit.

### Step E: Codex typed decoding (spec FR-016, FR-011, research R6)

- [X] T041 [P] [US1] Write `Tests/UsageCoreTests/CodexTypedLineTests.swift` for the lenient typed decoding:
  - A wrong-typed field reads as absent: a string where a number belongs, a number where a string belongs.
  - A token value at or above `maxTokenValue` is clamped, and negative or non-finite values read 0, as `Totals.init` does today.
  - `rate_limit_reached_type` present as `null` counts as not reached; present as a string counts as reached.
  - A missing `payload` skips the line.
  - Parent session fields are read as `parent(of:)` reads them today.
  - `CodexSessionParserTests` and `CodexLimitsTests` are not edited.
- [X] T042 [US1] Implement the typed decoding in `Sources/UsageCore/Logs/CodexSessionParser.swift`:
  - `CodexLine`, `CodexPayload`, `CodexTokenInfo`, `CodexTokenUsage`, `CodexRateLimits` and `CodexLimitWindowFields`, each with a custom `init(from:)` that decodes every key with `try?`.
  - One shared `JSONDecoder`.
  - `parse` and `latestLimitSnapshot` decode `CodexLine` instead of calling `JSONSerialization`. `Totals.init(_ usage: CodexTokenUsage)` and `limitSnapshot` take the typed values. `parent(of:)` and `nonEmpty` move to the typed fields.
  - No `[String: Any]` remains in the file.
  - Make T041 pass with the Codex suites unchanged.
- [X] T043 [US1] Run the comparison block for step E and record it in `specs/039-faster-session-scan/BENCHMARK.md` (note `step E: Codex typed`). Check SC-006: Codex CPU (user plus system) is at most half the baseline's. Commit.

**Checkpoint**: All parsing changes are in, each one measured and compared.

---

## Phase 6: Polish and cross-cutting concerns

- [X] T044 Run `make test` and `make test-release`; fix any failure at its cause.
- [X] T045 Add a "Result" section to `specs/039-faster-session-scan/BENCHMARK.md`:
  - The final warm figures against SC-001 (warm), SC-002, SC-003, SC-005 and SC-006, each marked met or missed with the numbers.
  - The digest comparison results.
  - The "Maintainer steps" list still open for the walkthrough: cold baseline and cold final run, the real-corpus comparison repeated by the maintainer, the incremental check in the app's log, and the responsiveness check.
  - If SC-001 or SC-002 is missed for a reason the bench attributes to parsing, note it for the maintainer's FR-020 decision.
- [X] T046 [P] Check every new or changed file under `Sources/` and `Tests/`:
  - Doc comments cite `spec 039 FR-0xx` or research `Rn`.
  - `rg -n '\x{2014}|\x{2013}' Sources Tests specs/039-faster-session-scan Makefile Package.swift` (em and en dash) finds nothing.
  - No `print` or debug output is left in `UsageCore`.
- [X] T047 [P] Remove the inbox entry `### parse-off-cooperative-pool` from `brainstorm/idea-inbox.md` (resolved by spec 039 FR-018). Leave `shared-codex-rollout-scan` in place.
- [X] T048 Final commit of the polish changes. Then confirm with `git status` that no file under `/tmp/agenttacho-bench/` or any real-corpus digest is tracked.

---

## Dependencies and execution order

- **Phase 1** (T001 to T005): T001 before T002. T003, T004 and T005 are independent of each other and of T001 and T002.
- **Phase 2, US3** (T006 to T017): the tests T006 to T009 come first, in parallel. T010 and T011 can run in parallel after them. T012 comes before T013 (`lastScanFigures` reads `linesVisited`). T014 needs T010 and T013. T015 needs T010, T011, T013 and T014. T015 comes before T016, and T016 before T017.
- **Phase 3, US2** (T018 to T021): needs T003 to T005 and T015 and T016. T018 and T019 can run in parallel. T018 and T020 come before T021, which generates the digests (including the T018 fixtures) that make T020 pass.
- **Phase 4, baseline** (T022, T023): needs Phases 2 and 3 committed. **Gate for Phase 5.**
- **Phase 5, US1**: the steps run in order B, C, D, E, because each step's comparison isolates its own change. Within a step, the tests marked [P] come first, then the implementation, then the measurement task.
- **Phase 6**: after T043.

## Parallel examples

```text
Phase 1:  T003 | T004 | T005   (alongside T001 -> T002)
US3:      T006 | T007 | T008 | T009   then   T010 | T011
US2:      T018 | T019
Step C:   T028 | T029   then   T030 | T031   then T032
Step D:   T034 | T035   then   T036 -> T037 -> T038 -> T039
```

## Implementation strategy

1. **Measure first (MVP of the process):** Phases 1 to 4 deliver the bench, the pinned records and the baseline. Without them no later claim can be checked.
2. **Biggest win first:** steps B (438 ms per 352 MB in the brainstorm's profile) and C (932 + 510 ms per 352 MB) remove most of the CPU time. Step D then turns CPU time into a quiet wall time. Step E is the Codex share.
3. **Stop after any step** whose comparison differs (stop rule). `BENCHMARK.md` keeps every step's numbers, so a partial result is still a measured one.
