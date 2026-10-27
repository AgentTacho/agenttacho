# Implementation Plan: Account Matching by Profile and Match Rules

**Branch**: `037-profile-account-matching` | **Date**: 2026-10-27 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/037-profile-account-matching/spec.md`

## Summary

Claude Code records are attributed first by the configuration directory their session ran under (read from the `api-request-shape` lines of the session file), then by per-account match rules. Token-based accounts lose the `Provider` enum: each gets exactly one `Harness` and a `MatchRule` (a preset of that harness, a custom field and text, or none). The log index learns a per-file profile, the attributor a profile step and harness-scoped rules, the configuration a new token-based form with a migration from `provider`, Settings a harness picker, a rule editor and an overlap warning, and the demo scenario splits its Vertex account so every account has one harness.

## Technical Context

**Language/Version**: Swift (tools version 5.10, as in `Package.swift`), macOS

**Primary Dependencies**: SwiftUI, Foundation; Swift Testing for tests. No new dependency.

**Storage**: `~/.config/agenttacho/config.json` (account keys change, see [contracts/configuration.md](contracts/configuration.md)); the in-memory log index (`LogIndex`) gains per-file profile state.

**Testing**: `make test` (UsageCoreTests, DemoModeTests), `make test-release` (shell tests); never `swift build` directly (constitution IV).

**Target Platform**: macOS menu bar app.

**Project Type**: desktop app with a logic library (`UsageCore`) and a thin SwiftUI layer (`Sources/AgentTacho`).

**Performance Goals**: an unchanged session file is not read again (SC-005); a shape line (tens of KB) is scanned with byte searches only, never JSON-decoded.

**Constraints**: read-only access to agent files (constitution III); nothing of a shape line but the matched directory is kept (FR-004); invented paths and model names in user-visible text, docs and tests (FR-018).

**Scale/Scope**: a few thousand session files per week, a handful of accounts, a handful of configured Claude Code directories (main, additional, wildcard matches up to 100 per entry).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | How |
|---|---|---|
| I. Issue first, specs recommended | Pass | Spec 037 from brainstorm 37, maintainer's own change. |
| II. Test-first, logic in UsageCore | Pass | Profile detection (`SessionProfile`), rules (`MatchRule`, `MatchPreset`), attribution, overlap detection, migration and all Settings texts (`MatchRuleText`) live in UsageCore with tests first; the SwiftUI layer only binds them. Doc comments cite `spec 037 FR-xxx`. |
| III. Read-only, private by default | Pass | Still only reads. Shape lines are scanned for configured paths only; README "Security and privacy", the website's privacy section and `docs/configuration.md` change in the same pull request (FR-016). |
| IV. One build entry point | Pass | Only `make test`, `make test-release`, `make app-demo`, `scripts/screenshots/capture.sh`. |
| V. Screenshots and website | Pass | See the section below; capture needs the maintainer's go (AGENTS.md step 4). |

Post-design re-check: unchanged, no violations, no complexity tracking needed.

## Screenshots and website

| | |
|---|---|
| Shots that change | budget, harnesses (the company group gains a member line: the demo's Vertex account splits into a Claude Code and an OpenCode member); one capture run writes all 14 files |
| New shots | none (Settings > Accounts is not captured; no card candidate: a matching change, not a new feature card) |
| Demo scenario | `Resources/demo/default.json`: `acc-vertex` becomes harness `claudeCode` with the Vertex preset and keeps its Claude Code usage; new `acc-vertex-opencode` (harness `openCode`, Vertex preset, `grp-company`) takes the 5 OpenCode usage entries; every token account gets `matchRule`. Coverage test: every usage entry's harness equals its account's harness, and `shotBudgetHasAllHarnesses` still holds |
| Website copy | privacy section (shape lines read for the configuration directory only, FR-016); check `features.ts` and the comparison for "Vertex counts Claude Code and OpenCode" wording |
| README image | unchanged |

## Project Structure

### Documentation (this feature)

```text
specs/037-profile-account-matching/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── configuration.md
│   └── settings-ui.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
Sources/UsageCore/
├── Config/
│   ├── Configuration.swift        # TokenBasedSettings: harness + matchRule (Provider removed),
│   │                              # Account.harness computed, decode/encode, migration, validate
│   ├── MatchRule.swift            # NEW: MatchRule, MatchPreset, MatchField, defaults per harness
│   ├── MatchRuleText.swift        # NEW: labels, captions, prompts, warning text (invented examples)
│   ├── MatchOverlap.swift         # NEW: Configuration.matchOverlaps(paths:) (FR-013)
│   ├── AccountDirectoryText.swift # keyed by Harness instead of Provider
│   └── AccountBudgetDescription.swift # names the preset or harness instead of the provider
├── Logs/
│   ├── Attribution.swift          # profile step, harness-scoped rules, custom rules, fingerprint
│   ├── SessionProfile.swift       # NEW: shape-line detection against configured directories
│   ├── LogIndex.swift             # per-file profile state, re-read rules, profile per line, LogIndexStats profile counts
│   ├── SessionLogSource.swift     # stats line counts (FR-012), profile candidates per refresh,
│   │                              # token-based Claude Code additional directories to the attributor
│   ├── CodexSessionSource.swift   # raw line when any rule needs it
│   └── OpenCodeSource.swift       # unchanged apart from the attributor call
Sources/AgentTacho/
├── AccountSettingsView.swift      # harness picker, Session matching section, warning, new account sheet
└── SettingsView.swift             # "Not applied" for an empty custom text
Sources/DemoMode/ScenarioCoverage.swift  # harness consistency check
Resources/demo/default.json
Tests/UsageCoreTests/              # AttributionTests, LogIndexTests, ConfigurationTests, new MatchRuleTests,
                                   # SessionProfileTests, MatchOverlapTests, MatchRuleTextTests
