# Brainstorm: Faster Session Scan with ripgrep's Techniques

**Date:** 2026-10-28
**Status:** active

## Problem Framing

The first scan of all Claude Code session files takes 10 to 13 s at 400 to 450% CPU on the maintainer's Mac (M4 Pro, 14 cores). The diagnostic log of 2026-10-28 shows the shape of it: 11,197 files seen, 2,310 re-read (3.5 GB, the files whose modification date lies in the collection window), 9.2 s. The whole corpus is 11,206 files, 7.2 GB, 1.9 million lines, of which 644,000 hold a `usage` object. Incremental refreshes are fine (0.8 to 1.6 s for a few changed files); the cold scan after a start, a window change or an attribution change is what makes the Mac feel busy.

The inbox idea (`faster-session-scan`, from the spec 038 walkthrough) asked to measure first and then apply the techniques that make `rg` (ripgrep) fast. Measured on 2026-10-28, warm page cache:

- `rg -c '"usage"'` over the whole 7.2 GB corpus: 1.65 s wall, 147% CPU. The data can be scanned in under 2 s; the app is CPU-bound, not I/O-bound.
- A single-threaded stage benchmark over one 352 MB project folder (42 files, 93,036 lines, 17,084 assistant lines) that replays what `LogIndex.readCompleteLines`, `SessionRecordParser` and `SessionProfile.detect` do per line:

| Stage (352 MB) | App today | Floor measured |
|---|---|---|
| Read files, `FileHandle.readToEnd` (warm) | 113 ms | 74 ms |
| Split into per-line `Data` copies (`for i in complete.indices where complete[i] == 0x0A`) | 932 ms | 7 ms, `memchr` over the file buffer, no copies |
| Assistant marker, `Data.range(of:)` x2 over the whole line | 206 ms | `memmem` over the whole line is the same (216 ms); a bounded window is what helps |
| Shape marker, `Data.range(of:)` x2 over every non-assistant line | 304 ms | same |
| `JSONDecoder` of `Envelope` on assistant lines (57.8 MB) | 190 ms | keep; about 300 MB/s |
| `ISO8601DateFormatter` per record (two formatters tried) | 438 ms | 1 ms, fixed-layout parse of `YYYY-MM-DDTHH:MM:SS(.fff)Z`, identical results |
| `String(decoding:)` of each raw assistant line for attribution | 8 ms | - |

About 2.2 s of CPU per 352 MB becomes roughly 0.35 s, a 6x cut, before any change to the JSON decoding. The two biggest costs, per-line `Data` copies with element-wise indexing and Foundation's date formatter, have nothing to do with Swift as a language: they are Foundation API choices. The Codex parser already does the right thing for its lines (`CodexSessionParser.relevantLines`: `memchr` per line, `memmem` over a head window), but still decodes with `JSONSerialization` dictionaries (315 ms on the same 17,084 lines vs. 190 ms for `JSONDecoder`) and uses `ISO8601DateFormatter`.

Where the markers sit (5 largest files, 4,180 assistant lines): the top-level `"type":"assistant"` key is in the last 406 to 1,143 bytes of every assistant line (median 455), after the `message` object whose `content` makes up the bulk of the line. `"timestamp"` is in the last 341 to 1,078 bytes. The longest line in the folder is 1.8 MB. A tail-window search finds the type of almost every line; a full-line fallback keeps it correct when the key is elsewhere. Note that `message.model` and `message.id` are at the start of the line and `message.usage` near the end of `message`, so a later field extractor could work from head and tail windows alone; key order is Claude Code's choice, not a contract.

What ripgrep does that applies here (BurntSushi, "ripgrep is faster than {grep, ag, git grep, ucg, pt, sift}", and `grep-searcher`):

- Search whole buffers with SIMD `memchr`/`memmem`, never start and stop a search per line. Applies as: iterate lines in place over the file buffer and search bounded windows.
- Buffered reads into a reused buffer beat memory maps when there are many files (0.33 s vs. 1.6 s on the Linux tree); mmap wins only for a few large files. Applies as: keep reading files into one buffer each; the largest session file is 49 MB and the batch cap is 64 MB, so no mmap.
- Run the expensive matcher only on candidate lines found by the literal search. Applies as: `JSONDecoder` only after the window search said "assistant", shape detection only after it said "api-request-shape".
- Parallel search over a work queue of files with bounded threads. Applies as: a fixed worker count at utility QoS, largest files first.
- Line counting costs: ripgrep's line numbers double its time. Applies as: the index needs byte offsets, not line numbers, so count nothing per line.

