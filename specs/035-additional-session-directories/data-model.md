# Data Model: Additional Session Directories per Account

Only what changes for spec 035. Main directories (spec 034) are untouched.

## Account settings

| Type | New field | Rule |
|---|---|---|
| `SubscriptionSettings` | `additionalSessionDirectories: [String] = []` | Claude Code directories; session files (`projects`) only (FR-001, FR-009) |
| `CodexSubscriptionSettings` | `additionalSessionDirectories: [String] = []` | Codex homes; `sessions` only; never `auth.json`, never limit snapshots for plan limits (FR-010) |
| `TokenBasedSettings` | `additionalSessionDirectories: [String] = []` | Claude Code directories for Vertex, Codex homes for OpenAI (follows `provider.sessionHarness`) |

- Entries are stored trimmed; blank entries never stay (decode drops them, `SessionDirectoryEntry.adding` never adds them).
- `TokenBasedSettings.provider` `didSet`: a change clears `enteredSessionDirectory` (spec 034) and `additionalSessionDirectories` (spec edge case "Switching a token-based account's provider").
- Initializers gain `additionalSessionDirectories: [String] = []` as their last parameter; existing call sites compile unchanged.

## AccountKind accessors

```text
extension AccountKind
    var sessionHarness: Harness { get }                       // .claudeCode, .codex, or provider.sessionHarness
    var additionalSessionDirectories: [String] { get set }    // the field of whichever settings struct
```

## Configuration lookups

```text
public struct AdditionalSessionEntry: Equatable, Sendable
    let accountId: String
    let entry: String            // trimmed, as stored
    var isWildcard: Bool { entry.contains("*") }

extension Configuration
    func additionalSessionEntries(for harness: Harness) -> [AdditionalSessionEntry]   // accounts order, entry order
```

`accountClaudeCodeDirectories` and `accountCodexHomes` keep returning main directories only.

## Entry validation

```text
public enum SessionDirectoryList: Sendable { case account, openCode }

public enum SessionDirectoryRefusal: Equatable, Sendable
    case relative, doubleStar, homeOrRoot, bareStarAtTop
    var reason: String           // texts in contracts/configuration.md

public enum SessionDirectoryEntry
    static func refusal(of entry: String, in list: SessionDirectoryList, paths: Paths) -> SessionDirectoryRefusal?
    static func adding(_ entry: String, to list: [String]) -> [String]
```

Check order: `relative` (account list always; OpenCode list only with `*`), `doubleStar`, `homeOrRoot`, `bareStarAtTop`. No file system access.

## Wildcard expansion

```text
public enum DirectoryContents: Equatable, Sendable
    case names([String]), missing, unreadable(String)

public protocol DirectoryFileSystem: Sendable
    func contents(ofDirectory path: String) -> DirectoryContents
    func isDirectory(_ path: String) -> Bool          // follows symlinks
    func canonicalPath(_ path: String) -> String      // symlinks resolved, `..` removed, no trailing slash

public struct LocalDirectoryFileSystem: DirectoryFileSystem

public enum WildcardPattern
    static func matches(name: String, component: String) -> Bool

public struct WildcardExpansion: Equatable, Sendable
    let entry: String
    let paths: [String]          // expanded spellings, path order, at most `cap`
    let matched: Int             // all matches before the cap (home and `/` excluded)
    let listingErrors: [String]
    var isCapped: Bool { matched > paths.count }

public struct WildcardExpander: Sendable
    static let cap = 100
    init(paths: Paths, fileSystem: any DirectoryFileSystem)
    func expand(_ entry: String) -> WildcardExpansion
```

## Directory resolution

```text
public struct SessionDirectory: Equatable, Sendable
    enum Origin: Equatable, Sendable { case main, literal(entry: String), wildcard(entry: String) }
    let path: String             // expanded spelling first named
    let canonical: String
    let origin: Origin           // the first route that named it
    var isMain: Bool { origin == .main }

public struct WildcardReport: Equatable, Sendable
    let entry: String
    let matched: Int
    let read: Int                // paths kept after the cap
    let listingErrors: [String]

public struct SessionDirectoryResolution: Equatable, Sendable
    let directories: [SessionDirectory]               // mains first, deduplicated by canonical path
    let additionalByAccount: [String: Set<String>]    // subscription account id -> canonical additional directories
    let wildcards: [WildcardReport]                   // one per distinct entry text, first-seen order

public struct SessionDirectoryResolver: Sendable
    init(paths: Paths, fileSystem: any DirectoryFileSystem = LocalDirectoryFileSystem())
    func resolve(_ harness: Harness, configuration: Configuration) -> SessionDirectoryResolution
```

Relationships: `SessionLogSource` and `CodexSessionSource` call `resolve` once per `collect`; `additionalByAccount` goes into `Attributor`; `wildcards` go into `WildcardCapLog` and the summary lines. `OpenCodeSource` uses `WildcardExpander` directly.

## Scanner

```text
public struct ScanTarget: Equatable, Sendable { let path: String; let isMain: Bool }

public struct ScanResult                     // existing, extended
    var files: [ScannedFile]
    var errors: [String]                     // main targets only
    var additionalNotes: [String] = []       // new: log lines for additional targets; the explicit init gains it with a default
    var scannedDirectories: Int              // unchanged: main and additional targets that existed and were readable

extension LogDirectoryScanner
    func scan(targets: [ScanTarget]) -> ScanResult
    func scan(directories: [String]) -> ScanResult       // existing; every path is a main target
```

## Session sources

```text
SessionLogSource
    nonisolated func resolution(for configuration: Configuration) -> SessionDirectoryResolution   // new
    nonisolated func directories(for configuration: Configuration) -> [String]                   // signature unchanged
    static func statsLine(_ stats: LogIndexStats, directories: Int, elapsed: TimeInterval) -> String   // was (_:elapsed:)

CodexSessionSource
    nonisolated func homes(for configuration: Configuration) -> [Location]                       // signature unchanged
    struct Location { directory: String; isDefault: Bool; origin: SessionDirectory.Origin }      // isDefault false for additional homes

OpenCodeSource
    struct Location { directory: String; isDefault: Bool; isWildcardMatch: Bool }
```

## Attribution

```text
Attributor.init(configuration: Configuration, paths: Paths = Paths(),
                additionalDirectories: [String: Set<String>] = [:])
```

Candidate (private) gains `additional: Set<String>` for subscription candidates. `fingerprint` per candidate appends the account's configured entries joined with `\u{1F}`.

## Cap log state

```text
public struct WildcardCapLog: Sendable
    init()
    mutating func lines(for reports: [WildcardReport], configuration: Configuration) -> [String]
```

State: the configuration last seen and, per entry text, the match count last logged. Reset when the configuration differs.

## Errors

`ConfigurationError.Kind` gains `sessionDirectoryEntry`.

## State transitions

```text
Settings edit (Add / Remove / undo / redo)
  -> draft differs -> validate()
       refused entry -> "Not applied: <message>" (draft keeps the entry)
       ok            -> save, needsRefresh = true, needsNetworkRefresh = false -> .local refresh

Every refresh
  -> resolve(harness)  (matches anew)
  -> scan targets in order (mains first)
  -> attribute with additionalByAccount
  -> log: per-location lines, one wildcard line per entry, cap line when WildcardCapLog says so

Load
  -> non-list value: [] + note;  refused entry: dropped + note;  next save omits both
```
