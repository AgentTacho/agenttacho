# Research: Multi-Harness Usage (Codex and OpenCode)

These decisions were made against `main` at `c752def`, together with the Codex and OpenCode data observed on the developer machine (2026-10-14). Codex session logs were at CLI 0.161.0. OpenCode stores its data in a SQLite database running in WAL mode.

## R1: Shape of the seam

- **Decision**: The Claude Code path stays as it is: `SessionLogSource`, `LogDirectoryScanner`, `LogIndex` and `SessionRecordParser`. Two new record sources sit next to it in `Sources/UsageCore/Logs/`, `CodexSessionSource` and `OpenCodeSource`. Each is a `WindowSensitiveSource` that emits `UsageRecord`s. All three share three things:
  - **One record type.** `RawUsageRecord` and `UsageRecord` gain `harness`, `providerHint`, `reasoningTokens` and `sessionId`.
  - **One attribution step.** `Attributor` becomes harness-aware.
  - **One pricing and project path.** That is `PriceTable` plus `ProjectResolver`.

  The "adapter" is therefore a source plus a parser per harness. Attribution, pricing, project resolution, aggregation and display are shared.
- **Rationale**:
  - Claude Code's reading is tuned for large append-only files (64 MB batches, offsets, last-wins dedupe). Codex and OpenCode have different shapes. Codex needs whole-session context to decide the auth mode and to compute deltas of the running total. OpenCode is a database queried by row watermark.
  - Pushing all three through one `LogIndex` would add branching without shared logic.
  - Approach A from the brainstorm is still met: there is one usage record and one attribution step, so a fourth harness needs only a new source and parser.
- **Alternatives considered**:
  - A protocol-based generic index for every harness was rejected. It is premature abstraction, because the read strategies have nothing in common.
  - Folding Codex into `SessionLogSource` was rejected. Its parser is line-local, while Codex needs per-session state.

## R2: Common record fields

- **Decision**:
  - `RawUsageRecord` gets new fields: `harness: Harness` (default `.claudeCode`), `providerHint: String?`, `reasoningTokens: Int` (default 0) and `sessionId: String?`. `UsageRecord` carries `harness` and `reasoningTokens`.
  - `outputTokens` is always the priced output, which includes reasoning. OpenCode reports reasoning separately, so it is added to output at parse time. Codex already includes it.
  - `reasoningTokens` is informational only and is never priced on top (FR-008, FR-008b, FR-020).
- **Rationale**: Pricing stays unchanged because `PriceEntry` has no reasoning price. FR-020's "dedicated reasoning price" therefore always resolves to the output price, and doing the addition at parse time keeps every cost path identical.
- **Alternatives considered**: A reasoning price column in `PriceEntry` was rejected. No source provides one, so it would be speculative.

## R3: Codex parsing

- **Decision**: `CodexSessionParser.parse(data:) -> CodexSession` reads one rollout file in order. It produces `CodexSession { sessionId, parentSessionId?, cwd?, planMarker: Bool, metaLine: String, records: [CodexRecord] }`, where `CodexRecord { raw, line }` keeps the event line for custom markers. Lines are handled like this:
  - **`session_meta`**: only the first one counts; forked files repeat the parent's. Read `id`, `cwd`, and the parent from `source.subagent.thread_spawn.parent_thread_id`, falling back to `forked_from_id`. A string `source.subagent` (such as `"review"`) has no parent.
  - **`turn_context`**: update the current model and cwd.
  - **`event_msg/token_count` with non-null `info`**: compare `info.total_token_usage` with the previous total. Emit a record only when the total changed (FR-008a). The record carries the difference of each field:
    - cache read = Δ`cached_input_tokens`
    - cache write (5m) = Δ`cache_write_input_tokens`
    - input = Δ`input_tokens` − cache read − cache write, clamped at 0
    - output = Δ`output_tokens` (already includes reasoning)
    - reasoning = Δ`reasoning_output_tokens`
  - **The record's other fields**: the timestamp is the line's `timestamp`; the model is the current one; the message id is `codex:<sessionId>:<total_tokens>` so it stays stable across re-reads; `providerHint` is set later (R5).
  - **Plan marker**: `planMarker` is true if any `rate_limits.plan_type` is a non-empty string (FR-014).
  - **Malformed input**: an incomplete last line, and lines that fail to decode, are skipped (FR-004).
