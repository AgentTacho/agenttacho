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

- [ ] T001 Create sanitized fixtures in `Tests/UsageCoreTests/Fixtures/classifier/`: `probe-session.jsonl` (one Claude Code session, sessionId `probe-session`, cwd `/fixture/W`, model `rits/zai-org/glm-5-3`, three assistant records between 17:36:23Z and 17:38:51Z on 2026-11-12 whose usage sums to 18,666 input, 61,440 cache read, 62 output = 80,168 tokens) and `probe-decisions.jsonl` (the two lines of `contracts/decision-log.md`, ts 1794505114575 and 1794505124339, summing to 969 input, 68,608 cache read, 47 output = 69,624). Tests copy them into a temporary directory and rewrite `/fixture/W` to the real temporary path.

---

## Phase 2: Foundational (blocks all stories)

- [ ] T002 Write failing tests in `Tests/UsageCoreTests/UsageRecordOriginTests.swift`: `UsageRecord` has `sessionKey: String?`, `cwd: String?` and `origin: RecordOrigin` defaulting to `nil`, `nil`, `.session`; `UsageRecord(raw:...)` copies `raw.cwd`; `LogIndex.update` over `Fixtures/direct-session.jsonl` stamps `sessionKey` with the record's `sessionId`, or with the file's canonical path when the line has no `sessionId`, and `cwd` with the raw cwd (data-model "UsageRecord (changed)").
- [ ] T003 Implement T002: add `public enum RecordOrigin: Sendable, Equatable { case session, classifier }` and the three defaulted fields to both initializers in `Sources/UsageCore/Logs/UsageRecord.swift`; in `Sources/UsageCore/Logs/LogIndex.swift` `readAndMerge`, pass `sessionKey: raw.sessionId ?? file.canonicalPath`. Run `make test`: every existing test still passes (SC-003 groundwork, FR-011).

---

## Phase 3: User Story 1, classifier usage counts toward the account (P1) MVP

**Goal**: One session plus its decision log gives the combined total on the session's account, same model row, same project.

**Independent test**: the probe fixture gives 149,792 tokens on the account (SC-001).

- [ ] T004 [P] [US1] Write failing tests in `Tests/UsageCoreTests/ClassifierRowParserTests.swift` for `ClassifierRowParser.parse(line: Data, offset: Int, logPath: String) -> ClassifierLineResult`: a contract line yields `.row` with `id == "<logPath>#<offset>"`, `timestamp == Date(timeIntervalSince1970: ts / 1000)`, model `rits/zai-org/glm-5-3` (trailing `[1m]` removed, FR-009), counters mapped `inputTokens`→input, `cacheReadInputTokens`→cacheRead, `cacheCreationInputTokens`→cacheWrite5m, `outputTokens`→output, absent counters as 0 (FR-008); unknown fields ignored (US4 scenario 3); `tool`, `decision`, `costUSD` never decoded (FR-015: the decoded struct has only the six fields).
- [ ] T005 [P] [US1] Implement `Sources/UsageCore/Logs/ClassifierRowParser.swift` per research R3, R6, R7: byte pre-check for `"classifierModel"`, minimal `Decodable` with `ts: Double`, `classifierModel: String`, four counters decoded so that absent and invalid are distinguishable; strip exactly one trailing `[...]` suffix from the model.
- [ ] T006 [P] [US1] Write failing tests in `Tests/UsageCoreTests/DecisionLogProbeTests.swift` for the found and absent cases: `DecisionLogProbe.check(directories: [String]) -> [String: ProbeResult]` keyed by the raw directory returns `.found(canonicalDirectory:, path:, size:, modificationDate:)` for a directory with a regular `.automode_decisions.jsonl`, `.absent` without one or for a directory that does not exist, and canonicalizes two spellings of one directory (trailing slash, symlinked parent) to one path that is checked once (FR-001).
- [ ] T007 [P] [US1] Implement the synchronous core of `Sources/UsageCore/Logs/DecisionLogProbe.swift`: canonicalize with `Attributor.canonical`, `lstat` `<dir>/.automode_decisions.jsonl`, map to `ProbeResult` (data-model "ProbeResult"); an injectable `check` closure for tests. Concurrency and timeout come in T024.
- [ ] T008 [US1] Write failing tests in `Tests/UsageCoreTests/ClassifierLogIndexTests.swift` for the first read: `ClassifierLogIndex.update(results: [String: ProbeResult], window: DateInterval) -> ClassifierIndexStats` reads a found file opened with `O_RDONLY | O_NOFOLLOW | O_NONBLOCK`, stores complete-line rows with `ts` at or after `window.start` (FR-004), keyed by canonical log path, `rows` in file order, `parsedOffset` at the end of the last complete line.
- [ ] T009 [US1] Implement the first-read path of `Sources/UsageCore/Logs/ClassifierLogIndex.swift` with `DecisionLogEntry` (data-model) and a reader that opens, `fstat`s (regular file check), seeks to the offset and reads to the end (research R5).
- [ ] T010 [US1] Write failing tests in `Tests/UsageCoreTests/ClassifierAttributionTests.swift` for one covering session: `ClassifierAttribution.records(rows:sessionRecords:pricer:) -> ClassifierAttributionResult` builds spans keyed by `(sessionKey, Attributor.canonical(cwd))` with `start` = earliest record, `end` = latest record + 300 s (FR-005); a row inside the span gets the session's `accountId`, its `project`, `origin == .classifier`, `messageId == row.id`, empty `requestId`, `canonicalModel == PriceTable.canonicalModel(model)` and `costUSD` from `pricer.cost(model:input:output:cacheWrite5m:cacheWrite1h:cacheRead:)` (FR-007, FR-008); a row 299 s after the last record is covered, one 301 s after is not.
- [ ] T011 [US1] Implement `Sources/UsageCore/Logs/ClassifierAttribution.swift` for the single-account case (spans per canonical directory, sorted by start, binary search by row time).
- [ ] T012 [US1] Write failing end-to-end tests in `Tests/UsageCoreTests/SessionLogSourceClassifierTests.swift`: a `SessionLogSource` over a temporary Claude config with `probe-session.jsonl` and `probe-decisions.jsonl` in the session cwd returns records whose total for the account is 149,792 tokens (SC-001), with the two classifier records under model `rits/zai-org/glm-5-3` and the session's project (US1 scenarios 1 to 3); without the decision log it returns exactly the records of the release before (US1 scenario 4, SC-003).
- [ ] T013 [US1] Wire the step into `Sources/UsageCore/Logs/SessionLogSource.swift` `collect` inside the existing `workers.offload` closure (plan "Refresh flow"): distinct non-nil `cwd` of in-window Claude Code session records → `DecisionLogProbe.check` → `ClassifierLogIndex.update` → `ClassifierAttribution.records` → return `index.records + classifierRecords`. Own the probe and the classifier index as stored properties; `resetIndex()` also resets the classifier index.

