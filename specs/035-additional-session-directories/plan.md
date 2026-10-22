# Implementation Plan: Additional Session Directories per Account

**Branch**: `035-additional-session-directories` | **Date**: 2026-10-22 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/035-additional-session-directories/spec.md`

## Summary

Every Claude subscription, Vertex, Codex subscription and OpenAI account gets an optional list `additionalSessionDirectories`: host folders whose session files (`projects` or `sessions`) count for usage on top of the account's main directory from spec 034, with `*` standing for one folder level. Plan limits keep coming from the main directory only. OpenCode's global list accepts the same wildcards. A pure entry check (`SessionDirectoryEntry`), a wildcard expander behind an injectable file system (`WildcardExpander`, `DirectoryFileSystem`) and one resolver per refresh (`SessionDirectoryResolver`: mains first, then entries, canonical dedupe, cap of 100 matches per entry) live in UsageCore with tests first. The Claude Code scanner and the Codex source learn main versus additional targets, so an additional directory never fails a source or adds a dropdown problem. The subscription tie-breaker ranks additional directories below main ones. The app target adds one reused list section per account editor. All examples are invented paths.

## Technical Context

**Language/Version**: Swift 5.10 toolchain, Swift 6 language features as used in the repo

**Primary Dependencies**: Foundation, SwiftUI, AppKit; no new dependencies

**Storage**: `config.json`: new optional account key `additionalSessionDirectories` (list of strings) on all four account kinds; `openCodeDirectories` unchanged in type, refused wildcard entries dropped at load. No new defaults key.

**Testing**: Swift Testing through `make test` (UsageCoreTests with an in-memory `DirectoryFileSystem` fake and temp-directory fixtures; DemoModeTests unchanged); UI through quickstart and walkthrough

**Target Platform**: macOS 14+

**Project Type**: desktop menu bar app (UsageCore library, DemoMode, thin SwiftUI app target)

**Performance Goals**: per refresh, one directory listing per wildcard level of each wildcard entry, then the existing incremental scans; a new or vanished sandbox folder never rereads unchanged files (SC-005, research R5)

**Constraints**: read-only; nothing but session files is opened in an additional directory (no login, keychain item, `auth.json`, limit snapshot for plan limits, external program or network request; FR-009, FR-010, constitution III); Settings never touches the file system; at most 100 matches read per entry; Settings window stays 720 by 560 points

**Scale/Scope**: a handful of accounts with a few entries each, up to 100 matches per entry; 4 new UsageCore files, 7 changed UsageCore files, 2 changed app files, 3 docs; 5 new and 9 changed test files

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status |
|---|---|
| I. Issue first, AI welcome, specs recommended | Pass: maintainer-initiated, full spec pipeline (brainstorm 34) |
| II. Test-first, logic in UsageCore | Pass: entry rules, wildcard matching and expansion, resolution, scan targets, attribution ranks, cap log, decoding, encoding, validation, the Add rule and every new text are UsageCore with tests first; the app places one reused section per editor |
| III. Read-only, privacy | Pass: additional directories reach only `LogDirectoryScanner`, `CodexSessionSource` and `OpenCodeSource`; `SubscriptionSource`, `CodexLimitsSource`, `KeychainServiceName` and `CodexCredentialReader` keep reading subscription main directories only (SC-004 tests with recording doubles). README "How it works" and the "Agent session data" row change; the site's `Privacy.astro` was checked and stays true (research R13) |
| IV. Makefile only | Pass |
| V. Screenshots and website | Pass: table below; no shot shows Accounts or General > Sources |
| No em or en dashes, Conventional Commits, doc comments cite `spec 035 FR-xxx`, no real local tool path | Planned (quickstart `rg` checks) |

Post-design re-check: unchanged, pass.

## Screenshots and website

| | |
|---|---|
| Shots that change | none. Verified in `scripts/screenshots/capture.sh` line 45: `STEMS="menubar budget harnesses prices menubar-settings glance same-provider"`. Its only Settings presses are "Menu Bar" (line 493, the `menubar-settings` crop) and "Prices", "Import", the OpenAI import item and "Cancel" (lines 503 to 523, the `prices` shot). No stem opens Settings > Accounts or General > Sources, and no new button name collides with a pressed one ("Add", "Remove" already exist in those tabs). No recapture (FR-017). |
| New shots | none (no new card, no stem, no card candidate entry: an account option, not a landing page feature) |
| Demo scenario | none: `Resources/demo/default.json` needs no additional directories; the demo's Accounts tab shows the empty section and no shot relies on it |
| Website copy | none. `src/components/agenttacho/Privacy.astro` (site checkout `1d2cc03`, 2026-10-21) says "Token counts and spend come from the files your agents write on this Mac" and names no directory; additional directories are host folders read the same way, with no new request, so it stays in step with the README change. `src/data/features.ts` ("pointing each one at its own directory") stays true. No site pull request. |
| README image | unchanged |

## Design

### UsageCore

1. **Account settings** (`Config/Configuration.swift`, research R1): `additionalSessionDirectories: [String] = []` on `SubscriptionSettings`, `CodexSubscriptionSettings` and `TokenBasedSettings` (init parameter with default, last); `TokenBasedSettings.provider` `didSet` also clears the list. `AccountKind.sessionHarness` and `AccountKind.additionalSessionDirectories { get set }`. `Configuration.additionalSessionEntries(for:) -> [AdditionalSessionEntry]` (accounts order, entry order; FR-001, FR-008).
2. **`Account` coding** (FR-001, FR-006, FR-007, research R12): `CodingKeys.additionalSessionDirectories`; `decodeAdditionalDirectories(_:name:notes:)` reads leniently (non-list: `[]` plus note; entries trimmed, blanks dropped, refused dropped with a note); `encode(to:)` writes non-blank trimmed entries only when there is one, for every kind.
3. **`Configuration` decoding and validation**: after the unchanged `openCodeDirectories` type check, refused entries are dropped, with a note when a `ConfigurationLoadNotes` is attached (the drop itself never depends on it) (FR-013). `validate()` throws `ConfigurationError(kind: .sessionDirectoryEntry)` for the first refused entry (contracts/configuration.md). `dataRelevant()` needs no line: the lists are part of the settings structs, so a change refreshes, and `subscriptionFingerprint()` is untouched, so it never asks the endpoint (FR-003, research R10).
4. **`Config/SessionDirectoryEntry.swift`** (new, research R2): `SessionDirectoryList`, `SessionDirectoryRefusal` with `reason`, `refusal(of:in:paths:)`, `adding(_:to:)`. Pure string work.
5. **`Logs/WildcardExpander.swift`** (new, research R3): `DirectoryContents`, `DirectoryFileSystem`, `LocalDirectoryFileSystem`, `WildcardPattern.matches(name:component:)`, `WildcardExpansion`, `WildcardExpander` with `cap = 100` (FR-004, FR-005, FR-006 home and `/` matches).
6. **`Logs/SessionDirectoryResolver.swift`** (new, research R4): `SessionDirectory` with `Origin`, `WildcardReport`, `SessionDirectoryResolution`, `SessionDirectoryResolver.resolve(_:configuration:)` per contracts/directory-resolution.md (FR-008, FR-012).
7. **`Logs/WildcardCapLog.swift`** (new, research R9): the once-per-configuration cap line (FR-005).
8. **`Logs/LogDirectoryScanner.swift`** (research R6): `ScanTarget`, `scan(targets:)`, `ScanResult.additionalNotes`; `scan(directories:)` maps to main targets. Additional targets never add to `errors`.
9. **`Logs/SessionLogSource.swift`**: init gains `fileSystem: any DirectoryFileSystem = LocalDirectoryFileSystem()`; `resolution(for:)` (new) and `directories(for:)` (now all resolved paths, mains first; unchanged for configurations without entries); `collect` scans targets, logs `additionalNotes`, the wildcard lines and the cap lines, builds `Attributor` with `additionalByAccount`, and `statsLine` becomes `statsLine(_:directories:elapsed:)` with the leading `directories read %ld` (the value is `scan.scannedDirectories`; the existing exact-text test `statsLineShowsLargeByteCounts` changes with it) (FR-016, SC-005). The failure rule stays `scannedDirectories == 0 && !errors.isEmpty`, now main errors only (FR-008).
10. **`Logs/CodexSessionSource.swift`** (research R7): init gains `fileSystem`; `Location` gains `origin`; `homes(for:)` keeps its signature `-> [Location]` (existing tests call it) and builds the locations from the resolution, `isDefault` true only for a main home equal to `~/.codex`; `collect` keeps main behavior, logs additional problems without issues, aggregates matched homes into one line per entry, adds `%ld home(s) read` to the final line, logs cap lines, passes `additionalByAccount` to `Attributor` (FR-008, FR-010, FR-016).
11. **`Logs/OpenCodeSource.swift`** (research R8): init gains `fileSystem`; `Location` gains `isWildcardMatch`; `directories(for:)` expands `*` entries; `collect` skips a matched folder without `opencode.db` silently, logs cap lines (FR-013).
12. **`Logs/Attribution.swift`** (research R5): `init(configuration:paths:additionalDirectories:)`, candidate `additional`, tie-breaker ranks, fingerprint with configured entries (FR-011, FR-012).
13. **`Config/AccountDirectoryText.swift`**: `additionalDirectoriesSection`, `additionalDirectoriesCaption(for: Harness)`, `additionalDirectoriesPrompt(for: Harness)`, `openCodeSection`, `openCodeCaption`, reworded `sourcesAccountsCaption` (contracts/settings-layout.md; FR-002, FR-013, FR-014).

### Interfaces

```text
extension AccountKind
    var sessionHarness: Harness { get }
    var additionalSessionDirectories: [String] { get set }
