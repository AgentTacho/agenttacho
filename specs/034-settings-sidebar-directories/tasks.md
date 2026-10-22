---

description: "Task list for the settings sidebar and per-account directories"
---

# Tasks: Settings Sidebar and Per-Account Directories

**Input**: Design documents from `specs/034-settings-sidebar-directories/`

**Prerequisites**: plan.md (Design, Interfaces block, Global constraints), spec.md, research.md, data-model.md, contracts/configuration.md, contracts/settings-layout.md, quickstart.md

**Tests**: Included. Constitution II requires tests first for logic in UsageCore (Swift Testing, run with `make test`).

**Organization**: Tasks are grouped by user story so each story can be implemented and tested on its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

## Conventions for every task

- Signatures follow the Interfaces block in plan.md; exact strings follow contracts/configuration.md and contracts/settings-layout.md.
- New and changed doc comments cite the requirements they implement (for example `spec 034 FR-008`).
- Test first, in the same task when the test needs a new type or property: the whole UsageCoreTests target stops compiling when one test file references a symbol that does not exist yet. For a new type or property, write the test, then the smallest implementation that compiles, then make the test pass, all before running `make test`. Tests that use only existing API (for example LogIndexTests with the account model of Phase 2) are written in their own task and fail until the implementation task lands.
- No em dash or en dash characters anywhere.
- Build and test only through the Makefile (`make test`, `make test-release`, `make app`, `make app-demo`). `make test` does not build the app target, so every task that touches `Sources/AgentTacho` ends with `make app-demo` compiling.
- Examples use invented paths only: `~/.claude-personal`, `~/profiles/acme/claude`, `~/.codex-lab`, `~/.local/share/opencode-lab`, test homes under `/Users/tester` (FR-013).
- A token-based account's directory never reaches `SubscriptionSource`, `CodexLimitsSource`, `KeychainServiceName` or `CodexCredentialReader` (FR-008, constitution III).
- Every new user-visible string and every load note is built in UsageCore.

---

## Phase 1: Setup

**Purpose**: Confirm a green baseline.

- [X] T001 Run `make test` and `make app-demo` on the branch and confirm both pass before any change (no file changes)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The account directory model, its coding, the configuration lookups and the shared texts that US1, US2 and US3 build on (data-model "Account directory", "Configuration lookups"; research R3, R4, R5; contracts/configuration.md "Account keys").

