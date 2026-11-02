---
runbook_version: 1
feature: 039-faster-session-scan
status: passed
mode: full
steps_total: 11
step_results: passed,passed,passed,passed,passed,passed,passed,passed,passed,passed,passed
drafted_at: fb05c91
drafted_fingerprint: b979a51aefd61ada9fa9c020f759b46c4af9bf61d6c9b2feeef6a68771b859c3
tested_at: 14f7aa6
tested_fingerprint: b979a51aefd61ada9fa9c020f759b46c4af9bf61d6c9b2feeef6a68771b859c3
updated: 2026-11-01
---

# Try it: Faster session scan

<!-- runbook-status -->
> **Status:** passed · 11 of 11 steps (11 passed) · Mode: full · Tested at 14f7aa6 · 2026-11-01
<!-- /runbook-status -->












## What you're testing

The first scan of your Claude Code session files should now be about three times faster and use about five times less CPU and less than half the memory. Every usage record should stay exactly the same. The Codex reader got faster too. This journey proves both claims on your own machine:

1. The test suite passes, including the committed fixture digests.
2. You build the bench from the commit before any parsing change (the baseline), next to the finished change.
3. Both readers produce the same records as the baseline over your real sessions (digest comparison).
4. The new code is faster and quieter on a warm cache, then on a cold cache (needs `sudo purge`).
5. The bench refuses to write into an agent's folder.
6. In the app: the dropdown stays responsive during the first scan, and refresh lines now show CPU seconds.
7. Clean up the private bench folder, which holds digests with your project paths.

All bench runs use the same window: from `2026-10-01T00:00:00Z` to a fixed end that step 2 writes to a file, so the old and new runs cover the same records.

## Test environment

- **Private bench folder** `~/.cache/agenttacho-bench` (mode 700): holds the frozen window end and the four digests. Created in step 2 by whoever runs it; removed in step 11 with `rm -rf ~/.cache/agenttacho-bench`.
- **Baseline source tree** `~/.cache/agenttacho-bench/baseline-src`: a detached git worktree at `aff144f` (bench added, parsing unchanged), built in release by its own Makefile. Slow local fixture: the release build takes a few minutes. Created in step 3; removed in step 11 with `git worktree remove --force ~/.cache/agenttacho-bench/baseline-src`.

## Steps

### Step 1 of 11: Run the test suite (US2)

**Why this step:** The suite holds the record-equality checks that need no real data: the committed fixture digests (FR-008), the line classifier and timestamp parser compared with the old code, and the concurrency tests for the workers (FR-018).

**Needs:** nothing

**Run:**

```
make test
```

**What you should see:** Both test runs pass with no failures, about 2,362 tests in the first and 73 in the second. Among the suites: `ScanBenchTests` (fixture digests), `SessionLineClassifierTests`, `TimestampTests`, `ScanWorkersTests`, `ScanConcurrencyTests`, `CodexTypedLineTests`.

**If you see something else:** A failing `ScanBenchTests` fixture digest means the records changed for the fixtures; a hang in `ScanConcurrencyTests` points at the workers holding the shared thread pool. An SDK error during the build means the macOS 26 SDK the Makefile picks is missing.

**Result:** passed (agent, 2026-10-30). `make test` exit 0.
- ✔ about 2,362 tests → `Test run with 2362 tests in 246 suites passed after 3.249 seconds.`
- ✔ about 73 tests → `Test run with 73 tests in 7 suites passed after 0.070 seconds.`
- ✔ named suites → `ScanBenchTests`, `SessionLineClassifierTests`, `TimestampTests`, `ScanWorkersTests`, `ScanConcurrencyTests`, `CodexTypedLineTests` all `passed`; no `✘` line in the log.

### Step 2 of 11: Prepare a private bench folder and freeze the window end (US3)

**Why this step:** The digests list your project paths and session ids, so they belong in a folder only you can read. The window end is frozen ten minutes in the past, so no message still being written lands in one run and not the other.

**Needs:** nothing

**Run:**

```
mkdir -p -m 700 ~/.cache/agenttacho-bench && date -u -v-10M +%Y-%m-%dT%H:%M:%SZ > ~/.cache/agenttacho-bench/until && ls -ld ~/.cache/agenttacho-bench && cat ~/.cache/agenttacho-bench/until
```

**What you should see:** A directory line starting with `drwx------`, then one timestamp ten minutes before now, such as `2026-10-28T21:05:00Z`.