Related inbox entries that touch the same code and are left in the inbox: `parse-off-cooperative-pool` (the parallel parse runs inside the actor on the cooperative pool; a bounded worker group bridged with a continuation would resolve it) and `shared-codex-rollout-scan` (Codex rollouts are enumerated and parsed twice per refresh).

## Approaches Considered

### A: ripgrep's techniques in Swift

- Iterate lines in place over each file's buffer with `memchr` (no per-line `Data`); keep the "complete lines only" rule and CRLF tolerance.
- Classify each line by a `memmem` search for the `"type":"..."` key over a bounded tail window, with a full-line search as fallback when the window holds no type key; decode only assistant lines, run shape detection only on shape lines.
- Keep `JSONDecoder` with the existing `Envelope` structs for the candidate lines: 190 ms per 352 MB, and the correctness anchor.
- One shared fixed-layout ISO 8601 parser for the forms Claude Code and Codex write, falling back to Foundation for anything else; used by both parsers.
- Codex: replace `JSONSerialization` dictionaries with targeted `Decodable` structs; keep its prefilter.
- Bounded parallelism: a fixed number of workers (for example half the performance cores, at most 4) at utility QoS, files sorted largest first so the tail of the batch balances; keep the 64 MB batch cap, which now bounds the buffers alone because the per-line copies are gone.
- Safety net: a differential test runs the current and the new line pipeline over the fixtures and, through a maintainer-only script, over the real session files, and requires identical record sets and values.
- Pros: no dependency, no toolchain change, every gain is measured, the logic stays in `UsageCore` with tests. Cons: unsafe byte code needs care (bounds, non-UTF-8 bytes, the 1.8 MB line); about 2x short of ripgrep's raw throughput, which is far inside the target.

### B: A plus a hand-written field extractor

- Skip `JSONDecoder` on candidate lines and pull `message.model`, `message.id`, `message.usage`, `requestId`, `timestamp`, `cwd` and `sessionId` out of head and tail windows directly.
- Pros: perhaps 2x on the decode stage, which after A is the largest remaining one. Cons: a second JSON reader to keep right (string escapes, a `"usage"` text inside content strings, key order changes across Claude Code versions) for about half a second of wall time on a cold scan.

### C: A Rust scanning library linked into the app

- Use ripgrep's own crates (`memchr`, `grep-searcher`, `ignore`, `serde_json` or `simd-json`) behind a C header, built as a static library into a SwiftPM binary target.
- Pros: the fastest raw scan, the real SIMD searchers and work-stealing walker. Cons: cargo and rustup in the local build and the release workflow, universal arm64 and x86_64 builds, an FFI boundary with its own ownership rules, a second language in a project whose constitution puts testable logic in `UsageCore`. The benchmark shows the slowness comes from Foundation API choices, not from Swift; the permanent cost buys a fraction of what A gets for free.

## Decision

**A now, B as a measured follow-up.** Rust (C) is parked: not needed for the target, and the toolchain and release costs are permanent. B is taken up only if the measured first scan misses the target after A, and then with its own differential test.

Target chosen: **fast and quiet**. The first scan of the maintainer's corpus (about 3.5 GB in the window, 2,300 files) finishes in under 3 s wall at well under 200% CPU on average, by running the parse on a bounded number of workers at utility QoS. Incremental refreshes stay as fast or get faster.

Scope: the Claude Code session reader (`LogIndex`, `SessionRecordParser`, `SessionProfile`) and the Codex rollout reader (`CodexSessionParser`). OpenCode reads SQLite and is out of scope.

## Measurement Protocol

Baseline first, then the same instrument after every step, so the improvement is a measured number and not a feeling. The brainstorm's figures (9.22 s wall from the log, 400 to 450% CPU observed, the per-stage benchmark above) are indicative; the spec's first task takes the real baseline before any parsing code changes.

