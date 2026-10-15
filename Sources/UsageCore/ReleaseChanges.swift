import Foundation

/// One feat, fix or perf commit of a release, as listed in the bundled
/// `changes.json` (written by `release_changes` in scripts/release/lib.sh).
public struct ReleaseChange: Equatable, Sendable, Decodable {
    /// The commit types the About tab lists, in the order of their groups.
    public enum Kind: String, CaseIterable, Sendable, Decodable {
        case feature = "feat"
        case fix
        case performance = "perf"

        /// Group heading, the same as in the release notes.
        public var title: String {
            switch self {
            case .feature: "Features"
            case .fix: "Fixes"
            case .performance: "Performance"
            }
        }
    }

    public let kind: Kind
    /// The conventional commit scope ("prices" in "fix(prices): ..."), if any.
    public let scope: String?
    public let subject: String
    /// Abbreviated commit hash.
    public let hash: String

    public init(kind: Kind, scope: String?, subject: String, hash: String) {
        self.kind = kind
        self.scope = scope
        self.subject = subject
        self.hash = hash
    }

    private enum CodingKeys: String, CodingKey {
        case kind = "type"
        case scope, subject, hash
    }

    /// The subject with its first letter capitalized, for a list entry.
    public var sentence: String {
        guard let first = subject.first else { return subject }
        return first.uppercased() + subject.dropFirst()
    }
}

/// The changes of the running build, for "What's new" on the About tab.
///
/// Decoding is tolerant: a missing or unreadable file gives an empty list, and
/// entries of other types or with missing fields are skipped. The entries are
/// ordered by group (features, then fixes, then performance), each group
/// keeping the file's order (newest first).
public struct ReleaseChanges: Equatable, Sendable {
    public struct Group: Equatable, Sendable {
        public let kind: ReleaseChange.Kind
        public let entries: [ReleaseChange]

        public var title: String { kind.title }
    }

    public let entries: [ReleaseChange]

    public init(entries: [ReleaseChange]) {
        self.entries = ReleaseChange.Kind.allCases.flatMap { kind in
            entries.filter { $0.kind == kind }
        }
    }

    /// Decodes the contents of `changes.json`; `nil` (no file) gives no changes.
    public init(data: Data?) {
        guard let data,
              let lossy = try? JSONDecoder().decode([Lossy].self, from: data)
        else {
            self.init(entries: [])
            return
        }
        self.init(entries: lossy.compactMap(\.change))
    }

    public var isEmpty: Bool { entries.isEmpty }
    public var count: Int { entries.count }

    /// The first `limit` entries, grouped; groups without entries are left out.
    public func groups(limit: Int) -> [Group] {
        let shown = entries.prefix(max(limit, 0))
        return ReleaseChange.Kind.allCases.compactMap { kind in
            let members = shown.filter { $0.kind == kind }
            return members.isEmpty ? nil : Group(kind: kind, entries: Array(members))
        }
    }

    /// An array element that decodes to `nil` instead of failing the array.
    private struct Lossy: Decodable {
        let change: ReleaseChange?

        init(from decoder: Decoder) throws {
            change = try? ReleaseChange(from: decoder)
        }
    }
}
