# Tasks: Multi-Harness Usage (Codex and OpenCode)

**Input**: Design documents from `/specs/006-multi-harness-usage/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/harness-formats.md, contracts/config-file.md, quickstart.md

**Tests**: Included. The project covers every `UsageCore` type with Swift Testing suites (`import Testing`, `@Suite`, `@Test`, `#expect`). Write each test task right before its implementation and confirm that it fails once the package compiles.

**Organization**:
- Phase 2 holds the shared model, attribution, coordinator, and aggregator changes. Every harness story depends on them.
- Stories run in priority order: US1 (OpenCode into budgets, P1), US2 (Codex API key, P2), US3 (Codex plan account, P2), US4 (locations and diagnostics, P3).

**Global constraints** (from plan.md):
- No package dependencies; the `SQLite3` system module is allowed.
- Never open `~/.codex/auth.json` or any credential file.
- Open the OpenCode database read-only, with a busy timeout of 250 ms or less.
- No em-dash or en-dash characters.
- Claude Code reading behaviour is unchanged.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on incomplete tasks)
- **[Story]**: US1 to US4

---

## Phase 1: Setup

- [X] T001 Run `make test` and confirm all existing suites pass (baseline).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Common record fields, new account and provider kinds, harness-aware attribution, per-source partial failures, the per-harness split, and model id normalization. Claude Code behaviour stays unchanged. The package must compile and pass at the end of this phase.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T002 In `Sources/UsageCore/Config/Paths.swift`, add `defaultCodexHome = "~/.codex"` and `defaultOpenCodeDirectory = "~/.local/share/opencode"`.
- [X] T003 In `Sources/UsageCore/Config/Configuration.swift` and `Sources/UsageCore/Logs/Attribution.swift` (research R9, data-model):
  - Add `Harness` cases `.codex` and `.openCode`, with a `displayName` ("Claude Code", "Codex", "OpenCode").
  - Add `Provider.openai`.
  - Add `public struct CodexSubscriptionSettings: Codable, Equatable, Sendable { public var codexHome: String = Paths.defaultCodexHome }` and `AccountKind.codexSubscription(CodexSubscriptionSettings)`. Add the accessors `codexSubscription` and `isCodexSubscription`. `typeName` returns `"codexSubscription"`.
  - In `IconDefaults`, map `Provider.openai` and `.codexSubscription` to `"brands:openai"`.
  - Add `Configuration.codexHomes: [String]`, `openCodeDirectories: [String]` (optional keys, default `[]`) and `codexSubscriptionAccounts`.
  - `Account` decode/encode handles type `"codexSubscription"` with an optional `codexHome`.
  - In `validate()`, reject two Codex subscription accounts with the same expanded `codexHome`.
  - Change `Configuration.tokenBasedAccounts` to filter on `kind.tokenBased != nil`, not `!isSubscription`, so Codex subscription accounts are never treated as priced token accounts. `subscriptionAccounts` stays `.subscription` only, which keeps `SubscriptionSource`, alignment and the network fingerprint free of Codex accounts.
  - Replace `Provider.builtInRule: DetectionRule` with `func builtInRule(for harness: Harness) -> DetectionRule?`, and add `DetectionRule.providerHint(Set<String>)`, which matches `raw.providerHint`. The rules are:
    - Claude Code: `.vertex` maps to `.requestIdPrefix("req_vrtx_")`, and `.openai` to nil.
    - OpenCode: `.vertex` maps to `.providerHint(["google-vertex", "google-vertex-anthropic"])`, and `.openai` to `.providerHint(["openai"])`.
    - Codex: `.vertex` maps to nil, and `.openai` to `.providerHint(["apikey"])`.
    Keep `Attributor` compiling by using the Claude Code rules for now, so Claude Code results are unchanged. T007 adds the harness branching.
  - Update every exhaustive switch over `AccountKind`/`Provider` in `Sources/` so the package compiles. In `Sources/UsageCore/Bar/BarLayout.swift`, `.codexSubscription` yields no bar item. `Configuration.dataRelevant()` blanks icon and displayName for every account as today; Codex subscription accounts need nothing else. Settings and dropdown views may temporarily show the new kind minimally; US3 finalizes them.
