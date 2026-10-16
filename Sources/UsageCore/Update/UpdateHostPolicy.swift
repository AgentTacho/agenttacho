import Foundation

/// The hosts update requests may reach (spec 013 FR-005, FR-014, research
/// R2). Applied to every starting URL, including asset URLs taken from the
/// GitHub API response, and to every redirect.
public enum UpdateHostPolicy {
    /// An explicit list; a suffix match would admit user content hosts such
    /// as `raw.githubusercontent.com`.
    public static let allowedHosts: Set<String> = [
        "api.github.com",
        "github.com",
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com",
    ]

    /// True only for an `https` URL on the default port whose host
    /// (compared case-insensitively) is in `allowedHosts`.
    public static func allows(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), allowedHosts.contains(host) else { return false }
        if let port = url.port, port != 443 { return false }
        return true
    }
}
