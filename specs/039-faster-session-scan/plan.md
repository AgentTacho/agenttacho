# Implementation Plan: Faster Session Scan

**Branch**: `039-faster-session-scan` | **Date**: 2026-10-28 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/039-faster-session-scan/spec.md` (from brainstorm `brainstorm/39-faster-session-scan.md`, decision A: ripgrep's techniques in Swift)

## Summary

The first scan of the Claude Code session files is CPU-bound in three Foundation choices: one `Data` copy per line with element-wise indexing, `ISO8601DateFormatter` per record, and whole-line marker searches. This plan replaces them with an in-place `memchr` line walk over each file's buffer, a head-and-tail `memmem` classification with a whole-line fallback, and one fixed-layout timestamp parser shared with the Codex reader. The Codex reader also decodes into typed values instead of dictionaries. Both readers parse on a few utility-priority workers off their actors instead of `concurrentPerform` on every core. `JSONDecoder` stays for candidate lines.

Measurement comes first: a `scan-bench` executable (logic in `UsageCore/Bench`) runs the real refresh code path and reports wall, CPU, peak memory and disk bytes. It also writes a records digest for the old-versus-new comparison. The warm baseline is recorded in `BENCHMARK.md` before any parsing code changes, and every later step is measured with the same command.

## Technical Context

**Language/Version**: Swift 5.10 tools (language mode 5), Swift 6 compiler, macOS 14+

**Primary Dependencies**: Foundation (`JSONDecoder`, `ISO8601DateFormatter` as fallback), Darwin libc (`memchr`, `memmem`, `getrusage`, `proc_pid_rusage`), Dispatch (`DispatchQueue.global(qos:)`, `DispatchGroup`). No new package dependency, no new toolchain (FR-019).

**Storage**: none in the app. The bench writes its report to stdout and a digest only to a path the maintainer names. `BENCHMARK.md` lives in the spec directory and the fixture digests in `Tests/UsageCoreTests/Fixtures/digests/`.

**Testing**: Swift Testing through `make test`. `make test-release` covers the scripts.

**Target Platform**: macOS menu bar app (Apple silicon and Intel)

**Project Type**: desktop app (UsageCore library, thin SwiftUI layer, DemoMode) plus one maintainer executable target (`ScanBench`)

**Performance Goals**: SC-001 sets the first scan of about 2,300 files and 3.5 GB under 3 s wall, warm and cold. SC-002 caps the average CPU at 200%. SC-006 halves the Codex CPU time.

**Constraints**: the same records out (SC-004, FR-008 to FR-011). Read-only (constitution III). Peak memory no higher than the baseline (SC-003). Neither the actors nor the cooperative pool may be blocked while the scan runs (FR-018).

**Scale/Scope**: 5 changed UsageCore files and 7 new ones, 1 new executable target, 3 Makefile targets, new fixtures and digests, 10 new test suites. No UI change.

## Global Constraints

Every task inherits these (spec, constitution, AGENTS.md):

- Build and test only through the Makefile: `make test`, `make test-release`, `make bench-scan`, `make bench-compare`, `make bench-digests` (constitution IV).
- "The change MUST add no dependency and no build toolchain; it uses the platform's libraries only." (spec FR-019). `Package.swift` gains the `ScanBench` target and nothing else.
- Logic in UsageCore with tests first. `Sources/ScanBench/main.swift` only parses arguments and prints (constitution II). Doc comments cite `spec 039 FR-0xx` or research `Rn`.
- AgentTacho only reads agent files. The bench never writes under `~/.claude`, `~/.codex` or a configured session directory (FR-004, constitution III).
- The bench report and `BENCHMARK.md` hold no session line, write `~` for the home directory and name no user (FR-003).
- Fixtures use invented data only: account names such as `acc-max`, `acc-vertex` and `acc-gateway`, working directories under `/fixture/`, no real model output. No em dash or en dash in any file.
- **Order of work:** the bench, the digests and the warm baseline land before any change to line reading, classification, timestamps, workers or Codex decoding (FR-006). Every parsing step is measured afterwards with the same `SINCE`.
- No regression of the read-only guarantee, per-file offsets, complete lines only, CRLF tolerance, dedupe, the batch cap, or the re-read rules of specs 035, 037 and 038 (FR-010). `LogIndexTests`, `SessionProfileTests` and `CodexSessionParserTests` pass without changed expectations.

## Constitution Check

| Principle | Status |
|---|---|
| I. Issue first, specs recommended | Spec-driven: brainstorm 39, then spec 039. This is the maintainer's own request. |
| II. Test-first, logic in UsageCore | Line reader, classifier, timestamp parser, workers, resources, digest and bench logic live in UsageCore with failing tests first. `ScanBench/main.swift` is a thin argument wrapper. The app target is untouched. |
| III. Read-only, private by default | Agent files are still only read. The bench writes only to the maintainer's path and refuses agent directories. Committed fixtures and digests hold invented data. The real-corpus digest is never committed. No new network or credential access, so the README's privacy section is unchanged. |
| IV. One build entry point | `make bench-scan`, `make bench-compare` and `make bench-digests` wrap the bench. `make build` builds the new target with the package. `build-app.sh` bundles only `AgentTacho`, so the bench never ships. |
| V. Screenshots and website follow the UI | No visible UI change (see below). |

Re-check after design: no violation. The new executable target is a maintainer tool next to the app, not a second build path for the app (Complexity Tracking).

## Screenshots and website

No visible UI change: the feature changes how session files are read and adds a maintainer bench. The only user-facing text that changes is the diagnostic log's refresh line (`, cpu <seconds> s`), and no screenshot stem or website copy shows it. The demo scenario, the shots and the site are unchanged, and there is no card candidate.

## Project Structure

### Documentation (this feature)

```text
specs/039-faster-session-scan/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── bench-cli.md
├── BENCHMARK.md          # created with the baseline (tasks), appended per step
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Package.swift                              # + executableTarget ScanBench (product scan-bench), depends on UsageCore
Makefile                                   # + bench-scan, bench-compare, bench-digests
Sources/ScanBench/
└── main.swift                             # NEW: argument parsing, calls UsageCore.ScanBench, prints, exit codes
Sources/UsageCore/Diagnostics/
└── ProcessResources.swift                 # NEW: getrusage + proc_pid_rusage snapshot and delta (R2); also used by the FR-007 log lines
Sources/UsageCore/Bench/
├── RecordsDigest.swift                    # NEW: digest text, parse, compare (R9)
└── ScanBench.swift                        # NEW: options, validation, source construction, report (R8)
Sources/UsageCore/Logs/
├── ScanWorkers.swift                      # NEW: offload + bounded forEach at utility QoS (R7)
├── SessionLineReader.swift                # NEW: memchr line walk, complete-lines rule, CR trim (R3)
├── SessionLineClassifier.swift            # NEW: head/tail/full memmem classification (R4)
├── Timestamp.swift                        # NEW: ISO8601Timestamp fast path + Foundation fallback (R5)
├── LogIndex.swift                         # read unread bytes once, walk in place, classify, workers.forEach, linesVisited
├── SessionLogSource.swift                 # offload update, scanning/resetPending, cpu in log line, seams, lastScanFigures
├── SessionRecordParser.swift              # parseDate -> ISO8601Timestamp
├── CodexSessionParser.swift               # typed CodexLine/CodexPayload decoding, ISO8601Timestamp, line count overload
└── CodexSessionSource.swift               # decide / parse via workers / apply, scanning/resetPending, cpu, seams
Tests/UsageCoreTests/
├── TimestampTests.swift                   # NEW
├── SessionLineReaderTests.swift           # NEW
├── SessionLineClassifierTests.swift       # NEW
├── ScanEquivalenceTests.swift             # NEW: long line, incomplete tail, append boundary on today's code
├── ScanWorkersTests.swift                 # NEW
├── ScanConcurrencyTests.swift             # NEW: FR-018 source tests, waiting collect, deferred reset
├── CodexTypedLineTests.swift              # NEW: lenient typed decoding
├── ProcessResourcesTests.swift            # NEW
├── RecordsDigestTests.swift               # NEW
├── ScanBenchTests.swift                   # NEW: fixture digests (FR-008), validation errors
└── Fixtures/
    ├── scan/claude/projects/fixture-project/*.jsonl   # NEW tree: existing fixtures (cwd under /fixture/) + nested-type-key, timestamps, crlf, incomplete tail, shape line, non-UTF-8
    ├── scan/codex/sessions/2026/10/13/rollout-*.jsonl # NEW tree: copies of the Codex fixtures
    └── digests/{claude,codex}.digest + {claude,codex}-config.json  # NEW, generated by make bench-digests
```

**Structure Decision**: The single Swift package keeps its layout. The new `ScanBench` executable target holds only `main.swift`. Everything testable sits in `UsageCore/Bench`, `UsageCore/Diagnostics` and `UsageCore/Logs`.

## Design

### Phase A: measure first (FR-001 to FR-009)

1. `ProcessResources` (R2), `RecordsDigest` (R9) and `ScanBench` (R8) in UsageCore, test-first.
2. The two source seams (`scanTargets:` and `homes:`), `lastScanFigures`, and `LogIndexStats.linesVisited` counted in today's line loop. None of these changes how lines are read. The `workers:` parameter comes in phase D with `ScanWorkers`.
3. The `ScanBench` target and the Makefile targets. `SCAN_BENCH_COMMIT` comes from `git rev-parse --short HEAD`, with `-dirty` added for uncommitted changes.
4. FR-007: each source takes `ProcessResources.cpuSeconds()` at the start and end of `collect` and appends `, cpu %.1f s` to its existing line.
5. Scan fixture trees, fixture configurations, and fixture digests generated by `make bench-digests` from this unchanged code, plus `ScanBenchTests` that check them (FR-008).
6. **Baseline**: `make bench-scan` (Claude Code and Codex) with a fixed `SINCE`, warm, recorded in `BENCHMARK.md` with its commit. Baseline digests of the real corpus are written outside the repository. Cold runs are a maintainer step (FR-006).

### Phase B: one timestamp parser (FR-015)

`ISO8601Timestamp.parse` (R5) is table-tested against `ISO8601DateFormatter` at millisecond precision, then used by `SessionRecordParser` and `CodexSessionParser`. The bench and the digest comparison follow, and the results are recorded.

### Phase C: lines in place and classification (FR-012 to FR-014)

`SessionLineReader` and `SessionLineClassifier` (R3, R4) are tested first, including the nested-type-key, CRLF, incomplete-tail, non-UTF-8 and long-line cases. `LogIndex` phase 2 then reads the unread bytes once, walks lines in place, and copies only `.assistant` lines (into `parser.parse(data:)`) and `.shape` lines (into `SessionProfile.detect`). `consumed` and `total` keep their meaning. The bench and the digest comparison follow, and the results are recorded.

### Phase D: workers off the actors (FR-017, FR-018)

`ScanWorkers` (R7) is tested for order, bound, largest-first ordering, QoS, and that it does not block the caller. `LogIndex` phase 2 uses `workers.forEach`, and `SessionLogSource.collect` offloads `index.update`. The Codex source is split into decide, parse-via-workers and apply, and its parent lookup in older files runs on the workers in rounds, so no file is parsed on the actor (R6). `scanning` and `resetPending` are added to both sources. FR-018 tests use the `beforeJob` hook. The worker-count step measures 2, 3 and 4 workers, records them, and keeps the smallest count that meets SC-001 within SC-002.

### Phase E: Codex typed decoding (FR-016, FR-011)

`CodexLine`, `CodexPayload` and the token and limit types decode with lenient per-key `try?` (R6). `Totals.init(CodexTokenUsage)` and `limitSnapshot` move to the typed values. `CodexSessionParserTests` and `CodexLimitsTests` must pass unchanged. The bench and the digest comparison follow, and the results are recorded.

### Phase F: wrap-up

The full `make test` and `make test-release` runs, the final warm runs in `BENCHMARK.md`, and a note that the cold runs and the real-corpus comparison are maintainer steps for the walkthrough. Then a doc pass: the `docs/` and README mentions of the scan, if any, and the inbox entry `parse-off-cooperative-pool` removed as resolved by FR-018.

### Stop rule

If a phase's digest comparison shows a difference, the phase is not finished. The cause is fixed, or, if it is an old-code bug, handled under FR-009: fixed as its own change, with a fresh baseline taken afterwards. If phase E ends with the warm SC-001 or SC-002 missed for a reason the bench attributes to parsing, `BENCHMARK.md` records it and FR-020's follow-up decision goes to the maintainer. The field extractor is not built here.

## Risks

| Risk | Mitigation |
|---|---|
| Classification misses a line type whose top-level `type` key is in neither window | The whole-line fallback marks a line with any candidate marker `.undecided`, and `LogIndex` runs today's parse-then-detect on it, so it is decided exactly as today (R4). |
| A nested object holds a record-type marker (for example `{"type":"user"}` in a tool call's input) | The head and tail scans read only the depth-1 `type` member, so nested keys never decide (R4, FR-013). A fixture line pins this case. |
| A marker string inside a content string matches | Inside a JSON string the quotes are escaped, so `"type":"assistant"` cannot match there. `JSONDecoder` still checks `envelope.type == "assistant"`. |
| Live session files change between the baseline and later comparisons | The release binary of the baseline commit is kept and run back to back with the new one. Both digests are cut at the same `--until`, a few minutes in the past (contracts/bench-cli.md). |
| Fast timestamp path differs from Foundation on some form | It accepts only `...SS(.f{1,9})?Z` with range checks. Everything else falls back to Foundation. A table test covers 0, 1, 2, 3, 6 and 9 fraction digits, offsets and invalid dates. |
| Actor reentrancy during the offloaded scan | In the app, `RefreshCoordinator` is the only caller and serializes refreshes. The sources do not rely on it: a `collect` that arrives during a scan waits for it, and `resetPending` defers a reset to the end of `collect`. `ScanConcurrencyTests` cover both (R7). |
| Fixture digests differ between machines | `digest` mode leaves the app's imported price file out, and the fixture working directories sit under `/fixture/` (R8, R9). |
| Floating-point noise between the formatter's and the fast path's `Date` | The digest and `TimestampTests` round to the nearest millisecond instead of flooring (R5). |
| Utility QoS on efficiency cores makes the scan slower in wall time | The worker-count step measures it. The QoS is one constant, and the bench records the effect. |
| Memory: whole unread tail per file | Same as today (`readToEnd`). The per-line copies, which roughly doubled the batch's bytes, are gone, so the peak can only drop (SC-003). |

## Review Focus

Failure modes the spec implies without listing them, each pinned by a test in the owning task:

| Mode | Owning task |
|---|---|
| A second `collect` on the same source during an offloaded scan | T035 (waits, same records), T037, T038 |
| Two `collect` calls waiting for the same scan | T035 (a file added meanwhile is read once), T037 (`while scanning`) |
| A subagent whose parent and grandparent lie in files older than the window | T038 (same hint, parents read on the workers) |
| A higher-priority caller lifting the scan's QoS | T034 (`.userInitiated` caller, utility inside the job) |
| Zero jobs, as in most incremental Codex refreshes | T034 |
| A worker count above the core count | T034, T036 (clamped) |
| A line the scans cannot decide that holds both candidate markers | T029 (`.undecided`), T032 (parse, then detect) |
| A top-level `type` with a non-string value | T029 |
| A file that vanished between the scan and the read | T032 (zero bytes, as today) |
| A fraction whose fourth digit rounds differently than it truncates | T024 |
| A bench directory without `projects` or `sessions`, a missing digest for `compare` | T008 |
| A fixture digest generated on a machine with imported prices | T015, T020 (digest mode without imported prices) |

## Complexity Tracking

| Item | Why needed | Simpler alternative rejected because |
|---|---|---|
| New executable target `ScanBench` | FR-001 asks for a maintainer command over a real corpus with arguments, running the app's code path | A hidden app flag runs a GUI process with no stdout, and a benchmark test cannot take a directory argument (R1) |
| `@unchecked Sendable` box around `LogIndex` for the offload | `LogIndex` is a non-Sendable class owned by the actor. The offloaded update needs it on a dispatch thread while the actor is suspended. | Making `LogIndex` an actor would make every `LogIndexTests` call async and change the tests. Copying the index in and out would double its memory. |