- [X] T004 Add tests in `Tests/UsageCoreTests/ConfigurationTests.swift` (FR-016 to FR-018, contracts/config-file.md):
  - A `codexSubscription` account with and without `codexHome` decodes and round-trips.
  - `provider: "openai"` decodes.
  - `codexHomes` and `openCodeDirectories` are optional and round-trip.
  - A previous-version file decodes unchanged.
  - A duplicate Codex home fails `validate()`.
  - `IconDefaults` returns `brands:openai` for both new kinds.
- [X] T005 In `Sources/UsageCore/Logs/UsageRecord.swift`, add the following, all with defaults so existing call sites compile (R2):
  - To `RawUsageRecord`: `harness: Harness = .claudeCode`, `providerHint: String? = nil`, `reasoningTokens: Int = 0`, `sessionId: String? = nil`.
  - To `UsageRecord`: `harness` and `reasoningTokens`, both carried over by `init(raw:...)`.
- [X] T006 Add tests in `Tests/UsageCoreTests/AttributionTests.swift` for harness-aware attribution (FR-011 to FR-015, R5):
  - OpenCode records with `providerHint` `google-vertex` and `google-vertex-anthropic` go to the Vertex account. `openai` goes to an OpenAI token-based account. `anthropic` and `litellm` go to Unassigned.
  - Codex `providerHint "apikey"` goes to the OpenAI account. `"chatgpt"` goes to the Codex subscription account.
  - Two Codex subscription accounts are told apart by `fileConfigDirectory == codexHome`.
  - A custom marker matches an OpenCode and a Codex raw line and wins over the built-in rule.
  - Claude Code records keep today's results, including `req_vrtx_`.
  - The attributor `fingerprint` changes when a Codex subscription account is added.
- [X] T007 In `Sources/UsageCore/Logs/Attribution.swift`, implement the per-harness built-in rules from R5:
  - Candidates know their kind (Anthropic subscription, Codex subscription, token-based with provider) and their directory (credential directory or expanded Codex home).
  - `accountId(for:rawLine:fileConfigDirectory:)` branches on `raw.harness` and evaluates `builtInRule(for: raw.harness)`. The "subscription only when no token-based rule matches" check for Claude Code uses only Claude Code token rules. Codex `"chatgpt"` matches Codex subscription accounts.
  - Claude Code rules stay unchanged. A Claude Code record never matches an OpenAI account or a Codex subscription account.
  - Include the new kinds in `fingerprint`.
- [X] T008 Add a test in `Tests/UsageCoreTests/PriceTableTests.swift`: `canonicalModel("claude-opus-4-6@default") == "claude-opus-4-6"`, and a record with that model prices like `claude-opus-4-6`. The existing `@20250929`-style cases still pass (FR-020a).
- [X] T009 In `Sources/UsageCore/Pricing/PriceTable.swift`, change `canonicalModel(_:)` to strip any trailing `@<suffix>` (R8).
- [X] T010 In `Sources/UsageCore/Snapshot/UsageSnapshot.swift` (R7, R10):
  - Add `public struct RecordBatch: Sendable { public var records: [UsageRecord]; public var issues: [String]; public var staleHarnesses: Set<Harness> }`.
  - Add `public struct HarnessUsage: Equatable, Sendable { harness, totalTokens, costUSD: Decimal?, priced: Bool }`.
  - Add `UsageBreakdown.perHarness: [HarnessUsage]` (default `[]`), `ModelUsage.reasoningTokens: Int` (default 0), and `UsageSnapshot.planAccounts: [String: TokenAccountEntry]` (default `[:]`).
  - In `Sources/UsageCore/Snapshot/RefreshCoordinator.swift`, add `SourceOutput.recordBatch(RecordBatch)`. In the same task, handle the new case in both exhaustive switches in `performRefresh`: break in the network-outcome switch, and append `batch.records` in the gathering switch. This keeps the package compiling. T012 adds issues and stale handling.
- [X] T011 Add tests (R7, R10, FR-006, FR-021, SC-004):
  - In `Tests/UsageCoreTests/AggregatorTests.swift`:
    - `perHarness` lists Claude Code and OpenCode with tokens and cost that sum to the entry total, sorted by cost.
    - `ModelUsage.reasoningTokens` sums reasoning.
    - With `staleHarnesses: [.openCode]`, entries containing OpenCode records are stale and entries without OpenCode records are not.
  - In `Tests/UsageCoreTests/RefreshCoordinatorTests.swift`: a stub source returning `.recordBatch` with one issue and `staleHarnesses = [.openCode]` produces one `SourceError` naming the issue, and does not mark a Claude-Code-only group stale.
