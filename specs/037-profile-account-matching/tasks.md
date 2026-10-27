---

description: "Task list for account matching by profile and match rules"
---

# Tasks: Account Matching by Profile and Match Rules

**Input**: Design documents from `specs/037-profile-account-matching/`

**Prerequisites**: plan.md (Design), spec.md, research.md, data-model.md, contracts/configuration.md, contracts/settings-ui.md, quickstart.md

**Tests**: Included. Constitution II requires tests first for logic in UsageCore (Swift Testing, run with `make test`).

**Organization**: Tasks are grouped by user story so each story can be implemented and tested on its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1 to US5)

## Conventions for every task

- Types, fields and file locations follow plan.md "Design" and data-model.md; exact strings (load notes, log lines, captions, prompts, warnings, validation messages) follow contracts/configuration.md and contracts/settings-ui.md.
- New and changed doc comments cite the requirements they implement (for example `spec 037 FR-003`).
- Test first, in the same task when the test needs a new type or member: the whole UsageCoreTests target stops compiling when one test references a missing symbol. Write the test, then the smallest implementation that compiles, then make it pass, before running `make test`.
- Build and test only through the Makefile (`make test`, `make test-release`, `make app`, `make app-demo`). `make test` does not build the app target, so every task that touches `Sources/AgentTacho` ends with `make app-demo` compiling.
- No em dash or en dash characters anywhere.
- Fixtures and examples use invented paths and model names only: `~/agent-profiles/personal/claude`, `~/agent-profiles/work/claude`, `~/agent-profiles/lab/claude`, `intranet/glm-5`, `intranet/deepseek-v4`, `proj-alpha`, test homes in a temp directory. Never spell the real workspace tool name in one piece in tests (join it from parts, as `AccountDirectoryTextTests.noRealToolPaths` does) (FR-018).
- A shape line is recognized and searched with byte searches only, never JSON-decoded, and nothing of it but the matched canonical directory is stored, logged or returned (FR-004).
- Fixture shape lines look like Claude Code's: `{"type":"api-request-shape","sessionId":"...","shape":{"system":[{"type":"text","text":"... You have a persistent file-based memory at `<dir>/projects/-Users-tester-proj/memory/` ..."}]}}` with `<dir>` the profile directory.
- Every user-visible string, log line and load note is built in UsageCore.

---

## Phase 1: Setup

**Purpose**: Confirm a green baseline.

- [X] T001 Run `make test` and `make test-release` on the unchanged branch and note the passing counts in the task log, so later failures are attributable.
  - Task log (2026-10-27): baseline `make test` 2070 tests in 218 suites (UsageCoreTests) and 70 tests in 7 suites (DemoModeTests) pass; `make test-release` 266 passed, 0 failed.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Replace `Provider` by harness and match rule in the model, so every story builds on it. The app must compile at the end of this phase.

