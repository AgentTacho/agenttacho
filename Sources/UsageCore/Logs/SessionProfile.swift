import Foundation

/// The Claude Code configuration directory a session ran under, read from
/// the `api-request-shape` lines of its session file (spec 037 FR-001,
/// FR-002, FR-004, research R1, R2). Since Claude Code 2.1.300 these lines
/// hold the request's system prompt, which names the auto-memory folder
/// `<configuration directory>/projects/<project>/memory/`. Detection looks
/// for the configured directories in the line instead of parsing the
/// prompt's wording, uses byte searches only and never decodes the line;
/// nothing of the line but the matched directory leaves it.
public enum SessionProfile {
    /// Main directories rank above additional ones (spec 035 FR-012, spec
    /// 037 FR-003).
    public enum Rank: String, Sendable {
        case main
        case additional
    }

    /// One account's claim on a directory.
    public struct Entry: Equatable, Sendable {
        public let accountId: String
        /// The directory as configured or resolved, unexpanded or expanded.
        public let path: String
        /// The canonical path when the caller already resolved it (wildcard
        /// matches); nil to resolve `path`.
        public let canonical: String?
        public let rank: Rank
        /// True for a wildcard match, which comes and goes with folders on
        /// disk rather than with a configuration edit.
        public let isWildcardMatch: Bool

        public init(accountId: String, path: String, canonical: String? = nil, rank: Rank, isWildcardMatch: Bool = false) {
            self.accountId = accountId
            self.path = path
            self.canonical = canonical
            self.rank = rank
            self.isWildcardMatch = isWildcardMatch
        }
    }

    /// The configured directories of one refresh and the byte strings that
    /// find them (spec 037 FR-001, FR-002).
    public struct Candidates: Equatable, Sendable {
        /// Each spelling of a candidate directory (without the `/projects/`
        /// that must follow it in the line) with its canonical directory,
        /// grouped by byte length, so a `/projects/` occurrence is compared
        /// with all spellings by one slice lookup per length.
        let searches: [Int: [Data: String]]
        /// Per canonical directory, its claimants and their rank, as one
        /// text (`claimKey(forDirectory:)`).
        private let claims: [String: String]
        /// One searched spelling with the canonical directory it names.
        public struct Spelling: Hashable, Sendable {
            public let spelling: String
            public let canonical: String
        }

        /// Every searched spelling: a shape line can name a directory only
        /// through one of them.
        public let spellings: Set<Spelling>
        /// The spellings of main directories and literal entries, without
        /// wildcard matches.
        public let configuredSpellings: Set<Spelling>
        /// Identifies the whole set: each canonical directory with its
        /// claimant account ids and rank, and every spelling, sorted. A
        /// directory that moves between accounts or ranks changes it (plan
        /// review finding 11), and so does a new alias of a directory.
        public let key: String

        /// The canonical directories that can be named.
        public var directories: Set<String> { Set(claims.keys) }

        public var isEmpty: Bool { claims.isEmpty }

        /// Each entry's search strings are its `~`-expanded, standardized
        /// path and its symlink-resolved path, each followed by
        /// `/projects/`; the `projects` folder itself is never resolved, so
        /// profiles that link it to one shared folder stay apart (FR-002).
        public init(entries: [Entry], paths: Paths = Paths()) {
            var searches: [Int: [Data: String]] = [:]
            var claimants: [String: Set<String>] = [:]
            var spellings = Set<Spelling>()
            var configured = Set<Spelling>()
            for entry in entries {
                let expanded = Self.standardized(paths.expand(entry.path))
                let canonical = entry.canonical.map(Self.standardized) ?? Attributor.canonical(expanded)
                claimants[canonical, default: []].insert("\(entry.rank.rawValue):\(entry.accountId)")
                for spelling in [expanded, canonical] where spelling != "/" {
                    let bytes = Data(spelling.utf8)
                    // A spelling shared by two canonical directories (not
                    // possible after resolution) would keep the first.
                    if searches[bytes.count]?[bytes] == nil {
                        searches[bytes.count, default: [:]][bytes] = canonical
                    }
                    let item = Spelling(spelling: spelling, canonical: canonical)
                    spellings.insert(item)
                    if !entry.isWildcardMatch { configured.insert(item) }
                }
            }
            self.searches = searches
            self.spellings = spellings
            self.configuredSpellings = configured
            let claims = claimants.mapValues { $0.sorted().joined(separator: ",") }
            self.claims = claims
            self.key = (claims.keys.sorted().map { "\($0)=\(claims[$0]!)" } + ["spellings:"] + spellings.map { "\($0.spelling) -> \($0.canonical)" }.sorted())
                .joined(separator: "\n")
        }