- [X] T012 Implement T011 (R7, R10):
  - `Aggregator.aggregate` gains a `staleHarnesses: Set<Harness> = []` parameter. It builds `perHarness` in `breakdown(...)`, sums `reasoningTokens` per model, and marks entries stale when any of their records has a harness in `staleHarnesses`.
  - `RefreshCoordinator.performRefresh` handles `.recordBatch` wherever it handles `.records`:
    - It appends the records.
    - It turns each issue into `SourceError(sourceName:message:at:)`.
    - It unions `staleHarnesses` and passes them to `aggregate`.
    - It logs `ok: N record(s)` for the batch.
    - When a record source throws, the existing carry-over also copies `planAccounts` and marks them stale.
  - Accepted limitation: if a harness is stale before it ever produced records (busy on the first refresh), no entry is marked stale. The issue still appears as a source error.
- [X] T013 Run `make test` and `make build`. All suites pass.

**Checkpoint**: Shared seam ready, Claude Code behaviour unchanged.

---

## Phase 3: User Story 1 - OpenCode usage counts toward the right budget (Priority: P1) 🎯 MVP

**Goal**: OpenCode assistant messages are read from its database, attributed by `providerID`, priced from the price table, and visible in the per-harness split.

**Independent Test**: With a temporary OpenCode database containing completed `google-vertex` messages in the window and a Vertex account, the snapshot shows the Vertex spend including those messages. The per-harness split shows OpenCode.

### Tests for User Story 1

- [X] T014 [US1] Create `Tests/UsageCoreTests/OpenCodeSourceTests.swift` with a helper that builds a temporary `opencode.db` through `SQLite3`. It creates the `session` table (`id`, `directory`) and the `message` table (`id`, `session_id`, `time_created`, `time_updated`, `data`), matching contracts/harness-formats.md. Add tests (FR-004, FR-005, FR-008b, FR-009, FR-019):
  - Only completed assistant messages produce records. User messages and messages without `time.completed` produce none.
  - The timestamp is `time.completed`.
  - `outputTokens == output + reasoning`, and `reasoningTokens == reasoning`.
  - Cache read and cache write go to `cacheReadTokens` and `cacheWrite5mTokens`.
  - cwd comes from `path.cwd`, falling back to `session.directory`.
  - `providerHint == providerID`.
  - OpenCode's `cost` is ignored: the record cost comes from the price table.
  - Updating a message's `time_updated` and tokens replaces its record and does not add one.
  - A second collect with no changes re-reads no rows (assert through a counter exposed for tests or through the watermark).
  - A database held under an exclusive lock returns the previous records with `staleHarnesses == [.openCode]` and one issue.
  - A missing database yields no records and no issue.
  - A record attributed to a Vertex account by `google-vertex` gets that account id.
  - The session id comes from the `message.session_id` column (`message.data` has no session id).
  - An errored assistant message with tokens counts. A completed message with zero tokens adds no record.
  - A message whose `path.cwd` is inside a git repository resolves to that project (FR-010).
  - Adding a Vertex account after the first collect re-attributes stored records without re-reading rows (fingerprint change).
  - Lock setup: open a second read-write connection, set `PRAGMA journal_mode=DELETE`, and hold `BEGIN EXCLUSIVE` while the source collects.

### Implementation for User Story 1

- [X] T015 [US1] Create `Sources/UsageCore/Logs/OpenCodeSource.swift` (R6):
  - `public actor OpenCodeSource: WindowSensitiveSource` with `sourceName = "opencode"`.
  - `init(paths:log:builtInPrices:importedPrices:)`, mirroring `SessionLogSource`.
  - A private SQLite wrapper (open with `SQLITE_OPEN_READONLY`, `sqlite3_busy_timeout(250)`, prepare, bind, step, and finalize via `defer`).
  - For each database in `directories(for:)` (the default `Paths.defaultOpenCodeDirectory` plus `configuration.openCodeDirectories`, expanded and deduped by canonical path), keep a watermark and `[String: RawUsageRecord]`. Query rows with `time_updated > watermark`.
  - Decode the rows into raw records (harness `.openCode`).
  - Select `m.session_id` for the record's `sessionId`, and use `requestId = ""`.
  - Attribute, price and resolve the project for newly read rows. Re-attribute and re-price all stored raw records only when `Attributor.fingerprint` or the effective `PriceTable` changed since the last collect, as `LogIndex` does. This keeps incremental refreshes cheap (SC-003). Use `fileConfigDirectory` set to the data directory. Prune records before `window.start`.
  - Return `.recordBatch`. Busy, locked, or open errors leave the stored records in place, add an issue, and add `.openCode` to `staleHarnesses`.
  - `resetForEarlierWindow()` clears the watermarks and records.