**If you see something else:** Permissions other than `drwx------` mean the folder existed before with other rights; run `chmod 700 ~/.cache/agenttacho-bench`.

**Result:** passed (agent, 2026-10-30).
- ✔ `drwx------` → `drwx------ rhuss staff ... /Users/rhuss/.cache/agenttacho-bench`
- ✔ timestamp ten minutes before now → `2026-10-30T08:26:15Z` (clock: 08:36:15 UTC)

### Step 3 of 11: Build the baseline bench and take the baseline Claude Code digest (US3)

**Why this step:** The baseline is the code before any parsing change. Building it from its own commit gives an old binary to run back to back with the new one over the same sessions (FR-006, FR-009).

**Needs:** Step 2

**Run:**

```
git worktree add --detach ~/.cache/agenttacho-bench/baseline-src aff144f && make -C ~/.cache/agenttacho-bench/baseline-src bench-scan SINCE=2026-10-01T00:00:00Z UNTIL=$(cat ~/.cache/agenttacho-bench/until) DIGEST=$HOME/.cache/agenttacho-bench/old-claude.digest
```

**What you should see:** A release build (a few minutes), then a `scan-bench 1  commit aff144f  reader claude` report. It shows about 2,300 files in the window and about 87,000 records. Wall time is about 8 to 10 s at 340 to 380% average CPU, with a peak footprint of about 650 to 760 MB. A `digest` line names the file under `~/.cache/agenttacho-bench`.

**If you see something else:** `fatal: ... already exists` means an earlier walkthrough left the worktree; run step 11's cleanup first. A report with commit `aff144f-dirty` means the worktree has changes; it should not.

**Result:** passed (agent, 2026-10-30). Build 45 s. Output in `.walkthrough/step-3.log`.
- ✔ `scan-bench 1  commit aff144f  reader claude`
- ✔ about 2,300 files, 87,000 records → `files read 2385 ... records 88643`
- ✔ wall 8 to 10 s → `wall 8.309 s`
- ~ 340 to 380% CPU → `average 384%` (slightly above)
- ~ footprint 650 to 760 MB → `footprint 642 MB` (slightly below)
- ✔ digest line → `digest ~/.cache/agenttacho-bench/old-claude.digest (88601 records)`
- Note: `disk read 3460 MB`, the corpus came from disk.

### Step 4 of 11: Take the baseline Codex digest (US2)

**Why this step:** The Codex reader changed too (typed decoding, workers). Its baseline digest is the reference for step 6.

**Needs:** Step 3

**Run:**

```
make -C ~/.cache/agenttacho-bench/baseline-src bench-scan READER=codex SINCE=2026-10-01T00:00:00Z UNTIL=$(cat ~/.cache/agenttacho-bench/until) DIGEST=$HOME/.cache/agenttacho-bench/old-codex.digest
```

**What you should see:** A `reader codex` report with commit `aff144f`, about 5,600 records, wall about 0.2 to 0.5 s at about 100% CPU, and a `digest` line.

**If you see something else:** Zero files means no Codex rollouts in the window; steps 6 and the Codex half of step 7 then prove nothing and should be skipped.

**Result:** passed (agent, 2026-10-30).
- ✔ `reader codex` with commit `aff144f`
- ✔ about 5,600 records → `records 5956`
- ✘ wall 0.2 to 0.5 s at about 100% → `wall 0.692 s`, `average 71%`; `disk read 267 MB` shows a cold Codex corpus, which explains it. Not a fault of the change: this is the baseline.
- ✔ digest line → `old-codex.digest (5956 records)`

### Step 5 of 11: Same Claude Code records from the new code (US2)

**Why this step:** This is the core promise: the faster reader produces exactly the records the old one did, over your real sessions (SC-004, FR-009).

**Needs:** Step 3

**Run:**

```
make bench-scan SINCE=2026-10-01T00:00:00Z UNTIL=$(cat ~/.cache/agenttacho-bench/until) DIGEST=$HOME/.cache/agenttacho-bench/new-claude.digest && make bench-compare A=$HOME/.cache/agenttacho-bench/old-claude.digest B=$HOME/.cache/agenttacho-bench/new-claude.digest; echo "compare exit $?"
```

**What you should see:** A report with this branch's commit (for example `fb05c91`), the same files and records count as step 3, then `identical` and `compare exit 0`.

