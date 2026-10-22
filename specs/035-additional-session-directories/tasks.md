---

description: "Task list for additional session directories per account"
---

# Tasks: Additional Session Directories per Account

**Input**: Design documents from `specs/035-additional-session-directories/`

**Prerequisites**: plan.md (Design, Interfaces block, Global constraints), spec.md, research.md, data-model.md, contracts/configuration.md, contracts/directory-resolution.md, contracts/settings-layout.md, quickstart.md

**Tests**: Included. Constitution II requires tests first for logic in UsageCore (Swift Testing, run with `make test`).

**Organization**: Tasks are grouped by user story so each story can be implemented and tested on its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)

## Conventions for every task

- Signatures follow the Interfaces block in plan.md and data-model.md; exact strings (reasons, load notes, refusal messages, log lines, captions, prompts) follow contracts/configuration.md, contracts/directory-resolution.md and contracts/settings-layout.md.
- New and changed doc comments cite the requirements they implement (for example `spec 035 FR-008`).
- Test first, in the same task when the test needs a new type, property or init parameter: the whole UsageCoreTests target stops compiling when one test file references a symbol that does not exist yet. For a new symbol, write the test, then the smallest implementation that compiles, then make the test pass, all before running `make test`. Tests that use only existing API (for example LogIndexTests with the account fields of Phase 2) are written in their own task and fail until the implementation task lands.
- No em dash or en dash characters anywhere.
- Build and test only through the Makefile (`make test`, `make test-release`, `make app`, `make app-demo`). `make test` does not build the app target, so every task that touches `Sources/AgentTacho` ends with `make app-demo` compiling.
- Examples and fixtures use invented paths only: `~/.claude-lab`, `~/.codex-lab`, `~/agent-sessions/openshell/*/claude`, `~/agent-sessions/openshell/*/codex`, `~/agent-sessions/openshell/*/opencode`, sandbox folders `alpha`, `beta`, `gamma`, test homes under `/Users/tester` or a temp directory (FR-014).
- An additional directory never reaches `SubscriptionSource`, `CodexLimitsSource`, `KeychainServiceName` or `CodexCredentialReader`; nothing but `projects`, `sessions` or `opencode.db` is opened in it (FR-009, FR-010, constitution III).
- Only `WildcardExpander` lists folders for wildcards, always through `DirectoryFileSystem`; Settings and `validate()` never touch the file system.
- Every new user-visible string, log line and load note is built in UsageCore.
- Source tests (`LogIndexTests`, `CodexSessionSourceTests`, `OpenCodeSourceTests`) use temp-directory fixtures with the default `LocalDirectoryFileSystem`, because the scanners read the real file system; the in-memory fake of T005 serves the expander and resolver tests only. Test homes are `Paths(home: URL(fileURLWithPath: ...))` (`Paths.init(home:)` takes a URL).
- Tests never spell the real local tool name in one piece (join it from parts, as `AccountDirectoryTextTests.noRealToolPaths` does), so the SC-006 search stays empty.

---

## Phase 1: Setup

**Purpose**: Confirm a green baseline.

- [X] T001 Run `make test` and `make app-demo` on the branch and confirm both pass before any change (no file changes)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The account list, its round trip, the entry rule, the wildcard expander and the per-refresh resolver that every story builds on (data-model "Account settings", "AccountKind accessors", "Configuration lookups", "Entry validation", "Wildcard expansion", "Directory resolution"; research R1 to R4).

