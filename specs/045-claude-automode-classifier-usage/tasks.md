# Tasks: Claude Code Auto-mode Classifier Usage

**Input**: Design documents from `/specs/045-claude-automode-classifier-usage/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/decision-log.md, quickstart.md

**Tests**: Required. Constitution II demands test-first for all `UsageCore` logic: in every phase the test task comes first and must fail before its implementation task. Tests use Swift Testing (`import Testing`) and run only through `make test`.

**Conventions for every task**: doc comments cite `spec 045 FR-xxx`; no em dash or en dash anywhere; build and test only with `make test` / `make test-release` (never `swift build` or `xcodebuild`).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: User story (US1 to US4)

---

## Phase 1: Setup

- [X] T001 Create sanitized fixtures in `Tests/UsageCoreTests/Fixtures/classifier/`: `probe-session.jsonl` (one Claude Code session, sessionId `probe-session`, cwd `/fixture/W`, model `rits/zai-org/glm-5-3`, three assistant records between 17:36:23Z and 17:38:51Z on 2026-11-12 whose usage sums to 18,666 input, 61,440 cache read, 62 output = 80,168 tokens) and `probe-decisions.jsonl` (the two lines of `contracts/decision-log.md`, ts 1794505114575 and 1794505124339, summing to 969 input, 68,608 cache read, 47 output = 69,624). Tests copy them into a temporary directory and rewrite `/fixture/W` to the real temporary path.

---

## Phase 2: Foundational (blocks all stories)

- [X] T002 Write failing tests in `Tests/UsageCoreTests/UsageRecordOriginTests.swift`: `UsageRecord` has `sessionKey: String?`, `cwd: String?` and `origin: RecordOrigin` defaulting to `nil`, `nil`, `.session`; `UsageRecord(raw:...)` copies `raw.cwd`; `LogIndex.update` over `Fixtures/direct-session.jsonl` stamps `sessionKey` with the record's `sessionId`; over a temporary session file whose assistant line has a `cwd` and no `sessionId`, it stamps `sessionKey` with the file's canonical path and `cwd` with the raw cwd (data-model "UsageRecord (changed)"; `direct-session.jsonl` has a `sessionId` on every line and no `cwd`, so it cannot cover the fallback).
- [X] T003 Implement T002: add `public enum RecordOrigin: Sendable, Equatable { case session, classifier }` and the three defaulted fields to both initializers in `Sources/UsageCore/Logs/UsageRecord.swift`; in `Sources/UsageCore/Logs/LogIndex.swift` `readAndMerge`, pass `sessionKey: raw.sessionId ?? file.canonicalPath`, reusing one `String` instance per distinct `sessionKey` and `cwd` value within a job's merge (a small dictionary per job, research R2 "Memory"). Run `make test`: every existing test still passes (SC-003 groundwork, FR-011).

---

## Phase 3: User Story 1, classifier usage counts toward the account (P1) MVP

**Goal**: One session plus its decision log gives the combined total on the session's account, same model row, same project.

**Independent test**: the probe fixture gives 149,792 tokens on the account (SC-001).

- [X] T004 [P] [US1] Write failing tests in `Tests/UsageCoreTests/ClassifierRowParserTests.swift` for `ClassifierRowParser.parse(line: Data, offset: Int, logPath: String) -> ClassifierLineResult`: a contract line yields `.row` with `id == "<logPath>#<offset>"`, `timestamp == Date(timeIntervalSince1970: ts / 1000)`, model `rits/zai-org/glm-5-3` (trailing `[1m]` removed, FR-009), counters mapped `inputTokens`→input, `cacheReadInputTokens`→cacheRead, `cacheCreationInputTokens`→cacheWrite5m, `outputTokens`→output, absent counters as 0 (FR-008); unknown fields ignored (US4 scenario 3); `tool`, `decision`, `costUSD` never decoded (FR-015: the decoded struct has only the six fields).
- [X] T005 [P] [US1] Implement `Sources/UsageCore/Logs/ClassifierRowParser.swift` per research R3, R6, R7: byte pre-check for `"classifierModel"`, minimal `Decodable` with `ts: Double`, `classifierModel: String`, four counters decoded so that absent and invalid are distinguishable; strip exactly one trailing `[...]` suffix from the model.
- [X] T006 [P] [US1] Write failing tests in `Tests/UsageCoreTests/DecisionLogProbeTests.swift` for the found and absent cases: `DecisionLogProbe.check(directories: [String], known: [String: KnownLogState]) -> ProbeReport` (data-model "ProbeResult and ProbeReport") returns per raw directory `.found(path:, size:, modificationDate:, chunk:)` for a directory with a regular `.automode_decisions.jsonl`, with `chunk` holding all bytes from 0 for an unknown file, the bytes from `parsedOffset` for a grown known file, all bytes from 0 for a file shorter than `parsedOffset`, and nil when size and modification date equal the known state; `.absent` without one or for a directory that does not exist, and `canonical[raw]` with the canonical directory; two spellings of one directory (trailing slash, symlinked parent) map to one canonical directory whose log is reported once (FR-001).
- [X] T007 [P] [US1] Implement the synchronous core of `Sources/UsageCore/Logs/DecisionLogProbe.swift`: canonicalize with `Attributor.canonical` inside the check, `lstat` `<dir>/.automode_decisions.jsonl`, and for a new or changed file open it with `O_RDONLY | O_NOFOLLOW | O_NONBLOCK`, `fstat` it (regular file check) and read the unread bytes (research R5 "Where"), map to `ProbeResult`, fill `ProbeReport.canonical`; nothing outside the probe opens a decision log; an injectable `check` closure and an injectable timeout (default 2 s) for tests. This is the only place that canonicalizes a working directory. Concurrency and timeout come in T024.
- [X] T008 [US1] Write failing tests in `Tests/UsageCoreTests/ClassifierLogIndexTests.swift` for the first read: `ClassifierLogIndex.update(report: ProbeReport, window: DateInterval) -> ClassifierIndexStats` (data-model "ClassifierIndexStats") parses the chunk of a `.found` result (built by hand in the test, no file needed), stores complete-line rows with `ts` at or after `window.start` (FR-004), keyed by canonical log path, `rows` in file order, `parsedOffset` at the end of the last complete line.
- [X] T009 [US1] Implement the first-read path of `Sources/UsageCore/Logs/ClassifierLogIndex.swift` with `DecisionLogEntry` (data-model) and `known() -> [String: KnownLogState]`, the snapshot handed to the probe; the index parses chunks and never opens a file (research R5).
- [X] T010 [US1] Write failing tests in `Tests/UsageCoreTests/ClassifierAttributionTests.swift` for one covering session: `ClassifierAttribution.records(entries: [DecisionLogEntry], sessionRecords: [UsageRecord], canonical: [String: String], pricer: PriceTable) -> ClassifierAttributionResult` (data-model "ClassifierAttributionResult") builds spans keyed by `(sessionKey, canonical[cwd])`, taking the canonical directory only from the map (a record whose raw cwd is not in the map builds no span; `Attributor.canonical` is never called here), with `start` = earliest record, `end` = latest record + 300 s (FR-005); a row inside the span gets the session's `accountId`, its `project`, `origin == .classifier`, `messageId == row.id`, empty `requestId`, `canonicalModel == PriceTable.canonicalModel(model)` and `costUSD` from `pricer.cost(model:input:output:cacheWrite5m:cacheWrite1h:cacheRead:)` (FR-007, FR-008); a row 299 s after the last record is covered, one 301 s after is not; a row whose model differs from the session's model is counted and priced under its own (normalized) model.
- [X] T011 [US1] Implement `Sources/UsageCore/Logs/ClassifierAttribution.swift` for the single-account case: spans per canonical directory; covering spans are all spans of the row's directory with `start <= t && t <= end`, found by a linear scan (spans overlap and their ends are unordered, so no binary search by start).
- [X] T012 [US1] Write failing end-to-end tests in `Tests/UsageCoreTests/SessionLogSourceClassifierTests.swift`: a `SessionLogSource` over a temporary Claude config with `probe-session.jsonl` and `probe-decisions.jsonl` in the session cwd returns records whose total for the account is 149,792 tokens (SC-001), with the two classifier records under model `rits/zai-org/glm-5-3` and the session's project (US1 scenarios 1 to 3); the same fixture without the decision log returns records equal (record by record, and by `RecordsDigest.line(for:)`) to the session records of the run with it, so nothing about session records changes (US1 scenario 4, SC-003, FR-011); with an injected probe check closure, a session whose records have no `cwd`, or whose records all lie before the window, causes no check of its directory (FR-002).
- [X] T013 [US1] Wire the step into `Sources/UsageCore/Logs/SessionLogSource.swift` `collect` inside the existing `workers.offload` closure (plan "Refresh flow"): distinct non-nil `cwd` of in-window Claude Code session records → `DecisionLogProbe.check(directories:known: classifierIndex.known())` → `ClassifierLogIndex.update` → `ClassifierAttribution.records` → return `index.records + classifierRecords`. Own the probe and the classifier index as stored properties; `resetIndex()` also resets the classifier index.

**Checkpoint**: `make test` passes; SC-001 holds.

---

## Phase 4: User Story 2, repeated refreshes never count a row twice (P1)

**Goal**: Incremental reading with the `LogIndex` rules (FR-003, FR-008a).

**Independent test**: unchanged, append, half line then rest, replace, delete.

- [X] T014 [US2] Add failing tests to `Tests/UsageCoreTests/ClassifierLogIndexTests.swift` (index fed by a real probe over temporary files): unchanged size and modification date → the probe returns no chunk (bytes read 0), rows unchanged (US2 scenario 1); one appended row → only appended bytes read, one more row (scenario 2); a last line without `\n` is not stored, completing it stores it once (scenario 3); a file shorter than `parsedOffset` → rows cleared and read from 0 (scenario 4); `.absent` → entry removed (scenario 5); a file whose modification date is before `window.start` → not read and removed (FR-002); two identical lines at different offsets → two rows (FR-008a); rows with `ts` before `window.start` are pruned on each update; when `window.start` moves earlier than the previous update's, all entries are dropped and the next update reads the files from 0, so rows pruned under the narrower window count again (as `LogIndex.update` does).
- [X] T015 [US2] Implement the incremental rules in `Sources/UsageCore/Logs/ClassifierLogIndex.swift` (applying chunks: `from == parsedOffset` appends, `from == 0` for a known file replaces the rows) and in `DecisionLogProbe.swift` (choosing the read offset from `KnownLogState`), including `lastWindowStart`; keep an entry only while its canonical directory appears among `report.canonical` values, so `.timedOut` and `.busy` directories (whose last canonical value the probe still reports) keep their entries.
- [X] T016 [US2] Add failing tests to `Tests/UsageCoreTests/SessionLogSourceClassifierTests.swift`: ten refreshes over unchanged data give identical totals; appending N rows changes totals by exactly those N rows (SC-002).
- [X] T017 [US2] Add a timing test in a `.serialized` suite in `Tests/UsageCoreTests/ClassifierLogIndexTests.swift`: 50 temporary directories each with a 100 KB decision log and one session record each, one cold run of the full classifier step (probe, then index update, then attribution), then a second run with unchanged files measured with `ContinuousClock` and asserted under 50 ms (SC-004, research R8). Make it pass.

**Checkpoint**: `make test` passes; SC-002 and SC-004 hold.

---

## Phase 5: User Story 3, unclear rows stay unassigned (P2)

**Goal**: FR-006 decision rule and recomputation every refresh.

**Independent test**: two overlapping sessions on different accounts in one directory.

- [X] T018 [US3] Add failing tests to `Tests/UsageCoreTests/ClassifierAttributionTests.swift`: overlapping spans on accounts A and B → unassigned (US3 scenario 1); overlapping spans both on A → A (scenario 2); no covering span → unassigned (scenario 3); covering span whose records are unassigned → unassigned (scenario 4); one span whose records went to A and B (or A and nil) → unassigned (FR-006, edge case "two accounts"); a session that started before the window has its span start at its first in-window record (FR-005).
- [X] T019 [US3] Implement the decision rule in `Sources/UsageCore/Logs/ClassifierAttribution.swift`: union of `accounts: Set<String?>` of all covering spans; exactly one element that is non-nil → that account, else nil.
- [X] T020 [US3] Add failing tests to `Tests/UsageCoreTests/SessionLogSourceClassifierTests.swift`: a row 6 minutes after the session's last record is unassigned; after a new record is appended to the session file only, the next refresh assigns it without reading the decision log again (US1 scenario 5, FR-006 recompute); a second session on another account appearing later in the same directory makes a covered row unassigned; no fixture row is assigned when its covering sessions disagree (SC-005). Make them pass (attribution runs on every refresh over all cached rows).

**Checkpoint**: `make test` passes; SC-005 holds.

---

## Phase 6: User Story 4, a changed log format fails quietly (P3)

**Goal**: Skipped lines never disturb the rest; diagnostics separate normal from broken (FR-004, FR-013).

**Independent test**: a mixed fixture counts only valid usage rows.

- [ ] T021 [P] [US4] Add failing tests to `Tests/UsageCoreTests/ClassifierRowParserTests.swift`: no counters → `.withoutUsage`; all counters zero → `.withoutUsage`; not JSON, missing or non-numeric `ts`, missing or empty `classifierModel` (also `"[1m]"` alone), a negative, fractional or string counter → `.malformed` (FR-004, US4 scenarios 1, 2, 4). Make them pass in `Sources/UsageCore/Logs/ClassifierRowParser.swift`.
- [ ] T022 [US4] Add failing tests to `Tests/UsageCoreTests/SessionLogSourceClassifierTests.swift` for the log line (FR-013), using a file-backed `DiagnosticLog(fileURL:)` in a temporary directory and reading it back with `tail(lines:)` (as `LogIndexTests.swift` does): a refresh that found at least one decision log appends one line containing `decision logs read`, `rows counted`, `assigned`, `unassigned`, `without usage`, `malformed` with the right numbers for a mixed fixture; a refresh whose checked directories have no decision log and none timed out, was busy or skipped appends no such line; no line contains a tool name, row content or the log file name beyond the working directory.
- [ ] T023 [US4] Implement the counters of `ClassifierIndexStats` and `ClassifierAttributionResult` and the log line in `Sources/UsageCore/Logs/SessionLogSource.swift` (format and condition in plan "Diagnostics"), plus the double-recording note: `ClassifierAttribution` returns `doubleRecordingSessions` (a session record of a covering span whose input, output, cache read and `cacheWrite5m + cacheWrite1h` equal the covered row's four counters), and `SessionLogSource` logs each key once, remembered in a `loggedDoubleRecording` set; too-large files are logged once per path via a `loggedTooLarge` set (FR-013, FR-001, Assumptions). Test the detection in `Tests/UsageCoreTests/ClassifierAttributionTests.swift` first.

**Checkpoint**: `make test` passes.

---

## Phase 7: Polish and cross-cutting (FR-001 guards, FR-012, FR-014, FR-016)

- [ ] T024 Add failing tests to `Tests/UsageCoreTests/DecisionLogProbeTests.swift` with an injected check closure that blocks on a semaphore and an injected timeout of 0.2 s (the default stays 2 s): the check returns within about the timeout with `.timedOut` for the blocked directory and results for the others (FR-012); a timed-out raw directory whose earlier check finished keeps its last canonical value in `report.canonical`; a second `check` while the first is still blocked returns `.busy` for it and does not call the closure again; after releasing the semaphore a later check calls it again; the timed-out directory appears in `report.newlyTimedOut` once until a check of it finishes. Implement concurrency in `Sources/UsageCore/Logs/DecisionLogProbe.swift` per research R4 (concurrent queue, `DispatchGroup.wait(timeout:)` with the injected deadline, lock-protected in-flight set and last-canonical map; canonicalization inside the timed check), and log `newlyTimedOut` in `SessionLogSource`.
- [ ] T025 Add failing tests to `Tests/UsageCoreTests/ClassifierLogIndexTests.swift` and `DecisionLogProbeTests.swift`: a symlink named `.automode_decisions.jsonl` → `.notRegular`, not read; a FIFO → `.notRegular`, open does not block; a file larger than 64 MB (sparse file via `truncate`) → `.tooLarge`, not read, logged once per file; a read that blocks (injected check closure blocking after the `lstat`) yields `.timedOut` within the injected timeout like a blocked `lstat`; `.timedOut` and `.busy` keep the entry's rows, and in an end-to-end run in `SessionLogSourceClassifierTests.swift` those rows stay counted and assigned to the session's account (FR-001, FR-012). Implement in `DecisionLogProbe.swift` (size limit checked after `fstat`, before reading) and `ClassifierLogIndex.swift`.
- [ ] T026 Add a test to `Tests/UsageCoreTests/SessionLogSourceClassifierTests.swift` that a refresh never creates, modifies or deletes a file in the session working directory and its Claude config directory (compare directory listings and modification dates before and after, FR-014).
- [ ] T027 [P] Update `README.md`: a short section on Auto-mode classifier usage (what it adds, enabling it with aprofile's `features` command or `"AUTOMODE_DECISION_LOG": "1"` in the `env` block of Claude Code's `settings.json`, that the log is an undocumented Claude Code diagnostic that may change, and adding `.automode_decisions.jsonl` to a global gitignore via `core.excludesFile`), and one sentence in "Security and privacy" that AgentTacho reads this file in session working directories when it exists, reading only timestamps, model names and token counts (FR-016).
- [ ] T028 Mirror the README's new privacy sentence in the website's privacy section: in a site checkout (`gh repo clone AgentTacho/agenttacho.github.io` into a sibling directory if missing), edit `src/components/agenttacho/Privacy.astro` by hand, run the site's check, build and tests, open a site pull request, and record its link for the app pull request (constitution III and V). No screenshots change.
- [ ] T029 Run `rg -n '\x{2014}|\x{2013}' Sources Tests README.md specs/045-claude-automode-classifier-usage` (em dash and en dash by code point; must find nothing), then `make test` and `make test-release`; both must pass.

---

## Dependencies and execution order

- Phase 1 → Phase 2 → Phase 3 (MVP). Phases 4, 5, 6 each depend on Phase 3 and touch different test cases; run them in order (they share source files). Phase 7 depends on Phases 3 to 6.
- Inside Phase 3: T004/T005 (parser) and T006/T007 (probe) are independent [P]; T008/T009 need the parser and probe types; T010/T011 need the parser types; T012/T013 need all of them.

## Parallel example (Phase 3)

```text
T004 + T006 together (parser tests, probe tests), then T005 + T007 together.
```

## Implementation strategy

MVP is Phase 3: after T013 the probe fixture already counts correctly. Phases 4 and 5 make it safe for continuous use, Phase 6 makes format changes visible, Phase 7 adds the hostile-file and hung-volume guards and the documentation. Do not merge before Phase 7: the guards are part of the read-only promise.
