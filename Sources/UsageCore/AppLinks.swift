import Foundation

/// The web pages the About tab links to: the GitHub repository, its issues and
/// releases, single commits, the security statement, the sponsor page and
/// the author's homepage; and the providers' usage pages the dropdown links
/// to (spec 033 FR-010a).
public enum AppLinks {
    public static let repository = URL(string: "https://github.com/AgentTacho/agenttacho")!
    public static let issues = repository.appendingPathComponent("issues")
    public static let newIssue = issues.appendingPathComponent("new")
    public static let releases = repository.appendingPathComponent("releases")
    public static let sponsor = URL(string: "https://github.com/sponsors/rhuss")!
    public static let author = URL(string: "https://ro14nd.de")!
    /// The README's security statement: which credentials AgentTacho reads,
    /// what for, and where they go.
    public static let securityStatement = URL(string: "https://github.com/AgentTacho/agenttacho#security-and-privacy")!

    /// Claude's usage page, where a free limit reset is redeemed ("Reset for
    /// free"); a gift glyph of a Claude account opens it (spec 033 FR-010a,
    /// research R6).
    public static let claudeUsagePage = URL(string: "https://claude.ai/settings/usage")!
    /// The ChatGPT usage page of a Codex account (spec 033 FR-010a, research
    /// R6).
    public static let codexUsagePage = URL(string: "https://chatgpt.com/settings/usage?tab=overview")!

    /// The GitHub release of a tag such as "v0.2.3", or the latest release for
    /// a development build, which has no tag of its own.
    public static func releasePage(for tag: String?) -> URL {
        guard let tag, !tag.isEmpty else { return releases.appendingPathComponent("latest") }
        return releases.appendingPathComponent("tag").appendingPathComponent(tag)
    }

    /// The commit page for a full or abbreviated hash.
    public static func commit(_ hash: String) -> URL {
        repository.appendingPathComponent("commit").appendingPathComponent(hash)
    }
}