public struct AdditionalSessionEntry: Equatable, Sendable { accountId: String; entry: String; isWildcard: Bool }
extension Configuration
    func additionalSessionEntries(for harness: Harness) -> [AdditionalSessionEntry]
ConfigurationError.Kind.sessionDirectoryEntry

public enum SessionDirectoryList { case account, openCode }
public enum SessionDirectoryRefusal { case relative, doubleStar, homeOrRoot, bareStarAtTop; var reason: String }
public enum SessionDirectoryEntry
    static func refusal(of: String, in: SessionDirectoryList, paths: Paths) -> SessionDirectoryRefusal?
    static func adding(_: String, to: [String]) -> [String]

public enum DirectoryContents { case names([String]), missing, unreadable(String) }
public protocol DirectoryFileSystem: Sendable
    func contents(ofDirectory: String) -> DirectoryContents
    func isDirectory(_: String) -> Bool
    func canonicalPath(_: String) -> String
public struct LocalDirectoryFileSystem: DirectoryFileSystem
public enum WildcardPattern { static func matches(name: String, component: String) -> Bool }
public struct WildcardExpansion { entry; paths: [String]; matched: Int; listingErrors: [String]; isCapped: Bool }
public struct WildcardExpander { static let cap = 100; init(paths:fileSystem:); func expand(_: String) -> WildcardExpansion }

