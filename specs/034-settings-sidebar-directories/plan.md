# Implementation Plan: Settings Sidebar and Per-Account Directories

**Branch**: `034-settings-sidebar-directories` | **Date**: 2026-10-22 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/034-settings-sidebar-directories/spec.md`

## Summary

Split the General tab into a fixed-width sidebar with six pages (Refresh, Appearance, Weekly window, Notifications, Sources, Startup), remembered across launches, and move the Claude Code and Codex directory configuration onto the accounts: subscription accounts keep their directory (now labeled "Claude Code directory" or "Codex home", empty meaning the default), Vertex accounts get an optional `claudeCodeDirectory` and OpenAI accounts an optional `codexHome`, read for session files only. The global `logDirectories` and `codexHomes` lists are dropped: their entries are no longer read, each one leaves a load note, and the keys are never written again. The page list, the account directory model, the load notes, the directory sets of the session sources and every new caption live in UsageCore with tests first; the app target rearranges views and binds fields. All examples use invented profile paths.

## Technical Context

**Language/Version**: Swift 5.10 toolchain, Swift 6 language features as used in the repo

**Primary Dependencies**: Foundation, SwiftUI, AppKit; no new dependencies

**Storage**: `config.json`: new optional account keys `claudeCodeDirectory` (Vertex) and `codexHome` (OpenAI); keys `logDirectories` and `codexHomes` read for load notes only, never written. Defaults key `generalSettingsPage` (the selected General page, like `settingsPane`).

**Testing**: Swift Testing through `make test` (UsageCoreTests with temp-directory fixtures, DemoModeTests unchanged); UI through quickstart and walkthrough

**Target Platform**: macOS 14+

**Project Type**: desktop menu bar app (UsageCore library, DemoMode, thin SwiftUI app target)

**Performance Goals**: no extra work per refresh beyond scanning the added account directories; canonical path resolution only for legacy entries at load

**Constraints**: read-only toward agents' files; a token-based account's directory yields session files only (no keychain item, no `auth.json`, no network request; FR-008, constitution III); Settings window stays 720 by 560 points (FR-005)

**Scale/Scope**: a handful of accounts; about 14 source files touched, 3 new UsageCore files, no new app file (the General pages stay in `SettingsView.swift`)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status |
|---|---|
| I. Issue first, AI welcome, specs recommended | Pass: maintainer-initiated, full spec pipeline |
| II. Test-first, logic in UsageCore | Pass: `GeneralSettingsPage`, `AccountDirectoryText`, `LegacyDirectoryNotes`, the account directory model (entered vs effective value, provider switch), decoding and encoding, and the directory sets of `SessionLogSource` and `CodexSessionSource` are UsageCore with tests first; the app lays out pages and binds fields |
| III. Read-only, privacy | Pass: token-based directories add only session folders (`projects`, `sessions`); `SubscriptionSource` and `CodexLimitsSource` keep iterating subscription accounts only, so no credential is read for them. README "How it works" and the "Agent session data" row change; the site's Privacy.astro was checked and stays true (see Screenshots and website) |
| IV. Makefile only | Pass |
| V. Screenshots and website | Pass: table below; no shot shows General or Accounts |
| No em or en dashes, Conventional Commits, doc comments cite `spec 034 FR-xxx` | Planned |

Post-design re-check: unchanged, pass.

## Screenshots and website

| | |
|---|---|
| Shots that change | none. Verified in `scripts/screenshots/capture.sh`: `STEMS="menubar budget harnesses prices menubar-settings glance same-provider"`; the only Settings shots are `menubar-settings` (presses the "Menu Bar" tab, crops `agenttacho.menubarPreview` to `agenttacho.menubarRunOutToggle`) and `prices` (presses "Prices", then the Import sheet). Neither shows General or Accounts, and the capture's pressed names ("Menu Bar", "Prices", "Import", the OpenAI import item, "Cancel", "Models") collide with no sidebar entry. No recapture (FR-015). |
| New shots | none (no new card, no stem) |
| Demo scenario | none: the demo build shows the new layout; no shot relies on it and its accounts need no directory |
| Website copy | none. `src/components/agenttacho/Privacy.astro` checked (site checkout of 2026-10-21): its points speak of "the files your agents write on this Mac" and name no directory, so they stay true with the README change; `features.ts` names no directory setting. No site pull request. |
| README image | unchanged |

## Design

### UsageCore

1. **`Config/GeneralSettingsPage.swift`** (new): `enum GeneralSettingsPage: String, CaseIterable` with cases `refresh, appearance, weeklyWindow, notifications, sources, startup` in sidebar order (FR-001), `title` and `systemImage` per `contracts/settings-layout.md`, `static let defaultsKey = "generalSettingsPage"`, and `init(stored: String?)` that falls back to `.refresh` for nil or an unknown value (FR-003).
2. **Account directory model** (`Config/Configuration.swift`, research R3, R4):
   - `SubscriptionSettings`: the stored value becomes `enteredCredentialDirectory` (what the user typed); `credentialDirectory` turns into a computed property whose getter returns `Paths.defaultClaudeDirectory` for an empty or whitespace-only entry and whose setter stores the entry (FR-006a). Every existing reader (`SessionLogSource`, `Attributor`, `SubscriptionSource`, `KeychainServiceName`, trackers, `validate`, fingerprints) gets the effective value without a call-site change. Init keeps its `credentialDirectory:` label.
   - `CodexSubscriptionSettings`: same split, `enteredCodexHome` stored, `codexHome` effective with `Paths.defaultCodexHome`.
   - `TokenBasedSettings`: new `enteredSessionDirectory: String?` and computed `sessionDirectory: String?` (nil when nil, empty or whitespace-only); `provider` gets `didSet { if oldValue != provider { enteredSessionDirectory = nil } }` (FR-007 provider switch). `Provider` gains `sessionDirectoryKey` (`"claudeCodeDirectory"` or `"codexHome"`), `sessionHarness` (`.claudeCode` or `.codex`) and `defaultSessionDirectory` (`~/.claude` or `~/.codex`).
3. **`Account` coding** (FR-007): `CodingKeys` gains `claudeCodeDirectory`. A token-based account reads the key of its provider leniently (a non-string value is ignored with a note); the other provider's key is ignored with a note (`contracts/configuration.md`). Encode writes the provider's key only when `sessionDirectory` is non-nil. Subscription accounts encode `enteredCredentialDirectory` and `enteredCodexHome` as they are today (an empty entry stays empty in the file and means the default).
4. **`Configuration`** (FR-010, FR-011, FR-012): remove the `logDirectories` and `codexHomes` properties, init parameters and `CodingKeys` cases, so the synthesized `encode(to:)` can no longer write them. `init(from:)` opens a second container keyed by a private `LegacyCodingKeys` (`logDirectories`, `codexHomes`), decodes each present key as `[String]` with `try?` after `accounts`, and appends the notes of `LegacyDirectoryNotes` (research R6). New lookups `accountClaudeCodeDirectories: [String]` (effective directory of every Claude subscription and Vertex account with one, in accounts order) and `accountCodexHomes: [String]` (every Codex subscription and OpenAI account).
5. **`dataRelevant()`**: sets `enteredCredentialDirectory`, `enteredCodexHome` and `enteredSessionDirectory` to their effective values, so typing whitespace or clearing a field to the default does not trigger a refresh. A token-based directory stays data relevant; `subscriptionFingerprint` is untouched, so it never triggers a network refresh (research R9). `validate()` keeps its rules, now on effective values (a blank entry and `~/.claude` on two Claude subscriptions are a duplicate), and its duplicate message becomes `Claude Code directory "<dir>" is used by more than one Claude subscription account.` (FR-006 label).
6. **`Config/LegacyDirectoryNotes.swift`** (new): `static func notes(key: LegacyDirectoryKey, entries: [String]?, readable: Bool, accounts: [Account], paths: Paths) -> [String]` builds the texts of `contracts/configuration.md`: the first covering account by canonical path (an empty field covers the default) (`Attributor.canonical(paths.expand(_))`), then the generic note; an unreadable value gives one note for the key; empty entries are skipped (research R6).
7. **`Config/AccountDirectoryText.swift`** (new): labels, prompts and captions of the account directory fields and the Sources page (`contracts/settings-layout.md`), so tests can check FR-006, FR-013 and the defaults they name.
8. **`Logs/SessionLogSource.directories(for:)`** (FR-008): `configuration.accountClaudeCodeDirectories` (an empty field meaning `~/.claude`; no default added on its own, walkthrough 2026-10-22), expanded, deduplicated by canonical path as today. Doc comment cites spec 034 FR-008.
9. **`Logs/CodexSessionSource.homes(for:)`** (FR-008): `configuration.accountCodexHomes` (an empty field meaning `~/.codex`; no default added on its own), deduplicated by canonical path (today by expanded path, with a second canonical check in `collect`, which stays). A missing non-default home is logged as `skipped, home not found` and no longer adds a record batch issue (spec edge case "does not exist", research R8); an unreadable home and scan errors stay issues.
10. **`Logs/OpenCodeSource`**: unchanged (FR-002 Sources page keeps the global list).

### Interfaces

```text
public enum GeneralSettingsPage: String, CaseIterable, Identifiable, Sendable
    case refresh, appearance, weeklyWindow, notifications, sources, startup
    static let defaultsKey: String                       // "generalSettingsPage"
    init(stored: String?)                                // unknown or nil -> .refresh
    var title: String; var systemImage: String

