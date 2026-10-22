import Foundation

/// One directory a refresh reads sessions from (spec 035 FR-008).
public struct SessionDirectory: Equatable, Sendable {
    /// The route that named the directory first.
    public enum Origin: Equatable, Sendable {
        /// An account's main directory (spec 034).
        case main
        /// A literal entry of an account's additional session directories.
        case literal(entry: String)
        /// A match of a wildcard entry.
        case wildcard(entry: String)
    }

    /// The expanded spelling the directory was first named with.
    public let path: String
    /// Symlinks resolved, `..` removed, no trailing slash.
    public let canonical: String
    public let origin: Origin

    /// True for a main directory, whose problems keep their spec 034
    /// handling; additional directories are only logged (FR-008).
    public var isMain: Bool { origin == .main }

    public init(path: String, canonical: String, origin: Origin) {
        self.path = path
        self.canonical = canonical
        self.origin = origin
    }
}

/// What one wildcard entry matched in a refresh, for the log lines and the
/// cap note (spec 035 FR-005, FR-016).
public struct WildcardReport: Equatable, Sendable {
    public let entry: String
    /// All matches before the cap.
    public let matched: Int
    /// Matches kept after the cap.
    public let read: Int
    /// Folders on the way that were not listed.
    public let listingErrors: [WildcardListingError]
    /// True when a level kept only `WildcardExpander.levelBudget` candidates.
    public let isTruncated: Bool

    public init(entry: String, matched: Int, read: Int, listingErrors: [WildcardListingError], isTruncated: Bool = false) {
        self.entry = entry
        self.matched = matched
        self.read = read
        self.listingErrors = listingErrors
        self.isTruncated = isTruncated
    }

    public init(_ expansion: WildcardExpansion) {
        self.init(entry: expansion.entry, matched: expansion.matched, read: expansion.paths.count,
                  listingErrors: expansion.listingErrors, isTruncated: expansion.isTruncated)
    }

    /// The per-refresh lines for the folders that were not listed, the same
    /// in every session source (spec 035 FR-008).
    public var listingLines: [String] {
        listingErrors.map { "wildcard \"\(entry)\": cannot list \($0.path): \($0.reason)" }
    }
}

/// The directories of one harness for one refresh (spec 035 FR-008,
/// FR-012).
public struct SessionDirectoryResolution: Equatable, Sendable {
    /// Main directories first, then additional ones; each canonical path once.
    public let directories: [SessionDirectory]
    /// Per subscription account id, the canonical paths of its literal
    /// entries and wildcard matches, for the attribution tie-breaker.
    public let additionalByAccount: [String: Set<String>]
    /// One report per distinct wildcard entry text, in first-seen order.
    public let wildcards: [WildcardReport]

    public init(directories: [SessionDirectory], additionalByAccount: [String: Set<String>], wildcards: [WildcardReport]) {
        self.directories = directories
        self.additionalByAccount = additionalByAccount
        self.wildcards = wildcards
    }
}

/// Turns the configuration into the directories one refresh reads for the
/// Claude Code or Codex sessions (spec 035 FR-005, FR-008, FR-012, research
/// R4, contracts/directory-resolution.md "Resolution order"): the main
/// directories of spec 034 in accounts order, then every account's
/// additional entries in accounts order and list order, wildcard matches
/// anew on every call in path order, at most 100 per entry. Each directory
/// appears once by canonical path, with the first spelling and origin, so
/// a file reached through a main and an additional directory is found in
/// the main one.
public struct SessionDirectoryResolver: Sendable {
    private let paths: Paths
    private let fileSystem: any DirectoryFileSystem

    public init(paths: Paths, fileSystem: any DirectoryFileSystem = LocalDirectoryFileSystem()) {
        self.paths = paths
        self.fileSystem = fileSystem
    }

    public func resolve(_ harness: Harness, configuration: Configuration) -> SessionDirectoryResolution {
        let mains: [String]
        switch harness {
        case .claudeCode: mains = configuration.accountClaudeCodeDirectories
        case .codex: mains = configuration.accountCodexHomes
        // OpenCode has one global list, resolved by `OpenCodeSource`.
        case .openCode: return SessionDirectoryResolution(directories: [], additionalByAccount: [:], wildcards: [])
        }
        // The home folder and `/` are never a Claude Code directory, and
        // never an additional Codex home; a Codex main home is not filtered
        // (spec 034 FR-008, spec 035 FR-006).
        let homeOrRoot: Set<String> = [fileSystem.canonicalPath(paths.home.path), "/"]
        var seen = Set<String>()
        var directories: [SessionDirectory] = []
        func add(_ path: String, canonical: String, origin: SessionDirectory.Origin) {
            if seen.insert(canonical).inserted {
                directories.append(SessionDirectory(path: path, canonical: canonical, origin: origin))
            }
        }

        for main in mains {
            let expanded = paths.expand(main)
            let canonical = fileSystem.canonicalPath(expanded)
            if harness == .claudeCode && homeOrRoot.contains(canonical) { continue }
            add(expanded, canonical: canonical, origin: .main)
        }

        let expander = WildcardExpander(paths: paths, fileSystem: fileSystem)
        var expansions: [String: WildcardExpansion] = [:]
        var wildcards: [WildcardReport] = []
        var additionalByAccount: [String: Set<String>] = [:]
        for item in configuration.additionalSessionEntries(for: harness) {
            var found: [(path: String, canonical: String, origin: SessionDirectory.Origin)] = []
            if item.isWildcard {
                let expansion: WildcardExpansion
                if let known = expansions[item.entry] {
                    expansion = known
                } else {
                    expansion = expander.expand(item.entry)
                    expansions[item.entry] = expansion
                    wildcards.append(WildcardReport(expansion))
                }
                // The expander already dropped the home folder and `/`.
                found = zip(expansion.paths, expansion.canonicalPaths).map { ($0, $1, .wildcard(entry: item.entry)) }
            } else {
                let expanded = paths.expand(item.entry)
                found = [(expanded, fileSystem.canonicalPath(expanded), .literal(entry: item.entry))]
            }
            for (path, canonical, origin) in found {
                guard !homeOrRoot.contains(canonical) else { continue }
                if item.joinsTieBreak { additionalByAccount[item.accountId, default: []].insert(canonical) }
                add(path, canonical: canonical, origin: origin)
            }
        }
        return SessionDirectoryResolution(directories: directories, additionalByAccount: additionalByAccount, wildcards: wildcards)
    }
}