**Checkpoint**: `make test` passes; SC-001 holds.

---

## Phase 4: User Story 2, repeated refreshes never count a row twice (P1)

**Goal**: Incremental reading with the `LogIndex` rules (FR-003, FR-008a).

**Independent test**: unchanged, append, half line then rest, replace, delete.

- [ ] T014 [US2] Add failing tests to `Tests/UsageCoreTests/ClassifierLogIndexTests.swift`: unchanged size and modification date → file not read (bytes read 0), rows unchanged (US2 scenario 1); one appended row → only appended bytes read, one more row (scenario 2); a last line without `\n` is not stored, completing it stores it once (scenario 3); a file shorter than `parsedOffset` → rows cleared and read from 0 (scenario 4); `.absent` → entry removed (scenario 5); a file whose modification date is before `window.start` → not read and removed (FR-002); two identical lines at different offsets → two rows (FR-008a); rows with `ts` before `window.start` are pruned on each update.
- [ ] T015 [US2] Implement the incremental rules in `Sources/UsageCore/Logs/ClassifierLogIndex.swift`; also remove entries whose directory is not in this refresh's results.
- [ ] T016 [US2] Add failing tests to `Tests/UsageCoreTests/SessionLogSourceClassifierTests.swift`: ten refreshes over unchanged data give identical totals; appending N rows changes totals by exactly those N rows (SC-002).
- [ ] T017 [US2] Add a timing test to `Tests/UsageCoreTests/ClassifierLogIndexTests.swift`: 50 temporary directories each with a 100 KB decision log, one cold update, then a second update with unchanged files measured with `ContinuousClock` and asserted under 50 ms (SC-004, research R8). Make it pass.

**Checkpoint**: `make test` passes; SC-002 and SC-004 hold.

---

## Phase 5: User Story 3, unclear rows stay unassigned (P2)

**Goal**: FR-006 decision rule and recomputation every refresh.

**Independent test**: two overlapping sessions on different accounts in one directory.

- [ ] T018 [US3] Add failing tests to `Tests/UsageCoreTests/ClassifierAttributionTests.swift`: overlapping spans on accounts A and B → unassigned (US3 scenario 1); overlapping spans both on A → A (scenario 2); no covering span → unassigned (scenario 3); covering span whose records are unassigned → unassigned (scenario 4); one span whose records went to A and B (or A and nil) → unassigned (FR-006, edge case "two accounts"); a session that started before the window has its span start at its first in-window record (FR-005).
- [ ] T019 [US3] Implement the decision rule in `Sources/UsageCore/Logs/ClassifierAttribution.swift`: union of `accounts: Set<String?>` of all covering spans; exactly one element that is non-nil → that account, else nil.
- [ ] T020 [US3] Add failing tests to `Tests/UsageCoreTests/SessionLogSourceClassifierTests.swift`: a row 6 minutes after the session's last record is unassigned; after a new record is appended to the session file only, the next refresh assigns it without reading the decision log again (US1 scenario 5, FR-006 recompute); a second session on another account appearing later in the same directory makes a covered row unassigned; no fixture row is assigned when its covering sessions disagree (SC-005). Make them pass (attribution runs on every refresh over all cached rows).