public struct SubscriptionSettings
    public var enteredCredentialDirectory: String        // stored, encoded as credentialDirectory
    public var credentialDirectory: String { get set }   // effective: blank -> "~/.claude"
public struct CodexSubscriptionSettings
    public var enteredCodexHome: String                  // stored, encoded as codexHome
    public var codexHome: String { get set }             // effective: blank -> "~/.codex"
public struct TokenBasedSettings
    public var provider: Provider { didSet }             // a change clears enteredSessionDirectory
    public var enteredSessionDirectory: String?          // stored
    public var sessionDirectory: String? { get }         // nil when nil or blank
    init(membership:provider:sessionDirectory: String? = nil)
extension Provider
    var sessionDirectoryKey: String; var sessionHarness: Harness; var defaultSessionDirectory: String

extension Configuration
    var accountClaudeCodeDirectories: [String] { get }   // effective, unexpanded, accounts order
    var accountCodexHomes: [String] { get }

public enum LegacyDirectoryKey: String, Sendable { case logDirectories, codexHomes }
public enum LegacyDirectoryNotes
    static func notes(key: LegacyDirectoryKey, entries: [String]?, readable: Bool,
                      accounts: [Account], paths: Paths) -> [String]

public enum AccountDirectoryText
    static let claudeCodeDirectoryLabel: String          // "Claude Code directory"
    static let codexHomeLabel: String                    // "Codex home"
    static let subscriptionCaption, codexSubscriptionCaption: String
    static func tokenBasedCaption(for: Provider) -> String
    static func tokenBasedPrompt(for: Provider) -> String
    static let usageSourceSection: String                // "Usage source"
    static let sourcesAccountsSection: String            // "Claude Code and Codex"
    static let sourcesAccountsCaption: String
    static let openCodePrompt: String                    // "~/.local/share/opencode-lab"
