# Implementation Plan: Multi-Harness Usage (Codex and OpenCode)

**Branch**: `006-multi-harness-usage` | **Date**: 2026-10-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/006-multi-harness-usage/spec.md`

## Summary

Codex and OpenCode become record sources next to Claude Code, and all three share one record type, one attribution step, one pricing path and one aggregation. The changes:

- **Common record.** Records gain a `harness`, a `providerHint`, `reasoningTokens` and a `sessionId`.
- **Codex.** A new source parses rollout files as whole sessions. It derives usage from changes in the running total and decides each session's auth mode from its plan marker, falling back to the parent session.
- **OpenCode.** A new source reads the SQLite database read-only, using a `time_updated` watermark, and keeps records keyed by message id.
- **Attribution.** The `Attributor` learns per-harness built-in rules: OpenCode `providerID`, and the Codex auth mode with Codex-home tie-breaking.
- **Accounts.** New `openai` provider and a new `codexSubscription` account kind (tokens only).
- **Display and pricing.** Breakdowns add a per-harness split. Model ids drop `@suffix` before price lookup.
- **Stale data.** A busy database or an unreadable location makes only that harness's entries stale.

## Technical Context

**Language/Version**: Swift 5.10, macOS 14+

**Primary Dependencies**: Foundation, SwiftUI, AppKit, and the system `SQLite3` module (`import SQLite3`, part of the macOS SDK). No package dependencies.

**Storage**: Reads `~/.codex/sessions/**`, `~/.local/share/opencode/opencode.db`, and the configured extra locations. Writes only `config.json`.

**Testing**: Swift Testing via `make test`. Synthetic Codex JSONL fixtures. A temporary SQLite database is built inside the tests.

**Target Platform**: macOS 14+ menu bar app

**Project Type**: desktop app (`AgentMeter`) with core library (`UsageCore`)

**Performance Goals**: spec 001 SC-004 with all three harnesses (spec SC-003). The OpenCode watermark and Codex mtime/size checks keep incremental refreshes under 1 s.

**Constraints**:
- Read-only access to harness data.
- Never read credential files (`~/.codex/auth.json`).
- Existing configs load unchanged.
- No change to the Anthropic subscription fetch.

**Scale/Scope**: 3 new core files (Codex parser, Codex source, OpenCode source), about 10 changed files, and about 9 test suites touched or added.

## Global Constraints

- Swift 5.10, macOS 14+. No package dependencies (the SQLite3 system module is allowed).
- Never open or parse `~/.codex/auth.json` or any credential file. Codex auth mode comes only from session logs.
- Open the OpenCode database with `SQLITE_OPEN_READONLY` and a busy timeout of 250 ms or less. Never write to it.
- No em-dash or en-dash characters in code, comments, or strings.
- Claude Code reading (`SessionLogSource`, `LogIndex`, `SessionRecordParser`) keeps its behaviour. Its tests must pass unchanged, except where they construct records with the new fields.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The constitution is the unfilled template. The plan follows the codebase conventions: pure logic in `UsageCore`, Swift Testing per type, thin views, and FR ids in doc comments. Post-design: no violations. SQLite comes from the system SDK, not a new dependency.

## Project Structure

### Documentation (this feature)

```text
specs/006-multi-harness-usage/
├── plan.md
├── research.md            # R1 to R11
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── harness-formats.md # Codex rollout and OpenCode DB fields (read-only)
│   └── config-file.md     # codexHomes, openCodeDirectories, codexSubscription, openai
└── tasks.md
```

### Source Code (repository root)

```text
Sources/UsageCore/
├── Config/Configuration.swift      # Harness .codex/.openCode; Provider .openai; AccountKind .codexSubscription;
│                                   # CodexSubscriptionSettings; codexHomes; openCodeDirectories; IconDefaults; validation (R9)
├── Config/Paths.swift              # defaultCodexHome "~/.codex", defaultOpenCodeDirectory "~/.local/share/opencode"
├── Logs/UsageRecord.swift          # harness, providerHint, reasoningTokens, sessionId (R2)
├── Logs/Attribution.swift          # per-harness built-in rules, codex home tie-breaker, fingerprint (R5)
├── Logs/CodexSessionParser.swift   # NEW: whole-file session parse, running-total deltas, plan marker (R3)
├── Logs/CodexSessionSource.swift   # NEW: scan homes, re-parse changed files, resolve auth mode, attribute, price (R4)
├── Logs/OpenCodeSource.swift       # NEW: SQLite read-only, watermark, completed assistant messages (R6)
├── Pricing/PriceTable.swift        # canonicalModel strips any @suffix (R8)
├── Snapshot/RefreshCoordinator.swift # SourceOutput.recordBatch, issues -> SourceError, staleHarnesses (R7)
├── Snapshot/UsageSnapshot.swift    # RecordBatch; planAccounts; UsageBreakdown.perHarness; HarnessUsage; ModelUsage.reasoningTokens (R10)
└── Snapshot/Aggregator.swift       # perHarness; planAccounts; stale by harness (R7, R10)

Sources/AgentMeter/
├── App.swift                 # register CodexSessionSource and OpenCodeSource
├── DropdownView.swift        # Codex subscription token-only section
├── BreakdownView.swift       # "Harnesses" view in the switch; reasoning hover
├── AccountSettingsView.swift # subscription dialog Platform picker (Claude, ChatGPT); CodexSubscriptionEditor (codex home); openai in provider pickers
└── SettingsView.swift        # sections for additional Codex homes and OpenCode data directories

Tests/UsageCoreTests/
├── CodexSessionParserTests.swift (new), CodexSessionSourceTests.swift (new), OpenCodeSourceTests.swift (new)
├── Fixtures/codex/*.jsonl (new, synthetic)
└── AttributionTests, PriceTableTests, AggregatorTests, ConfigurationTests, RefreshCoordinatorTests (extended)
```

**Structure Decision**: Keep the two-target layout. New harness sources live next to `SessionLogSource` in `Sources/UsageCore/Logs/`.

## Design Notes

1. **Records and model (R2, R9).**
   - Extend `RawUsageRecord` and `UsageRecord` with defaults, so every existing initializer and test still compiles.
   - Add `Harness`, `Provider`, `AccountKind` and `Configuration` cases and fields, with decoding defaults.
   - Update every exhaustive switch (`IconDefaults`, `AccountKind` accessors, settings, dropdown).
2. **Attribution (R5).** Candidates carry `kind` (anthropicSubscription, codexSubscription, tokenBased(provider)) and `directory` (credential directory or Codex home). `accountId(for:rawLine:fileConfigDirectory:)` branches on `raw.harness` for the built-in match. Custom markers apply to every harness.
3. **Codex (R3, R4).**
   - **Parser**: `CodexSessionParser` is pure and works on `Data`.
   - **Source**: `CodexSessionSource` is an actor and a `WindowSensitiveSource`. It keeps a per-file cache `{size, mtime, home, session}`.
   - **Collect**: scan, re-parse changed files, drop deleted or old files, resolve auth modes (own marker, else parent, else API key), then attribute, price and resolve the project for each record. It returns `.recordBatch` with issues for unreadable homes.
4. **OpenCode (R6).**
   - `OpenCodeSource` is an actor and a `WindowSensitiveSource`. Per database it keeps a watermark and `[messageId: UsageRecord]`.
   - The SQLite helper is a small private wrapper (open read-only, prepare, step, finalize).
   - On a busy or locked database it returns the previous records with `staleHarnesses = [.openCode]` and an issue. A missing database means no records and no issue.
   - New rows are attributed and priced as they are read. Stored records are re-attributed and re-priced only when the attributor fingerprint or the price table changes, the same approach as `LogIndex`.
5. **Coordinator and aggregator (R7, R10).**
   - The coordinator handles `.recordBatch`: it appends the records, turns each issue into a `SourceError`, and unions `staleHarnesses`. It passes `staleHarnesses` to `aggregate`.
   - The aggregator marks any entry stale whose records include a stale harness. It builds `perHarness`, and builds `planAccounts` for `.codexSubscription` accounts over the weekly window with `priced: false`.
6. **Pricing (R8).** `canonicalModel` uses the regex `@[^@]+$`.
7. **UI (R10).**
   - Settings: provider picker gains OpenAI; the subscription dialog gains a Platform picker (Claude, ChatGPT); the editor gets a Codex home field; `GeneralSettingsTab` gets two directory list sections that mirror the existing Claude directories section.
   - Dropdown: a Codex plan section with icon, name, tokens and a breakdown, placed after the Claude subscriptions.
   - `BreakdownView`: adds a harness view.
   - Bar: never shows Codex plan accounts, and `BarLayout` ignores the new kind.

## Risks

- **Format drift.** Codex and OpenCode formats are undocumented and can change. Mitigation: tolerant decoding (unknown or missing fields skip the line or row), parser tests built on the observed shapes, and source issues surfaced in the dropdown.
- **API-key misclassification.** Codex sessions without a plan marker are treated as API-key usage. This is accepted per the spec, and a custom marker can correct it.
- **SQLite from Swift.** The C API needs careful finalization. Mitigation: a small RAII-style wrapper with `defer` finalization, plus tests against a real temporary database.

## Complexity Tracking

No constitution violations to justify.
