# Contract: Bench Command, Makefile Targets, Digest and Record Formats

## Makefile targets (constitution IV)

```
make bench-scan [READER=claude|codex] [DIR=<session directory>] [CONFIG=<file>] [SINCE=<ISO date>] [UNTIL=<ISO date>] [DIGEST=<file>] [WORKERS=<n>] [BENCH_BIN=<binary>]
make bench-compare A=<digest> B=<digest>
make bench-digests
```

- `bench-scan` builds `scan-bench` in release configuration and runs it with `SCAN_BENCH_COMMIT` set to `git rev-parse --short HEAD` plus `-dirty` when the tree has changes. `READER` defaults to `claude`. Without `DIR` the bench runs over the configuration's directories, as the app does.
- `BENCH_BIN` runs a saved binary instead of building, for example the release binary of the baseline commit copied aside. `SCAN_BENCH_COMMIT` is then `baseline-binary`, unless the variable is given explicitly.
- `UNTIL` limits the digest to records stamped before that instant (the scan itself is unchanged). The comparison step runs the baseline binary and the new one back to back with the same `SINCE` and `UNTIL`, so session files written in between do not show up as differences.
- `bench-compare` runs `scan-bench compare A B`.
- `bench-digests` regenerates `Tests/UsageCoreTests/Fixtures/digests/*.digest` from the fixture trees with their committed configurations and the fixed window start `2026-10-01T00:00:00Z`. It is the only way the committed digests change (spec FR-008).

## `scan-bench` command line

```
scan-bench run --reader claude|codex [--dir <path>] [--config <file>] [--since <ISO date>] [--until <ISO date>] [--digest <file>] [--workers <n>]
scan-bench compare <digest-a> <digest-b>
scan-bench digest --reader claude|codex --dir <path> --config <file> --since <ISO date> --out <file>
```

`--workers` is accepted only by binaries that have `ScanWorkers` (phase D on). An older binary rejects it with exit code 2. A value above the machine's core count is clamped to it.

`run` prices with the built-in table, the app's imported price file and the configuration's overrides, as the app does. `digest` leaves the imported price file out (built-in prices and the configuration's overrides only), so the committed fixture digests are the same on every machine (research R8).

`run` always performs a second `collect` on the same source right after the first and reports it on a `second refresh` line (`wall`, `cpu`, `files read`). The first `collect` starts with an empty index; the second reads only the files that changed in between, which on the maintainer's Mac are the few live session files. This is the incremental figure for SC-005. The digest and the figures above it are taken from the first `collect`.

```
second refresh wall 0.412 s   cpu 0.6 s   files read 3
```

Exit codes: 0 success (for `compare`: identical); 1 `compare` found differences; 2 bad arguments, unreadable directory, a directory without `projects` (Claude Code) or `sessions` (Codex), configuration file that cannot be read or does not validate, digest path under an agents' directory, or a missing digest file for `compare`. Error text goes to stderr, one line, naming the path with `~`.

## Report (stdout of `run`)

```
scan-bench 1  commit <short sha>  reader claude
directory      ~/.claude
config         ~/.config/agenttacho/config.json
window start   2026-10-01T00:00:00Z
files seen     11197   files read 2310   bytes read 3513654740   lines 1911272   records 85796
wall           9.220 s
cpu            user 34.1 s   system 3.9 s   average 412%
peak memory    footprint 812 MB   rss 905 MB
disk read      3351 MB
workers        3
```

Numbers are examples. No line of a session file appears in the report (spec FR-003). The home directory is written as `~`.

## Digest file

```
digest 1
config ~/.config/agenttacho/config.json
window-start 2026-10-01T00:00:00Z
directory ~/.claude
claudeCode	msg:msg_01AB	2026-10-14T19:44:01.080Z	claude-sonnet-5-5	claude-sonnet-5-5	12	340	0	0	18000	0	/fixture/proj-alpha	acc-max	0.0123
...
```

Columns after the header, tab-separated: harness, key, timestamp (rounded to the nearest millisecond, `Z`), model, canonical model, input, output, cache write 5m, cache write 1h, cache read, reasoning, project root, account id, cost. Lines sorted by harness, key, timestamp, model. Empty text for nil fields. Codex keys carry the session id (`codex:<session id>:<total>`). The digest of the real corpus holds project paths and session ids, so it is never committed and never written under `~/.claude` or `~/.codex` (spec FR-004). `compare` compares the record lines; differing header lines are printed as notes only.

## `compare` output

```
identical: 85796 records
```

or

```
different: 85796 records in A, 85794 in B
only in A (2 shown of 2):
  claudeCode	msg:...	...
only in B (0 shown of 0):
```

Up to 20 lines per side.

## Diagnostic log lines (spec FR-007)

Claude Code session source, today:

```
directories read 3, files seen 11197, re-read 2310 (3513654740 bytes), records since collection start 85796, profile named 210, none 2100, 9.220 s
```

becomes

```
directories read 3, files seen 11197, re-read 2310 (3513654740 bytes), records since collection start 85796, profile named 210, none 2100, 9.220 s, cpu 38.0 s
```

Codex session source, today:

```
2 home(s) read, 41 session(s), 1203 record(s) since collection start, 41 file(s) parsed, 0.412 s
```

becomes

```
2 home(s) read, 41 session(s), 1203 record(s) since collection start, 41 file(s) parsed, 0.412 s, cpu 0.5 s
```

`cpu` is the process's CPU time (user plus system, `getrusage`) consumed between the start and the end of that refresh, with one decimal.

## Benchmark record (`specs/039-faster-session-scan/BENCHMARK.md`)

A Markdown table with the columns of data-model.md "Benchmark record row", one row per run, newest last, followed by a "Digest comparisons" list (`<commit> vs baseline <commit>: identical, N records` or the difference counts) and the protocol (warm: run twice, keep the second; cold: `sudo purge`, run once; cold is confirmed by disk MB read close to bytes read). Paths use `~`; no user name appears (spec FR-003).

## Source initializer seams (bench only)

```swift
SessionLogSource(paths:log:builtInPrices:importedPrices:scanner:index:fileSystem:workers: ScanWorkers = .default, scanTargets: [ScanTarget]? = nil)
CodexSessionSource(paths:log:builtInPrices:importedPrices:workers: ScanWorkers = .default, homes: [String]? = nil)
```

`scanTargets:` and `homes:` arrive in phase A (T013); `workers:` arrives in phase D (T037, T038), since `ScanWorkers` does not exist before. When set, the targets or homes replace the configuration's directories for the scan of that source only; profile candidates, attribution and pricing still come from the configuration. The app never passes them. `workers` is injected by the bench (`--workers`) and by tests (the `beforeJob` hook); the app uses the default.