- [X] T002 [P] Write `Tests/UsageCoreTests/MatchRuleTests.swift` and create `Sources/UsageCore/Config/MatchRule.swift` with `MatchPreset`, `MatchField` and `MatchRule` per data-model.md: presets and fields per harness in order, `default(for:)`, `isOffered(for:)`, `needsRawLine`, `detectionRule` of each preset (same rules as today's `Provider.builtInRule`), case-sensitive prefix and contains matching on a `RawUsageRecord` and raw line, blank custom text detection (spec 037 FR-007, FR-011).
- [X] T003 Write `Tests/UsageCoreTests/MatchRuleTextTests.swift` and create `Sources/UsageCore/Config/MatchRuleText.swift` with every label, caption, prompt, display name prompt and the overlap warning text of contracts/settings-ui.md; test that all examples are invented and that no text contains a dash character (FR-007, FR-013, FR-018).
- [X] T004 Change `TokenBasedSettings` in `Sources/UsageCore/Config/Configuration.swift`: remove `provider`, add `harness: Harness` (a changed value clears `enteredSessionDirectory` and `additionalSessionDirectories` and resets `matchRule` to `MatchRule.default(for:)`) and `matchRule: MatchRule`; make `Account.harness` computed from `kind` and remove the `harness:` init parameter; update `AccountKind.sessionHarness`, `agentDirectory(for:)` (nil for OpenCode), `IconDefaults` (by preset, custom and none by harness per plan) and remove the `Provider` enum. Update `Tests/UsageCoreTests/ConfigurationTests.swift` suites `TokenBasedSessionDirectoryTests` and `AdditionalSessionDirectoryTests` from provider switches to harness switches, including the rule reset (FR-006, FR-007).
- [X] T005 Rewrite token-based decoding and encoding in `Sources/UsageCore/Config/Configuration.swift` per contracts/configuration.md: new form with `harness` and `matchRule`; legacy form without `matchRule` migrated from `provider` (default `vertex`) and `customMarker`, ignoring the stored `harness`; directory key by harness, the other harness's key and any directory key on OpenCode ignored with load notes; never write `provider` or a token-based `customMarker`. Tests first in `ConfigurationTests.swift` (`HarnessConfigurationTests`, `TokenBasedDirectoryCodingTests`): new form round trip for all three harnesses, legacy Vertex, legacy OpenAI, legacy marker, missing provider means Vertex (FR-014).
- [X] T006 Add to `Configuration.validate()` in `Sources/UsageCore/Config/Configuration.swift` the refusal of a custom rule with blank text, message per contracts/configuration.md; test in `ConfigurationTests.swift` (FR-011).
- [X] T007 Replace every remaining `Provider` use: `Sources/UsageCore/Config/AccountDirectoryText.swift` keyed by `Harness` (OpenCode caption from contracts/settings-ui.md, invented prompt `~/agent-profiles/work/claude`), `Sources/UsageCore/Config/AccountBudgetDescription.swift` (preset display name, or harness name for custom and none), `Sources/UsageCore/Logs/Attribution.swift` (`builtInRule` replaced by `MatchPreset.detectionRule`; behavior unchanged except that a preset matches only records of its own harness, so a Vertex account no longer counts OpenCode records, FR-008), and their tests (`AccountDirectoryTextTests`, `AccountBudgetDescriptionTests`, `AttributionTests`, `Tests/DemoModeTests/ScenarioTests.swift`, `RefreshCoordinatorTests.swift`); existing `AttributionTests` that expect a Vertex or OpenAI account to count OpenCode records change to expect an OpenCode account instead. `make test` passes.
- [X] T008 Make the app compile with the new model: in `Sources/AgentTacho/AccountSettingsView.swift` replace the Provider pickers (account editor and new account sheet) by a Harness picker bound to `settings.harness`, with `AccountDirectoryText` keyed by harness; the full rule UI follows in US2. `make app-demo` compiles.

**Checkpoint**: model migrated, behavior unchanged except that `Provider` is gone and presets are scoped to their harness; `make test` and `make app-demo` pass.
  - Task log: T004 to T008 removed `Provider` across UsageCore, the app and the tests, so the targets compile only together; they were built as one unit and checked together (`make test` 2099 + 70 pass, `make app-demo` builds). `make test` also builds the app target. `Attributor.needsRawLine` already replaced `usesCustomMarkers` in T007 (needed to compile).

---

## Phase 3: User Story 1 - Profiles that share one projects folder count separately (Priority: P1) MVP

**Goal**: Claude Code records count for the account of the profile their session ran under.

**Independent Test**: fixture session files in one shared `projects` tree whose shape lines name three directories; three accounts; each account's totals match its profile, Unassigned is empty.

- [X] T009 [P] [US1] Write `Tests/UsageCoreTests/SessionProfileTests.swift` and create `Sources/UsageCore/Logs/SessionProfile.swift` (`Candidates` built from main and additional Claude Code directories with expanded and symlink-resolved search strings plus `/projects/`, `key`, `SessionProfile.detect(line:candidates:) -> Detection`): a line that is no shape line, a shape line naming one, none and two candidates, `~` versus absolute path, a configuration directory reached through a symlinked parent, a configured path that sits inside a longer path (`/var/sandbox` prefix) and must not match without a path boundary, a key that changes when a directory moves between accounts or ranks, and a marker text inside the shape line that must not appear in any result (FR-001, FR-002, FR-004, SC-004).
- [X] T010 [US1] Add the profile step to `Sources/UsageCore/Logs/Attribution.swift`: `accountId(for:rawLine:fileConfigDirectory:profileDirectory:)`, candidates with the canonical main directory of Claude subscriptions and token-based Claude Code accounts (empty field means `~/.claude`), main claimants then additional claimants (spec 035 ranking), several claimants at the deciding rank restrict the rule step to them, token candidates filtered to their harness. Additional claimants include token-based Claude Code accounts: today `SessionDirectoryResolution.additionalByAccount` carries subscription accounts only (`joinsTieBreak` is false for token-based accounts, `Configuration.swift` near line 1202), so the attributor also receives the canonical additional directories of token-based Claude Code accounts for the profile step, while the rule-step directory tie-breaker stays limited to subscriptions. Tests first in a new suite `ProfileAttributionTests` in `Tests/UsageCoreTests/AttributionTests.swift`: US1 acceptance scenarios 1 to 4 and 7, a profile naming no account falls back to rules, subscription and Vertex on one directory fall back to rules, a profile named only as one token-based account's additional directory (literal and wildcard match) counts for it, a main claim beats an additional claim, two additional claimants fall back to the rules among them, a Vertex OpenCode record no longer counts for a Claude Code Vertex account (FR-003, FR-005, FR-008).
- [X] T011 [US1] Extend `Sources/UsageCore/Logs/LogIndex.swift`: run `SessionProfile.detect` sequentially over the lines read from a file, assign each assistant record the profile in effect (lines before the first shape line take the first), store `profile` and `sawShapeLine` in `FileIndexEntry`, carry `profile` to appended lines, evict and re-read a file whose first named profile arrives in a later read, store the candidates key and on change evict only files with `sawShapeLine && profile == nil`, files whose profile left the candidates, and files whose profile's claimants changed (a directory moved between accounts' additional lists re-attributes its files). Pass the profile to the attributor. Tests first in `Tests/UsageCoreTests/LogIndexTests.swift`: three profiles sharing one `projects` folder (SC-001), a subagent file with its own shape lines, appended lines keep the profile, late first shape line re-attributes earlier records, two profiles in one file, an unchanged refresh re-reads 0 files (SC-005), a new wildcard match does not re-read files without shape lines (FR-001), and the SC-004 marker text of a fixture shape line appears in no `FileIndexEntry`, record or stats value (FR-004).
- [X] T012 [US1] Build the profile candidates per refresh in `Sources/UsageCore/Logs/SessionLogSource.swift` from the resolved Claude Code directories (main and additional, `SessionDirectoryResolver`), hand them to the index, add two counts to `LogIndexStats` in `Sources/UsageCore/Logs/LogIndex.swift` (`filesWithProfile`, `filesWithoutProfile`: files read in this refresh whose profile in effect at the end is named, or nil), and extend `statsLine` with `profile named %ld, none %ld` from them; test the counts in `LogIndexTests.swift` and the line in the source's tests (FR-012).
- [X] T013 [US1] Update the attributor calls in `Sources/UsageCore/Logs/CodexSessionSource.swift` and `Sources/UsageCore/Logs/OpenCodeSource.swift` (no profile; `needsRawLine` replaces `usesCustomMarkers` for building Codex raw lines) and their tests (FR-005).

