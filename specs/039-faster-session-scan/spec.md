# Feature Specification: Faster Session Scan

**Feature Branch**: `039-faster-session-scan`

**Created**: 2026-10-28

**Status**: Draft

**Input**: Brainstorm `brainstorm/39-faster-session-scan.md`: "The first scan of all Claude Code session files takes 10 to 13 s at 400 to 450% CPU. ripgrep scans the whole corpus in 1.65 s. The app is CPU-bound in how it visits lines, searches markers and parses timestamps, not in the language or the disk. Decision: apply ripgrep's techniques in Swift, keep the JSON decoding of candidate lines, share one fast timestamp parser between the Claude Code and Codex readers, parse on a bounded number of low-priority workers, no new dependency. Target: fast and quiet. Baseline first, then measure every step: wall, CPU, memory, disk."

## Background

AgentTacho keeps an incremental index over the Claude Code session files (`~/.claude/projects/**/*.jsonl`, spec 001 FR-018) and the Codex rollout files (spec 007). A refresh reads only files that changed since the last one, so refreshes are cheap (0.8 to 1.6 s in the maintainer's log). The first scan after a start, after the collection window moved earlier, or after an attribution change reads every file in the window from the start. On the maintainer's Mac (M4 Pro) that scan reads 2,310 files holding 3.5 GB and takes 9 to 13 s at 400 to 450% CPU. The Mac feels busy, the fans may come on, and the dropdown shows stale or empty numbers until it is over.

The brainstorm measured where the time goes (2026-10-28, warm page cache, one 352 MB project folder with 93,036 lines, single-threaded):

| Stage | Today | Measured floor |
|---|---|---|
| Split the file into one copy per line | 932 ms | 7 ms (visit lines in place) |
| Parse each record's timestamp with the system date formatter | 438 ms | 1 ms (fixed-layout parse) |
| Find the record-type marker, whole line, every line | 206 + 304 ms | small (bounded window) |
| Decode the assistant records' JSON | 190 ms | keep |
| Read the files | 113 ms | same |

ripgrep (`rg -c '"usage"'`) scans the whole 7.2 GB corpus in 1.65 s on the same machine. The app's cost is not the disk and not the language: it is per-line copies, a slow date formatter, and whole-line marker searches on lines that average 3.7 KB and reach 1.8 MB. The record-type key and the timestamp sit in the last 1.2 KB of every assistant line.

The Codex reader already finds its relevant lines with a byte search over a bounded head window, but decodes them into dictionaries and parses timestamps with the same slow formatter.

This spec makes the first scan fast and quiet, keeps every record the same, and makes the gain a measured number: the baseline is taken with a bench command before any parsing change, and every step is measured with the same command.

## Clarifications

### Session 2026-10-28

- Q: Which configuration does the bench command attribute with, and how does it choose the collection window? → A: The app's configuration file by default (another file can be given); the collection window is derived from that configuration as the app derives it, and an explicit window start can be given instead; the report names the configuration file and the window start (FR-001, FR-002).
- Q: How is the fixture expectation of FR-008 kept? → A: As a committed digest file per fixture set, generated from the unchanged code by a bench digest run and compared by the test suite; it is regenerated only by an explicit command when the fixtures change (FR-008).
- Q: What do the CPU seconds in the diagnostic log's refresh line measure? → A: The process's CPU time consumed between the start and the end of that source's refresh, which includes whatever else the app did meanwhile; the line states it as `cpu <seconds> s` (FR-007).
- Q: Do incremental refreshes use the same worker bound and priority as the first scan? → A: Yes, one setting for every refresh; SC-005 checks that a small refresh is not slower (FR-017).
- Q: What happens when the digest comparison finds a difference that turns out to be a bug of the old code? → A: Identical output stays the rule. The old-code bug is fixed as its own change first, the baseline digest is taken again from that fix, and the comparison must then show zero differences (FR-009, SC-004).
- Q (planning): The app keeps neither the working directory nor the session id per record; what does the digest compare? → A: The record as the app keeps it, which is what the dropdown shows: the project the working directory resolves to instead of the directory, and the session id only where it is part of the record key (Codex keys are `codex:<session id>:<total>`). No field is added to the app's records for the bench (FR-004, research R9).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The first scan is fast and quiet (Priority: P1)

A user with a year of Claude Code sessions starts AgentTacho. The dropdown shows numbers within a few seconds, the Mac stays responsive, and the activity monitor shows the app well below the load of today's scan.

**Why this priority**: It is the complaint: the first scan makes the Mac busy for 10 s and more, and every window or attribution change repeats it.

**Independent Test**: Run the bench command over the maintainer's corpus (about 3.5 GB in the collection window) before and after; compare wall time, CPU seconds, peak memory and disk bytes read.

**Acceptance Scenarios**:

1. **Given** the maintainer's corpus and an empty index, **When** the first scan runs with a warm page cache, **Then** it takes at most half the baseline's wall time and a quarter of its CPU time, run back to back with the baseline in the same cache state.
2. **Given** the same corpus with a cold page cache, **When** the first scan runs, **Then** it takes at most half the baseline's wall time at no more than 200% CPU on average, and the report shows the bytes that came from disk.
3. **Given** the first scan is running, **When** the user opens the dropdown or another source refreshes, **Then** the UI responds and the other sources are not held up by the scan.
4. **Given** the scan ran, **When** the user reads the diagnostic log, **Then** the refresh line shows the elapsed time and the CPU seconds of that refresh.
5. **Given** a refresh after the first scan with a handful of changed files, **When** it runs, **Then** it is as fast as before the change or faster.

---

### User Story 2 - Every record stays the same (Priority: P1)

A user updates to the release with the faster scan. Every number in the dropdown, every account total and every unassigned row is what it was before the update, given the same files.

**Why this priority**: A faster scan that drops or changes a record is a regression in the app's one job.

**Independent Test**: Record the records the current code produces over the fixture corpus and over the real corpus (a digest: record key, timestamp, model, token counts, project, account, cost). Run the new code over the same files and compare: the digests are identical.

**Acceptance Scenarios**:

1. **Given** the fixture session files, **When** the test suite runs, **Then** the records produced equal the recorded expectation, record for record, field for field.
2. **Given** the maintainer's real corpus, **When** the maintainer compares the baseline digest with the digest of the new code, **Then** the comparison reports no difference.
3. **Given** a line whose record-type key sits outside the portion the reader looks at first, or whose portion holds only a `type` key nested in the message content, **When** the file is read, **Then** the line is still classified and parsed as before.
4. **Given** a file ending in an incomplete line, a file with CRLF line endings, a line of 1.8 MB, or a line with bytes that are not valid UTF-8, **When** the file is read, **Then** the outcome is the same as today: complete lines are parsed, the incomplete tail waits for the next refresh, CRLF is tolerated, and the long or malformed line is classified without copying it.
5. **Given** a session file whose shape lines name a configured Claude Code directory (spec 037) or a condition that sat out (spec 038), **When** the index decides which files to read again, **Then** it decides as before: the per-file offsets, the re-read rules and the dedupe are unchanged.
6. **Given** a Codex rollout file, **When** it is parsed, **Then** the sessions, totals, plan markers and fork handling equal today's; the Codex tests pass unchanged.
7. **Given** a timestamp in any form the fixtures contain (with and without fractional seconds, with `Z` or an offset), **When** it is parsed, **Then** the instant equals the one the system formatter yields today; a form the fast path does not know still parses through the system formatter.

---

### User Story 3 - The gain is a measured number (Priority: P2)

The maintainer runs one bench command before touching the parser and after every step. Each run reports wall time, CPU time, peak memory, disk bytes read and the corpus it ran over. The results are kept with the spec, so a later regression is visible and a reviewer can check the claim.

**Why this priority**: The brainstorm's figures are from a throwaway script; the spec's claim must rest on the real code path. Without the baseline there is nothing to compare against.

**Independent Test**: Run the bench command on an unchanged checkout and read the report; run it again after the change; append both to the benchmark record; check that the record names the commit, the corpus and the cache condition of each run.

**Acceptance Scenarios**:

1. **Given** an unchanged checkout, **When** the maintainer runs the bench command over a session directory, **Then** it runs the same code path as a refresh with an empty index (scan, read, parse, attribute, price, merge) and prints wall time, CPU time (user and system), average CPU, peak memory, disk bytes read, files seen and read, bytes read, lines, records, and the corpus description.
2. **Given** the bench report, **When** the maintainer reads it, **Then** it contains no content of any session line, only counts, sizes, times and the directory it ran over.
3. **Given** the bench command is run twice in a row, **When** the maintainer compares the two reports, **Then** the second shows the warm-cache figures and the disk bytes read tell the two conditions apart.
4. **Given** the baseline run, **When** the parsing change lands, **Then** the benchmark record in the spec directory holds the baseline and at least one later run, each with its commit, corpus, condition and figures.
5. **Given** the bench command, **When** the maintainer asks for a digest, **Then** it writes the per-file record digest used for the differential comparison to a path of the maintainer's choosing, never under the agents' directories.
6. **Given** a Codex rollout directory, **When** the bench command runs over it, **Then** it reports the same figures for the Codex reader.

---

### Edge Cases

- A line whose record-type key is not in the portion the reader looks at first (a different key order, or a very long tail): the reader falls back to the whole line, so classification stays correct and only costs more on that line.
- A line whose first-looked-at portion holds a `type` key of a content block (a text or tool block) but not the line's own record-type key: the nested key does not count, the reader falls back to the whole line, and the line is classified as today. The fixtures hold such a line.
- A line without any record-type key: it is neither an assistant record nor a shape line and is skipped, as today.
- A file that is replaced by a shorter one, or shrinks below its parsed offset: it is read from the start, as today.
- A file that grows while it is read: only the complete lines present at read time count; the rest waits for the next refresh.
- A batch that holds one file larger than the batch cap: it forms its own batch, as today.
- A timestamp with an offset other than `Z`, without fractional seconds, or with more than three fractional digits: parsed through the fallback when the fast path does not know the form; the instant is the same.
- A Mac with few cores (a two-core Intel): the worker count never exceeds the core count and the scan still completes.
- The bench command is pointed at a directory without a `projects` tree, or at an unreadable one: it reports the problem and exits without a report.
- The bench command is given a configuration file it cannot read or parse: it reports the problem and exits without a report; it never falls back to the app's configuration silently.
- The comparison is given a digest file that is missing or unreadable: it reports the problem and gives no verdict.
- A cold-cache run on a machine where the page cache cannot be dropped: the report still shows the disk bytes read, so the reader can tell the condition.

## Requirements *(mandatory)*

### Functional Requirements

**Measurement**

- **FR-001**: A maintainer bench command, run through the Makefile, MUST execute the refresh code path of the Claude Code session reader, and of the Codex rollout reader, over a given session directory with an empty index: directory scan, file reads, parsing, attribution, pricing and merge. It attributes with the app's configuration file by default (another file can be given) and derives the collection window from that configuration as the app does; an explicit window start can be given instead.
- **FR-002**: The bench report MUST state wall time, CPU time (user and system), average CPU (CPU time over wall time), peak resident memory, disk bytes physically read during the run, files seen, files read, bytes read, lines visited, records produced, the directory and corpus size it ran over, the configuration file and window start it used, and the commit it was built from.
- **FR-003**: The bench report MUST NOT contain the content of any session line; it holds counts, sizes, times, the paths of the directories and the configuration file given, written with `~` for the home directory, and the commit. The benchmark record of FR-006 follows the same rule, so it names no user name.
- **FR-004**: The bench command MUST be able to write a records digest: one entry per record with the record key (which carries the session id where the record key holds one), timestamp (stated at millisecond precision), model, token counts, the project its working directory resolves to, attributed account and cost, in a stable order, to a path given by the maintainer. It MUST never write under the agents' directories.
- **FR-005**: A maintainer comparison, run through the Makefile, MUST report whether two digests are identical and, when not, the first differences.
- **FR-006**: The baseline MUST be measured and recorded in the spec directory before any parsing code changes. Every later measurement MUST be appended with the commit, corpus, cache condition and figures. The record MUST hold at least the baseline and one run of the finished change, warm and cold. The warm runs can be taken by whoever implements the change; the cold runs and the real-corpus comparison of FR-009 need the maintainer's corpus and the privilege to drop the page cache, so they are maintainer steps, taken in the walkthrough before the pull request is submitted and marked as such in the record.
- **FR-007**: The refresh line of the Claude Code session source and the refresh line of the Codex session source in the diagnostic log MUST each state, next to the elapsed time they state today, the process's CPU seconds consumed between the start and the end of that refresh, as `cpu <seconds> s`.

**Same records out**

- **FR-008**: Over the fixture session files, the records produced MUST equal a committed digest file per fixture set, record for record and field for field; the test suite checks it. The digest files are generated from the unchanged code by a bench digest run and regenerated only by an explicit command when the fixtures change. Each fixture digest is generated and checked with a fixture configuration file committed next to it and an explicit window start named in the digest file, never with the app's configuration or a window derived from the current date, so the committed digests hold no real account name and do not change with the calendar.
- **FR-009**: Over the maintainer's real corpus, the digest of the new code MUST equal the baseline digest (FR-004, FR-005), and the result MUST be noted in the benchmark record. A difference that turns out to be a bug of the old code is fixed as its own change first; the baseline digest is then taken again from that fix, and the comparison must show zero differences.
- **FR-010**: The read-only guarantee, the per-file parsed offsets, the complete-lines-only rule, CRLF tolerance, the dedupe by message or request id, the batch cap on bytes read at once, and the re-read rules of specs 035, 037 and 038 MUST be unchanged.
- **FR-011**: The Codex reader MUST produce the same sessions, totals, plan markers and fork handling as today; its tests pass unchanged.

**Scan behavior**

- **FR-012**: The reader MUST visit the lines of a file in place over the file's buffer; it MUST NOT make a copy of every line. Only the lines classified as candidates (FR-013) may be copied or referenced for decoding and attribution. Memory held during a batch is bounded by the batch's bytes and the records produced.
- **FR-013**: The reader MUST determine each line's record type from a bounded portion of the line first, and MUST look at the whole line when that portion holds no record-type key, so a line whose key sits elsewhere is classified the same as today. The record-type key is the line's own top-level `type` member; a `type` key nested inside the message content (a text or tool block) does not count, so a portion that holds only nested `type` keys holds no record-type key.
- **FR-014**: Only lines classified as assistant records MUST be decoded, and only lines classified as shape lines MUST be searched for configured directories. A line whose record type the bounded reading cannot settle, and whose whole line holds a candidate marker (FR-013's fallback), follows today's path: it is decoded, and searched for directories when it yields no record.
- **FR-015**: Both readers MUST parse timestamps with one shared parser that handles the forms the agents write directly and hands any other form to the system formatter; for every form in the fixtures its result MUST equal the system formatter's at millisecond precision, the finest the agents write. A text that neither parses yields no record both ways.
- **FR-016**: The Codex reader MUST decode its relevant lines into typed values holding only the fields it uses, not into generic dictionaries.
- **FR-017**: Files MUST be parsed by a bounded number of workers, never more than the machine's cores, at a priority below user interaction, with the largest files first, so the Mac stays responsive and the user interface and other sources are not held up by the scan. The same bound and priority apply to every refresh, the first scan and the incremental ones alike.
- **FR-018**: The source MUST NOT block the shared concurrency pool while the workers run; other sources refresh and the UI responds during the scan. A test checks that a second refresh completes while the workers of a first are busy; the walkthrough checks scenario 3 of User Story 1 by hand.

**Scope and dependencies**

- **FR-019**: The change MUST add no dependency and no build toolchain; it uses the platform's libraries only.
- **FR-020**: A hand-written field extractor that replaces the JSON decoding of candidate lines is OUT of scope; it is taken up only if the finished change misses a first scan under 3 s within 200% average CPU (the targets of SC-001 and SC-002 before the 2026-11-01 change, see "Changelog") for a reason the bench attributes to parsing, as its own change with its own differential test. A miss of the cold-cache figure that the baseline's cold run attributes to reading the corpus from disk is noted in the benchmark record and is not a reason to take it up.
- **FR-021**: The OpenCode reader is out of scope.

### Key Entities

- **Scan measurement**: One bench run: commit, directory, corpus size (files, bytes, lines), cache condition, wall time, CPU time, average CPU, peak memory, disk bytes read, files seen and read, bytes read, records.
- **Benchmark record**: The file in the spec directory holding the baseline and every later measurement, each with its commit.
- **Records digest**: The per-record metadata the differential comparison compares: record key, timestamp, model, token counts, project, account, cost. Never message content.
- **Line classification**: The record type of one line (assistant record, shape line, other), decided from a bounded portion of the line with a whole-line fallback; a line the fallback cannot settle follows today's path (FR-014).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On the maintainer's corpus (about 2,300 files and 3.5 GB in the collection window), the first scan takes at most half the baseline's wall time, run back to back with the baseline in the same cache state, warm and cold.
- **SC-002**: During that scan the app uses at most a quarter of the baseline's CPU time, and at most 200% CPU on average whenever the corpus comes from disk.
- **SC-003**: Peak memory during the first scan is no higher than the baseline's.
- **SC-004**: The records digest of the new code equals the baseline digest over the fixtures and over the real corpus: zero differences.
- **SC-005**: A refresh with a handful of changed files is no slower than the baseline.
- **SC-006**: The Codex reader's CPU time over the maintainer's Codex corpus is at least 40% below the baseline's (mean of five alternating runs of each binary).
- **SC-007**: The benchmark record exists in the spec directory with the baseline and at least one run of the finished change, warm and cold, each naming its commit.
- **SC-008**: The whole test suite passes, and the Codex tests pass without changes to their expectations.

## Changelog

- **2026-11-01, SC-001, SC-002 and SC-006 evolved** (maintainer's decision at verification). The original absolute targets were missed as measured, and the maintainer accepted the result on 2026-10-28. The criteria now state what this change delivers against the baseline; the absolute targets move to the follow-up `hand-written-field-extractor` (`brainstorm/idea-inbox.md`), measured against the same baseline. Previous wording:
  - SC-001: the first scan finishes in under 3 s wall time with a warm cache and under 3 s with a cold cache, down from 9 to 13 s.
  - SC-002: during that scan the app uses at most 200% CPU on average (CPU seconds at most twice the wall time), down from 400 to 450%.
  - SC-006: the Codex reader's CPU time is at most half the baseline's.
  - Measured against the new wording (`BENCHMARK.md`): wall 3.69 to 3.78 s against 8.06 to 9.19 s for the baseline in the same pairs (41 to 46%), warm and cold; CPU time 6.4 to 6.5 s against 31.6 to 32.1 s (20%); 167 to 194% average in every run from disk; Codex CPU 0.271 s against 0.469 s (a 42% cut).

Why the absolute targets were missed (recorded 2026-10-28, figures in `BENCHMARK.md`, section "Maintainer decision (2026-10-28)"):

- **SC-001 together with SC-002 (original targets)**: each is met on its own, never in the same run. With the corpus cached the first scan takes 2.91 s at 210% average CPU; when files come from disk it stays at 167 to 194% but takes 3.1 to 4.0 s. Both can only hold at under 6 s of CPU per scan, and the finished change costs 6.0 to 6.8 s at any worker count; JSON decoding of the assistant records is the largest share. Follow-up: the hand-written field extractor of FR-020 (idea inbox entry `hand-written-field-extractor`), measured against the same baseline.
- **SC-006 (original target)**: the Codex reader's CPU time is 58% of the baseline's (mean of five runs each, 0.469 s before, 0.271 s after), against at most 50%. Follow-up: the same extractor entry.
- Every other success criterion is met as measured; SC-007's cold rows came from the walkthrough (2026-10-30) and are in `BENCHMARK.md`.

## Assumptions

- The bench command and the digest comparison live behind Makefile targets (constitution IV); where the code lives (an executable target of the package, a hidden flag of the app, or a test marked as a benchmark) is decided in the plan.
- Runs on different days stay comparable by giving the bench command the same explicit window start; the benchmark record names it for every run.
- A cold cache is produced by dropping the page cache (`purge`) or a reboot; the measurement protocol in the spec directory says how, and the disk bytes read in the report confirm the condition.
- The records digest of the real corpus contains project paths and Codex session ids; it is written only where the maintainer asks and is never committed. The fixture digests of FR-008 are committed; the fixtures hold no private data.
- The inbox entry `parse-off-cooperative-pool` (the parallel parse blocks the actor's pool) is resolved by FR-018; `shared-codex-rollout-scan` (two Codex sources enumerate the same files per refresh) stays in the inbox.
- There is no visible UI change: no screenshot and no website copy changes (constitution V). The diagnostic log's refresh line gains CPU seconds, which no screenshot shows.
- The brainstorm's stage figures came from a throwaway script and set expectations only; the baseline of FR-006 is the reference for every claim.
- The worker count and the exact priority level are decided in the plan within FR-017's bounds; SC-001 and SC-002 judge the choice.
- The cold-cache runs and the real-corpus digest comparison are maintainer steps (FR-006, FR-009): they need the maintainer's corpus and `purge`, which asks for an administrator password. The implementation delivers the warm runs and the fixture digests; the walkthrough delivers the rest, so the automated gates judge SC-007 on the warm runs and the fixture digests until the walkthrough adds the cold runs.
- Each fixture digest is checked with a committed fixture configuration and a fixed window start (FR-008), so the test is independent of the maintainer's configuration and of the date it runs.