**Checkpoint**: `make test` passes; SC-005 holds.

---

## Phase 6: User Story 4, a changed log format fails quietly (P3)

**Goal**: Skipped lines never disturb the rest; diagnostics separate normal from broken (FR-004, FR-013).

**Independent test**: a mixed fixture counts only valid usage rows.

- [ ] T021 [P] [US4] Add failing tests to `Tests/UsageCoreTests/ClassifierRowParserTests.swift`: no counters → `.withoutUsage`; all counters zero → `.withoutUsage`; not JSON, missing or non-numeric `ts`, missing or empty `classifierModel` (also `"[1m]"` alone), a negative, fractional or string counter → `.malformed` (FR-004, US4 scenarios 1, 2, 4). Make them pass in `Sources/UsageCore/Logs/ClassifierRowParser.swift`.
- [ ] T022 [US4] Add failing tests to `Tests/UsageCoreTests/SessionLogSourceClassifierTests.swift` for the log line (FR-013): with an in-memory `DiagnosticLog`, a refresh that checked at least one directory appends one line containing `decision logs read`, `rows counted`, `assigned`, `unassigned`, `without usage`, `malformed` with the right numbers for a mixed fixture; a refresh with no Claude Code working directory appends no such line; no line contains a tool name, row content or the log file name beyond the working directory.
- [ ] T023 [US4] Implement `ClassifierIndexStats`/`ClassifierAttributionResult` counters and the log line in `Sources/UsageCore/Logs/SessionLogSource.swift` (format in plan "Diagnostics"), plus the double-recording note: one line per session key, once per session, when a session record of a covering span carries the same four counters as a covered row (FR-013, Assumptions); test it in `Tests/UsageCoreTests/ClassifierAttributionTests.swift` first.

**Checkpoint**: `make test` passes.

---

## Phase 7: Polish and cross-cutting (FR-001 guards, FR-012, FR-014, FR-016)

- [ ] T024 Add failing tests to `Tests/UsageCoreTests/DecisionLogProbeTests.swift` with an injected check closure that blocks on a semaphore: the check returns within about 2 s with `.timedOut` for the blocked directory and results for the others (FR-012); a second `check` while the first is still blocked returns `.busy` for it and does not call the closure again; after releasing the semaphore a later check calls it again; the timed-out directory is reported for logging once until a check of it finishes. Implement concurrency in `Sources/UsageCore/Logs/DecisionLogProbe.swift` per research R4 (concurrent queue, `DispatchGroup.wait(timeout:)` with a 2-second deadline, lock-protected in-flight set; canonicalization inside the timed check).
- [ ] T025 Add failing tests to `Tests/UsageCoreTests/ClassifierLogIndexTests.swift` and `DecisionLogProbeTests.swift`: a symlink named `.automode_decisions.jsonl` → `.notRegular`, not read; a FIFO → `.notRegular`, open does not block; a file larger than 64 MB (sparse file via `truncate`) → `.tooLarge`, not read, logged once per file; `.timedOut` and `.busy` keep the entry's rows (FR-001, FR-012). Implement in `DecisionLogProbe.swift` and `ClassifierLogIndex.swift`.
- [ ] T026 Add a test to `Tests/UsageCoreTests/SessionLogSourceClassifierTests.swift` that a refresh never creates, modifies or deletes a file in the session working directory and its Claude config directory (compare directory listings and modification dates before and after, FR-014).
- [ ] T027 [P] Update `README.md`: a short section on Auto-mode classifier usage (what it adds, enabling it with aprofile's `features` command or `"AUTOMODE_DECISION_LOG": "1"` in the `env` block of Claude Code's `settings.json`, that the log is an undocumented Claude Code diagnostic that may change, and adding `.automode_decisions.jsonl` to a global gitignore via `core.excludesFile`), and one sentence in "Security and privacy" that AgentTacho reads this file in session working directories when it exists, reading only timestamps, model names and token counts (FR-016).
- [ ] T028 Mirror the README's new privacy sentence in the website's privacy section: in a site checkout (`gh repo clone AgentTacho/agenttacho.github.io` into a sibling directory if missing), edit the privacy data file named in `docs/website.md`, run the site's check, build and tests, open a site pull request, and record its link for the app pull request (constitution III and V). No screenshots change.
- [ ] T029 Run `rg -n '—|–' Sources Tests README.md specs/045-claude-automode-classifier-usage` (must find nothing), then `make test` and `make test-release`; both must pass.

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