**Checkpoint**: the reported setup attributes correctly; `make test` passes.

---

## Phase 4: User Story 2 - A harness and a match rule instead of "Provider" (Priority: P1)

**Goal**: records without a profile signal find their account through the account's rule, and Settings shows harness and rule.

**Independent Test**: fixture records without profile signal per harness; each preset and custom field decides as specified; Settings offers only the chosen harness's presets.

- [X] T014 [US2] Implement the rule step with `MatchRule` in `Sources/UsageCore/Logs/Attribution.swift`: custom rules (token `custom`, subscription `customMarker`) before presets and subscription rules, `none` never matches, the subscription rule still excludes records matching a Claude Code token preset, fingerprint covers harness and rule, `needsRawLine`. Tests first in `AttributionTests.swift`: a table per harness of fixture records against every preset and custom field (SC-002), case sensitivity, custom before preset, `none`, US2 scenarios 5 and 6, two token-based Claude Code accounts with the same preset on different directories leave a record without profile signal Unassigned (spec edge case), and a harness or rule change alters `Attributor.fingerprint` while `Configuration.needsNetworkRefresh(comparedTo:)` stays false (US2 scenario 7) (FR-007, FR-009, FR-010, FR-011).
- [X] T015 [US2] Build the "Session matching" section of the token-based editor in `Sources/AgentTacho/AccountSettingsView.swift` per contracts/settings-ui.md: Match rule pop-up from `MatchRule` offers, preset caption, custom Field pop-up and text field, Claude Code and "None" captions, the Usage source section by harness (OpenCode caption instead of a field, no additional directories for OpenCode). All texts from `MatchRuleText` and `AccountDirectoryText`. `make app-demo` compiles (FR-006, FR-007).
- [X] T016 [US2] Update the new account sheet in `Sources/AgentTacho/AccountSettingsView.swift`: Harness and Match rule pop-ups (custom field and text when "Custom"), display name prompt and default icon from harness and preset until the user picks an icon; `add()` creates the account with harness and rule. `make app-demo` compiles (FR-006).
- [X] T017 [US2] Change the subscription marker caption in `Sources/AgentTacho/AccountSettingsView.swift` to the text of contracts/settings-ui.md (from `MatchRuleText`), and make a blank custom text show the "Not applied" line through `Sources/AgentTacho/SettingsView.swift` using `validate()` (FR-009, FR-011).

  - Task log: `SettingsView` needed no change for T017: applying a draft goes through `ConfigStore.save`, which runs `validate()`, so a blank custom text already shows "Not applied: Account \"X\": the match rule needs a text".

