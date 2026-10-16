import Foundation

/// The disk image a one-click install downloads (spec 013 FR-014, FR-015).
public struct DownloadTarget: Equatable, Sendable {
    /// 100 MB, about ten times the current disk image (FR-014).
    public static let maximumBytes = 104_857_600

    public let url: URL
    /// Size reported by the GitHub API, in bytes.
    public let size: Int
    /// 64 lowercase hex characters from release-info.json.
    public let sha256: String

    public init(url: URL, size: Int, sha256: String) {
        self.url = url
        self.size = size
        self.sha256 = sha256
    }
}

/// A newer release AgentMeter can tell the user about (spec 013 FR-009).
/// `download` is nil when the release information does not allow a one-click
/// install; `infoProblem` then says why (FR-004, FR-019).
public struct AvailableRelease: Equatable, Sendable {
    public let version: ReleaseVersion
    public let pageURL: URL
    public let download: DownloadTarget?
    public let infoProblem: UpdateBlockReason?

    public init(version: ReleaseVersion, pageURL: URL, download: DownloadTarget?, infoProblem: UpdateBlockReason?) {
        self.version = version
        self.pageURL = pageURL
        self.download = download
        self.infoProblem = infoProblem
    }
}

/// What a check found (spec 013 FR-004, FR-006).
public enum ReleaseCheckResult: Equatable, Sendable {
    /// Why a release is not considered at all; no update line.
    public enum IgnoreReason: Equatable, Sendable {
        case noReleaseInfo
        case releaseInfoUnreadable
        case invalidVersion
        case versionMismatch
        case draftOrPrerelease
    }

    case ignored(IgnoreReason)
    case notNewer
    case available(AvailableRelease)
}

/// Decides what the latest release means for the running version (spec 013
/// FR-004, FR-006, FR-014).
public enum ReleaseEvaluator {
    /// `info` is nil when the release has no release-info.json asset or the
    /// file could not be read or decoded.
    public static func evaluate(release: GitHubRelease, info: ReleaseInfo?, runningVersion: ReleaseVersion) -> ReleaseCheckResult {
        if release.draft || release.prerelease { return .ignored(.draftOrPrerelease) }
        guard let info else {
            return .ignored(release.releaseInfoAsset == nil ? .noReleaseInfo : .releaseInfoUnreadable)
        }
        guard let infoVersion = info.version, let version = ReleaseVersion(infoVersion) else { return .ignored(.invalidVersion) }
        // The version must equal the tag without "v" as text (FR-004): a tag
        // parses only when written like its version, so both texts match.
        guard let tagVersion = ReleaseVersion(tag: release.tag), tagVersion.description == infoVersion else {
            return .ignored(.versionMismatch)
        }
        guard version > runningVersion else { return .notNewer }

        let download: DownloadTarget?
        let problem: UpdateBlockReason?
        switch downloadTarget(release: release, info: info, version: version) {
        case .success(let target): (download, problem) = (target, nil)
        case .failure(let reason): (download, problem) = (nil, reason)
        }
        return .available(AvailableRelease(version: version, pageURL: release.pageURL, download: download, infoProblem: problem))
    }

    private static func downloadTarget(release: GitHubRelease, info: ReleaseInfo, version: ReleaseVersion) -> Result<DownloadTarget, UpdateBlockReason> {
        let expectedName = "AgentMeter-\(version).dmg"
        guard info.dmg == expectedName,
              let asset = release.asset(named: expectedName),
              let url = asset.downloadURL, UpdateHostPolicy.allows(url),
              let size = asset.size, size >= 0,
              let sha = info.sha256.flatMap(normalizedSHA256),
              let tier = info.tier, let notarized = info.notarized else {
            return .failure(.releaseInfoIncomplete)
        }
        guard tier == "developer-id", notarized else { return .failure(.releaseNotNotarized) }
        guard size <= DownloadTarget.maximumBytes else { return .failure(.downloadTooLarge) }
        return .success(DownloadTarget(url: url, size: size, sha256: sha))
    }

    /// 64 hex characters, lowercased; nil otherwise.
    static func normalizedSHA256(_ text: String) -> String? {
        let lower = text.lowercased()
        guard lower.count == 64, lower.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) || ("a"..."f").contains($0) }) else { return nil }
        return lower
    }
}