- [X] T002 Add tests in Tests/UsageCoreTests/ConfigurationTests.swift, then implement in Sources/UsageCore/Config/Configuration.swift (together, test first): `additionalSessionDirectories: [String] = []` on `SubscriptionSettings`, `CodexSubscriptionSettings` and `TokenBasedSettings` (init parameter with default, last; not in the explicit `CodingKeys` of the two subscription structs); `TokenBasedSettings.provider` `didSet` also clears the list; `AccountKind.sessionHarness` (`.claudeCode`, `.codex`, or `provider.sessionHarness`) and `AccountKind.additionalSessionDirectories { get set }`; `AdditionalSessionEntry` (`accountId`, `entry`, `isWildcard`) and `Configuration.additionalSessionEntries(for:)` (accounts order, entry order; Vertex entries only for `.claudeCode`, OpenAI only for `.codex`). Tests: accessors per kind, provider switch clears the list and setting the same provider keeps it, lookup order and harness filtering, `needsRefresh(comparedTo:)` true and `needsNetworkRefresh(comparedTo:)` false for an added, removed or reordered entry on each kind, `accountClaudeCodeDirectories` and `accountCodexHomes` unchanged (spec 035 FR-001, FR-003, research R1, R10)
- [X] T003 Add tests in Tests/UsageCoreTests/ConfigurationTests.swift, then implement the round trip in `Account.init(from:)` and `Account.encode(to:)` in Sources/UsageCore/Config/Configuration.swift (`CodingKeys.additionalSessionDirectories`): a list of strings decodes on all four kinds with entries trimmed and blanks dropped; encode writes the trimmed non-blank entries in order and omits the key for an empty or blank-only list; the contract example (`acc-max`, `acc-plan`) round trips. The lenient handling of non-list values and refused entries comes in US3 (T022); until then decode the key with `decodeIfPresent([String].self)` (spec 035 FR-001, contracts/configuration.md)
- [X] T004 [P] Add Tests/UsageCoreTests/SessionDirectoryEntryTests.swift and Sources/UsageCore/Config/SessionDirectoryEntry.swift together (test first): `SessionDirectoryList`, `SessionDirectoryRefusal` with `reason` (exact texts of contracts/configuration.md), `SessionDirectoryEntry.refusal(of:in:paths:)` and `adding(_:to:)`. Tests with an injected `Paths(home: URL(fileURLWithPath: "/Users/tester"))`: each refusal and its reason; check order (`relative`, `doubleStar`, `homeOrRoot`, `bareStarAtTop`; for example `agent-sessions/**/x` is `relative`); `~name/x` relative; `~`, `~/`, `/`, `/Users/tester`, `/Users/tester/` and `~/x/..` are `homeOrRoot`; `~/*/claude`, `/*`, `~/*` are `bareStarAtTop`; the accepted examples of the contract give nil; in `.openCode` a literal relative entry is accepted and a relative entry with `*` refused; `adding` trims whitespace and newlines, ignores blank entries and entries already in the list (spec 035 FR-002, FR-006, research R2)
- [X] T005 [P] Add Tests/UsageCoreTests/InMemoryDirectoryFileSystem.swift (test double: folders, files, symlinks to folders, unreadable folders, canonical paths) and Tests/UsageCoreTests/WildcardExpanderTests.swift together with Sources/UsageCore/Logs/WildcardExpander.swift (test first): `DirectoryContents`, `DirectoryFileSystem`, `LocalDirectoryFileSystem` (FileManager, `Attributor.canonical`), `WildcardPattern.matches(name:component:)`, `WildcardExpansion` (`isCapped`), `WildcardExpander` with `cap = 100`. Tests: every row of the contracts/directory-resolution.md expansion table; `*` matches the empty run and never `/`; partial names (`~/.claude-*`, `sandbox-*`); a leading `*` skips dot names while `.claude-*` matches `.claude-lab`; one level only; files never match; a symlink to a folder matches; other glob characters (`?`, `[`, `]`, `{`, `}`) literal; a missing parent gives no match and no error; an unreadable parent lands in `listingErrors`; a match that is the home folder or `/` is dropped and not counted; path order by `String <`; 101 matches give 100 `paths`, `matched` 101, `isCapped`; one temp-directory run with `LocalDirectoryFileSystem` including a symlink (spec 035 FR-004, FR-005, FR-006, research R3)
- [X] T006 Add Tests/UsageCoreTests/SessionDirectoryResolverTests.swift and Sources/UsageCore/Logs/SessionDirectoryResolver.swift together (test first, with the in-memory file system of T005): `SessionDirectory` with `Origin` and `isMain`, `WildcardReport`, `SessionDirectoryResolution`, `SessionDirectoryResolver.resolve(_:configuration:)` per contracts/directory-resolution.md "Resolution order". Tests: main directories first in accounts order, then entries in accounts and list order, wildcard matches in path order; dedupe by canonical path across main, literal, wildcard and two accounts (symlink, `~/x` versus `/Users/tester/x`, trailing slash) keeping the first spelling and origin; `additionalByAccount` holds the canonical literal and matched directories of each subscription account even when first reached another way, and no token-based account; one `WildcardReport` per distinct entry text in first-seen order with `matched`, `read` and `listingErrors`; the home folder and `/` skipped for every Claude Code directory and every additional Codex directory, a Codex main home not filtered; harness filtering (Vertex only for `.claudeCode`, OpenAI only for `.codex`); the contract example gives the documented result; folders added and removed between two calls change the result (SC-002); two accounts listing the same wildcard entry give one report and one expansion; a `*` in a main directory (`credentialDirectory`, `codexHome`, `claudeCodeDirectory`) is not expanded; a configuration without entries resolves to exactly today's main directories (spec 035 FR-005, FR-008, FR-012, research R4)