```

### App target (thin)

11. **`GeneralSettingsTab`** (`SettingsView.swift`): `@AppStorage(GeneralSettingsPage.defaultsKey) private var storedPage = GeneralSettingsPage.refresh.rawValue`; body `HStack(spacing: 0) { List(selection:) { ForEach(GeneralSettingsPage.allCases) { Label(page.title, systemImage: page.systemImage).tag(page) } }.listStyle(.sidebar).frame(width: 170); Divider(); page view }`. The selection binding maps through `GeneralSettingsPage(stored:)` and ignores nil. Each page is its own private `View` with a `.grouped` `Form` holding exactly today's rows (FR-002, `contracts/settings-layout.md`), bound to the same `draft` (FR-004). The old "Display", "Launch" and "Updates" section headers become "Appearance" and "Startup". `DirectoryListSection` loses its Claude Code and Codex uses; its doc comment names only OpenCode; its text field width becomes flexible with a 320-point maximum (research R10).
12. **`SubscriptionEditor`**: label `AccountDirectoryText.claudeCodeDirectoryLabel`, field bound to `$settings.enteredCredentialDirectory`, prompt `~/.claude`, caption `subscriptionCaption`.
13. **`CodexSubscriptionEditor`**: field bound to `$settings.enteredCodexHome`, caption `codexSubscriptionCaption`.
14. **`TokenBasedEditor`**: after `Section("Token-based")`, a new `Section(AccountDirectoryText.usageSourceSection)` with `LabeledContent(provider label)` and a `TextField` bound to `enteredSessionDirectory` (empty string for nil, an empty entry stores nil), prompt and caption per provider; then the own budget's `BudgetFields` as today. The provider picker keeps binding `$settings.provider`; the clearing happens in UsageCore.
15. **`NewAccountSheet`**: the Claude directory label becomes "Claude Code directory". The token-based branch gets no directory field (set it after adding; research R11).

### DemoMode

16. No change: no scenario state, no coverage test (the Settings pages are not captured).

### Docs and website

17. **README**: "How it works" Claude Code and Codex bullets (account directories instead of extra directories, token-based ones for sessions only); "Security and privacy" row "Agent session data" (FR-014); the Codex sign-in row stays.
18. **`docs/configuration.md`**: example drops `codexHomes`, shows `claudeCodeDirectory` on `acc-own` and `codexHome` on `acc-oai`; a paragraph on the account directory keys and the dropped global keys with their load notes; the General bullet follows the six pages; the Accounts bullet names "Claude Code directory", "Codex home" and the "Usage source" section; "Settings > General" references get their page (Appearance, Startup).
19. **`docs/development.md`**: first-launch paragraph says "Claude Code directory" and drops "extra Claude Code directories". **`docs/usage.md`** and **`docs/installation.md`**: "Settings > General > Display" becomes "Settings > General > Appearance", the update check names "Settings > General > Startup".
20. Website: no change (table above).

### Tests (written first)

- `GeneralSettingsPageTests` (new): order, titles, symbols, `init(stored:)` fallback.
- `ConfigurationTests`: Vertex `claudeCodeDirectory` and OpenAI `codexHome` round trip; blank omitted; mismatched and non-string keys ignored with notes and not written back; provider switch clears; FR-006a effective values for blank subscription directories; legacy keys not decoded into anything, notes present, never encoded (replaces the tests at lines 9, 80, 154, 178, 984 to 1034); `dataRelevant` treats blank and default alike; the reworded duplicate message.
- `LegacyDirectoryNotesTests` (new): generic, covered (canonical: `~/x`, absolute, trailing slash), default, unreadable value, empty entries; injected `Paths(home:)` with temp directories.
- `LogIndexTests`: replace `logDirectories` uses (lines 105, 408, 537) with Vertex and subscription account directories; SC-003 fixture: a Vertex session in `~/profiles/acme/claude` counts for the Vertex account with the same totals as the old global-list test; blank subscription directory reads `~/.claude` once.
- `CodexSessionSourceTests`: replace `codexHomes` uses (lines 309 to 407) with OpenAI and Codex subscription account homes (`~/.codex-lab`); a missing account home is logged, not an issue; canonical dedupe in `homes(for:)`.
- `SubscriptionSourceTests` and `CodexLimitsSourceTests`: a configuration with only a Vertex account with `claudeCodeDirectory` and an OpenAI account with `codexHome` makes no credential read (stub readers record no call; FR-008); a Claude subscription with a blank directory reads the `Claude Code-credentials` item (FR-006a).
- `AttributionTests`, `CredentialReaderTests`, `SecurityToolCredentialReaderTests`: invented paths (research R12, recomputed keychain service names; the two credential suites move their test home from `/Users/rhuss` to `/Users/tester`).
- `AccountDirectoryTextTests` (new): captions name the defaults, examples are the invented ones, no `cc-deck`.

### Global constraints

- No em or en dash characters; doc comments cite `spec 034 FR-xxx`.
- Token-based directories never reach `SubscriptionSource`, `CodexLimitsSource`, `KeychainServiceName` or `CodexCredentialReader`.
- Every new user-visible string and every load note is built in UsageCore.
- `rg cc-deck Sources Tests docs README.md` finds nothing (SC-005).

## Project Structure

### Documentation (this feature)

```text
specs/034-settings-sidebar-directories/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/configuration.md
├── contracts/settings-layout.md
├── checklists/requirements.md
└── tasks.md            # from /speckit-tasks
```

### Source Code (repository root)

```text
Sources/UsageCore/
├── Config/Configuration.swift            # account directory model, coding, dropped keys, lookups, dataRelevant
├── Config/GeneralSettingsPage.swift      # new
├── Config/LegacyDirectoryNotes.swift     # new
├── Config/AccountDirectoryText.swift     # new
├── Logs/SessionLogSource.swift           # directories(for:)
└── Logs/CodexSessionSource.swift         # homes(for:), missing account home

Sources/AgentTacho/
├── SettingsView.swift                    # GeneralSettingsTab sidebar and pages, DirectoryListSection
└── AccountSettingsView.swift             # editors, Usage source section, sheet label

Tests/UsageCoreTests/ (GeneralSettingsPageTests, LegacyDirectoryNotesTests, AccountDirectoryTextTests,
  ConfigurationTests, LogIndexTests, CodexSessionSourceTests, AttributionTests, CredentialReaderTests,
  SecurityToolCredentialReaderTests)

README.md, docs/configuration.md, docs/development.md, docs/usage.md, docs/installation.md
```

**Structure Decision**: Existing layout. The new types sit in `Config/` next to the configuration they describe; the General pages stay in `SettingsView.swift` because each is a few rows.

## Complexity Tracking

No gate violations.