- **Rationale**:
  - Using the change in the running total removes double counting from repeated events, null events and zero events. The data showed that running totals never decrease.
  - Message ids keyed on `total_tokens` stay the same when the file is re-read.
- **Alternatives considered**: summing `last_token_usage` was rejected, because repeated events make the totals too high (spec review finding #3).

## R4: Codex source and incrementality

- **Decision**:
  - **Reading.** `CodexSessionSource` scans `<home>/sessions/**/rollout-*.jsonl` for the default home `~/.codex` plus `Configuration.codexHomes`. Paths are canonical, and the first home wins for a file. A file is re-parsed **as a whole** only when its size or mtime changed (FR-004). The parsed `CodexSession` is kept per file, and files whose mtime is before the window start are dropped.
  - **Auth mode.** After each update a resolution pass runs over all sessions. A session's mode is its own marker, else its parent's mode when the parent is known, else API key. Records get `providerHint` `"chatgpt"` or `"apikey"` and are attributed with `location = home`.
  - **Effect of the pass.** Re-attribution after a late marker (FR-014) is automatic, because modes are resolved from the stored sessions on every refresh.
- **Rationale**: Rollout files are small (216 files, a few MB in total), and whole-file parsing keeps the session state exact.
- **Known limitation**: Codex `review` subagent sessions that `codex exec` starts carry no plan marker and no parent link. On a ChatGPT login they are classified as API-key usage. The spec accepts this, and a custom marker can claim them.
- **Alternatives considered**: offset-based tailing like `LogIndex` was rejected, because it would need to persist parser state per file.

## R5: Attribution across harnesses

- **Decision**: `Attributor.accountId(for raw: RawUsageRecord, rawLine: String, fileConfigDirectory: String)` keeps its signature, and `fileConfigDirectory` becomes the harness location: the Claude config dir, the Codex home, or the OpenCode data dir. Candidates are built per account kind:
  - **Claude Code records**: today's rules, unchanged.
  - **OpenCode records**:
    - `providerHint` `google-vertex` or `google-vertex-anthropic` matches `.vertex` token-based accounts.
    - `openai` matches `.openai` token-based accounts.
    - Anything else (`anthropic`, `litellm`, custom ids) has no built-in match.
  - **Codex records**:
    - `providerHint == "apikey"` matches `.openai` token-based accounts.
    - `"chatgpt"` matches `.codexSubscription` accounts, with ties broken by `codexHome == location`.
  - **Custom markers**: these are substrings of `rawLine` and keep precedence for every harness (FR-013). For Codex, `rawLine` is the `token_count` line plus the session's meta line. For OpenCode, it is the message JSON.
  - **Unassigned**: anything left ambiguous or unmatched goes to Unassigned.
  - **Fingerprint**: `fingerprint` includes the new rules, so a rule change makes the sources re-attribute.
- **Rationale**: This keeps one place where "which account pays" is decided (approach A).

## R6: OpenCode reading

- **Decision**: `OpenCodeSource` reads `<dataDir>/opencode.db` for the default `~/.local/share/opencode` plus `Configuration.openCodeDirectories`. It uses the system `SQLite3` module, `import SQLite3`, which macOS provides with no package dependency.
  - **Opening.** The database is opened read-only (`SQLITE_OPEN_READONLY`) with a busy timeout of 250 ms.
  - **Query.** `SELECT m.id, m.session_id, m.time_updated, m.data, s.directory FROM message m JOIN session s ON s.id = m.session_id WHERE m.time_updated > ?1 ORDER BY m.time_updated`. The watermark is per database; the first read uses 0.
  - **Which rows count.** Only rows whose JSON `role == "assistant"` and that carry `time.completed` (FR-009). The record's timestamp is `time.completed`.
  - **Tokens.** input, output plus reasoning (R2), cache read, cache write (5m), and reasoning.
  - **Other record fields.** `providerHint` is `providerID`, `model` is `modelID`, `sessionId` is the `message.session_id` column, and cwd is `path.cwd`, falling back to the session directory.
  - **Updates and pruning.** Records are kept in a dictionary keyed by message id, so updates replace rather than add. Records before the window start are pruned.
- **Busy handling (FR-005)**:
  - `SQLITE_BUSY`, `SQLITE_LOCKED` and open errors do not throw. The source returns its previous records flagged stale, with an issue message (R7).
  - A database file that has disappeared clears its records.
- **Rationale**:
  - WAL mode allows readers alongside the writer, and read-only mode never blocks OpenCode.
  - The `time_updated` watermark keeps refreshes incremental (SC-003).
- **Alternatives considered**: copying the database file before reading was rejected. It is slow for 28 MB and racy with the WAL file.

## R7: Partial failures and stale data per source

- **Decision**:
  - `SourceOutput` gains `case recordBatch(RecordBatch)`, where `RecordBatch { records: [UsageRecord]; issues: [String]; staleHarnesses: Set<Harness> }`. The new sources always return `.recordBatch`, and `SessionLogSource` keeps `.records`.
  - In `RefreshCoordinator`, records from all batches are concatenated. Each issue becomes a `SourceError(sourceName:message:at:)`, which covers a per-location failure (FR-006).
  - The aggregator receives `staleHarnesses`. An entry is marked stale (spec 001 FR-007) when it contains records from a stale harness. Groups, own budgets, token accounts, Codex plan accounts and Unassigned all follow this rule.
  - The existing all-or-nothing carry-over stays for a source that throws.
- **Rationale**: A busy OpenCode database or an unreadable extra Codex home must not mark Claude Code values stale (FR-005, FR-006, SC-004).
- **Alternatives considered**: throwing from the source would trigger the global stale carry-over and freeze every account.

## R8: Model id normalization

- **Decision**: `PriceTable.canonicalModel(_:)` strips any trailing `@<suffix>`, not only `@YYYYMMDD` (FR-020a). For example, `claude-opus-4-6@default` becomes `claude-opus-4-6`. The existing date-suffix and prefix matching are unchanged.
- **Rationale**: This is the observed OpenCode Vertex id, and it should price as the same model.

## R9: Account model changes

- **Decision**:
  - **Provider**: gains `case openai`. Its default icon is `brands:openai`.
  - **AccountKind**: gains `case codexSubscription(CodexSubscriptionSettings)`, where `CodexSubscriptionSettings { codexHome: String = "~/.codex" }` and the JSON type is `"codexSubscription"`. The default icon is `brands:openai`. `Configuration.subscriptionAccounts` stays `.subscription` only, so the Anthropic fetch, alignment and network fingerprint code never sees Codex accounts. A new `codexSubscriptionAccounts` is added.
  - **Validation**: a Codex home used by two Codex subscription accounts is invalid, mirroring the credential directory rule.
  - **Harness**: gains `.codex` and `.openCode`. `Account.harness` is still decoded and encoded but no longer read by attribution (FR-018).
  - **Configuration**: gains optional `codexHomes: [String]` and `openCodeDirectories: [String]` (default `[]`). Existing files decode unchanged.
- **Rationale**: A separate kind keeps every Anthropic-specific path untouched (spec 001 subscriptions) and gives part B a clear home.

## R10: Snapshot and display

- **Decision**:
  - **Snapshot**: `UsageSnapshot` gains `planAccounts: [String: TokenAccountEntry]` for Codex subscription accounts. These are token-only, use the weekly window (spec clarification), and have no cost.
  - **Breakdown**: `UsageBreakdown` gains `perHarness: [HarnessUsage]`, where `HarnessUsage { harness, totalTokens, costUSD?, priced }`. It is sorted by cost, then tokens.
  - **Model rows**: `ModelUsage` gains `reasoningTokens`.
  - **Dropdown and settings**:
    - The dropdown shows Codex subscription accounts as token-only sections, with no bar entry, thresholds or percent.
    - `BreakdownView` adds a "Harnesses" option to its existing models/projects switch (FR-021). The Out cell's hover text names the reasoning share when it is non-zero.
    - Settings get two new sections in `GeneralSettingsTab` ("Additional Codex homes", "Additional OpenCode data directories"), a Platform picker (Claude or ChatGPT) in the subscription dialog of the Add menu, and `openai` in the provider pickers.
- **Rationale**: This reuses the existing breakdown UI patterns from the project-breakdown feature.

## R11: Diagnostics

- **Decision**: Each new source writes one log line per location and refresh, using the source names `codex` and `opencode`. The line reads either `"<location>: N record(s) in window, M file(s)/row(s) read"` or the skip or failure reason (FR-022).