**Checkpoint**: `make test` green; accounts carry their lists, the lists round trip, and entry rules, expansion and resolution exist in UsageCore. Nothing reads additional directories yet.

---

## Phase 3: User Story 1 - Add a second session directory to an account (Priority: P1) MVP

**Goal**: A literal additional directory on any of the four account kinds is read for sessions from the next refresh on, with the same totals as a main directory, never fails a source, never reads a login, and is editable in Settings > Accounts.

**Independent Test**: Fixture tests give an account a main directory and one additional directory with session files in both; after a refresh both count with main-directory totals, `auth.json` and credential readers are never touched (SC-001, SC-003, SC-004); in `make app-demo` the section appears under the main directory section on every account (quickstart "Demo build", fixture walk-through steps 1 and 3).

### Tests for User Story 1

- [X] T007 [P] [US1] Add tests in Tests/UsageCoreTests/LogIndexTests.swift through `SessionLogSource` with literal entries: a Claude subscription and a Vertex account each with an additional directory under a temp home count with the same totals as the same fixtures in a main directory (SC-001); a Vertex account with an empty main directory reads `~/.claude` plus its additional directories; one directory named as a main directory and as a literal entry counts each session once (SC-003); an additional directory equal to the account's own main directory is read once; a missing or unreadable additional directory neither throws nor adds to the source's errors and leaves its log line (`<path>: skipped, not found`, `<path>: error: not readable`); with every main directory missing and one additional directory readable the source does not throw, with nothing readable and a main error it still throws; removing the entry, or the account that lists it, stops reading the directory unless another account still names it (spec 035 FR-008, FR-009, US1 scenarios 4 and 6)
- [X] T008 [P] [US1] Add tests in Tests/UsageCoreTests/CodexSessionSourceTests.swift with literal entries: a Codex subscription with main `~/.codex-lab` and additional `~/.codex` counts the ChatGPT-plan sessions of both (US1 scenario 3); an OpenAI account with additional `~/.codex` counts its API-key sessions (US1 scenario 5); both with the same totals as the same fixtures in a main home (SC-001); a fixture `auth.json` in the additional home is never opened (the file is unreadable or a recording reader sees no call); one home as main and literal entry counts once (SC-003); a missing additional home logs `<home>: skipped, not found`, an unreadable one logs `<home>: error: <message>`, and neither adds an issue; main and literal homes keep their per-home line (spec 035 FR-008, FR-009, FR-010, FR-016)
- [X] T009 [P] [US1] Add tests in Tests/UsageCoreTests/SubscriptionSourceTests.swift and Tests/UsageCoreTests/CodexLimitsSourceTests.swift: configurations whose Claude subscription lists `~/.claude-lab` and whose Codex subscription lists `~/.codex` (fixture folders holding a credentials file and an `auth.json`) make exactly the credential reads and requests of the same configuration without the lists; the existing `RecordingCredentialReader` (SubscriptionSourceTests) never sees a keychain service name for `~/.claude-lab` and the existing `FakeCodexCredentialReader` (CodexLimitsSourceTests) never a home under `~/.codex` (SC-004; spec 035 FR-009, FR-010)

### Implementation for User Story 1

