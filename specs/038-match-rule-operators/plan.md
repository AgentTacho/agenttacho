# Implementation Plan: Session Kinds and Match Conditions for Token-Based Accounts

**Branch**: `038-match-rule-operators` | **Date**: 2026-10-27, reworked 2026-10-28 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/038-match-rule-operators/spec.md` (reworked: session kinds per harness plus an optional "Only when" condition that only narrows)

## Summary

A token-based account no longer has a "match rule" (preset, custom or none). It has a **session kind** of its harness (Claude Code: Directory only, Vertex, Other provider; Codex: API key; OpenCode: Vertex, OpenAI, Other provider) and an optional **condition** (field, operator, text) that narrows the kind and never widens it. Attribution checks the kind first and runs a condition only on records of that kind, so a condition can never take a subscription's or another kind's records; subscription markers narrow the same way. The configuration stores `sessionKind` and `condition` and reads every earlier form (v0.8.0, spec 037, first 038). Settings gets the section "Which sessions count" with a Sessions pop-up, an "Only when" checkbox and the Condition row.

The first version of this spec is implemented on the branch and is **reused**: the operators with case-insensitive literal and regex matching, `MatchRuntime` with the 50 ms limit, sit-out, retry memory and given-up state, the re-attribution in `LogIndex`, `CodexSessionSource` and `OpenCodeSource`, `validateForSaving()`, the case-folded overlap key, `ConditionControls`, `StableWidthPicker` and the caption notes inside the group. What is **replaced**: the rule model (`MatchRule`, `MatchPreset`, `MatchRuleChoice`), the stored `matchRule`, the rule step's "custom beats built-in across kinds", the Settings section's structure and texts, the new account sheet's rule controls, and the docs.

## Technical Context

**Language/Version**: Swift 5.10 tools, Swift 6 compiler, macOS 14+

**Primary Dependencies**: Foundation (`NSRegularExpression`, `ContinuousClock`), SwiftUI (grouped `Form`, `Toggle` with checkbox style, `ViewThatFits`)

**Storage**: `~/.config/agenttacho/config.json` (`sessionKind`, `condition` replace `matchRule`)

**Testing**: Swift Testing through `make test`; `make test-release` for the scripts

**Target Platform**: macOS menu bar app

**Project Type**: desktop app (UsageCore library + thin SwiftUI layer + DemoMode)

**Performance Goals**: SC-005 as in the first version (rule step over 10,000 raw lines with an Anywhere regex under 1 s; one pathological pattern costs at most 100 ms per refresh); the condition now runs only on records of the account's kind, which can only lower the cost

**Constraints**: read-only towards agent files (constitution III); nothing more of a record is kept; kinds and subscription markers keep exact, case-sensitive checks

**Scale/Scope**: about 12 UsageCore files, the Settings view, the demo scenario, docs; no new screens

## Global Constraints

Every task inherits these (spec, constitution, AGENTS.md):

- macOS 14+, Swift 6 compiler; build and test only through `make test`, `make test-release`, `make app`, `make app-demo`.
- Logic in UsageCore (or DemoMode), test first; `Sources/AgentTacho` only lays out. Doc comments cite `spec 038 FR-0xx` or research `Rn`.
- AgentTacho only reads agent files; no more of a record is kept than today.
- Invented examples only (`intranet/`, `glm`, `gateway-a/`, `proj-alpha`, `~/.claude-gateway`); never real model names, account names or paths; no em dash or en dash in any file.
- Exact UI strings from contracts/settings-ui.md; no "profile", "Match rule", "Custom" or "preset" for token-based accounts (FR-017).
- Kinds and the subscription marker are exact and case-sensitive; conditions ignore case (FR-002, FR-005). Regex limit 50 ms per record (FR-007).
- A condition never widens a kind (FR-004); the Claude Code directory decides first (FR-003).

## Constitution Check

| Principle | Status |
|---|---|
| I. Issue first, specs recommended | Spec-driven (brainstorm 38 with its revisit, spec 038 reworked); maintainer's own request |
| II. Test-first, logic in UsageCore | Kinds, conditions, transitions, storage and migration, attribution, overlap, notes and the demo scenario live in UsageCore or DemoMode with failing tests first; `AccountSettingsView` only lays out |
| III. Read-only, private by default | No new reads, no new network; the request id and provider were already read. The research check of real record shapes counted request id prefixes only and kept nothing. README "How it works" updated in the same pull request; the privacy section is unchanged because nothing new is read or kept |
| IV. One build entry point | `make test`, `make test-release`, `make app`, `make app-demo` only |
| V. Screenshots and website follow the UI | See "Screenshots and website": no captured stem shows Settings > Accounts; one copy line on the site |

Re-check after design: no violation. The removal of `MatchRule` touches many tests; they move with the types (Complexity Tracking).

## Screenshots and website

| | |
|---|---|
| Shots that change | none: the changed UI is Settings > Accounts, which no stem of `scripts/screenshots/capture.sh` captures (Settings strips: `menubar-settings`, `prices`); the dropdown does not show kinds |
| New shots | none; no card candidate (a refinement of the token-based setup, not a new capability) |
| Demo scenario | migrate the four token-based accounts of `Resources/demo/default.json` from `matchRule` presets to `sessionKind` (`vertex`, `vertex`, `apiKey`, `openai`); coverage test: `DefaultScenarioTests` checks `acc-side` is OpenCode `openai` and no account in the scenario uses `matchRule` |
| Website copy | `src/data/features.ts`, the pay-per-token card: "Pay-per-token spend on Vertex, the OpenAI API or a company gateway, ..." (site pull request linked from the app pull request); privacy section unchanged |

## Project Structure

### Documentation (this feature)

```text
specs/038-match-rule-operators/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── configuration.md
│   └── settings-ui.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Sources/UsageCore/Config/
├── SessionKind.swift         # NEW (from MatchPreset): kinds per harness, stored values, checks, fallback, icon
├── MatchCondition.swift      # git mv of MatchRule.swift: MatchField, MatchOperator (reused), MatchCondition (from MatchRule.custom)
├── MatchRuntime.swift        # Entry holds a MatchCondition; CompiledCondition (reused logic)
├── SessionMatchText.swift    # git mv of MatchRuleText.swift: new texts, noteLines with merges
├── MatchOverlap.swift        # kind + condition key; Directory only skipped; directoryOnlyConflict
├── Configuration.swift       # TokenBasedSettings.sessionKind/condition and transitions; decode/encode; migration; validate/validateForSaving; IconDefaults
└── AccountBudgetDescription.swift  # subtitle = kind name
Sources/UsageCore/Config/AccountDirectoryText.swift  # token-based Claude Code prompt without "profiles"
Sources/UsageCore/Logs/Attribution.swift             # rule step: kind, then condition; markers narrow; sit-out wording
Sources/AgentTacho/AccountSettingsView.swift         # "Which sessions count", SessionsFields, sheet
Resources/demo/default.json                          # sessionKind
Tests/UsageCoreTests/
├── SessionKindTests.swift          # NEW
├── SessionKindStorageTests.swift   # NEW: round trip and every earlier form
├── MatchConditionTests.swift       # git mv of MatchRuleTests.swift, rewritten for MatchCondition and transitions
├── MatchOperatorTests.swift        # reused, adapted to MatchCondition
├── MatchRuntimeTests.swift         # reused, adapted
├── SessionMatchTextTests.swift     # git mv of MatchRuleTextTests.swift
├── MatchOverlapTests.swift, AttributionTests.swift, ConfigurationTests.swift, ConfigStoreTests.swift,
│   AccountBudgetDescriptionTests.swift, LogIndexTests.swift, CodexSessionSourceTests.swift,
│   OpenCodeSourceTests.swift, AggregatorTests.swift, SessionProfileTests.swift, AccountDirectoryTextTests.swift
└── Fixtures/gateway-session.jsonl  # NEW: records without requestId (invented model intranet/glm-5)
Tests/DemoModeTests/DefaultScenarioTests.swift
docs/configuration.md, README.md
```

**Structure Decision**: Existing UsageCore + AgentTacho + DemoMode layout. Two files are renamed with `git mv` so their history stays; one new type file for `SessionKind`.

## Design

### Model (FR-001, FR-002, FR-004; research R10; data-model.md)

`SessionKind` replaces `MatchPreset` with the same shape plus Directory only and the two Other provider kinds. `MatchCondition` takes over `MatchRule.custom` with all of its matching code. `TokenBasedSettings` holds `sessionKind` and `condition: MatchCondition?`; `effectiveCondition` hides a condition the kind does not offer. Transitions (`harness` didSet, `choosingKind`, `settingConditionOn`, `conditionForEditing`) are UsageCore functions with tests, so the view never decides.

### Attribution (FR-003, FR-006, FR-007; research R11)

Profile step unchanged. Rule step: kind first (token-based kinds, a Claude subscription's direct request id, a Codex subscription's plan hint), then the condition (token-based through `MatchRuntime`, a subscription marker as case-sensitive raw-line check); conditioned matches beat plain ones; one wins, subscriptions of one kind tie-break by directory, else Unassigned. `claudeCodeTokenRules` goes. The fingerprint includes kind and effective condition, so a kind or condition change re-attributes through the existing paths. `MatchRuntime`, `MatchMemory`, `tracking(retry:)` and the sources' re-attribution are reused; only `Entry` holds a `MatchCondition` and the log line says "condition".

### Configuration (FR-008, FR-010, FR-011; research R6, R7, R14; contracts/configuration.md)

Encode `sessionKind` always and `condition` when effective; never `matchRule`, `provider` or a token-based `customMarker`. Decode `sessionKind` first, then `matchRule` through `StoredMatchRule.migrated(for:)`, then `provider`/`customMarker`; unreadable values give `SessionKind.fallback(for:)` without a condition; every migrated account gets one load note. `validate()` checks a blank effective condition; `validateForSaving()` adds the invalid pattern and OpenCode Other provider without a condition.

### Overlap and conflicts (FR-009, FR-013; research R12)

`matchOverlaps` keys on harness, kind, condition overlap key and the Claude Code main directory, skipping Directory only; `directoryOnlyConflict(forAccount:)` names the accounts that share a Directory only account's main directory.

### Settings (FR-012 to FR-019; research R8, R13; contracts/settings-ui.md)

`Section(SessionMatchText.sectionTitle)` ("Which sessions count") with a new `SessionsFields` view: `StableWidthPicker` for the kind (or the Codex sentence), `Toggle` "Only when" with checkbox style, `LabeledContent("Condition") { ConditionControls }` bound to the condition, and `MatchRuleNotes` fed by `SessionMatchText.noteLines`. `SessionsFields` keeps the last non-nil condition in `@State` (keyed by `.id(accountId)`) and passes it to the transitions. The new account sheet uses `SessionsFields(captions: true)` with the harness's default kind and `validateForSaving()` on "Add"; icon and name follow the kind. The subscription marker notes get the narrowing sentence. The token-based Claude Code directory prompt drops "profiles".

### Demo (constitution V)

`Resources/demo/default.json` moves to `sessionKind`; `DefaultScenarioTests` asserts the kinds and that the scenario has no `matchRule`. No new visual state, so no capture stem changes.

### Docs and release (FR-020)

`docs/configuration.md`: replace "Match rules (`matchRule`)", "Custom rules" and the migration paragraph with "Which sessions count" (kinds per harness and their checks, the Directory only setup for a per-token Anthropic API key, the Bedrock caveat), "Conditions" (fields, operators, case handling, ICU, 50 ms), the stored form, migration from v0.8.0 and spec 037/038 files, subscription markers narrowing, the overlap and Directory only warnings; the Settings > Accounts bullet and the icon paragraph follow. `README.md` "How it works": one or two sentences on kinds and conditions (Claude Code and OpenCode bullets). Release notes line (squash subject): `feat(accounts): token-based accounts choose a session kind with an optional condition that ignores case; v0.8 markers become Vertex conditions, subscription markers only narrow`.

## Complexity Tracking

| Addition | Why needed | Simpler alternative rejected because |
|---|---|---|
| Replacing `MatchRule` across UsageCore, the view and about 15 test files | FR-004: the old model let a condition replace the kind; keeping the type would keep the confusion and the misattribution | Adding a kind next to `MatchRule` (two overlapping models, every caller must combine them right) |
| Three readers (new form, `matchRule`, `provider`) | FR-011: v0.8.0 is released; 037/038 files exist on the maintainer's machine | Dropping the 037/038 reader (those files would lose their rules) |
| `effectiveCondition` next to `condition` | Edge case "Kind change": a hidden condition is kept but must not count or be written | Clearing it on Directory only (undo would not restore it) |
| `directoryOnlyConflict` next to `matchOverlaps` | FR-013: a Directory only account on a shared directory counts nothing, which the overlap warning cannot say | Reusing the overlap warning (wrong advice: another condition does not help) |