public struct SessionDirectory { path; canonical; origin: Origin (main | literal(entry:) | wildcard(entry:)); isMain }
public struct WildcardReport { entry; matched; read; listingErrors }
public struct SessionDirectoryResolution { directories; additionalByAccount: [String: Set<String>]; wildcards }
public struct SessionDirectoryResolver { init(paths:fileSystem:); func resolve(_: Harness, configuration:) -> SessionDirectoryResolution }
public struct WildcardCapLog { init(); mutating func lines(for: [WildcardReport], configuration: Configuration) -> [String] }

public struct ScanTarget { path: String; isMain: Bool }
LogDirectoryScanner.scan(targets: [ScanTarget]) -> ScanResult          // ScanResult.additionalNotes
Attributor.init(configuration:paths:additionalDirectories: [String: Set<String>] = [:])
SessionLogSource / CodexSessionSource / OpenCodeSource init(..., fileSystem: any DirectoryFileSystem = LocalDirectoryFileSystem())
SessionLogSource
    nonisolated func resolution(for: Configuration) -> SessionDirectoryResolution
    nonisolated func directories(for: Configuration) -> [String]            // unchanged signature
    static func statsLine(_: LogIndexStats, directories: Int, elapsed: TimeInterval) -> String
CodexSessionSource
    nonisolated func homes(for: Configuration) -> [Location]                // unchanged signature
    Location { directory; isDefault; origin: SessionDirectory.Origin }
OpenCodeSource.Location { directory; isDefault; isWildcardMatch: Bool }

public enum AccountDirectoryText
    static let additionalDirectoriesSection: String               // "Additional session directories"
    static func additionalDirectoriesCaption(for: Harness) -> String
    static func additionalDirectoriesPrompt(for: Harness) -> String   // "~/.claude-lab" / "~/.codex-lab"
    static let openCodeSection, openCodeCaption: String