**Checkpoint**: US1 and US2 work together; `make test` and `make app-demo` pass.

---

## Phase 5: User Story 3 - Settings warns about accounts it cannot tell apart (Priority: P2)

**Goal**: overlapping token-based accounts carry an inline warning.

**Independent Test**: a table of account pairs; warnings appear for exactly the pairs neither step separates.

- [X] T018 [P] [US3] Write `Tests/UsageCoreTests/MatchOverlapTests.swift` and create `Sources/UsageCore/Config/MatchOverlap.swift` (`Configuration.matchOverlaps(paths:)`): same harness, same rule and, for Claude Code, same canonical main directory (empty means `~/.claude`) overlap; different directory or rule do not; Codex and OpenCode overlap on rule alone; subscriptions never appear; US3 scenarios 1 to 4 (FR-013, SC-006).
  - Task log (checkpoint 2/3): the correctness review found that a candidate change only checked the profile in effect at the end of a file. Fixed: `FileIndexEntry` keeps every named profile and whether a shape line named none or several, and a candidate change re-reads the file when any named profile changes claimants or such a line was seen (tests `earlierProfileLosingItsClaimantIsReread`, `newlyConfiguredEarlierDirectoryIsPickedUp`). Left as is, per plan "Re-read rules": a shape line that named one configured directory and also holds a newly added additional directory is not re-read (catching it would re-read every file with shape lines whenever a wildcard match appears).