- [X] T010 [P] [US1] Add tests in Tests/UsageCoreTests/AttributionTests.swift, then implement in Sources/UsageCore/Logs/Attribution.swift (together, test first, the init gains a parameter): `Attributor.init(configuration:paths:additionalDirectories:)` with default `[:]`; subscription candidates carry `additional`; the tie-breaker of contracts/directory-resolution.md "Tie-breaker"; `fingerprint` appends each subscription account's configured entries joined with `\u{1F}`. Tests: main beats additional for two Claude subscriptions; exactly one additional claim wins when no main matches; two additional claims stay Unassigned; a session whose request id or provider hints point to another account is not forced onto the listing account (FR-011); the fingerprint changes when an entry is added and not when only `additionalDirectories` matches change (spec 035 FR-011, FR-012, research R5)
- [X] T011 [US1] Add tests for the scanner in Tests/UsageCoreTests/LogIndexTests.swift, then implement in Sources/UsageCore/Logs/LogDirectoryScanner.swift (together, test first): `ScanTarget`, `scan(targets:)`, `ScanResult.additionalNotes`; `scan(directories:)` maps every path to a main target so existing tests pass unchanged; a missing, unreadable or partly unreadable additional target writes the lines of contracts/directory-resolution.md to `additionalNotes` and never to `errors`; `scannedDirectories` counts readable main and additional targets; a file reached through a main and an additional target is found in the main one (spec 035 FR-008, FR-012, research R6)
- [X] T012 [US1] In Sources/UsageCore/Logs/SessionLogSource.swift: init gains `fileSystem: any DirectoryFileSystem = LocalDirectoryFileSystem()`; `resolution(for:)` (new) calls `SessionDirectoryResolver`; `directories(for:)` returns all resolved paths, mains first (unchanged for configurations without entries); `collect` scans `ScanTarget`s, logs `additionalNotes`, builds `Attributor` with `resolution.additionalByAccount`, and keeps the failure rule `scannedDirectories == 0 && !errors.isEmpty` (main errors only); make T007 pass (spec 035 FR-008, FR-012, research R4, R6)
- [X] T013 [US1] In Sources/UsageCore/Logs/CodexSessionSource.swift: init gains `fileSystem`; `Location` gains `origin`; `homes(for:)` keeps its signature `-> [Location]` (the existing tests in CodexSessionSourceTests call it) and builds the locations from the resolution's directories (main homes keep `isDefault` and today's lines and issues; additional homes have `isDefault` false, so a missing additional `~/.codex` logs `skipped, not found`, not `Codex not installed`); additional homes read `sessions` only, log `skipped, not found` and `error: <message>` without issues; `Attributor` gets `additionalByAccount`; make T008 and T009 pass (spec 035 FR-008, FR-009, FR-010, research R7)
- [X] T014 [P] [US1] Add tests in Tests/UsageCoreTests/AccountDirectoryTextTests.swift, then implement in Sources/UsageCore/Config/AccountDirectoryText.swift (together, test first): `additionalDirectoriesSection`, `additionalDirectoriesCaption(for:)`, `additionalDirectoriesPrompt(for:)` and the reworded `sourcesAccountsCaption`, exact texts of contracts/settings-layout.md. Tests: exact texts per harness; the Claude Code caption names `~/agent-sessions/openshell/*/claude` and the Codex caption `~/agent-sessions/openshell/*/codex` and `auth.json`; both mention `*` and "never a login"; prompts `~/.claude-lab` and `~/.codex-lab`; the new texts join the `noRealToolPaths` list (real tool name spelled in parts); the exact text in the existing `sourcesPageTexts` test changes to the reworded `sourcesAccountsCaption`, and `captionsNameTheirDefault` still passes (spec 035 FR-002, FR-014)
- [X] T015 [US1] App target, Sources/AgentTacho/SettingsView.swift and Sources/AgentTacho/AccountSettingsView.swift: `DirectoryListSection`'s Add button sets the list to `SessionDirectoryEntry.adding(_:to:)` and clears the field, its doc comment names both uses; `SubscriptionEditor`, `CodexSubscriptionEditor` and `TokenBasedEditor` add `DirectoryListSection(title: AccountDirectoryText.additionalDirectoriesSection, caption: additionalDirectoriesCaption(for: harness), prompt: additionalDirectoriesPrompt(for: harness), directories: $settings.additionalSessionDirectories)` directly after "Subscription", "Codex subscription" and "Usage source" respectively (the editors bind the settings struct, so the harness is `.claudeCode`, `.codex` and `settings.provider.sessionHarness`); `SourcesSettingsPage` uses the reworded `sourcesAccountsCaption`; `NewAccountSheet` unchanged. Run `make app-demo` and check the section order of contracts/settings-layout.md on all four account kinds, in light and dark appearance, with no clipping in the 720 by 560 window (spec 035 FR-002, FR-003, research R11)

