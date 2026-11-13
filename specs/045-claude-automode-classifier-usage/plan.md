# Implementation Plan: Claude Code Auto-mode Classifier Usage

**Branch**: `045-claude-automode-classifier-usage` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/045-claude-automode-classifier-usage/spec.md`

## Summary

AgentTacho reads Claude Code's `.automode_decisions.jsonl` in the working directories of the Claude Code sessions it already indexed, turns every usage-bearing row into a usage record, and assigns it to the account of the session whose time span (first record to last record plus 5 minutes) covers it in the same directory. Rows whose covering sessions disagree on the account stay unassigned. Totals, model rows, project rows and Unassigned change; nothing visible is added.

Technical approach (research R1 to R8): a second, small incremental index (`ClassifierLogIndex`) next to `LogIndex`, fed after each `LogIndex.update` with the distinct working directories of the in-window Claude Code records. Directory checks run on a probe with a 2-second per-directory limit and an in-flight set, so a hung volume never blocks the refresh and never piles up checks. Rows are parsed once (incremental, keyed by path and byte offset); their account is recomputed on every refresh from session spans built from the current session records. `UsageRecord` gains three defaulted fields (`sessionKey`, `cwd`, `origin`) so spans can be built from what `LogIndex` already holds.

## Technical Context

**Language/Version**: Swift 5.10 (swift-tools-version 5.10), macOS app

**Primary Dependencies**: Foundation only (no new dependency)

**Storage**: In-memory index only; reads `<cwd>/.automode_decisions.jsonl`, writes nothing

**Testing**: Swift Testing (`import Testing`) in `Tests/UsageCoreTests`, run through `make test`

**Target Platform**: macOS menu bar app (AgentTacho)

**Project Type**: desktop app with a logic library (`UsageCore`) and a thin SwiftUI layer

**Performance Goals**: SC-004: at most 50 ms extra per refresh for 50 working directories with 100 KB logs already read

**Constraints**: read-only (constitution III); a hung volume must not stall a refresh (FR-012); no row content kept beyond parsing (FR-015)

**Scale/Scope**: tens of working directories per usage window; logs of up to tens of kilobytes per day, capped at 64 MB per file

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Check | Status |
|---|---|---|
| I. Issue first, specs recommended | Feature comes from brainstorm 45 and this spec; maintainer accepted the approach | Pass |
| II. Test-first, logic in UsageCore | All new logic in `Sources/UsageCore/Logs`; tests written before each piece; doc comments cite `spec 045 FR-xxx`. No change in `Sources/AgentTacho` | Pass |
| III. Read-only, private by default | Opens the decision log read-only with `O_NOFOLLOW | O_NONBLOCK`; never creates or edits it, never sets `AUTOMODE_DECISION_LOG`, never touches Claude settings. README "Security and privacy" and the website privacy section gain the same sentence (FR-016) | Pass |
| IV. One build entry point | `make test`, `make test-release`; no new build path | Pass |
| V. Screenshots and website | No visible UI change (see below); website privacy copy mirrors the README | Pass |

Post-design re-check (after Phase 1): unchanged, all pass. The design adds no UI, no network request, no credential access.

## Screenshots and website

| | |
|---|---|
| Shots that change | none: classifier usage only changes numbers inside existing rows, and the demo build has no decision logs |
| New shots | none |
| Demo scenario | none: no new visual state |
| Website copy | privacy section (`src/components/agenttacho/Privacy.astro` in the site repository, edited by hand): one sentence that AgentTacho reads Claude Code's `.automode_decisions.jsonl` in session working directories when it exists, mirrored from the README (FR-016) |
| README image | unchanged |

## Project Structure

### Documentation (this feature)

```text
specs/045-claude-automode-classifier-usage/
├── plan.md              # This file
├── research.md          # Phase 0
├── data-model.md        # Phase 1
├── quickstart.md        # Phase 1
├── contracts/
│   └── decision-log.md  # Input contract: the decision log line format
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
Sources/UsageCore/Logs/
├── UsageRecord.swift               # + sessionKey, cwd, origin (defaulted)
├── LogIndex.swift                  # sets sessionKey and cwd on session records
├── ClassifierRowParser.swift       # NEW: one line -> row | withoutUsage | malformed (FR-004, FR-009)
├── DecisionLogProbe.swift          # NEW: per-directory check with 2 s limit and in-flight set (FR-001, FR-012)
├── ClassifierLogIndex.swift        # NEW: incremental per-file read, rows keyed by path+offset (FR-003, FR-008a)
├── ClassifierAttribution.swift     # NEW: session spans, covering, account decision, records (FR-005 to FR-011)
└── SessionLogSource.swift          # wires the classifier step after LogIndex.update, log line (FR-013)

Tests/UsageCoreTests/
├── ClassifierRowParserTests.swift
├── DecisionLogProbeTests.swift
├── ClassifierLogIndexTests.swift
├── ClassifierAttributionTests.swift
├── SessionLogSourceClassifierTests.swift   # end to end over fixtures, SC-001 to SC-005
└── Fixtures/classifier/                    # sanitized session file + decision logs