- [X] T016 [US1] In `Sources/AgentMeter/App.swift`, construct and register `OpenCodeSource` next to `SessionLogSource`, logging and skipping it if initialisation fails.
- [X] T017 [US1] In `Sources/AgentMeter/BreakdownView.swift`, add a "Harnesses" option to the existing details switch (models, projects). It lists `breakdown.perHarness` rows: the harness display name, total tokens, and cost when priced. In the per-model table, the Out cell's hover text says "of which reasoning N" when `reasoningTokens > 0`. Change `DetailsMode.title` from a two-way ternary to a switch. Update the legend text (FR-021, FR-008).
- [X] T018 [US1] Run `make test` and `make build`.

**Checkpoint**: OpenCode usage counts toward matching budgets (MVP).

---

## Phase 4: User Story 2 - Codex usage with an API key is priced (Priority: P2)

**Goal**: Codex rollout files are parsed into usage records. Sessions without a plan marker are attributed to OpenAI token-based accounts and priced.

**Independent Test**: With synthetic Codex rollout files without a plan marker and an OpenAI account, the account's spend equals the priced deltas of the running totals.

### Tests for User Story 2

- [X] T019 [P] [US2] Create synthetic fixtures under `Tests/UsageCoreTests/Fixtures/codex/`, following contracts/harness-formats.md:
  - `apikey-session.jsonl`: `session_meta`, `turn_context` with a model and cwd, and three `token_count` events with growing totals, one exact duplicate, one `info: null`, and `plan_type: null`.
  - `plan-session.jsonl`: as above, but a later event carries `rate_limits.plan_type: "plus"`.
  - `subagent-session.jsonl`: the first `session_meta` has `source.subagent.thread_spawn.parent_thread_id` set to the id of `plan-session`. A second `session_meta` line (the parent's) follows, as in real forked files. There is no plan type.
  - `review-subagent.jsonl`: `source.subagent` is the string `"review"`, with no parent link and no plan type.
  - `truncated.jsonl`: the last line is cut off.
- [X] T020 [US2] Create `Tests/UsageCoreTests/CodexSessionParserTests.swift` (FR-008, FR-008a, FR-014, R3):
  - Deltas: input = Δinput − Δcached − Δcache_write, cache read = Δcached, cache write (5m) = Δcache_write, output = Δoutput including reasoning, reasoning = Δreasoning.
  - The duplicate, null and zero events add no records.
  - The timestamp comes from the line, and the model from the latest `turn_context`.
  - Message ids are stable across two parses of the same file.
  - `planMarker` is false for `apikey-session` and true for `plan-session`.
  - `parentSessionId` is read from `source.subagent.thread_spawn.parent_thread_id`, falling back to `forked_from_id`.
  - Only the first `session_meta` line defines the session (id, cwd), and the duplicated parent meta line is ignored.
  - `review-subagent` has no parent, and its `planMarker` is false.
  - Records carry `requestId == ""` and `sessionId`.
  - The truncated last line is skipped without failing.
- [X] T021 [US2] Create `Sources/UsageCore/Logs/CodexSessionParser.swift`: `public struct CodexSessionParser` with `func parse(data: Data) -> CodexSession`, `public struct CodexSession { sessionId, parentSessionId, cwd, planMarker, metaLine: String, records: [CodexRecord] }` and `public struct CodexRecord { raw: RawUsageRecord; line: String }`, implementing R3. Records use harness `.codex`, `requestId ""`, and `providerHint` left nil. Use only the first `session_meta` line. The parent is read from `source.subagent.thread_spawn.parent_thread_id`, then `forked_from_id`; when `source.subagent` is a string or another shape, there is no parent. Tolerate unknown or missing fields by skipping the line.
- [X] T022 [US2] Create `Tests/UsageCoreTests/CodexSessionSourceTests.swift`, with a helper that installs fixtures as `<home>/sessions/YYYY/MM/DD/rollout-<name>.jsonl`, because the existing `Fixtures.install` writes under `projects/` (FR-002, FR-004, FR-010, FR-012, FR-014):
  - With an installed home containing `apikey-session.jsonl` and an OpenAI token-based account, the records are attributed to that account and priced (`providerHint == "apikey"`).
  - Without an OpenAI account, they go to Unassigned.
  - A missing default home yields no records and no issue.
  - A second collect with unchanged files does not re-parse them (test counter).
  - Files with an mtime before `window.start` are dropped.
  - A session whose cwd is inside a git repository resolves to that project (FR-010).
- [X] T023 [US2] Create `Sources/UsageCore/Logs/CodexSessionSource.swift` (R4):
  - `public actor CodexSessionSource: WindowSensitiveSource` with `sourceName = "codex"` and an init that mirrors `SessionLogSource`.
  - Scan `<home>/sessions/**/rollout-*.jsonl` for `Paths.defaultCodexHome` plus `configuration.codexHomes` (canonical paths, first home wins).
  - Keep a per-file cache `{size, mtime, home, session}` and re-parse only changed files.
  - Resolve each session's mode: own marker, else the parent's resolved mode when the parent session is cached, else API key. Set `providerHint` to `"chatgpt"` or `"apikey"`.
  - Attribute with `fileConfigDirectory = home`. The raw line for custom markers is `session.metaLine + "\n" + record.line`.
  - Price and resolve the project, prune before `window.start`, and return `.recordBatch`.
  - An unreadable configured home becomes an issue. A missing default home is skipped silently.
  - `resetForEarlierWindow()` clears the cache.
- [X] T024 [US2] Register `CodexSessionSource` in `Sources/AgentMeter/App.swift`.
- [X] T025 [US2] In `Sources/AgentMeter/AccountSettingsView.swift`, offer `openai` in both provider pickers (the token-based editor and the new-account sheet), shown as "OpenAI", with the default icon applied per `IconDefaults` when the provider changes in the new-account sheet (FR-016).
- [X] T026 [US2] Run `make test` and `make build`.

**Checkpoint**: Codex API-key usage is priced into OpenAI budgets.

---

## Phase 5: User Story 3 - Codex usage with a ChatGPT plan is visible (Priority: P2)

**Goal**: Plan sessions (and their subagents) go to a Codex subscription account, shown with tokens only over the weekly window.

**Independent Test**: With `plan-session.jsonl` and `subagent-session.jsonl` and a Codex subscription account, `snapshot.planAccounts[accountId]` lists the tokens of both sessions. The account has no bar entry and no thresholds.

### Tests for User Story 3

- [X] T027 [P] [US3] Extend `Tests/UsageCoreTests/CodexSessionSourceTests.swift` (FR-014, FR-015):
  - `plan-session` and `subagent-session` are attributed to the Codex subscription account.
  - Re-attribution: write `plan-session` first without the marker event and collect, so it goes to the OpenAI account or Unassigned. Then append the marker event and collect again. All of the session's records now belong to the Codex subscription account.
  - Two Codex subscription accounts with different homes each get their home's sessions.
  - Without a Codex subscription account, plan sessions go to Unassigned (US3 scenario 3).
- [X] T028 [P] [US3] Add tests in `Tests/UsageCoreTests/AggregatorTests.swift` (FR-017):
  - Codex subscription accounts appear in `planAccounts` with the weekly window breakdown and no cost.
  - They are not in `tokenAccounts`, `groups` or `accountBudgets`.
  - In `Tests/UsageCoreTests/BarLayoutTests.swift`: a Codex subscription account never yields a bar item.
  - In `Tests/UsageCoreTests/ThresholdTrackerTests.swift`: it yields no crossings.

### Implementation for User Story 3

- [X] T029 [US3] In `Sources/UsageCore/Snapshot/Aggregator.swift`, build `planAccounts` for `configuration.codexSubscriptionAccounts` from their records over the weekly window, with `priced: false` and stale by harness. `BarLayout` already ignores the kind (T003), and `ThresholdTracker` iterates only budget owners and Anthropic subscriptions, so both ignore it.
- [X] T030 [US3] In `Sources/AgentMeter/AccountSettingsView.swift`:
  - Add "Codex subscription" to the Add menu.
  - Add a `CodexSubscriptionEditor` with a Codex home text field (default `~/.codex`) and the shared name, icon and custom marker fields. It has no shown-in-bar setting and no thresholds.
  - The list subtitle reads "Codex subscription".
  - The default icon is `brands:openai`.
- [X] T031 [US3] In `Sources/AgentMeter/DropdownView.swift`, add a Codex plan section after the Claude subscription sections: icon and name, total tokens for the week, and `BreakdownView(breakdown:showsCost: false, period: .weekly)`, plus the stale note. It has no percent and no reset (FR-017).
- [X] T032 [US3] Run `make test` and `make build`.

**Checkpoint**: Codex plan usage is visible.

---

## Phase 6: User Story 4 - Harness locations and visibility (Priority: P3)

**Goal**: Extra Codex homes and OpenCode directories are configurable, per-location failures are isolated and reported, and the diagnostic log names every harness and location.

**Independent Test**: With an extra Codex home and a nonexistent extra OpenCode directory configured, Codex usage from both homes is counted once, and the missing directory appears as a source error. Claude Code values stay fresh.

### Tests for User Story 4

- [X] T033 [P] [US4] Extend `Tests/UsageCoreTests/CodexSessionSourceTests.swift` (FR-003, FR-006):
  - An extra home is read.
  - The same file reachable through two configured homes (one a symlink) is counted once.
  - A configured but nonexistent home yields one issue and the other homes' records.
- [X] T034 [P] [US4] Extend `Tests/UsageCoreTests/OpenCodeSourceTests.swift` (FR-003, FR-006): a configured but nonexistent extra directory yields one issue, and two configured paths to the same database are read once.

### Implementation for User Story 4

- [X] T035 [US4] In `Sources/AgentMeter/SettingsView.swift` (`GeneralSettingsTab`), add the sections "Additional Codex homes" and "Additional OpenCode data directories". They mirror the existing "Additional Claude Code directories" section: list, add and remove, with a caption naming the default location (FR-003).
- [X] T036 [US4] In `Sources/UsageCore/Logs/CodexSessionSource.swift` and `Sources/UsageCore/Logs/OpenCodeSource.swift`, write one diagnostic log line per location per collect (FR-022). The line is either `"<location>: N record(s) in window, M file(s)/row(s) read"` or the reason the location was skipped or failed. Make the existing source issues name the harness and the location.
- [X] T037 [US4] Run `make test` and `make build`.

**Checkpoint**: All user stories complete.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T038 [P] Update `README.md`: supported harnesses (Claude Code, Codex, OpenCode), the OpenAI provider, Codex subscription accounts (tokens only for now), and the extra locations.
- [X] T039 [P] Update `specs/001-agentmeter/contracts/config-file.md` with a pointer to `specs/006-multi-harness-usage/contracts/config-file.md`.
- [X] T040 Run a temporary, uncommitted test or a `swift run` probe against the real local data (read-only):
  - Confirm that `CodexSessionParser` parses every file under `~/.codex/sessions` without crashing.
  - Confirm that the OpenCode source reads `~/.local/share/opencode/opencode.db`. Record the counts and the timing (SC-002, SC-003).
  - Do not read `~/.codex/auth.json`, and do not commit the probe.
- [X] T041 Build the app (`make app`). Record the GUI steps of `quickstart.md` as not run if GUI interaction is not possible.
  - Result: `make app` built `build/AgentMeter.app`. The manual GUI steps 1 to 4 of quickstart.md were NOT run (no GUI interaction available in the pipeline).
- [X] T042 Run `make test` and `make build` a final time.

---

## Dependencies & Execution Order

- **Phase 1**, then **Phase 2**, which blocks everything.
- **US1 (Phase 3)** depends on Phase 2.
- **US2 (Phase 4)** depends on Phase 2 and is independent of US1.
- **US3 (Phase 5)** depends on US2 (Codex parser and source).
- **US4 (Phase 6)** depends on US1 and US2 (both sources exist).
- **Polish** comes after all stories.

### Parallel Opportunities

- T019 (fixtures) can be written in parallel with T020.
- T027 (CodexSessionSourceTests) and T028 (Aggregator, BarLayout and ThresholdTracker tests) touch different files.
- T033 and T034 touch different test files.
- T038 and T039 are independent documentation edits.

## Implementation Strategy

1. Phase 2: the shared seam. Nothing changes for Claude Code.
2. US1 (MVP): OpenCode usage counts toward existing budgets.
3. US2 and US3: Codex usage, priced (API key) or visible (plan).
4. US4: extra locations and diagnostics.
5. Polish, including a read-only probe against the real local data.