- [X] T019 [US3] Show the warning in the "Session matching" section of `Sources/AgentTacho/AccountSettingsView.swift` from `matchOverlaps(paths:)` on the draft, as a caption with `exclamationmark.triangle` and the `MatchRuleText` wording; sidebar rows unchanged. `make app-demo` compiles (FR-013).

---

## Phase 6: User Story 4 - Existing configurations keep working (Priority: P2)

**Goal**: old files load, migrate visibly in the log, and save in the new form.

**Independent Test**: load files from before this feature; check accounts, notes, log lines and the next save.

- [X] T020 [US4] Log each migrated token-based account once per load in `Sources/UsageCore/Config/Configuration.swift` (through the load notes that reach the diagnostic log) with the text of contracts/configuration.md; tests in `ConfigurationTests.swift`: US4 scenarios 1 to 6, including a subscription marker that stays, and that the next save writes `harness` and `matchRule` but neither `provider` nor a token-based `customMarker` (FR-014).
- [X] T021 [US4] Lenient reading of `matchRule` in `Sources/UsageCore/Config/Configuration.swift` per the table in contracts/configuration.md (not an object, unknown type, preset of another harness, field not offered, blank text): rule `none`, one load note, configuration stays valid; tests in `ConfigurationTests.swift` (FR-015, SC-003).
  - Task log: the migration note and the lenient reading were built with the decoder in T005; T020 and T021 added the US4 and FR-015 tests (`MatchRuleMigrationTests`, `MatchRuleLenientReadingTests`), which passed without code changes.

---

## Phase 7: User Story 5 - Spend across harnesses through a budget group (Priority: P3)

**Goal**: one budget for Vertex usage from Claude Code and OpenCode.

**Independent Test**: two members of one group with different harnesses; the group's spend is their sum.