        public static let empty = Candidates(entries: [])

        /// The claimants and rank of `directory` (canonical), nil when it is
        /// no candidate. A file whose profile's claim key changed is read
        /// again (spec 037 plan "Re-read rules").
        public func claimKey(forDirectory directory: String) -> String? {
            claims[directory]
        }

        static func standardized(_ path: String) -> String {
            var p = URL(fileURLWithPath: path).standardizedFileURL.path
            while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
            return p
        }
    }

    /// What one line says about the profile.
    public enum Detection: Equatable, Sendable {
        /// Not a shape line.
        case notShape
        /// A shape line naming exactly one configured directory (canonical).
        case named(String)
        /// A shape line naming no configured directory.
        case none
        /// A shape line naming two or more configured directories; treated
        /// like `.notShape` (FR-001).
        case ambiguous
    }

    private static let shapeMarkers = [Data(#""type":"api-request-shape""#.utf8), Data(#""type": "api-request-shape""#.utf8)]
    private static let projectsSegment = Data("/projects/".utf8)

    /// Recognizes a shape line by a byte search, then, at every
    /// `/projects/` in the line, checks whether a candidate's spelling ends
    /// right before it at a path boundary (FR-001, FR-004). One pass over
    /// the line finds the occurrences, so the cost does not grow with the
    /// number of candidates times the line length.
    public static func detect(line: Data, candidates: Candidates) -> Detection {
        guard shapeMarkers.contains(where: { line.range(of: $0) != nil }) else { return .notShape }
        var found = Set<String>()
        var from = line.startIndex
        while from < line.endIndex, let range = line.range(of: projectsSegment, in: from..<line.endIndex) {
            let end = range.lowerBound
            for (length, spellings) in candidates.searches where end - line.startIndex >= length {
                let start = end - length
                if let canonical = spellings[Data(line[start..<end])], isBoundary(before: start, in: line) {
                    found.insert(canonical)
                }
            }
            from = range.lowerBound + 1
        }
        switch found.count {
        case 0: return .none
        case 1: return .named(found.first!)
        default: return .ambiguous
        }
    }

    public static func detect(line: String, candidates: Candidates) -> Detection {
        detect(line: Data(line.utf8), candidates: candidates)
    }

    /// True when no path character comes right before `index`, so
    /// `/Users/t/.claude` is not found inside
    /// `/var/sandbox/Users/t/.claude/projects/` (plan review finding 12). An
    /// escaped `\n`, `\t` or `\r` of the JSON text counts as a boundary.
    private static func isBoundary(before index: Data.Index, in line: Data) -> Bool {
        guard index > line.startIndex else { return true }
        let previous = line[index - 1]
        if !isPathByte(previous) { return true }
        // `\n`, `\t`, `\r` escapes in the JSON text.
        if [UInt8(ascii: "n"), UInt8(ascii: "t"), UInt8(ascii: "r")].contains(previous),
           index - 1 > line.startIndex, line[index - 2] == UInt8(ascii: "\\") {
            return true
        }
        return false
    }

    /// Letters, digits and the characters a path segment is made of.
    private static func isPathByte(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "0")...UInt8(ascii: "9"):
            return true
        case UInt8(ascii: "."), UInt8(ascii: "-"), UInt8(ascii: "_"), UInt8(ascii: "/"), UInt8(ascii: "~"), UInt8(ascii: "@"),
             UInt8(ascii: "+"), UInt8(ascii: "%"):
            return true
        default:
            return byte >= 0x80
        }
    }
}