Tests/DemoModeTests/DefaultScenarioTests.swift
README.md, docs/configuration.md, docs/accounts-and-budgets.md, docs/development.md
```

**Structure Decision**: existing layout; three new UsageCore files under `Config/` and one under `Logs/`, no new target.

## Design

### Profile detection (FR-001, FR-002, FR-004; research R1, R2)

- `SessionProfile.Candidates` is built once per refresh from the configuration and the resolved Claude Code directories: for every main directory (subscription `credentialDirectory`, token-based Claude Code `sessionDirectory ?? ~/.claude`) and every additional directory (literal and wildcard match), the search strings are the `~`-expanded standardized path and the symlink-resolved path (`Attributor.canonical`), each followed by `/projects/`. Each maps to the canonical directory. A match counts only at a path boundary: the character before the search string must not be a path character (it is a quote, backtick, whitespace, `(` or the start of the line), so `/Users/t/.claude` does not match inside `/var/sandbox/Users/t/.claude/projects/` (plan review finding 12). A `key` identifies the set: each canonical directory with its claimant account ids and rank (main or additional), sorted, so a directory that moves between accounts changes the key (plan review finding 11).
- `SessionProfile.detect(line:candidates:) -> Detection` returns `.notShape` unless the line contains `"type":"api-request-shape"` (byte search, the same way the parser rejects non-assistant lines); otherwise `.named(canonical)` when exactly one canonical directory's search strings occur, `.none` when no candidate occurs, and `.ambiguous` (treated like `.notShape`) when two or more canonical directories occur. Only the canonical directory leaves the function.
- `LogIndex` runs detection sequentially over the lines read from a file and assigns each assistant line the profile in effect (latest `.named` before it; lines before the first take the first). `FileIndexEntry` gains `profile: String?` (in effect at the end of the read) and `sawShapeLine: Bool`.

### Re-read rules in LogIndex (FR-001; research R3)

- A file whose first `.named` detection arrives in a later refresh (entry exists, `profile == nil`, new lines name one) is evicted and read again from offset 0, so its earlier records are attributed with the profile.
- The index stores the candidates' `key`. When it changes, it evicts only files whose result could change: files with `sawShapeLine && profile == nil`, files whose `profile` is no longer a candidate, and files whose `profile`'s claimants (account ids or rank) changed. Files without shape lines and files whose profile is still a candidate keep their records. This keeps spec 035's goal (a new sandbox folder does not re-read everything).
- Appended lines start with the entry's stored `profile`.

### Attribution (FR-003, FR-005, FR-008 to FR-010; research R4)

- `Attributor.accountId(for:rawLine:fileConfigDirectory:profileDirectory:)` gains the profile. For a Claude Code record with a profile: main claimants are Claude subscription accounts and token-based Claude Code accounts whose canonical main directory equals it; exactly one wins; with none, additional claimants (spec 035 ranking); exactly one wins. Additional claimants include token-based Claude Code accounts, whose additional directories today do not reach the attributor (`joinsTieBreak` is false for them); the attributor receives them for the profile step only, and the rule-step tie-breaker stays limited to subscriptions. Several claimants at the deciding rank restrict the rule step to them; no claimant leaves all accounts in the rule step.
- Rule step: token-based candidates match only records of their own harness. Custom rules (token `MatchRule.custom`, subscription `customMarker`) first: if any matches, only those are considered. Then presets (`MatchPreset.detectionRule`) and the subscription rules, as today; the subscription rule keeps excluding records that match a Claude Code token preset. Then the subscription directory tie-breaker as today.
- `MatchRule.none` never matches in the rule step.
- The fingerprint covers id, kind, harness, rule, marker and main directory; additional directories stay out (spec 035).
- `needsRawLine` replaces `usesCustomMarkers`: true when any subscription marker or any token rule with the field `anywhere` exists. Field rules read `RawUsageRecord.model`, `requestId`, `messageId`.

### Configuration (FR-006, FR-007, FR-014, FR-015; contracts/configuration.md)

- `TokenBasedSettings`: `harness: Harness` (setting it to a new value clears the entered directory and additional directories and resets `matchRule` to `MatchRule.default(for:)`), `matchRule: MatchRule`, `sessionDirectory` meaning the Claude Code directory or Codex home by harness, nil for OpenCode.
- `Provider` is removed; `MatchPreset` holds its remaining jobs (preset names, icons). Default icon: Vertex presets `brands:google`, Codex API key and OpenCode OpenAI `brands:openai`, custom and none by harness (`brands:claude`, `brands:openai`, `solid:code`).
- `Account.harness` becomes computed from `kind` (Claude subscription `claudeCode`, Codex subscription `codex`, token-based its own harness); the init parameter goes away. The stored `harness` key of old files is ignored for migration (FR-014).
- Decoding a token-based account: with a `matchRule` key it is the new form (harness from `harness`, default `claudeCode`); without it, the legacy form migrates (`provider` with today's default `vertex`, its directory key, `customMarker` to `custom(anywhere, text)`) and the diagnostic log names the account once ("account X migrated from provider vertex"). `customMarker` on token-based accounts is no longer written; subscriptions keep it.
- `Configuration.validate()` refuses a custom rule with blank text ("Not applied"); decoding a blank or unreadable rule drops it with a load note and uses `.none` (FR-015).

### Settings (FR-006, FR-007, FR-011, FR-013; contracts/settings-ui.md)

- Token-based editor: "Token-based" section with Harness and Budget pickers; "Usage source" with the directory field for Claude Code and Codex (OpenCode shows a caption pointing to General > Sources); additional directories as today but not for OpenCode; new "Session matching" section with the rule popup, the preset caption or the custom field popup and text field, and the overlap warning.
- Subscriptions keep "Session matching (advanced)" with the custom marker; its caption drops the sentence that Vertex counts OpenCode.
- New account sheet: Harness and Match rule replace Provider; the display name prompt and default icon follow the harness and preset.
- Apply, undo and redo come from the existing draft mechanism; harness or rule changes are attribution changes (fingerprint), never a plan-limit request.

### Diagnostics (FR-012)

`LogIndexStats` gains `filesWithProfile` and `filesWithoutProfile` over the files read in that refresh; `SessionLogSource.statsLine` adds `profile named %ld, none %ld` from them.

### Docs and release (FR-016, FR-017, FR-018)

README "How it works" and the "Agent session data" row, `docs/accounts-and-budgets.md` (account kinds, budget groups across harnesses), `docs/configuration.md` (harness, presets, custom rules, profile step, overlap warning, budget groups across harnesses, migration note, new keys), `docs/development.md` where it describes attribution, and the website's privacy section. The squash commit subject (the release notes line): `feat(accounts): match accounts by profile and rule; OpenCode usage needs its own account`; `docs/configuration.md` holds the longer migration note.

## Complexity Tracking

None.