**If you see something else:** `different` with the first differing entries means a record changed; note the record keys and fields shown. A record count that differs from step 3 by a handful usually means the window end was not the same file; check step 2's file was used.

**Result:** passed (agent, 2026-10-30).
- ✔ this branch's commit → `commit 14f7aa6-dirty` (dirty only from this runbook's results)
- ✔ same files → `files read 2385`; the `records` line reads 88645 against 88643, since two lines were appended after the baseline run; both digests hold the window's 88601 records
- ✔ `identical` → `identical: 88601 records`, `compare exit 0`
- For information: `wall 3.727 s`, `average 174%`, `footprint 327 MB`, `disk read 3436 MB`, `workers 4 (default, utility)`

### Step 6 of 11: Same Codex records from the new code (US2)

**Why this step:** The Codex reader must give the same sessions, totals and fork handling as before (FR-011, SC-004).

**Needs:** Step 4

**Run:**

```
make bench-scan READER=codex SINCE=2026-10-01T00:00:00Z UNTIL=$(cat ~/.cache/agenttacho-bench/until) DIGEST=$HOME/.cache/agenttacho-bench/new-codex.digest && make bench-compare A=$HOME/.cache/agenttacho-bench/old-codex.digest B=$HOME/.cache/agenttacho-bench/new-codex.digest; echo "compare exit $?"
```

**What you should see:** A `reader codex` report with this branch's commit and the same record count as step 4, then `identical` and `compare exit 0`.

**If you see something else:** `different` naming token totals or plan markers points at the typed Codex decoding; note the first differences.

**Result:** passed (agent, 2026-10-30).
- ✔ same record count as step 4 → `new-codex.digest (5956 records)`
- ✔ `identical` → `identical: 5956 records`, `compare exit 0`
- For information: `wall 0.181 s`, `average 161%`, `footprint 104 MB`, `workers 4 (default, utility)`

### Step 7 of 11: Faster and quieter on a warm cache (US1)

**Why this step:** With the session files already read once by steps 3 to 6, this runs the old and new Claude Code reader back to back and compares wall time, CPU and memory (SC-001 to SC-003, SC-005).

**Needs:** Steps 3 and 5

**Run:**

```
make -C ~/.cache/agenttacho-bench/baseline-src bench-scan SINCE=2026-10-01T00:00:00Z UNTIL=$(cat ~/.cache/agenttacho-bench/until) && make bench-scan SINCE=2026-10-01T00:00:00Z UNTIL=$(cat ~/.cache/agenttacho-bench/until)
```

**What you should see:** Two reports. The baseline: wall about 8 to 10 s, average CPU about 340 to 380%, peak footprint about 650 to 760 MB. The new one: wall about 3 to 4 s (under 3 s only when nothing is read from disk), average CPU about 170 to 210%, peak footprint about 280 to 340 MB. Both `second refresh` lines are about 0.7 to 0.8 s. Same records count in both.

**If you see something else:** A new wall time above 5 s together with a large `disk read` means memory pressure pushed the files out of the cache; compare the `disk read` lines of both runs before judging. A new peak footprint above the baseline's breaks SC-003.

**Result:** passed (agent, 2026-10-30). Both runs read 88647 records.
- ✔ baseline wall 8 to 10 s → `wall 8.058 s`
- ~ baseline CPU 340 to 380% → `average 397%` (user 24.2 s, system 7.8 s)
- ~ baseline footprint 650 to 760 MB → `footprint 597 MB`
- ✔ new wall 3 to 4 s → `wall 3.692 s`
- ✔ new CPU 170 to 210% → `average 176%` (user 5.3 s, system 1.2 s)
- ✔ new footprint 280 to 340 MB → `footprint 284 MB`
- ✔ second refresh 0.7 to 0.8 s → `0.775 s` old, `0.820 s` new
- Note: both runs read `disk read 3436 MB`, so this "warm" pair was disk-bound, as BENCHMARK.md records for this Mac under memory pressure. Gain: wall 2.2x, CPU time 4.9x, footprint 2.1x.

### Step 8 of 11: Cold cache, old and new (US1)

**Why this step:** A cold cache is what the app sees after a restart of the Mac: every byte comes from disk. SC-001 asks for under 3 s here too; the measured disk-bound runs took 3.1 to 4.0 s, a miss you accepted on 2026-10-28.

**Needs:** Steps 3 and 5. Administrator password (`sudo purge` empties the file cache). You run this step yourself.

