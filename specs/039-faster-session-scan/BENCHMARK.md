# Benchmark Record: Faster Session Scan

The measured figures of spec 039 (FR-006, SC-007): the baseline on the unchanged parsing code, then one block per parsing step, each with its commit. Every run uses the same window start, so runs on different days cover the same records.

- **Window start**: `SINCE=2026-10-01T00:00:00Z`
- **Configuration**: the app's, `~/.config/agenttacho/config.json`, read only (the bench refuses to run when it is missing, and never creates one)
- **Corpus**: the directories that configuration names, as the app reads them: 3 Claude Code directories and 2 Codex homes (with `~`, names of the folders left out)
- **Machine**: the maintainer's Mac, Apple M4 Pro (10 performance and 4 efficiency cores), 48 GB

## Protocol

From contracts/bench-cli.md and research R10.

- **Warm**: run the bench twice in a row and record the second run.
- **Cold**: `sudo purge`, then run the bench once. A cold run is recognized by `disk read` close to `bytes read`. Cold runs are maintainer steps (see below).
- **Commit**: `make bench-scan` builds `scan-bench` from the checkout and names its commit, with `-dirty` when the tree has uncommitted changes; a saved binary run through `BENCH_BIN` is named `baseline-binary`. A step is measured before it is committed, so its rows first carry the build label (`<parent>-dirty`); the next commit replaces it with the step's own commit and keeps the build label in parentheses.
- **Bench files**: the saved baseline binary and the digests live in a scratch directory outside the repository, written `$BENCH` below. A digest of the real corpus holds project paths and session ids, so it is never committed.

### Comparison block

Run at the end of each parsing step (tasks.md "Common steps"):

1. `make test` passes, including the fixture digests (`ScanBenchTests`), which are never edited to make a test pass.
2. Set `UNTIL` to ten minutes ago (`date -u -v-10M +%Y-%m-%dT%H:%M:%SZ`). Then for `READER=claude` and `READER=codex`, run the baseline binary and the new build back to back with the same `SINCE` and `UNTIL`:

   ```
   make bench-scan READER=$READER SINCE=$SINCE UNTIL=$UNTIL BENCH_BIN=$BENCH/scan-bench-baseline DIGEST=$BENCH/old-$READER.digest
   make bench-scan READER=$READER SINCE=$SINCE UNTIL=$UNTIL DIGEST=$BENCH/new-$READER.digest
   make bench-compare A=$BENCH/old-$READER.digest B=$BENCH/new-$READER.digest
   ```

   `make bench-compare` must print `identical`.
3. Run the new build twice per reader without `DIGEST` and record the second run of each below, with the step, the second-refresh figures and the comparison result.
4. Commit the step, its tests and these rows together.

**Stop rule** (plan): a comparison that differs means the step is not done. An old-code bug is fixed as its own commit first (spec FR-009), then the baseline binary and the baseline rows are taken again from that fix.

## Runs

Newest last. Sizes in MB are 1,048,576 bytes. `second refresh` is the bench's second `collect` right after the first: wall, CPU and files read (SC-005).