- [X] T022 [P] [US5] Add a test to `Tests/UsageCoreTests` (the aggregator's existing suite) with a Claude Code and an OpenCode account, both with the Vertex preset, in one group: the group's spend is the sum and its harness breakdown lists both harnesses (US5 scenario 1).
- [X] T023 [US5] Update `Resources/demo/default.json` per plan "Screenshots and website": `acc-vertex` becomes harness `claudeCode` with the Vertex preset and keeps its Claude Code usage entries; new `acc-vertex-opencode` (harness `openCode`, Vertex preset, `grp-company`, display name "OpenCode via Vertex") takes the 5 OpenCode entries; every token account gets `harness` and `matchRule`; then add the coverage check "every usage entry's harness equals its account's harness" in `Sources/DemoMode/ScenarioCoverage.swift` with its test in `Tests/DemoModeTests/DefaultScenarioTests.swift`, keeping `shotBudgetHasAllHarnesses` green (FR-019).
  - Task log: besides the split of `acc-vertex`, `acc-side` ("Side project", 3 OpenCode entries, stored `provider: openai`) became harness `openCode` with the OpenAI preset; migrated from its old provider it would have been a Codex account, which the new coverage check refuses. Its dropdown content is unchanged (demo usage bypasses the attributor). The company group now has three member lines, so the `budget` and `harnesses` shots change as planned.

---

## Phase 8: Polish & Cross-Cutting Concerns

- [X] T024 [P] Update `README.md` ("How it works", the "Agent session data" row of "Security and privacy"), `docs/configuration.md` (harness, presets, custom rules, profile step, overlap warning, budget groups across harnesses, new keys, migration note that OpenCode usage needs its own account), `docs/accounts-and-budgets.md` and `docs/development.md` where they describe providers or attribution; invented paths only. Record in the task log the `feat` commit subject from plan "Docs and release" for the squash commit (FR-016, FR-017, FR-018).
  - Task log: squash commit subject (release notes line, FR-017): `feat(accounts): match accounts by profile and rule; OpenCode usage needs its own account`. `docs/configuration.md` has the new section "Matching usage to accounts" with the migration note. `docs/development.md` needed no change (it names attribution only as a module). For T027: the site's card copy "An account stands for who pays, so Vertex spend from Claude Code and OpenCode lands in one budget" (see `docs/superpowers/plans/2026-10-16-landing-site.md`) needs rewording in the site pull request.
- [X] T025 [P] Extend the invented-paths test (`AccountDirectoryTextTests.noRealToolPaths` or a new test) to `MatchRuleText`, and check with `rg` that `Sources`, `Tests`, `docs` and `README.md` contain no real workspace tool name and no model name outside the invented examples (SC-007).
- [X] T026 Run `make test`, `make test-release` and `make app-demo`; fix failures (at most three rounds, then report). Search the changed files for the em dash and en dash characters (U+2014, U+2013, for example `rg -n '\x{2014}|\x{2013}'`); it must find nothing.
  - Task log (2026-10-27): `make test` 2152 tests in 228 suites (UsageCoreTests) and 71 tests in 7 suites (DemoModeTests) pass; `make test-release` 266 passed, 0 failed; `make app-demo` builds. The dash search over the changed files finds nothing. First round, no fixes needed.
- [X] T027 Screenshots and website (AGENTS.md steps 4 to 7, needs the maintainer's go before capturing): `scripts/screenshots/capture.sh <site checkout>/src/assets/agenttacho`, review `budget` and `harnesses` in both appearances, update the site's privacy section (and any "Vertex counts OpenCode" wording in `features.ts` or the comparison), run the site's check, build and tests, open the site pull request and link it from the app pull request. Record in the task log if the go is still pending.
  - Task log: captured from the demo build on 2026-10-27; glance, harnesses, menubar-settings and prices-dark changed; the budget shots stayed (the demo's monthly budget is on pace late in the month, inbox entry `demo-budget-pace-follows-calendar`). Site pull request: https://github.com/AgentTacho/agenttacho.github.io/pull/24 (privacy note, two card texts). No app pull request (direct merge).
  - Task log: waiting for the maintainer's go. The capture was not run and the site repository was not touched (AGENTS.md step 4). Shots that change: `budget`, `harnesses` (the company group gains the "OpenCode via Vertex" member line). Site copy to update: the privacy section (request shape lines read for the configuration directory only) and the "Three agents, one view" card text that says Vertex spend from Claude Code and OpenCode lands in one budget through one account.

---

## Dependencies & Execution Order

- Phase 1, then Phase 2 (blocks everything). Within Phase 2: T003 needs T002 (its texts are keyed by `MatchPreset` and `MatchField`); T004 needs T002; T005 and T006 need T004; T007 needs T004 and T005; T008 needs T007.
- US1 (Phase 3) needs Phase 2. T009 first (parallel with nothing else in US1), then T010, T011, T012, T013 in order.
- US2 (Phase 4) needs T010 (shared attributor). T015 to T017 need T014 only for behavior, not for compiling.
- US3 needs Phase 2 and T015 (the section it adds to). US4 needs Phase 2. US5 needs Phase 2; T023 can run any time after T008.
- Polish last; T027 waits for the maintainer.

## Parallel Example

```text
Phase 2: T003 (MatchRuleText) | T004 (TokenBasedSettings), both after T002
After Phase 2: T009 (SessionProfile) | T018 (MatchOverlap) | T022 (group test)
Polish: T024 (docs) | T025 (invented paths)
```

## Implementation Strategy

1. MVP: Phases 1 to 3 (US1). The reported failure is fixed: shared-profile setups attribute correctly with the migrated Vertex rule.
2. Add US2 (rule UI and custom rules, needed for the gateway profile's older sessions), then US3 and US4, then US5 and the demo.
3. Polish, then screenshots and the site pull request after the maintainer's go.