**Checkpoint**: `make test` green and `make app-demo` builds; literal additional directories are read for sessions only on all four kinds and editable in Settings.

---

## Phase 4: User Story 2 - Cover every sandbox with one wildcard entry (Priority: P1)

**Goal**: A wildcard entry reads every matching folder anew on every refresh, at most 100 per entry, with one summary line per entry, a cap line only when needed, and no full reread when folders come and go.

**Independent Test**: Fixture folders `alpha/claude` and `beta/claude` under a temp home, the entry `~/agent-sessions/openshell/*/claude` on an account; refresh, add `gamma/claude`, refresh, delete `beta`, refresh; each refresh counts exactly the folders present and the log names the match count (SC-002, SC-005; quickstart fixture walk-through steps 2 and 5).

### Tests for User Story 2

- [X] T016 [P] [US2] Add Tests/UsageCoreTests/WildcardCapLogTests.swift and Sources/UsageCore/Logs/WildcardCapLog.swift together (test first): `WildcardCapLog.lines(for:configuration:)` returns `wildcard "<entry>": <n> folders matched, only the first 100 are read` for a capped report on the first call, nothing on a repeat with the same count and configuration, a line again when the count changes, and a line again after the configuration changes; uncapped reports give nothing (spec 035 FR-005, research R9)
- [X] T017 [P] [US2] Add tests in Tests/UsageCoreTests/LogIndexTests.swift through `SessionLogSource` with the entry `~/agent-sessions/openshell/*/claude` under a temp home: `alpha` and `beta` count (US2 scenario 1); `gamma` added between refreshes counts from the second refresh, `beta` deleted stops counting and nothing fails (SC-002, scenarios 2 and 3); `team/alpha/claude` and `.cache/claude` do not count (scenarios 4 and 5); an entry matching nothing reads nothing and fails nothing (scenario 7); one directory named as a main directory, a literal entry and a wildcard match counts each session once (SC-003); the log has `wildcard "<entry>": <n> folder(s) matched` once per entry and the stats line `directories read <d>`; a second refresh over unchanged matches logs `re-read 0` (SC-005); a newly matched folder does not reread the files already indexed (fingerprint unchanged); a capped entry logs the cap line once across two refreshes (spec 035 FR-004, FR-005, FR-008, FR-016)
- [X] T018 [P] [US2] Add tests in Tests/UsageCoreTests/CodexSessionSourceTests.swift with the entry `~/agent-sessions/openshell/*/codex` on a Codex subscription and an OpenAI account: matched homes count by auth mode; matched homes share one line `wildcard "<entry>": <n> folder(s) matched, <r> record(s) in window, <f> file(s) read` and get no per-home line unless one fails to read (`<home>: error: <message>`, no issue); the final line starts with `<h> home(s) read`; a second refresh over unchanged matches logs `0 file(s) parsed` (SC-005); a fixture `auth.json` in a matched home is never opened; the rate-limit data of a matched session decides its auth mode and never feeds plan limits (spec 035 FR-008, FR-010, FR-016)

### Implementation for User Story 2

- [X] T019 [US2] In Sources/UsageCore/Logs/SessionLogSource.swift: log one `wildcard "<entry>": <n> folder(s) matched` line per `WildcardReport`, one `wildcard "<entry>": cannot list <path>` line per listing error, the cap lines from an actor-held `WildcardCapLog`, and change `statsLine` to `statsLine(_:directories:elapsed:)` with the leading `directories read %ld` (value `scan.scannedDirectories`); update the exact expectation of the existing `statsLineShowsLargeByteCounts` test in Tests/UsageCoreTests/LogIndexTests.swift in the same task; make T017 pass (spec 035 FR-005, FR-016, SC-005)
- [X] T020 [US2] In Sources/UsageCore/Logs/CodexSessionSource.swift: aggregate matched homes into one summary line per entry (failures still get their own line), log listing errors and cap lines through an actor-held `WildcardCapLog`, and start the final line with `%ld home(s) read` (homes that existed and were readable, main and additional); make T018 pass (spec 035 FR-005, FR-016, research R7)