README.md                                   # enabling section + Security and privacy sentence (FR-016)
```

**Structure Decision**: Everything lives in `UsageCore/Logs`, next to the session index it depends on. The classifier index is a separate type, not a branch inside `LogIndex`, because its files are found differently (from records, not from a directory scan), are keyed differently (path plus offset, not message id) and are attributed differently (from spans, not from rules). `LogIndex` changes only to stamp two fields on the records it already builds.

## Design

### Refresh flow (SessionLogSource.collect)

1. `LogIndex.update` as today (unchanged behavior, plus `sessionKey`/`cwd` on records).
2. Session records of Claude Code inside the window → distinct `cwd` values (raw strings).
3. `DecisionLogProbe.check(directories:) -> ProbeReport`: for each raw directory not in flight, start a check on a concurrent queue: canonicalize the directory (`Attributor.canonical`, which touches the file system and therefore runs inside the timed check, FR-012), `lstat` `<dir>/.automode_decisions.jsonl`. Wait until all are done or the timeout (injectable, default 2 seconds) passed. Finished checks return `.found(path, size, mtime)`, `.absent`, `.notRegular` or `.tooLarge`; unfinished ones return `.timedOut` and stay in flight until their thread returns. A directory still in flight from an earlier refresh returns `.busy` without a new check. The report also carries `canonical: [rawCwd: canonicalDirectory]`: the value of this check, or for `.timedOut`/`.busy` the last value a finished check produced for that raw directory (kept in the probe). Nothing outside the probe canonicalizes a working directory.
4. `ClassifierLogIndex.update(report:window:)` reads new bytes of found files (same size/date/offset rules as `LogIndex`); `.absent`, `.notRegular`, `.tooLarge` drop the entry; `.timedOut` and `.busy` keep the entry unchanged (FR-012: records already read keep counting). An entry is kept only while its canonical directory appears among the report's canonical values. Like `LogIndex`, it remembers `lastWindowStart` and drops all entries when `window.start` moves earlier, so rows pruned under the narrower window come back.
5. `ClassifierAttribution.records(entries: [DecisionLogEntry], sessionRecords: [UsageRecord], canonical: [String: String], pricer: PriceTable) -> ClassifierAttributionResult` builds spans from the session records whose raw cwd has a canonical value in the map (others build no span), decides each row's account, and returns the classifier `UsageRecord`s, the assigned and unassigned counts, and the session keys with a possible double recording.
6. `collect` returns `index.records + classifierRecords` and appends one log line when at least one decision log was found, or a directory timed out, was busy or was skipped (FR-013: no line on refreshes where nothing was there to read).

Steps 2 to 5 run inside the same offloaded closure as `LogIndex.update` (spec 039 FR-018), so the actor is never held. The probe's own threads are separate, so a hung `lstat` blocks only its own thread.

### Attribution

- Span key: `(sessionKey, canonical cwd)`, the canonical cwd taken from the probe report's map (never computed here), where `sessionKey` is the Claude session id or, without one, the session file's canonical path (clarification Q1).
- Span: `[min(timestamp), max(timestamp) + 300 s]` over in-window session records with that key; account set = set of their `accountId` values (nil included).
- A row in directory `D` with time `t`: covering spans = spans with canonical cwd `D` and `t` in range. Union of their account sets: exactly one non-nil account → that account; anything else (empty, contains nil, more than one) → unassigned (FR-006).
- Project: the project of any covering or same-directory session record (they share the cwd, so they share the project); no new file-system walk.
- Price: `pricer.cost(model:input:output:cacheWrite5m:cacheWrite1h:cacheRead:)` with the normalized model.
- Covering spans: all spans of the row's directory with `start <= t && t <= end`, found by a linear scan of that directory's spans (spans can overlap and their ends are not ordered, so a binary search by start would miss some).
- Recomputed on every refresh from the cached rows (FR-006); cheap because spans are built once per refresh (dictionary by canonical directory).
- Double recording: a session record of a covering span whose input, output, cache read and `cacheWrite5m + cacheWrite1h` equal the row's four counters; `ClassifierAttribution` returns those session keys, and `SessionLogSource` logs each once (a `loggedDoubleRecording` set). `SessionLogSource` also keeps `loggedTooLarge` (per file); the probe keeps the "timed out, not yet logged" state per directory.

### Diagnostics (FR-013)

One line per refresh in which at least one decision log was found, or a directory timed out, was busy or was skipped, for example:
`decision logs read 2 (checked 14, timed out 0, busy 0, skipped 0), rows counted 31, assigned 29, unassigned 2, without usage 5, malformed 0`.
A separate line per directory when it times out (once until its check finishes), per file skipped as too large (once per file), and per session with a possible double recording (once per session).

## Complexity Tracking

No constitution violations.