- One instrument for before and after: a maintainer-only bench command over a session directory (the real `~/.claude` corpus or a fixture tree) that runs the same code path as a refresh (scan, read, parse, attribute, merge) with an empty index, and reports per run:
  - wall time and CPU time (user and system), so the CPU percentage is derived, not eyeballed;
  - peak memory (maximum resident set size, and the delta over the process's starting footprint);
  - disk I/O: physical bytes read, so a cold run shows what came from disk; `proc_pid_rusage` with `RUSAGE_INFO_V4` has `ri_diskio_bytesread`, and `/usr/bin/time -l` gives the maximum RSS as a cross-check;
  - files seen, files read, bytes read and records, as the stats line does today.
- Two conditions each time: warm page cache (run twice, report the second) and cold cache (after a `purge`, or a fresh reboot when `purge` is unavailable), since the cold start is the complaint.
- The corpus is named in the report (file count, bytes, lines), so numbers from different days are comparable; a fixture tree with a few large files gives a reproducible small case for CI, the real corpus gives the number that matters.
- The baseline run is recorded in the spec (a table in `research.md` or a `BENCHMARK.md` next to it) and every later run is appended with the commit it measured.
- Success is judged against the target on the real corpus: under 3 s wall for the cold-cache first scan at well under 200% average CPU, and no higher peak memory than the baseline. A step that regresses any of the three is not merged on wall time alone.
- The refresh stats line in the diagnostic log gains CPU seconds (and, if cheap, disk bytes read), so a regression in a later release is visible to users and in bug reports without the bench command.

## Key Requirements

- Baseline before, same instrument after: the bench command of the measurement protocol exists and the baseline is recorded before any parsing code changes; every step is measured with it (wall, CPU, peak memory, disk bytes, warm and cold).
- Same records out: over the fixtures and over real session files, the new pipeline yields the same `RawUsageRecord` set and values as the current one (differential test; a maintainer script for the real corpus).
- Read-only, the per-file parsed offsets, the "complete lines only" rule, CRLF tolerance, dedupe and the re-read rules of specs 035, 037 and 038 are unchanged.
- No per-line copies: lines are visited in place over the file buffer; peak memory is bounded by the batch cap and lower than today.
- Line classification uses a bounded window search with a full-line fallback, so a line whose type key sits elsewhere is still classified right.
- Shape detection and JSON decoding run only on lines the classification selected.
- One shared ISO 8601 parser for both readers, equal to Foundation's result on the forms the agents write, with a Foundation fallback for other forms.
- The Codex parser decodes with targeted `Decodable` structs; its existing tests pass unchanged.
- Parallel parsing uses a bounded worker count at utility QoS, largest files first; the actor is not blocked on the cooperative pool while the workers run.
- No new dependency and no new build toolchain.
- The refresh stats line makes regressions visible: elapsed time is there, CPU seconds join it.

## Open Questions

- Worker count and QoS: utility or background, and whether the first scan after a start uses a different setting than a refresh.
- Tail-window size for the type key, and the fallback behavior on very long lines (1.8 MB seen).
- Whether files above a size threshold are read in chunks rather than whole, given the 49 MB maximum and the 64 MB batch cap.
- How much of the 10 to 13 s cold start is disk I/O: the benchmark ran on a warm page cache; the baseline's cold run answers it.
- Where the bench command lives (a `make` target over a hidden CLI flag of the app, a separate executable target, or a test marked as a benchmark) and how a cold cache is produced reliably on the maintainer's Mac.
- Whether phase 3 (sequential attribution, pricing, dedupe, including spec 038 regex rules per record) needs its own measurement and bound.
- The maintainer script for the real-corpus differential test: a `make` target, its location, and what it prints.
- Which ISO 8601 forms the fast parser accepts and which fall back to Foundation (offsets such as `+02:00`, no fractional seconds, Codex's forms).
- Whether `SessionRecordParser.parse(line: String)` stays as the test entry point and what the byte-level API looks like for the index.
- Whether `parse-off-cooperative-pool` and `shared-codex-rollout-scan` are folded into the spec or stay in the inbox.