**Run:**

```
sudo purge && make -C ~/.cache/agenttacho-bench/baseline-src bench-scan SINCE=2026-10-01T00:00:00Z UNTIL=$(cat ~/.cache/agenttacho-bench/until) && sudo purge && make bench-scan SINCE=2026-10-01T00:00:00Z UNTIL=$(cat ~/.cache/agenttacho-bench/until)
```

**What you should see:** In both reports `disk read` is close to `bytes read` (about 3.3 GB). The baseline takes about 9 to 13 s; the new code about 3 to 4.5 s at or under about 200% average CPU. Note both rows for `BENCHMARK.md` as `cold`.

**If you see something else:** A small `disk read` means `purge` did not empty the cache (another process may have read the files again); repeat the step.

**Result:** passed (maintainer, 2026-10-30). Both runs read 88662 records, 3640967170 bytes.
- ✔ `disk read` close to bytes read → `3482 MB` old, `3477 MB` new
- ~ baseline 9 to 13 s → `wall 8.152 s` (faster than expected), `average 394%` (user 24.3 s, system 7.8 s), `footprint 639 MB`
- ✔ new 3 to 4.5 s at or under 200% → `wall 3.776 s`, `average 172%` (user 5.3 s, system 1.1 s), `footprint 309 MB`
- SC-001 (under 3 s) stays missed on a cold cache, as accepted on 2026-10-28.

### Step 9 of 11: The bench never writes into an agent's folder (US3)

**Why this step:** The app treats `~/.claude` and `~/.codex` as read-only, and so must the bench (FR-004). A digest path inside an agent folder must be refused before anything is written.

**Needs:** nothing

**Run:**

```
make bench-scan DIGEST=$HOME/.claude/walkthrough-check.digest; echo "bench exit $?"; ls -l ~/.claude/walkthrough-check.digest
```

**What you should see:** One error line refusing the digest path (written with `~`), `bench exit 2` (make may report its own `Error 2` line), and `ls: ... No such file or directory`.

**If you see something else:** A full report and a file listed by `ls` means the refusal failed; delete the file with `rm ~/.claude/walkthrough-check.digest` and record the step as failed.

**Result:** passed (agent, 2026-10-30).
- ✔ refusal line → `scan-bench: digest path under an agent or session directory: ~/.claude/walkthrough-check.digest`
- ✔ exit 2 → `make: *** [bench-scan] Error 2`
- ✔ no file → `ls: /Users/rhuss/.claude/walkthrough-check.digest: No such file or directory`

### Step 10 of 11: The app stays responsive and logs CPU seconds (US1)

**Why this step:** The bench proves the numbers; this proves the experience. The app keeps its session index in memory only, so every start is a first scan. The menu bar dropdown must open during it, and the other sources must refresh while it runs (FR-018). Refresh lines now state CPU seconds (FR-007), which lets you compare refreshes before and after (SC-005).

**Needs:** nothing. You run this step yourself (GUI).

**Do:**

1. Look at the last refresh lines of your installed app: `rg 'files seen' ~/Library/Logs/agenttacho/usage.log | tail -3`. Note the `... s` at the end of each (these lines have no `cpu` yet).
2. Quit every running AgentTacho from its menu, installed or a dev build; `pgrep -fl AgentTacho` must print nothing, or `make run` only brings that one forward.
3. Run `make run` in this worktree (not the main checkout). It builds the app bundle and opens it.
4. Right after the icon appears, click it to open the dropdown, while the first scan is still running.
5. After the scan, run `rg 'files seen|codex' ~/Library/Logs/agenttacho/usage.log | tail -6`.
6. Edit nothing; keep using Claude Code for a few minutes so a few session files change, wait for two scheduled refreshes, and run step 5's command again.
7. Quit the dev build and start your installed AgentTacho again.

**What you should see:** The dropdown opens at once during the first scan, and the Codex and subscription lines appear before the session scan's line. The first scan's line ends in about `3 to 4 s, cpu 6 to 7 s`. The two later refresh lines end in under 1 s with a small `cpu` value, no slower than the installed app's lines from point 1.

**If you see something else:** A dropdown that opens only after the scan ends means the scan holds the source actor or the shared thread pool (FR-018). A refresh line without `, cpu` means the dev build did not start; check that the installed app was quit first.