**Checkpoint**: `make test` green; wildcard entries on all four kinds follow the folders present at each refresh with the log lines of the contract.

---

## Phase 5: User Story 3 - Hand-edit the configuration (Priority: P2)

**Goal**: Hand-written `additionalSessionDirectories` values load with the same rules as Settings: refused entries and non-list values are dropped with a load note and never written back; Settings refuses the same entries with a "Not applied" line.

**Independent Test**: Load configurations with valid, blank, refused and malformed values and check the directories read, the load notes, that the configuration stays valid, and what the next save writes (quickstart "Hand edit", fixture walk-through step 4).

### Tests for User Story 3

- [X] T021 [P] [US3] Add tests in Tests/UsageCoreTests/ConfigStoreTests.swift: a stored file with a refused entry and a non-list value on two accounts hands its notes out once through `takeLoadNotes()`, the loaded configuration validates, and a save through `ConfigStore` writes neither the refused entry nor the malformed key (spec 035 FR-006, FR-007)

### Implementation for User Story 3

- [X] T022 [US3] Add tests in Tests/UsageCoreTests/ConfigurationTests.swift, then implement lenient decoding in `Account.init(from:)` in Sources/UsageCore/Config/Configuration.swift (together, test first; private helper `decodeAdditionalDirectories(_:name:notes:)`): `null`, a string, a number, an object and a list holding a number each give an empty list and one note `additionalSessionDirectories of account "<name>" is not readable, ignored` on all four kinds and keep the configuration valid; each refused entry (checked with `SessionDirectoryEntry.refusal(of:in: .account, paths: Paths())`) is dropped with the note `additionalSessionDirectories entry "<entry>" of account "<name>" is refused (<reason>), ignored`; names and entries clipped with `Configuration.clipped`; encode then writes only the kept entries (US3 scenarios 1 to 4; spec 035 FR-006, FR-007, research R12)
- [X] T023 [US3] Add tests in Tests/UsageCoreTests/ConfigurationTests.swift, then implement in Sources/UsageCore/Config/Configuration.swift (together, test first, new enum case): `ConfigurationError.Kind.sessionDirectoryEntry`; `validate()` throws it for the first refused entry in accounts order, then the OpenCode list, with the unclipped messages `Additional session directory "<entry>" of account "<name>": <reason>.` and `OpenCode data directory "<entry>": <reason>.`; `Configuration.init(from:)` keeps the `openCodeDirectories` type check unchanged (a non-list stays a decoding error) and then drops refused entries (`.openCode`) whether or not a `ConfigurationLoadNotes` is attached (today `noteDirectories` runs only with one), noting `openCodeDirectories entry "<entry>" is refused (<reason>), ignored` when it is, and keeping literal relative entries. Tests: each message; order between accounts and the OpenCode list; a `*` in `credentialDirectory`, `codexHome` or `claudeCodeDirectory` is not refused; a refused OpenCode wildcard entry is noted and not written back, `opencode-lab` (relative literal) kept; make T021 pass (spec 035 FR-006, FR-013, research R12, contracts/configuration.md "Settings refusal")

**Checkpoint**: `make test` green; hand-edited lists load cleanly with notes, and Settings shows "Not applied" for a refused entry through the existing draft path (no app change).

---

## Phase 6: User Story 4 - Wildcards for OpenCode data directories (Priority: P3)

**Goal**: OpenCode data directory entries with `*` read the `opencode.db` of every matched folder once, in addition to the default, and the Sources caption explains `*`.

**Independent Test**: Fixture databases in two matched folders, the entry `~/agent-sessions/openshell/*/opencode`; refresh and check both databases are read once each plus the default, a matched folder without `opencode.db` stays silent (quickstart fixture walk-through step 7).

### Implementation for User Story 4

