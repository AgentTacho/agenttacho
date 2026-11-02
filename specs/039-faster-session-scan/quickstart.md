# Quickstart: Faster Session Scan

How to prove the feature works. Commands run from the repository root (or the feature worktree). Build and test only through the Makefile.

## Prerequisites

- macOS 14 or later, Command Line Tools with the macOS 26 SDK next to the 27 one (the Makefile picks it).
- For the real-corpus figures: the maintainer's `~/.claude` (about 11,000 session files) and `~/.codex`; for the fixtures nothing but the repository.
- `sudo purge` for the cold-cache runs (administrator password); optional.

## 1. Tests

```
make test
```

Expected: the whole suite passes, including the new `TimestampTests`, `SessionLineReaderTests`, `SessionLineClassifierTests`, `ScanEquivalenceTests`, `ScanWorkersTests`, `ScanConcurrencyTests`, `CodexTypedLineTests`, `ProcessResourcesTests`, `RecordsDigestTests` and `ScanBenchTests` (fixture digests, spec FR-008), and the unchanged `CodexSessionParserTests` (spec FR-011, SC-008).

## 2. Baseline, before any parsing change

On the commit that adds the bench and nothing else. Use one fixed window start for every run of this feature, so runs on different days cover the same records (the example uses the start of the maintainer's monthly window):

```
export SINCE=2026-10-01T00:00:00Z
make bench-scan SINCE=$SINCE                       # Claude Code reader, warms the cache
make bench-scan SINCE=$SINCE                       # second warm run, this one is recorded
make bench-scan READER=codex SINCE=$SINCE          # twice as well
make bench-scan READER=codex SINCE=$SINCE
export BENCH=$(mktemp -d -t agenttacho-bench)     # private to the user (mode 700); the digests hold project paths
cp .build/release/scan-bench $BENCH/scan-bench-baseline
cp -R .build/release/agenttacho_UsageCore.bundle $BENCH/   # the built-in prices; the copied binary traps without it
```

Expected: a report as in contracts/bench-cli.md; figures recorded as the `baseline` rows of `specs/039-faster-session-scan/BENCHMARK.md` (spec FR-006). The copied binary is the old code for every later comparison: session files keep growing while the work goes on, so each comparison runs the baseline binary and the new one back to back with the same `SINCE` and `UNTIL`.

Cold baseline (maintainer step):

```
sudo purge && make bench-scan
```

Expected: `disk read` close to `bytes read`; recorded as the cold baseline row.

## 3. After the change

```
make bench-scan SINCE=$SINCE                       # twice, record the second
make bench-scan READER=codex SINCE=$SINCE          # twice, record the second
make bench-scan SINCE=$SINCE WORKERS=2             # worker count step (research R7): 2, 3, 4
make bench-scan SINCE=$SINCE WORKERS=4
export UNTIL=$(date -u -v-10M +%Y-%m-%dT%H:%M:%SZ)   # ten minutes ago: no message still being written
make bench-scan SINCE=$SINCE UNTIL=$UNTIL BENCH_BIN=$BENCH/scan-bench-baseline DIGEST=$BENCH/old-claude.digest
make bench-scan SINCE=$SINCE UNTIL=$UNTIL DIGEST=$BENCH/new-claude.digest
make bench-compare A=$BENCH/old-claude.digest B=$BENCH/new-claude.digest
make bench-scan READER=codex SINCE=$SINCE UNTIL=$UNTIL BENCH_BIN=$BENCH/scan-bench-baseline DIGEST=$BENCH/old-codex.digest
make bench-scan READER=codex SINCE=$SINCE UNTIL=$UNTIL DIGEST=$BENCH/new-codex.digest
make bench-compare A=$BENCH/old-codex.digest B=$BENCH/new-codex.digest
```

Expected:

- Claude Code reader: wall under 3 s, average CPU at most 200%, peak footprint not above the baseline (SC-001, SC-002, SC-003).
- Codex reader: CPU user plus system at most half the baseline (SC-006).
- Both comparisons print `identical` (SC-004).
- Rows appended to BENCHMARK.md with the commit; the comparison results listed under "Digest comparisons" (SC-007).

Cold run (maintainer step): `sudo purge && make bench-scan`, wall under 3 s; recorded as a cold row.

## 4. Incremental refresh (SC-005)

The bench's `second refresh` line (contracts/bench-cli.md) is the automated figure: every warm run records it next to the first scan, and `BENCHMARK.md` compares it with the baseline's. The bench's index lives only for the run, so the maintainer also checks the app with its real index (maintainer step): run the app before and after the change, wait for two scheduled refreshes with a few changed session files, and compare the `... s, cpu ... s` of the refresh lines (`~/Library/Logs/AgentTacho/`). Expected: not slower than before.

## 5. Responsiveness (spec FR-018, scenario 3 of User Story 1)

Start the app with an empty index (first start, or after changing an account's directory so the index resets), open the dropdown during the first scan. Expected: the dropdown opens and the Codex and subscription sources' log lines appear while the session scan is still running. The automated check is `ScanConcurrencyTests` (a second source's `collect` and the held source's `isScanning()` complete while the workers are blocked).

## 6. Edge cases worth a look

- `Tests/UsageCoreTests/Fixtures/scan/claude/projects/fixture-project/nested-type-key.jsonl`: an assistant line whose head window holds only a content block's `type`, and one whose `type` sits outside both windows; the tests assert both are parsed as before.
- `Tests/UsageCoreTests/Fixtures/scan/claude/projects/fixture-project/timestamps.jsonl`: one record per timestamp form (no fraction, 1, 2, 3, 6 and 9 fractional digits, offset); `TimestampTests` compares the fast path with `ISO8601DateFormatter`, both rounded to the nearest millisecond.
- `make bench-scan DIR=/nonexistent` exits 2 with one error line; `make bench-scan CONFIG=/tmp/broken.json` exits 2 and names the file; `make bench-compare A=/missing B=/missing` exits 2.
- `make bench-scan DIGEST=~/.claude/x.digest` exits 2 (never writes under the agents' directories).
