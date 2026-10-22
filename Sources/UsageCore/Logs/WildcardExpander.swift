import Foundation

/// What listing a folder found (spec 035 research R3).
public enum DirectoryContents: Equatable, Sendable {
    /// The names in the folder, files and folders alike.
    case names([String])
    /// The folder does not exist (or is no folder): no match, no error.
    case missing
    /// The folder exists but cannot be listed, with the reason.
    case unreadable(String)
}

/// The file system calls of wildcard expansion, injectable so the matching
/// rules are tested without building trees on disk (spec 035 research R3).
/// Nothing but folder listings and folder checks; no file is opened.
public protocol DirectoryFileSystem: Sendable {
    func contents(ofDirectory path: String) -> DirectoryContents
    /// True for a folder or a symlink to one; false for a file or nothing.
    func isDirectory(_ path: String) -> Bool
    /// Symlinks resolved, `..` removed, no trailing slash.
    func canonicalPath(_ path: String) -> String
}

/// `DirectoryFileSystem` over the real file system.
public struct LocalDirectoryFileSystem: DirectoryFileSystem {
    public init() {}

    public func contents(ofDirectory path: String) -> DirectoryContents {
        guard isDirectory(path) else { return .missing }
        do {
            return .names(try FileManager.default.contentsOfDirectory(atPath: path))
        } catch {
            // A folder deleted between the check and the listing (a sandbox
            // folder going away) is missing, not an error (spec 035 User
            // Story 2 scenario 3).
            let ns = error as NSError
            if ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoSuchFileError { return .missing }
            if let posix = ns.userInfo[NSUnderlyingErrorKey] as? NSError, posix.domain == NSPOSIXErrorDomain,
               posix.code == Int(ENOENT) || posix.code == Int(ENOTDIR) {
                return .missing
            }
            return .unreadable(error.localizedDescription)
        }
    }

    public func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// The same rule as `Attributor.canonical`, which the scanner and the
    /// tie-breaker use; another `DirectoryFileSystem` must agree with it.
    public func canonicalPath(_ path: String) -> String {
        Attributor.canonical(path)
    }
}

/// The `*` rule of the session directory lists (spec 035 FR-004): `*`
/// matches any run of characters within one folder name, including none;
/// a component that starts with `*` never matches a name that starts with
/// `.`. No other character is special.
public enum WildcardPattern {
    public static func matches(name: String, component: String) -> Bool {
        guard component.contains("*") else { return name == component }
        if component.hasPrefix("*") && name.hasPrefix(".") { return false }
        let pieces = component.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
        guard let first = pieces.first, let last = pieces.last, name.hasPrefix(first) else { return false }
        var rest = Substring(name).dropFirst(first.count)
        // Middle pieces left to right, each at its first place.
        for piece in pieces.dropFirst().dropLast() where !piece.isEmpty {
            guard let range = rest.range(of: piece) else { return false }
            rest = rest[range.upperBound...]
        }
        return rest.count >= last.count && rest.hasSuffix(last)
    }
}

/// A folder on the way of an expansion that was not listed, with the reason
/// for the log (spec 035 FR-008).
public struct WildcardListingError: Equatable, Sendable {
    public let path: String
    public let reason: String

    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }

    /// The reason of a bare `*` whose folder resolves to the home folder or
    /// `/` (spec 035 FR-006).
    public static let bareStarReason = SessionDirectoryRefusal.bareStarAtTop.reason
}

/// The folders one entry with `*` names at the time of a refresh (spec 035
/// FR-004, FR-005).
public struct WildcardExpansion: Equatable, Sendable {
    /// The entry as given.
    public let entry: String
    /// Matched folders, expanded spelling, in path order, at most `cap`.
    public let paths: [String]
    /// The canonical path of each of `paths`, in the same order.
    public let canonicalPaths: [String]
    /// All matches before the cap; the home folder and `/` are not counted.
    public let matched: Int
    /// Folders on the way that exist but were not listed.
    public let listingErrors: [WildcardListingError]
    /// True when one level held more than `WildcardExpander.levelBudget`
    /// candidates and only the first ones in path order were looked at.
    public let isTruncated: Bool

    /// True when more folders matched than are read.
    public var isCapped: Bool { matched > paths.count }