- [X] T024 [P] [US4] Add tests in Tests/UsageCoreTests/AccountDirectoryTextTests.swift, then implement in Sources/UsageCore/Config/AccountDirectoryText.swift (together, test first): `openCodeSection` (`Additional OpenCode data directories`) and `openCodeCaption` with the exact text of contracts/settings-layout.md, naming `*` and `~/agent-sessions/openshell/*/opencode`; `openCodeCaption` joins the `noRealToolPaths` list and its `/.local/share/` check exempts it like `openCodePrompt` (the caption names the default `~/.local/share/opencode`) (spec 035 FR-013, FR-014)
- [X] T025 [US4] Add tests in Tests/UsageCoreTests/OpenCodeSourceTests.swift, then implement in Sources/UsageCore/Logs/OpenCodeSource.swift (together, test first, the init gains a parameter): init gains `fileSystem: any DirectoryFileSystem = LocalDirectoryFileSystem()`; `Location` gains `isWildcardMatch`; `directories(for:)` keeps the default first and literal entries as today and expands `*` entries through `WildcardExpander`; `collect` skips a matched folder without `opencode.db` silently, handles an unreadable or busy matched database like a literal one (issue plus stale), logs listing errors and cap lines through an actor-held `WildcardCapLog`. Tests: two matched databases read once each plus the default (US4 scenario 1); a database reached through a literal entry and a match read once; a matched folder without `opencode.db` gives no line and no issue (scenario 3); an unreadable matched database gives the literal issue (spec 035 FR-005, FR-013, research R8)
- [X] T026 [US4] In Sources/AgentTacho/SettingsView.swift `SourcesSettingsPage` takes the OpenCode section title and caption from `AccountDirectoryText.openCodeSection` and `openCodeCaption` (the inline caption string goes). Run `make app-demo` and check General > Sources in light and dark appearance for clipping (spec 035 FR-013, US4 scenario 2)

**Checkpoint**: `make test` green and `make app-demo` builds; OpenCode wildcard entries work with the same rules as the account lists.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T027 [P] Update README.md: the Claude Code and Codex bullets of "How it works" name each account's additional session directories, `*` for one folder level re-evaluated on every refresh, session files only, plan limits from the main directory only, no tool run and nothing pulled from sandboxes; the "Agent session data" row of "Security and privacy" adds "and of each account's additional session directories (session files only)" and the OpenCode matched databases (spec 035 FR-015, constitution III)
- [X] T028 [P] Update docs/configuration.md: the example gains `additionalSessionDirectories` with invented paths; a paragraph on the key, the wildcard rule, the refusals, the load notes and the cap of 100; the Accounts and Sources bullets mention the new section and the OpenCode wildcard; a new section "Sessions from sandboxes" (a deliverer copies `projects`, `sessions` or `opencode.db` to `~/agent-sessions/<tool>/<sandbox>/<claude|codex|opencode>`, lists it on the account or on General > Sources, and keeps it at least for the budget period; AgentTacho runs no tool and pulls nothing) (spec 035 FR-015)
- [X] T029 [P] Update docs/development.md: the first-launch paragraph ("It reads no other Claude Code directory") names the additional session directories as the one other source of Claude Code sessions (spec 035 FR-015)
- [X] T030 Run `rg cc-deck Sources Tests docs README.md` and fix every hit until it prints nothing; the term may appear only in specs/ (the SC-006 search itself), never in the searched folders, and tests build it from parts (spec 035 SC-006, FR-014)
- [X] T031 Run `rg -n "[\x{2013}\x{2014}]" specs/035-additional-session-directories Sources Tests docs README.md` (no en or em dash), then `make test`, `make test-release` and `make app-demo`; fix until all are green. No screenshot recapture and no site pull request (plan "Screenshots and website", FR-017)

---

## Phase 8: Directory list in the macOS style (walkthrough 2026-10-22)

The walkthrough found that per-row "Remove" buttons and the inline "Add directory" field do not follow the macOS list pattern (spec FR-002, FR-013 revised, contracts/settings-layout.md).