| date | commit | condition | reader | directory | config | window start | files seen | files read | bytes read | lines | records | wall s | cpu user s | cpu sys s | avg cpu % | peak footprint MB | disk MB read | workers | second refresh | note |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-10-28 | `aff144f` | warm | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11227 | 2340 | 3556009824 | 801082 | 86753 | 8.647 | 24.3 | 8.0 | 373 | 752 | 3323 | all 14 cores (`concurrentPerform`) | 0.769 s, cpu 0.8 s, 0 files | baseline |
| 2026-10-28 | `aff144f` | warm | codex | configured (2) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 559 | 398 | 266687522 | 54527 | 5629 | 0.469 | 0.4 | 0.0 | 100 | 89 | 0 | 1 (on the source's actor) | 0.012 s, cpu 0.0 s, 0 files | baseline |
| 2026-10-28 | `baseline-binary` | digest run | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11228 | 2341 | 3557896645 | 801573 | 86795 | 8.903 | 23.6 | 7.6 | 350 | 673 | 3366 | all 14 cores (`concurrentPerform`) | 0.794 s, cpu 0.8 s, 0 files | step B block: the old code in the same session, right before the new |
| 2026-10-28 | `6734afb` (built as `cdb1bfe-dirty`) | digest run | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11228 | 2341 | 3557896645 | 801573 | 86795 | 5.526 | 15.8 | 1.8 | 317 | 720 | 3024 | all 14 cores (`concurrentPerform`) | 0.802 s, cpu 0.8 s, 0 files | step B block: the new code right after the old |
| 2026-10-28 | `6734afb` (built as `cdb1bfe-dirty`) | warm | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11228 | 2341 | 3557896645 | 801573 | 86795 | 5.307 | 16.1 | 1.3 | 328 | 661 | 323 | all 14 cores (`concurrentPerform`) | 0.814 s, cpu 0.8 s, 0 files | step B: timestamps |
| 2026-10-28 | `6734afb` (built as `cdb1bfe-dirty`) | warm | codex | configured (2) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 559 | 398 | 267132735 | 54702 | 5652 | 0.225 | 0.2 | 0.0 | 99 | 89 | 0 | 1 (on the source's actor) | 0.012 s, cpu 0.0 s, 0 files | step B: timestamps |
| 2026-10-28 | `baseline-binary` | digest run | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11229 | 2342 | 3560699256 | 802290 | 86870 | 9.967 | 24.1 | 7.7 | 320 | 651 | 3395 | all 14 cores (`concurrentPerform`) | 0.813 s, cpu 0.8 s, 0 files | step C block: the old code in the same session, right before the new |
| 2026-10-28 | `71f7a05` (built as `6734afb-dirty`) | digest run | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11229 | 2342 | 3560709802 | 802295 | 86870 | 3.490 | 5.7 | 1.6 | 210 | 836 | 3173 | all 14 cores (`concurrentPerform`) | 0.800 s, cpu 0.8 s, 0 files | step C block: the new code right after the old |
| 2026-10-28 | `71f7a05` (built as `6734afb-dirty`) | warm | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11229 | 2342 | 3560833355 | 802373 | 86879 | 3.316 | 5.9 | 1.7 | 230 | 709 | 3317 | all 14 cores (`concurrentPerform`) | 0.775 s, cpu 0.8 s, 0 files | step C: lines in place |
| 2026-10-28 | `71f7a05` (built as `6734afb-dirty`) | warm | codex | configured (2) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 559 | 398 | 268087482 | 55038 | 5690 | 0.228 | 0.2 | 0.0 | 100 | 89 | 0 | 1 (on the source's actor) | 0.011 s, cpu 0.0 s, 0 files | step C: lines in place (no Codex change) |
| 2026-10-28 | `71f7a05-dirty` (never committed) | digest run | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11230 | 2343 | 3562866837 | 802913 | 86917 | 4.196 | 5.1 | 1.3 | 153 | 1512 | 3318 | 3 (utility) | 0.823 s, cpu 0.8 s, 0 files | step D, first block, before the per-job autorelease pools: footprint doubled; not kept |
| 2026-10-28 | `baseline-binary` | digest run | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11230 | 2343 | 3562951453 | 802939 | 86919 | 8.245 | 23.8 | 7.7 | 382 | 781 | 3318 | all 14 cores (`concurrentPerform`) | 0.779 s, cpu 0.8 s, 0 files | step D block: the old code in the same session, right before the new |
| 2026-10-28 | `8cec6f4` (built as `71f7a05-dirty`) | digest run | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11230 | 2343 | 3562951453 | 802939 | 86919 | 4.320 | 5.3 | 1.2 | 151 | 318 | 3318 | 3 (utility) | 0.783 s, cpu 0.8 s, 0 files | step D block: the new code right after the old |
| 2026-10-28 | `8cec6f4` (built as `71f7a05-dirty`) | warm | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11230 | 2343 | 3563338450 | 802994 | 86922 | 4.062 | 5.0 | 1.2 | 153 | 281 | 3318 | 3 (utility) | 0.764 s, cpu 0.8 s, 0 files | step D: workers |
| 2026-10-28 | `8cec6f4` (built as `71f7a05-dirty`) | warm | codex | configured (2) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 559 | 398 | 268524050 | 55206 | 5712 | 0.179 | 0.2 | 0.1 | 150 | 87 | 179 | 3 (utility) | 0.011 s, cpu 0.0 s, 0 files | step D: workers |
| 2026-10-28 | `8cec6f4` (built as `71f7a05-dirty`) | warm | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11230 | 2343 | 3563384639 | 803019 | 86924 | 5.019 | 5.1 | 1.2 | 126 | 297 | 3318 | 2 (utility) | 0.800 s, cpu 0.8 s, 0 files | step D worker count: `WORKERS=2` |
| 2026-10-28 | `8cec6f4` (built as `71f7a05-dirty`) | warm | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11230 | 2343 | 3563387331 | 803022 | 86924 | 4.097 | 5.2 | 1.2 | 157 | 295 | 3320 | 3 (utility) | 0.799 s, cpu 0.8 s, 0 files | step D worker count: `WORKERS=3` |
| 2026-10-28 | `8cec6f4` (built as `71f7a05-dirty`) | warm | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11230 | 2343 | 3563403014 | 803027 | 86925 | 3.783 | 5.2 | 1.3 | 171 | 304 | 3319 | 4 (utility) | 0.802 s, cpu 0.8 s, 0 files | step D worker count: `WORKERS=4`, kept as the default |
| 2026-10-28 | `8cec6f4` (built as `71f7a05-dirty`) | warm | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11230 | 2343 | 3563403014 | 803027 | 86925 | 3.540 | 5.4 | 1.3 | 189 | 291 | 3320 | 6 (utility) | 0.771 s, cpu 0.8 s, 0 files | step D worker count: `WORKERS=6`, for information |
| 2026-10-28 | `8cec6f4` (built as `71f7a05-dirty`) | warm | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11230 | 2343 | 3563454523 | 803051 | 86927 | 2.744 | 5.9 | 1.0 | 252 | 295 | 22 | 8 (utility) | 0.795 s, cpu 0.8 s, 0 files | step D worker count: `WORKERS=8`, for information; the only run whose corpus was in the page cache |
| 2026-10-28 | `8cec6f4` (built as `71f7a05-dirty`) | warm | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11230 | 2343 | 3563477247 | 803061 | 86928 | 3.598 | 5.5 | 1.4 | 193 | 322 | 3312 | 8 (utility) | 0.764 s, cpu 0.8 s, 0 files | step D worker count: `WORKERS=8` again, read from disk |
| 2026-10-28 | `baseline-binary` | digest run | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11230 | 2343 | 3564069823 | 803248 | 86945 | 8.727 | 24.4 | 7.8 | 369 | 814 | 3318 | all 14 cores (`concurrentPerform`) | 0.817 s, cpu 0.8 s, 0 files | step E block: the old code in the same session, right before the new |
| 2026-10-28 | `273d987` (built as `8cec6f4-dirty`) | digest run | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11230 | 2343 | 3564069823 | 803248 | 86945 | 3.817 | 5.4 | 1.3 | 174 | 307 | 2810 | 4 (utility) | 0.813 s, cpu 0.8 s, 1 file | step E block: the new code right after the old |
| 2026-10-28 | `273d987` (built as `8cec6f4-dirty`) | warm | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11230 | 2343 | 3564108271 | 803261 | 86946 | 4.047 | 5.4 | 1.4 | 167 | 334 | 3312 | 4 (utility) | 0.801 s, cpu 0.8 s, 0 files | step E: Codex typed (no Claude Code change); final |
| 2026-10-28 | `baseline-binary` | digest run | codex | configured (2) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 559 | 398 | 269052830 | 55380 | 5728 | 0.689 | 0.4 | 0.1 | 74 | 95 | 248 | 1 (on the source's actor) | 0.011 s, cpu 0.0 s, 0 files | step E block: the old code in the same session, right before the new |
| 2026-10-28 | `273d987` (built as `8cec6f4-dirty`) | digest run | codex | configured (2) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 559 | 398 | 269052830 | 55380 | 5728 | 0.104 | 0.2 | 0.0 | 253 | 96 | 0 | 4 (utility) | 0.012 s, cpu 0.0 s, 0 files | step E block: the new code right after the old |
| 2026-10-28 | `273d987` (built as `8cec6f4-dirty`) | warm | codex | configured (2) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 559 | 398 | 269087149 | 55397 | 5729 | 0.103 | 0.2 | 0.0 | 253 | 96 | 0 | 4 (utility) | 0.012 s, cpu 0.0 s, 0 files | step E: Codex typed; final |
| 2026-10-28 | `273d987` (built as `273d987-dirty`, tasks.md only) | warm, cached | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11230 | 2343 | 3566260762 | 803531 | 86970 | 2.910 | 5.2 | 0.9 | 210 | 278 | 0 | 4 (utility) | 0.752 s, cpu 0.8 s, 0 files | final: the corpus in the page cache |
| 2026-10-28 | `273d987` (built as `273d987-dirty`, tasks.md only) | warm | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11230 | 2343 | 3566282744 | 803541 | 86971 | 3.117 | 5.1 | 0.9 | 194 | 285 | 1137 | 4 (utility) | 0.735 s, cpu 0.7 s, 0 files | final: a third of the corpus from disk |
| 2026-10-28 | `273d987` (built as `273d987-dirty`, tasks.md only) | warm | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11230 | 2343 | 3566282744 | 803541 | 86971 | 3.263 | 5.2 | 1.0 | 192 | 305 | 556 | 4 (utility) | 0.765 s, cpu 0.8 s, 0 files | final |
| 2026-10-28 | `273d987` (built as `273d987-dirty`, tasks.md only) | warm | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11230 | 2343 | 3566282744 | 803541 | 86971 | 3.579 | 5.1 | 1.2 | 174 | 293 | 3217 | 4 (utility) | 0.759 s, cpu 0.8 s, 0 files | final: the corpus from disk |
| 2026-10-28 | `baseline-binary` | digest run | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11237 | 2350 | 3585616974 | 807506 | 87398 | 9.192 | 23.9 | 7.7 | 344 | 675 | 3454 | all 14 cores (`concurrentPerform`) | 0.796 s, cpu 0.8 s, 0 files | review fix block: the old code in the same session, right before the new |
| 2026-10-28 | `46a01de` | digest run | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11237 | 2350 | 3585617691 | 807507 | 87398 | 3.732 | 5.2 | 1.2 | 173 | 285 | 3348 | 4 (utility parse, merge at the refresh's priority) | 0.773 s, cpu 0.8 s, 0 files | review fix block: attribution at the refresh's priority, right after the old code |
| 2026-10-30 | `aff144f` (own worktree) | digest run | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11272 | 2385 | 3640170739 | 819746 | 88643 | 8.309 | 24.2 | 7.8 | 384 | 642 | 3460 | all 14 cores (`concurrentPerform`) | 0.815 s, cpu 0.8 s, 0 files | walkthrough step 3: baseline built from its own commit |
| 2026-10-30 | `aff144f` (own worktree) | digest run | codex | configured (2) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 569 | 408 | 278665668 | 57380 | 5956 | 0.692 | 0.4 | 0.1 | 71 | 96 | 267 | 1 (on the source's actor) | 0.011 s, cpu 0.0 s, 0 files | walkthrough step 4 |
| 2026-10-30 | `14f7aa6` (built as `14f7aa6-dirty`, RUNBOOK.md only) | digest run | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11272 | 2385 | 3640208269 | 819767 | 88645 | 3.727 | 5.3 | 1.2 | 174 | 327 | 3436 | 4 (default, utility) | 0.730 s, cpu 0.7 s, 0 files | walkthrough step 5 |
| 2026-10-30 | `14f7aa6` (built as `14f7aa6-dirty`, RUNBOOK.md only) | digest run | codex | configured (2) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | not captured | not captured | not captured | not captured | 5956 | 0.181 | 0.2 | 0.1 | 161 | 104 | 265 | 4 (default, utility) | 0.011 s, cpu 0.0 s, 0 files | walkthrough step 6; the count lines of the report were not kept, the record count is the digest's |
| 2026-10-30 | `aff144f` (own worktree) | warm | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11272 | 2385 | 3640242400 | 819786 | 88647 | 8.058 | 24.2 | 7.8 | 397 | 597 | 3436 | all 14 cores (`concurrentPerform`) | 0.775 s, cpu 0.8 s, 0 files | walkthrough step 7: the old code, right before the new; the corpus from disk |
| 2026-10-30 | `14f7aa6` (built as `14f7aa6-dirty`, RUNBOOK.md only) | warm | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11272 | 2385 | 3640242400 | 819786 | 88647 | 3.692 | 5.3 | 1.2 | 176 | 284 | 3436 | 4 (default, utility) | 0.820 s, cpu 0.8 s, 0 files | walkthrough step 7: the new code, right after the old; the corpus from disk |
| 2026-10-30 | `aff144f` (own worktree) | cold | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11273 | 2386 | 3640967170 | 819987 | 88662 | 8.152 | 24.3 | 7.8 | 394 | 639 | 3482 | all 14 cores (`concurrentPerform`) | not captured | walkthrough step 8, maintainer step: `sudo purge`, then the old code |
| 2026-10-30 | `14f7aa6` (built as `14f7aa6-dirty`, RUNBOOK.md only) | cold | claude | configured (3) | `~/.config/agenttacho/config.json` | 2026-10-01T00:00:00Z | 11273 | 2386 | 3640967170 | 819987 | 88662 | 3.776 | 5.3 | 1.1 | 172 | 309 | 3477 | 4 (default, utility) | not captured | walkthrough step 8, maintainer step: `sudo purge`, then the new code |

## Digest comparisons

`<commit> vs baseline <commit>: identical, N records`, or the difference counts.

- Baseline binary (`aff144f`) against itself, `UNTIL=2026-10-28T16:44:22Z`: claude identical, 86731 records; codex identical, 5607 records. This proves the comparison on the real corpus before any parsing change.
- Step B, timestamps (`6734afb`, built as `cdb1bfe-dirty`) vs baseline binary, `UNTIL=2026-10-28T16:50:21Z`: claude identical, 86748 records; codex identical, 5626 records.
- Step C, lines in place (`71f7a05`, built as `6734afb-dirty`) vs baseline binary, `UNTIL=2026-10-28T17:10:23Z`: claude identical, 86807 records; codex identical, 5665 records.
- Step D, workers, before the autorelease pools (never committed, 3 workers) vs baseline binary, `UNTIL=2026-10-28T17:29:36Z`: claude identical, 86895 records; codex identical, 5702 records. Repeated with the pools (`8cec6f4` with 3 workers, built as `71f7a05-dirty`; the commit then set the default to 4), `UNTIL=2026-10-28T17:35:37Z`: claude identical, 86903 records; codex identical, 5708 records.
- Step E, Codex typed (`273d987`, built as `8cec6f4-dirty`, 4 workers) vs baseline binary, `UNTIL=2026-10-28T17:54:15Z`: claude identical, 86925 records; codex identical, 5717 records.
- Review fix, attribution at the refresh's priority (`46a01de`, 4 workers) vs baseline binary, `UNTIL=2026-10-28T20:47:50Z`: claude identical, 87385 records.
- Walkthrough, maintainer's real-corpus repeat (`14f7aa6`, built as `14f7aa6-dirty`, RUNBOOK.md only) vs baseline `aff144f` built from its own commit in a separate worktree, `UNTIL=2026-10-30T08:26:15Z`: claude identical, 88601 records; codex identical, 5956 records.

## Observations

- **The Claude Code "warm" runs read the corpus from disk.** Both baseline runs read about 3.3 GB from disk (3406 MB in the first run, 3323 MB in the recorded second), against 3391 MB of bytes read. The Mac was under memory pressure (18 GB compressed, 5 GB file-backed of 48 GB), so the page cache did not keep the corpus between runs. The Codex corpus (254 MB) stayed cached: its second run read 0 MB from disk. Each row's `disk MB read` shows the condition it actually ran in.
- **Codex CPU at one decimal**: the report prints CPU seconds with one decimal, so the Codex rows are compared on `avg cpu %` times `wall s` as well: 1.00 × 0.469 s = 0.47 s for the baseline (SC-006).
- **Rows from a step's digest runs**: a step's comparison block runs the baseline binary and the new build back to back. Both digest runs are recorded as `digest run` rows, since they ran in the same cache and memory state; writing the digest comes after the measured scan, so their figures count as runs.
- **Step B, timestamps**: in the same session, the Claude Code scan went from 8.9 s to 5.5 s with about the same disk reads (3366 and 3024 MB). User CPU fell from 23.6 to 15.8 s and system CPU from 7.6 to 1.8 s: much of the system formatter's cost was system time. The recorded warm run read only 323 MB from disk and took 5.3 s. Codex CPU fell from 0.47 s to 0.22 s (0.99 × 0.225 s).
- **Step C, lines in place**: in the same session, the Claude Code scan went from 10.0 s to 3.5 s with about the same disk reads (3395 and 3173 MB). CPU time fell from 31.8 s (24.1 user, 7.7 system) to 7.3 s (5.7 user, 1.6 system), and the average from 320% to 210%. The recorded warm run took 3.3 s at 230% while it read 3317 MB from disk, about 1 GB/s: the scan is now close to bound by the disk on this machine, not by parsing. Peak footprint stays within the baseline's range (651 to 836 MB across runs; it varies with the cache state).
- **Step D, workers**: with 3 workers at utility priority the Claude Code scan took 4.1 s at 153%, against 8.2 s at 382% for the old code in the same block; CPU time stays at about 6.3 s (5.0 to 5.3 user, 1.2 system). The first measurement showed a peak footprint of 1512 MB: the jobs ran inside long-lived dispatch work items, so the file buffers Foundation autoreleases piled up until the scan ended. Each job now runs in its own autorelease pool, and the footprint fell to 281 to 318 MB, below the baseline's 752 MB (SC-003). The Codex reader parses on the workers too: 0.18 s at 150%, CPU about 0.27 s.
- **Worker count (T040)**: 2, 3 and 4 workers gave 5.0, 4.1 and 3.8 s at 126, 157 and 171%, all reading 3.3 GB from disk. None met SC-001's 3 s within SC-002's 200%, so the count closest to both, 4, is the default (`ScanWorkers.defaultCount`, at most 4 and half the cores). For information, 6 workers gave 3.5 s at 189%, and 8 workers 3.6 s at 193% from disk, but 2.7 s at 252% in the one run whose corpus was in the page cache.
- **SC-001 and SC-002 together need less CPU.** A scan now costs about 6.3 to 6.9 s of CPU on this corpus, whatever the worker count. A wall time under 3 s then means an average above 210 to 230%, so the two criteria cannot both hold until the CPU time falls below 6 s. On this machine the scan is also bound by the disk (about 1 GB/s with 4 to 8 workers) whenever the page cache does not hold the corpus.
- **Step E, Codex typed decoding (SC-006)**: one decimal is too coarse for 0.2 s, so the Codex CPU was measured as `avg cpu %` times `wall s` over five runs of each binary, alternating, on the step E commit's build: the old code 0.465, 0.467, 0.469, 0.474 and 0.470 s (mean 0.469 s), the new code 0.274, 0.265, 0.277, 0.267 and 0.272 s (mean 0.271 s). The new reader uses 58% of the old CPU time: a cut of 42%, short of SC-006's half. Its wall time fell from 0.47 s to 0.10 s with the corpus cached.
- **The saved baseline binary needs its resource bundle.** `scan-bench` loads the built-in prices from `agenttacho_UsageCore.bundle`, which must sit next to the copied binary (`cp -R .build/release/agenttacho_UsageCore.bundle $BENCH/`); without it the binary traps at start.

## Result

The finished change is `273d987` (step E) with 4 workers by default, measured warm on 2026-10-28. On this Mac the page cache kept the Claude Code corpus only now and then (see Observations), so the final runs range from fully cached to fully read from disk; each is a row above.

| criterion | target | baseline (`aff144f`) | finished change (`273d987`) | verdict |
|---|---|---|---|---|
| SC-001, warm | first scan under 3 s | 8.647 s (3323 MB from disk) | 2.910 s with the corpus cached; 3.117 to 4.047 s with 556 to 3312 MB from disk | met with a warm cache; missed by 0.1 to 1.0 s when the memory pressure evicted part or all of the corpus |
| SC-001, cold | under 3 s | 8.152 s (3482 MB from disk, walkthrough) | 3.776 s at 172% (3477 MB from disk, `14f7aa6`, walkthrough) | missed by 0.8 s; disk-bound, which FR-020 notes here and does not count as a reason for the extractor |
| SC-002 | at most 200% average | 373% | 167 to 194% from disk; 210% with the corpus cached | met in the runs that read from disk; missed by 10 points in the cached run |
| SC-003 | peak footprint not above the baseline | 752 MB | 278 to 334 MB | met |
| SC-005 | second refresh no slower | 0.769 s, cpu 0.8 s | 0.735 to 0.801 s, cpu 0.7 to 0.8 s | met (within the 0.74 to 0.82 s spread both binaries show from run to run) |
| SC-006 | Codex CPU at most half | 0.469 s (mean of five runs) | 0.271 s (mean of five runs) | missed: 58% of the baseline, a 42% cut |

**Digest comparisons (SC-004, FR-009)**: every step compared identical against the baseline binary, for both readers (see "Digest comparisons"); the committed fixture digests pass unchanged (`ScanBenchTests`). The maintainer's own repeat over the real corpus in the walkthrough (2026-10-30) compared identical for both readers.

**Tests (SC-008)**: `make test` passes (2349 and 73 tests; 2362 and 73 at `14f7aa6` in the verification of 2026-11-01), the Codex test suites pass without changed expectations, and `make test-release` passes (266 tests).

**For the maintainer's FR-020 decision**: SC-001 and SC-002 can hold together only when a scan costs less than 6 s of CPU (3 s at 200%). The finished scan costs 6.0 to 6.8 s (5.1 to 5.4 s user, 0.9 to 1.4 s system) on this corpus, whatever the worker count, so the cached run takes 2.9 s at 210% and the runs from disk stay below 200% only because the disk slows them. A `sample` profile of one final run shows where the busy time goes in the line loop:

- decoding the assistant records with `JSONDecoder`: about 2300 of 3400 busy samples, the cost FR-020's hand-written field extractor would replace;
- whole-line marker searches: `memmem` (about 570 samples) for lines neither bounded scan decides, and `Data.range(of:)` (about 130) in the record parser's marker pre-filter, which still runs on lines the classifier already found to be assistant records;
- reading the files, blocked on the disk whenever the cache does not hold them.

A head window of 1024 bytes instead of 256 did not change the CPU time (5.2 s user either way), so the fallback lines are not user lines cut by the head window. Skipping the record parser's pre-filter for lines already classified as assistant records is a smaller step that stays clear of FR-020; it was not measured here.

**Review fix (`46a01de`)**: the merge and attribution now run at the refresh's priority instead of utility (code review FINDING-6, spec 038's 50 ms condition limit), the parse jobs stay at utility. Back to back with the old code it took 3.732 s at 173% (5.2 s user, 1.2 s system, 285 MB, 3348 MB from disk) against 9.192 s at 344% for the old code, in line with the step E rows, and the digests compared identical.

## Maintainer decision (2026-10-28)

SC-001 together with SC-002, and SC-006, are missed as measured above. The maintainer accepts the result for this feature and ships it; the spec targets stay as they are. The hand-written field extractor (approach B, FR-020) is the measured follow-up: the scan costs 6.0 to 6.8 s of CPU and needs less than 6 s for both targets, and `JSONDecoder` on the assistant records is the largest share of the profile. It is recorded in `brainstorm/idea-inbox.md` as `hand-written-field-extractor`.

**2026-11-01**: at verification the maintainer evolved SC-001, SC-002 and SC-006 to the delivered levels against the baseline (spec "Changelog"): wall at most half the baseline's in the same cache state, CPU time at most a quarter, at most 200% from disk, and a Codex CPU cut of at least 40%. The verdicts in the "Result" table above judge the original targets, which the follow-up keeps.

## Maintainer steps

Steps that need the maintainer's corpus at the walkthrough or administrator rights (spec FR-006, FR-009, quickstart sections 2 to 5). They are not taken by the implementation. The walkthrough of 2026-10-30 to 2026-11-01 (RUNBOOK.md, 11 of 11 steps passed) recorded them: the cold pair and the real-corpus comparison are in the rows and comparisons above. The incremental check: the last 0.8.0 refresh lines took 0.728 to 1.054 s; the dev build's took 0.675 to 0.804 s at cpu 0.7 to 0.8 s, except two refreshes right after a restart at 1.275 and 1.475 s with an unchanged cpu 0.8 to 0.9 s, accepted by the maintainer. The responsiveness check passed: the dropdown opened at once during the first scan, and the Codex line came before the session scan's.

- **Cold baseline**: on the baseline commit (or with the saved baseline binary), `sudo purge && make bench-scan SINCE=$SINCE`, recorded as a `cold` row.
- **Cold final run**: the same on the finished change; wall under 3 s (SC-001).
- **Real-corpus comparison**: repeat the comparison block's digest pair for both readers with a fresh `UNTIL`; both print `identical` (SC-004, FR-009).
- **Incremental check**: run the app before and after the change, wait for two scheduled refreshes with a few changed session files, and compare the `... s, cpu ... s` of the refresh lines in `~/Library/Logs/agenttacho/usage.log` (SC-005).
- **Responsiveness check**: start the app with an empty index and open the dropdown during the first scan; it opens, and the Codex and subscription lines appear while the scan still runs (User Story 1 scenario 3, FR-018).