- [X] T002 Add tests in Tests/UsageCoreTests/ConfigurationTests.swift, then implement in Sources/UsageCore/Config/Configuration.swift (together, test first): `SubscriptionSettings` stores `enteredCredentialDirectory` with computed `credentialDirectory` (getter returns `Paths.defaultClaudeDirectory` for an empty or whitespace and newline only entry, the entry otherwise; setter stores the entry; init keeps its `credentialDirectory:` label); `CodexSubscriptionSettings` the same with `enteredCodexHome` and `codexHome` (`Paths.defaultCodexHome`); explicit `CodingKeys` (`enteredCredentialDirectory = "credentialDirectory"`, `enteredCodexHome = "codexHome"`) so the encoded shape is unchanged; `Account` decodes into and encodes the entered value. Tests: blank and whitespace entries give the default, a typed entry is returned as typed, an empty entry round-trips as empty in the file, the encoded keys are unchanged (spec 034 FR-006a, research R3)
- [X] T003 Add tests in Tests/UsageCoreTests/ConfigurationTests.swift, then implement in Sources/UsageCore/Config/Configuration.swift (together, test first): `TokenBasedSettings.enteredSessionDirectory: String?` and computed `sessionDirectory` (nil for nil or blank), init parameter `sessionDirectory: String? = nil`, `provider` `didSet` that sets `enteredSessionDirectory = nil` when the provider changes (not in initializers); `Provider.sessionDirectoryKey` (`"claudeCodeDirectory"` or `"codexHome"`), `sessionHarness` (`.claudeCode` or `.codex`) and `defaultSessionDirectory` (`~/.claude` or `~/.codex`). Tests: blank gives nil, switching Vertex to OpenAI and back clears the entry, setting the same provider keeps it, the three provider properties per case (spec 034 FR-007, research R4)
- [X] T004 Add tests in Tests/UsageCoreTests/ConfigurationTests.swift, then implement the token-based branch of `Account.init(from:)` and `encode(to:)` in Sources/UsageCore/Config/Configuration.swift (`CodingKeys` gains `claudeCodeDirectory`): Vertex `claudeCodeDirectory` and OpenAI `codexHome` round trip; a blank value is omitted on save; the provider's own key with a non-string value (including `null`) is ignored with the note `<key> of account "<name>" is not readable, ignored`; the other provider's key is ignored with `codexHome of account "<name>" does not belong to a Vertex account, ignored` or `claudeCodeDirectory of account "<name>" does not belong to an OpenAI account, ignored` and not written back; a blank string gives no note; names clipped with `Configuration.clipped`; subscription accounts keep strict decoding (a wrong type stays a decoding error); none of these makes the configuration invalid (spec 034 FR-007, research R5, contracts/configuration.md)
- [X] T005 Add tests in Tests/UsageCoreTests/ConfigurationTests.swift, then implement in Sources/UsageCore/Config/Configuration.swift: `Configuration.accountClaudeCodeDirectories` (effective directory of every Claude subscription and the `sessionDirectory` of every Vertex account with one, accounts order, unexpanded) and `accountCodexHomes` (Codex subscription and OpenAI); `dataRelevant()` replaces `enteredCredentialDirectory`, `enteredCodexHome` and `enteredSessionDirectory` with their effective values, so a blank subscription entry and the default compare equal and whitespace in a token-based field does not refresh, while a new token-based directory does; `subscriptionFingerprint` unchanged (a token-based directory never changes it). `validate()` keeps its rules on effective values, and its duplicate message (today's line 927, shown in the Settings "Not applied" line) becomes `Claude Code directory "<dir>" is used by more than one Claude subscription account.`, so no user-visible "Credential directory" remains. Tests: the lookups in accounts order with blank subscriptions giving the default; a blank entry and `~/.claude` on two Claude subscriptions are a `.duplicateCredentialDirectory` error with the new message; a token-based directory equal to a subscription directory is valid (spec 034 FR-006, FR-006a, FR-008, research R9, data-model "Configuration lookups")
- [X] T006 [P] Add Tests/UsageCoreTests/AccountDirectoryTextTests.swift and Sources/UsageCore/Config/AccountDirectoryText.swift together (test first): `claudeCodeDirectoryLabel`, `codexHomeLabel`, `subscriptionCaption`, `codexSubscriptionCaption`, `tokenBasedCaption(for:)`, `tokenBasedPrompt(for:)`, `usageSourceSection`, `sourcesAccountsSection` ("Claude Code and Codex"), `sourcesAccountsCaption`, `openCodePrompt` with the exact texts of contracts/settings-layout.md. Tests: exact texts, each caption names its default (`~/.claude` or `~/.codex`), the subscription captions name `~/.claude-personal` and `~/.codex-lab`, the Codex subscription caption no longer contains "It only matters", no text contains `cc-deck` (spec 034 FR-006, FR-007, FR-013)

**Checkpoint**: `make test` green; accounts carry their directories with effective values, the new keys round trip, and all new texts exist. The global lists are still read (they go in US2 and US3).

---

## Phase 3: User Story 1 - Find a General option through a sidebar (Priority: P1) MVP, part 1

**Goal**: Settings > General shows a fixed-width sidebar with Refresh, Appearance, Weekly window, Notifications, Sources, Startup; each page holds exactly its old options; the selected page is remembered.

**Independent Test**: In `make app-demo`, click each sidebar entry and compare with contracts/settings-layout.md; every option of the old General tab is on exactly one page; the selection survives closing Settings, switching tabs and relaunching (quickstart "Demo build" steps 1 to 5 and 8).

### Tests for User Story 1

- [X] T007 [P] [US1] Add Tests/UsageCoreTests/GeneralSettingsPageTests.swift and Sources/UsageCore/Config/GeneralSettingsPage.swift together (test first): `allCases.map(\.title) == ["Refresh", "Appearance", "Weekly window", "Notifications", "Sources", "Startup"]`, the system images of data-model.md (`arrow.clockwise`, `paintbrush`, `calendar`, `bell`, `folder`, `power`), raw values, `defaultsKey == "generalSettingsPage"`, `init(stored:)` maps each raw value to its case and nil, empty or unknown values to `.refresh`, `Identifiable` id is the raw value (spec 034 FR-001, FR-003, research R2)

### Implementation for User Story 1

- [X] T008 [US1] Rebuild `GeneralSettingsTab` in Sources/AgentTacho/SettingsView.swift: `@AppStorage(GeneralSettingsPage.defaultsKey)` with default `GeneralSettingsPage.refresh.rawValue`; `HStack(spacing: 0) { List(selection:) { ForEach(GeneralSettingsPage.allCases) { Label(page.title, systemImage: page.systemImage).tag(page) } }.listStyle(.sidebar).frame(width: 170); Divider(); page }` with a selection binding that maps through `GeneralSettingsPage(stored:)` and ignores nil; one private `View` per page with a `.grouped` `Form` holding exactly today's rows in the order of contracts/settings-layout.md, bound to the same `draft` (Refresh; Appearance, renamed from "Display"; Weekly window; Notifications; Startup, merging "Launch" and "Updates"). Labels, captions, validation, apply, undo, redo and the "Not applied" line unchanged; the window stays 720 by 560 points and the other tabs stay as they are (spec 034 FR-001 to FR-005, research R1, R2, R10)
- [X] T009 [US1] Sources page in Sources/AgentTacho/SettingsView.swift: `Section("Additional OpenCode data directories")` through `DirectoryListSection` with prompt `AccountDirectoryText.openCodePrompt` (replacing today's `~/.local/share/opencode-work` at line 287; the `cc-deck` prompt at line 278 goes with the Claude Code section) and a text field width of `frame(minWidth: 200, maxWidth: 320)`; then `Section(AccountDirectoryText.sourcesAccountsSection)` with `sourcesAccountsCaption`; remove the "Additional Claude Code directories" and "Additional Codex homes" sections (the `$draft.logDirectories` and `$draft.codexHomes` bindings go); `DirectoryListSection` doc comment names only OpenCode. Run `make app-demo` and check every page in light and dark appearance for clipping (spec 034 FR-002, FR-010, FR-013, research R10)

**Checkpoint**: `make test` green and `make app-demo` builds; the General tab shows the sidebar and six pages (quickstart "Demo build" steps 1 to 5 and 8).

---

## Phase 4: User Story 2 - Set the agent directory on the account (Priority: P1) MVP, part 2

**Goal**: Claude Code sessions come from `~/.claude` plus the Claude Code directory of every Claude subscription and Vertex account, Codex sessions from `~/.codex` plus the Codex home of every Codex subscription and OpenAI account; the Accounts editors show the relabeled fields and the new "Usage source" section.

**Independent Test**: Fixture tests give a Vertex account `~/profiles/acme/claude` and an OpenAI account `~/.codex-lab` with session files; after a refresh their sessions count for those accounts with the same totals as the old global-list tests; no credential is read for them (spec US2, SC-003; quickstart "Demo build" steps 6 and 7).

### Tests for User Story 2

- [X] T010 [P] [US2] Rewrite the `logDirectories` uses in Tests/UsageCoreTests/LogIndexTests.swift (today lines 105, 408, 537) with account directories: the scan-failure test at line 105 ("one extra directory that exists is enough") adds a Vertex account whose `sessionDirectory` is the existing `extra` directory; the `credentialConfig(work:extra:more:)` helper at line 537 drops its `extra` parameter and its callers pass Vertex accounts through `more`; a Vertex account with `sessionDirectory` `~/profiles/acme/claude` (fixture under a temp home) whose sessions count for the Vertex account with the same totals the old global-list test expected (SC-003); `~/.claude` listed as an account directory and in a second spelling (`/Users/tester/.claude/`, absolute, trailing slash) is scanned once; a Claude subscription with a blank directory reads `~/.claude` once; two accounts with the same directory read it once and attribution decides per session; an account directory that does not exist reads nothing and adds no source error; removing the account stops reading its directory (spec 034 FR-008, FR-009, edge cases)
- [X] T011 [P] [US2] Rewrite the `codexHomes` uses in Tests/UsageCoreTests/CodexSessionSourceTests.swift (today lines 309 to 407) with account homes: an OpenAI account with `sessionDirectory` `~/.codex-lab` and a Codex subscription home both read, and `extraHomeIsRead` (line 339) becomes an OpenAI account home whose sessions count for the OpenAI account with the totals the old test expected (SC-003); `homes(for:)` deduplicates by canonical path (symlink, `~/.codex/` spelling of the default) keeping the first spelling; `missingConfiguredHomeIsAnIssueAndOthersStillCount` and `logNamesEveryLocation` become a missing account home logged as `<path>: skipped, home not found` with no record batch issue while the other homes still count; an unreadable home stays an issue; the test at line 407 that asserts `configuration.codexHomes.isEmpty` goes (spec 034 FR-008, research R8)
- [X] T012 [P] [US2] Add tests in Tests/UsageCoreTests/SubscriptionSourceTests.swift and Tests/UsageCoreTests/CodexLimitsSourceTests.swift: a configuration with only a Vertex account with `claudeCodeDirectory` and an OpenAI account with `codexHome` makes no credential read (the stub keychain and `auth.json` readers record no call) and no request; a Claude subscription with a blank directory reads the `Claude Code-credentials` item (no suffix), and a Codex subscription with a blank home reads `~/.codex/auth.json` (spec 034 FR-006a, FR-008, constitution III)
- [X] T013 [P] [US2] Update Tests/UsageCoreTests/AttributionTests.swift: replace the `cc-deck` paths (today lines 65 to 68) with `~/.claude-personal` and `~/profiles/acme/claude` under `/Users/tester`; add a test that a session found through a Vertex account's directory is attributed by its request id and provider hints exactly as before, and that the directory tie-breaker still separates only subscription accounts of the same kind, now with effective values (a blank subscription directory ties on `~/.claude`) (spec 034 FR-006a, FR-009, FR-013)

### Implementation for User Story 2

- [X] T014 [US2] In Sources/UsageCore/Logs/SessionLogSource.swift `directories(for:)` returns `[Paths.defaultClaudeDirectory] + configuration.accountClaudeCodeDirectories`, expanded and deduplicated by canonical path as today; `configuration.logDirectories` is no longer read; doc comment cites spec 034 FR-008; make T010 pass
- [X] T015 [US2] In Sources/UsageCore/Logs/CodexSessionSource.swift `homes(for:)` returns `[Paths.defaultCodexHome] + configuration.accountCodexHomes`, deduplicated by canonical path (the canonical recheck in `collect` stays); `configuration.codexHomes` is no longer read; a missing non-default home is logged as `skipped, home not found` and adds no record batch issue (spec 034 FR-008, research R8); make T011 pass
- [X] T016 [US2] Update the editors in Sources/AgentTacho/AccountSettingsView.swift: `SubscriptionEditor` uses `AccountDirectoryText.claudeCodeDirectoryLabel`, binds `$settings.enteredCredentialDirectory`, prompt `~/.claude`, caption `subscriptionCaption` (replacing the `cc-deck` text at today's line 205); `CodexSubscriptionEditor` binds `$settings.enteredCodexHome` with caption `codexSubscriptionCaption`; `TokenBasedEditor` gets `Section(AccountDirectoryText.usageSourceSection)` directly after `Section("Token-based")` and before the own budget's "Budget" section, with `LabeledContent` of the provider's label and a `TextField` (width 320) bound to `enteredSessionDirectory` (nil shown as empty, an empty entry stores nil), prompt and caption from `tokenBasedPrompt(for:)` and `tokenBasedCaption(for:)`; the provider picker keeps binding `$settings.provider` (UsageCore clears the field); `NewAccountSheet` labels the Claude field "Claude Code directory" and gets no token-based directory field. Run `make app-demo` and walk quickstart "Demo build" steps 6 and 7 (spec 034 FR-006, FR-007, FR-013, research R11)

**Checkpoint**: `make test` green and `make app-demo` builds; account directories are read, token-based ones for sessions only; Settings offers no global Claude Code or Codex list.

---

## Phase 5: User Story 3 - Upgrade with old global entries (Priority: P2)

**Goal**: `logDirectories` and `codexHomes` are no longer properties of the configuration; each old entry leaves one load note in the diagnostic log; saving never writes either key.

**Independent Test**: Load a configuration with entries in both keys (generic, covered by an account, equal to the default, blank, and a non-list value) and check the notes of contracts/configuration.md, that nothing is read from them, and that the next save writes neither key (spec US3, SC-004; quickstart "Upgrade with old global entries").

### Tests for User Story 3

- [X] T017 [P] [US3] Add Tests/UsageCoreTests/LegacyDirectoryNotesTests.swift and Sources/UsageCore/Config/LegacyDirectoryNotes.swift (`LegacyDirectoryKey`, `LegacyDirectoryNotes.notes(key:entries:readable:accounts:paths:)`) together (test first), with an injected `Paths(home:)` over temp directories: the generic note per key; the covered note naming the first matching account in list order (Claude subscription or Vertex for `logDirectories`, Codex subscription or OpenAI for `codexHomes`; a Codex account never covers a `logDirectories` entry) for `~/x`, the absolute spelling and a trailing slash, compared with `Attributor.canonical(paths.expand(_))`; the default note for `~/.claude` and `~/.codex` (default checked first, even when an account also uses the default); blank entries give no note; `readable: false` gives one `<key> is not a list of directories, ignored` note; entries clipped to 160 characters and names to 32 with `...` (spec 034 FR-011, research R6, contracts/configuration.md "Load notes")
- [X] T018 [US3] Rewrite the tests in Tests/UsageCoreTests/ConfigurationTests.swift that use the global lists (today lines 9, 80, 154, 178 and 984 to 1034): the sample configuration keeps a `logDirectories` key with an invented entry (`~/profiles/acme/claude`) and the test asserts its load note instead of a property; the data-relevance tests at lines 154 and 178 use a token-based account directory instead; a file with `logDirectories` and `codexHomes` decodes, yields the notes in order after the account notes, and encodes to JSON containing neither key; `null`, a string and a list holding a number each give the "not a list" note and keep the configuration valid; a Vertex account's `claudeCodeDirectory` equal to a `logDirectories` entry gives the covered note. Add a test in Tests/UsageCoreTests/ConfigStoreTests.swift that a stored file with both keys hands its notes out once through `takeLoadNotes()` and that a save through `ConfigStore` writes neither key. Write these tests first, then do T019 before running `make test`: they stop referencing `config.logDirectories` and `config.codexHomes`, which T019 removes (spec 034 FR-011, FR-012, FR-013)

### Implementation for User Story 3

- [X] T019 [US3] In Sources/UsageCore/Config/Configuration.swift remove the `logDirectories` and `codexHomes` properties, init parameters and `CodingKeys` cases (so the synthesized encoder can no longer write them); in `init(from:)`, after `accounts` is decoded, open a private `LegacyCodingKeys` container (`logDirectories`, `codexHomes`), decode each present key as `[String]` with `try?` (absent key: nothing; present but not decodable: `readable: false`) and append `LegacyDirectoryNotes.notes` to `ConfigurationLoadNotes`; doc comments cite spec 034 FR-011 and FR-012. Confirm nothing else in Sources or Tests references the removed properties (`rg -n "logDirectories|codexHomes" Sources Tests` only finds the legacy decoding, the notes and their tests); make T017 and T018 pass and `make app-demo` build

**Checkpoint**: `make test` green and `make app-demo` builds; old entries are reported once per load, not read, and never written again.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T020 [P] Replace the `cc-deck` paths in Tests/UsageCoreTests/CredentialReaderTests.swift (today lines 16 to 19) and Tests/UsageCoreTests/SecurityToolCredentialReaderTests.swift (today line 23) with `/Users/tester/.claude-personal` (`Claude Code-credentials-de0a6064`) and `/Users/tester/profiles/acme/claude` (`Claude Code-credentials-f15f9b72`) per research R12; both suites change `Paths(home:)` from `/Users/rhuss` to `/Users/tester` (and line 10's `/Users/rhuss/.claude` to `/Users/tester/.claude`), since the `~` spellings only hash to these names under that home; the expected service names must come out of the existing hashing unchanged (spec 034 FR-013)
- [X] T021 Run `rg cc-deck Sources Tests docs README.md` and fix every hit until it prints nothing (spec 034 SC-005, FR-013)
- [X] T022 [P] Update README.md: the Claude Code and Codex bullets of "How it works" name the account directories (a Claude subscription's or Vertex account's Claude Code directory, a Codex subscription's or OpenAI account's Codex home) instead of extra directories, and say that a token-based account's directory is read for session files only; the "Agent session data" row of "Security and privacy" says the same; any "Settings > General" reference names its page (spec 034 FR-014, constitution III)
- [X] T023 [P] Update docs/configuration.md: the example drops `codexHomes` and `logDirectories`, shows `claudeCodeDirectory` on `acc-own` and `codexHome` on `acc-oai` with invented paths; a paragraph on the account directory keys (blank subscription value means the default; token-based keys follow the provider, are read for sessions only, and a mismatched key is ignored with a load note) and on the dropped global keys with their load notes; the General bullet follows the six pages of FR-001; the Accounts bullet names "Claude Code directory", "Codex home" and the "Usage source" section; "Settings > General" references name their page (Appearance, Startup) (spec 034 FR-014)
- [X] T024 [P] Update docs/development.md (first-launch paragraph says "Claude Code directory" and drops "extra Claude Code directories"), docs/usage.md and docs/installation.md (every "Settings > General" reference names its page: "Show usage as" at usage.md line 29 and "Settings > General > Display" at line 33 become "Settings > General > Appearance", the update check at installation.md line 25 names "Settings > General > Startup"); then `rg -n "Additional Claude Code directories|Additional Codex homes|Credential directory|General > Display" Sources docs README.md` prints nothing (spec 034 FR-010, FR-014)
- [X] T025 Website check (FR-014, constitution III): with the README text of T022 in hand, re-read `src/components/agenttacho/Privacy.astro` and `src/data/features.ts` in the site checkout (clone with `gh repo clone AgentTacho/agenttacho.github.io` if missing); they name no directory setting per the plan, so no site pull request; only if one now contradicts the README, open a site pull request mirroring the change and link it from the app pull request
- [X] T026 Run `rg -n "[\x{2013}\x{2014}]"` over the changed files and the spec directory (no en or em dash), then `make test`, `make test-release` and `make app-demo`; fix until all are green (no screenshot recapture: plan "Screenshots and website", FR-015)

---

## Dependencies & Execution Order

- Phase 1, then Phase 2. T002 to T005 run in order (all in Configuration.swift and ConfigurationTests.swift; T004 needs T003's `sessionDirectory`, T005 needs T002 and T003). T006 is independent.
- US1 (Phase 3) depends on T006 (Sources page texts) only; T007 before T008; T009 after T008 (same file).
- US2 (Phase 4) depends on Phase 2. Tests T010 to T013 compile against the Phase 2 model and fail until T014 (T010) and T015 (T011); T012 and T013 guard behavior Phase 2 already provides. T016 depends on T006 and on T009 only through the shared app target build.
- US1 and US2 are both P1 and ship together: after T009 Settings no longer offers the global lists, and the global lists stay read until T014 and T015, so between T009 and T015 the branch is a work in progress, never a release.
- US3 (Phase 5) depends on US2 (T014 and T015 stop reading the properties T019 removes) and on T009 (the app no longer binds them). T017 before T019; T018 written before T019 and run with it.
- Polish after the stories; T021 after T009, T013, T016, T018 and T020; T025 after T022; T026 last.

## Parallel Opportunities

- Phase 2: T006 next to the T002 to T005 chain.
- US1: T007 next to any Phase 2 task after T006.
- US2 tests T010, T011, T012 and T013 together (four files); T014 and T015 in parallel tracks; T016 next to them.
- US3: T017 next to the T018 test rewrite.
- Polish: T020, T022, T023 and T024 together.

## Implementation Strategy

MVP is US1 plus US2 (both P1): the General sidebar and the per-account directories land together, since the Sources page drops the global lists that the account directories replace. US3 then removes the old keys with their load notes. Each phase ends with `make test` green and, from Phase 3 on, `make app-demo` building.