    public init(entry: String, paths: [String], canonicalPaths: [String]? = nil, matched: Int,
                listingErrors: [WildcardListingError], isTruncated: Bool = false) {
        self.entry = entry
        self.paths = paths
        self.canonicalPaths = canonicalPaths ?? paths
        self.matched = matched
        self.listingErrors = listingErrors
        self.isTruncated = isTruncated
    }
}

/// Expands an entry of an additional session directory list or of the
/// OpenCode list (spec 035 FR-004 to FR-006, contracts/directory-resolution.md
/// "Wildcard expansion"). The only code that lists folders for wildcards;
/// it runs anew on every refresh, so folders that appear or disappear count
/// or stop counting without a Settings change.
public struct WildcardExpander: Sendable {
    /// The most matched folders one entry reads (spec 035 FR-005).
    public static let cap = 100
    /// The most candidate folders one level of an expansion keeps, so a
    /// broad or mistyped entry (`~/Library/*/*/sessions`) costs a bounded
    /// number of listings on every refresh (spec 035 assumption "the cap
    /// bounds a mistyped entry").
    public static let levelBudget = 10 * cap

    private let paths: Paths
    private let fileSystem: any DirectoryFileSystem

    public init(paths: Paths, fileSystem: any DirectoryFileSystem) {
        self.paths = paths
        self.fileSystem = fileSystem
    }

    /// `~` expanded and the entry standardized, the leading components
    /// without `*` are the base; each later component with `*` keeps the
    /// listed names it matches that are folders (symlinks followed), a
    /// component without `*` is appended. A bare `*` never lists a folder
    /// whose canonical path is the home folder or `/`, whatever its
    /// spelling (case, firmlink, symlink). Each level keeps at most
    /// `levelBudget` candidates in path order. Only folders stay; a match
    /// whose canonical path is the home folder or `/` is dropped; the rest
    /// is sorted by path and capped at `cap`.
    public func expand(_ entry: String) -> WildcardExpansion {
        let normalized = SessionDirectoryEntry.normalized(entry.trimmingCharacters(in: .whitespacesAndNewlines), paths: paths)
        guard normalized.hasPrefix("/") else {
            return WildcardExpansion(entry: entry, paths: [], matched: 0, listingErrors: [])
        }
        let excluded: Set<String> = [fileSystem.canonicalPath(paths.home.path), "/"]
        let components = SessionDirectoryEntry.components(of: normalized)
        let firstWildcard = components.firstIndex { $0.contains("*") } ?? components.count
        var candidates = ["/" + components[..<firstWildcard].joined(separator: "/")]
        var listingErrors: [WildcardListingError] = []
        var isTruncated = false
        // Folders are checked while matching a `*` component; only a
        // literal last component still needs the check below.
        var lastChecked = false
        for component in components[firstWildcard...] {
            guard component.contains("*") else {
                candidates = candidates.map { Self.join($0, component) }
                lastChecked = false
                continue
            }
            var next: [String] = []
            for parent in candidates {
                // `~/*` under another spelling of the home folder (spec 035
                // FR-006).
                if component == "*" && excluded.contains(fileSystem.canonicalPath(parent)) {
                    listingErrors.append(WildcardListingError(path: parent, reason: WildcardListingError.bareStarReason))
                    continue
                }
                switch fileSystem.contents(ofDirectory: parent) {
                case .names(let names):
                    for name in names.sorted() where WildcardPattern.matches(name: name, component: component) {
                        let path = Self.join(parent, name)
                        if fileSystem.isDirectory(path) { next.append(path) }
                    }
                case .missing:
                    continue
                case .unreadable(let reason):
                    listingErrors.append(WildcardListingError(path: parent, reason: reason))
                }
            }
            next.sort()
            if next.count > Self.levelBudget {
                next = Array(next.prefix(Self.levelBudget))
                isTruncated = true
            }
            candidates = next
            lastChecked = true
        }
        var matches: [(path: String, canonical: String)] = []
        for path in candidates.sorted() where lastChecked || fileSystem.isDirectory(path) {
            let canonical = fileSystem.canonicalPath(path)
            if !excluded.contains(canonical) { matches.append((path, canonical)) }
        }
        let kept = matches.prefix(Self.cap)
        return WildcardExpansion(entry: entry, paths: kept.map(\.path), canonicalPaths: kept.map(\.canonical),
                                 matched: matches.count, listingErrors: listingErrors, isTruncated: isTruncated)
    }

    private static func join(_ parent: String, _ name: String) -> String {
        parent == "/" ? "/" + name : parent + "/" + name
    }
}