```

### App target (thin)

14. **`SettingsView.swift`**: `DirectoryListSection`'s Add button (today it trims `.whitespaces` only and keeps the field on a duplicate) uses `SessionDirectoryEntry.adding(_:to:)` and clears the field; its doc comment names both uses. `SourcesSettingsPage` takes title and caption from `AccountDirectoryText.openCodeSection` and `openCodeCaption`.
15. **`AccountSettingsView.swift`**: `SubscriptionEditor`, `CodexSubscriptionEditor` and `TokenBasedEditor` add `DirectoryListSection(title: additionalDirectoriesSection, caption: additionalDirectoriesCaption(for: harness), prompt: additionalDirectoriesPrompt(for: harness), directories: $settings.additionalSessionDirectories)` directly after the main directory's section (contracts/settings-layout.md). The editors bind the settings struct, not `AccountKind`, so `harness` is `.claudeCode` in `SubscriptionEditor`, `.codex` in `CodexSubscriptionEditor` and `settings.provider.sessionHarness` in `TokenBasedEditor`. `NewAccountSheet` unchanged (FR-002).

### DemoMode

16. No change: no scenario state, no coverage test (the Accounts tab and Sources page are not captured).

### Docs and website

17. **README**: "How it works" Claude Code and Codex bullets: additional session directories per account, `*` for one folder level re-evaluated on every refresh, session files only, plan limits from the main directory only, no tool run, nothing pulled from sandboxes; "Security and privacy" row "Agent session data": add "and of each account's additional session directories (session files only)" and the OpenCode matched databases (FR-015).
18. **`docs/configuration.md`**: example with `additionalSessionDirectories`; a paragraph on the key, the wildcard rule, refusals, load notes and the cap; the Accounts and Sources bullets; a new section "Sessions from sandboxes" (deliverer copies `projects`, `sessions` or `opencode.db` to `~/agent-sessions/<tool>/<sandbox>/<claude|codex|opencode>`, lists it on the account or on Sources, keeps it at least for the budget period; AgentTacho runs no tool and pulls nothing) (FR-015).
19. **`docs/development.md`**: the first-launch paragraph (line 20, "It reads no other Claude Code directory") names the additional session directories as the one other source of Claude Code sessions.
20. Website: no change (table above).

### Tests (written first)

- `SessionDirectoryEntryTests` (new): each refusal with its reason and order; accepted examples; OpenCode literal relative accepted, relative with `*` refused; `~`, `~/`, `/`, the home folder's full path (injected `Paths(home:)`); `adding` trims, ignores blank and duplicates.
- `WildcardExpanderTests` (new, in-memory fake): one level only, dot rule, partial names (`~/.claude-*`), files never match, symlinked folder matches, missing parent no error, unreadable parent in `listingErrors`, home and `/` dropped, path order, cap at 100 with `matched` 101, other glob characters literal; plus one temp-directory run with `LocalDirectoryFileSystem`.
- `SessionDirectoryResolverTests` (new): mains first; dedupe across main, literal, wildcard and two accounts (canonical, symlink, `~/x` versus absolute); `additionalByAccount`; one report per entry text; harness filtering (Vertex entries only for Claude Code, OpenAI only for Codex); folders added and removed between two calls (SC-002).
- `WildcardCapLogTests` (new): first refresh logs, repeat silent, count change logs, configuration change logs again.
- `ConfigurationTests`: round trip on all four kinds; empty and blank omitted; non-list values (`null`, string, number, mixed list) ignored with one note and not written; refused entries noted and not written; refused OpenCode wildcard entries noted, literal relative kept; `validate()` message per contract; provider switch clears the list; `needsRefresh` true and `needsNetworkRefresh` false for a list change.
- `LogIndexTests`: additional literal and wildcard directories counted with the same totals as a main directory for Claude subscription and Vertex (SC-001); one directory as main, literal and match counted once (SC-003); missing or unreadable additional directory never throws, a missing main still throws when nothing else scanned; `directories read` and `re-read 0` on an unchanged second refresh (SC-005); wildcard summary line.
- `CodexSessionSourceTests`: Codex subscription and OpenAI additional homes counted (SC-001, US1 scenario 3 with `~/.codex-lab` main and `~/.codex` additional); a fixture `auth.json` in an additional home never opened; additional problems give log lines, no issues; one wildcard line per entry; `0 file(s) parsed` on an unchanged second refresh; `home(s) read` count.
- `OpenCodeSourceTests`: two matched databases read once each plus the default; matched folder without `opencode.db` silent; a matched unreadable database gives the literal issue (FR-013).
- `AttributionTests`: main beats additional; one additional claim wins when no main; two additional claims Unassigned; fingerprint changes with entries, not with matches.
- `SubscriptionSourceTests`, `CodexLimitsSourceTests`: configurations with additional directories (holding `auth.json` and a credentials file) make no extra reader or client call (SC-004).
- `AccountDirectoryTextTests`: captions name `*` and the invented examples, prompts per harness, no real tool name (spelled in parts in the test, as `noRealToolPaths` does today, so the SC-006 search finds nothing); the exact text of `sourcesPageTexts` follows the reworded caption; `openCodeCaption` joins the `noRealToolPaths` list with the same `/.local/share/` exemption as `openCodePrompt`.

Source tests (`LogIndexTests`, `CodexSessionSourceTests`, `OpenCodeSourceTests`) run on temp-directory fixtures with the default `LocalDirectoryFileSystem`, since the scanners themselves read the real file system; the in-memory fake serves `WildcardExpanderTests` and `SessionDirectoryResolverTests` only.

### Review Focus

Input classes the spec implies beyond its stated list, each pinned by a test in the owning task:

| Failure mode | Owning task |
|---|---|
| Entry with a trailing slash, `..` or a symlinked base that resolves to the home folder or `/` | T004 (refusal), T005 (match dropped), T006 (canonical dedupe) |
| A matched folder that vanishes between expansion and scan | T011 (missing additional target goes to `additionalNotes`, never `errors`), T013 |
| A `*` in a main directory field | T006 (not expanded), T023 (not refused) |
| Two accounts listing the same wildcard entry | T006 (one `WildcardReport`, cap counted once per entry text) |
| Whitespace, newline or duplicate input in the Add field | T004 (`adding`) |
| An account removed or its provider switched | T002 (provider switch clears), T007 (removed account no longer read) |
| A deliverer writing a file during a refresh | existing partial-line handling of `LogIndex` and `CodexSessionParser`; no new code path |

### Global constraints

- No em or en dash characters; doc comments cite `spec 035 FR-xxx`.
- Additional directories never reach `SubscriptionSource`, `CodexLimitsSource`, `KeychainServiceName` or `CodexCredentialReader`.
- Only `WildcardExpander` lists folders for wildcards, always through `DirectoryFileSystem`; Settings and `validate()` never touch the file system.
- Every new user-visible string, log line and load note is built in UsageCore.
- `rg cc-deck Sources Tests docs README.md` finds nothing (SC-006).

## Project Structure

### Documentation (this feature)

```text
specs/035-additional-session-directories/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/configuration.md
├── contracts/directory-resolution.md
├── contracts/settings-layout.md
├── checklists/requirements.md
└── tasks.md            # from /speckit-tasks
```

### Source Code (repository root)

```text
Sources/UsageCore/
├── Config/Configuration.swift             # settings fields, AccountKind accessors, coding, validate, lookups
├── Config/SessionDirectoryEntry.swift     # new
├── Config/AccountDirectoryText.swift      # new texts
├── Logs/WildcardExpander.swift            # new
├── Logs/SessionDirectoryResolver.swift    # new
├── Logs/WildcardCapLog.swift              # new
├── Logs/LogDirectoryScanner.swift         # scan targets
├── Logs/SessionLogSource.swift            # resolution, log lines
├── Logs/CodexSessionSource.swift          # resolution, additional homes, log lines
├── Logs/OpenCodeSource.swift              # wildcard entries
└── Logs/Attribution.swift                 # tie-breaker ranks, fingerprint

Sources/AgentTacho/
├── SettingsView.swift                     # DirectoryListSection add rule, Sources texts
└── AccountSettingsView.swift              # one section per editor

Tests/UsageCoreTests/ (new: SessionDirectoryEntryTests, InMemoryDirectoryFileSystem, WildcardExpanderTests,
  SessionDirectoryResolverTests, WildcardCapLogTests; changed: ConfigurationTests, ConfigStoreTests, LogIndexTests,
  CodexSessionSourceTests, OpenCodeSourceTests, AttributionTests, SubscriptionSourceTests, CodexLimitsSourceTests,
  AccountDirectoryTextTests)

README.md, docs/configuration.md, docs/development.md
```

**Structure Decision**: Existing layout. The entry rule sits in `Config/` next to the configuration it validates; expansion, resolution and the cap log sit in `Logs/` next to the sources that use them.

## Complexity Tracking

No gate violations.