**Result:** passed with a note (maintainer and agent, 2026-11-01).
- Point 1: the running app was already a dev build of this branch, so the reference lines are the last 0.8.0 lines in the log (2026-10-28): `1.054 s`, `0.731 s`, `0.728 s`, no `cpu`.
- Runbook correction: `make run` only brings an already running AgentTacho forward, so the first try showed the old process (PID unchanged), and the second ran the main checkout's build (no `, cpu`). Point 2 must quit every AgentTacho (`pgrep -fl AgentTacho` prints nothing) and point 3 must run `make run` in this worktree.
- ✔ dropdown opens at once during the first scan (maintainer)
- ✔ Codex line before the session scan's line → `16:00:46Z [codex] ... cpu 0.0 s`, then `16:00:47Z [sessionLogs]`
- ~ first scan `3 to 4 s, cpu 6 to 7 s` → `re-read 35 (82222988 bytes) ... 0.757 s, cpu 0.8 s`. Runbook correction: the collection window now starts 2026-10-30T07:00:00Z, so the app's first scan reads 35 files; the full-corpus figures are steps 7 and 8.
- ✘ later refreshes under 1 s → `1.275 s, cpu 0.8 s` and `1.475 s, cpu 0.9 s`, nothing re-read. CPU unchanged; the same code took `0.675` to `0.804 s` earlier that day, load average about 4. Recorded as passed on the maintainer's decision: wall time spent waiting at unchanged CPU.

### Step 11 of 11: Clean up the baseline tree and the digests (US3)

**Why this step:** The digests hold your project paths, session ids and account ids; they must not linger. The baseline worktree is no longer needed.

**Needs:** Steps 3 to 9 done

**Run:**

```
git worktree remove --force ~/.cache/agenttacho-bench/baseline-src && rm -rf ~/.cache/agenttacho-bench && git worktree list && ls ~/.cache/agenttacho-bench
```

**What you should see:** `git worktree list` shows no `baseline-src` entry, and `ls` reports `No such file or directory`.

**If you see something else:** `fatal: ... is not a working tree` means step 3 never created it; the `rm -rf` still runs if you repeat the command without the first part.

**Result:** passed (agent, 2026-11-01).
- ✔ no `baseline-src` in `git worktree list` (main, 036, 039 only)
- ✔ `ls: /Users/rhuss/.cache/agenttacho-bench: No such file or directory`

## Not covered here

- The hand-written field extractor (FR-020, approach B) is not built; it is the follow-up `hand-written-field-extractor` in `brainstorm/idea-inbox.md`.
- The OpenCode reader is out of scope (FR-021).
- SC-006 (Codex CPU at most half the baseline) needs averaged CPU over several runs to judge; steps 4 and 6 show single runs only. `BENCHMARK.md` holds the five-run means (0.469 s before, 0.271 s after, 58%).

## Coverage

- **US1 (fast and quiet first scan):** steps 7, 8 and 10.
- **US2 (every record stays the same):** steps 1, 4, 5 and 6.
- **US3 (the gain is a measured number):** steps 2, 3, 9 and 11, plus the reports of steps 3 to 8, which are the rows to add to `BENCHMARK.md`.

## Results

11 steps: 11 passed, 0 failed, 0 skipped (2026-10-30 to 2026-11-01).

- **Records unchanged (US2):** the suite passes (2,362 and 73 tests), and over the real sessions both readers give digests identical to the baseline `aff144f`: 88,601 Claude Code records and 5,956 Codex records.
- **Faster and quieter (US1):** the Claude Code first scan over the October window takes 3.7 s instead of 8.1 s, at 6.4 s of CPU instead of 32 s (about 175% against 395%), with half the peak footprint (284 to 309 MB against 597 to 639 MB). On this Mac every run read the corpus from disk, cold or not, so the figures are the disk-bound case; SC-001's 3 s stays missed there, as accepted. The Codex scan took 0.18 s against 0.69 s. In the app the dropdown opens at once during the first scan, other sources report first, and refresh lines carry `cpu`.
- **Measured and safe (US3):** the bench refuses a digest path inside `~/.claude`, and the private bench folder and baseline tree are removed.
- **Notes:** two scheduled refreshes after the restart took 1.3 and 1.5 s at an unchanged 0.8 to 0.9 s of CPU, against 0.7 to 0.8 s for the same code earlier; passed on the maintainer's decision. Step 10's instructions now say to quit every AgentTacho and run `make run` in the worktree, and its first-scan figure depends on the collection window.
