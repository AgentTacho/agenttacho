import Foundation

/// The GitHub repository whose releases AgentMeter checks (spec 013 FR-004,
/// FR-025). Always `rhuss/agentmeter`, except in an update-test build, which
/// reads `owner/repo` from its Info.plist (research R11).
public struct UpdateSource: Equatable, Sendable {
    public let owner: String
    public let repo: String

    public init(owner: String, repo: String) {
        self.owner = owner
        self.repo = repo
    }

    /// `rhuss/agentmeter`.
    public static let official = UpdateSource(owner: "rhuss", repo: "agentmeter")

    /// `owner/repo` as `make app-update-test` accepts it
    /// (contracts/make-targets.md, `^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$`); nil
    /// for anything else (FR-025).
    public static func parse(_ value: String) -> UpdateSource? {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { return nil }
        let ownerOK = !parts[0].isEmpty && parts[0].unicodeScalars.allSatisfy { isASCIIAlphanumeric($0) || $0 == "-" }
        let repoOK = !parts[1].isEmpty && parts[1].unicodeScalars.allSatisfy { isASCIIAlphanumeric($0) || "._-".unicodeScalars.contains($0) }
        return ownerOK && repoOK ? UpdateSource(owner: parts[0], repo: parts[1]) : nil
    }

    /// The source an update-test build uses: the stamped value when it
    /// parses, `official` otherwise (FR-025).
    public static func resolve(_ stamped: String?) -> UpdateSource {
        stamped.flatMap(parse) ?? official
    }

    private static func isASCIIAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar)
    }
}