- [X] T032 [P] Add tests in Tests/UsageCoreTests/AccountDirectoryTextTests.swift, then implement in Sources/UsageCore/Config/AccountDirectoryText.swift (together, test first): `chooseFolderItem`, `enterPathItem`, `enterPathTitle`, `enterPathCaption`, `emptyList` and `chooseFolderMessage(for:)` (Claude Code, Codex, OpenCode) with the exact texts of contracts/settings-layout.md; the new texts join `noRealToolPaths` (spec 035 FR-002, FR-014)
- [X] T033 [P] Add tests in Tests/UsageCoreTests/SessionDirectoryEntryTests.swift, then implement `SessionDirectoryEntry.entry(forChosenFolder:paths:)` in Sources/UsageCore/Config/SessionDirectoryEntry.swift (together, test first): the home folder becomes `~`, a folder below it `~/<rest>`, a folder outside it stays absolute, a trailing slash is dropped, a sibling whose name starts with the home folder's name (`/Users/ann2` for home `/Users/ann`) stays absolute (spec 035 FR-002)
- [X] T034 Rebuild `DirectoryListSection` in Sources/AgentTacho/SettingsView.swift after contracts/settings-layout.md: bordered list with multi-selection, middle truncation and tooltip, empty text, plus menu (Choose Folder…, Enter Path…), minus button and Delete key; `EnterPathSheet`; the account and OpenCode call sites pass the folder message. Run `make app-demo` and check Settings > Accounts and General > Sources in light and dark appearance for clipping (spec 035 FR-002, FR-013)
- [X] T036 Edit a row in place (walkthrough 2026-10-22, follows T034): tests in Tests/UsageCoreTests/SessionDirectoryEntryTests.swift and AccountDirectoryTextTests.swift, then `SessionDirectoryEntry.replacing(at:with:in:)` and `AccountDirectoryText.editItem`; in `DirectoryListSection` the list's `contextMenu(forSelectionType:menu:primaryAction:)` starts the edit on a double-click or Return and offers Edit and Remove (spec 035 FR-002)
- [X] T035 Update RUNBOOK.md Steps 3, 6 and 8 for the new controls; run `make test`, `make test-release` and `make app-demo` until green; no screenshot stem opens Accounts or Sources (plan "Screenshots and website")

---

## Dependencies & Execution Order

- Phase 1, then Phase 2. T002 before T003 (same files, T003 needs the field). T004 and T005 are independent of T002 and T003 and of each other. T006 needs T002 (`additionalSessionEntries`, `sessionHarness`) and T005 (`DirectoryFileSystem`, `WildcardExpander`, the in-memory fake).
- US1 (Phase 3) depends on Phase 2. Tests T007, T008 and T009 compile against the Phase 2 model and fail until T012 (T007) and T013 (T008, T009). T010 and T011 before T012 and T013 (both use the new `Attributor` init; T012 uses `scan(targets:)`). T014 before T015; T015 needs T004 (`adding`) and T002 (the field).
- US2 (Phase 4) depends on US1 (T012, T013). T016 before T019 and T020. T017 fails until T019, T018 until T020.
- US3 (Phase 5) depends on Phase 2 only (T003 decoding, T004 refusals); T022 before T023 (same files); T021 written first and passing after T023. It can run next to US1 and US2.
- US4 (Phase 6) depends on Phase 2 (T005) and on T016 (`WildcardCapLog`); T024 before T026; T025 independent of T024.
- Polish after the stories; T030 after T014, T024 and T027 to T029; T031 last.

## Parallel Opportunities

- Phase 2: T004 and T005 next to the T002 and T003 chain.
- US1: tests T007, T008 and T009 together (three files); T010 and T014 next to them (own files); T011, then T012 and T013 in parallel tracks (different source files).
- US2: T016, T017 and T018 together; T019 and T020 in parallel tracks.
- US3 next to US1 and US2 (Configuration.swift and ConfigStoreTests only; avoid running it at the same time as T002 or T003).
- US4: T024 next to T025.
- Polish: T027, T028 and T029 together.

## Implementation Strategy

MVP is US1 plus US2 (both P1): literal entries close the gap the spec 034 walkthrough found, and wildcard entries cover the sandbox case that motivates the feature; both rest on the resolver of Phase 2. US3 then hardens hand-edited files and the Settings refusal, and US4 extends the same wildcard rule to OpenCode. Each phase ends with `make test` green and, for phases that touch `Sources/AgentTacho` (US1, US4), `make app-demo` building.
