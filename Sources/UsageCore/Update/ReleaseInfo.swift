import Foundation

/// One asset of a GitHub release, as read from the API (spec 013 FR-004,
/// contracts/update-requests.md). Only name, size and download URL are read.
public struct GitHubAsset: Decodable, Equatable, Sendable {
    public var name: String
    public var size: Int?
    public var downloadURL: URL?

    public init(name: String, size: Int?, downloadURL: URL?) {
        self.name = name
        self.size = size
        self.downloadURL = downloadURL
    }

    private enum CodingKeys: String, CodingKey {
        case name, size
        case downloadURL = "browser_download_url"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        size = (try? c.decodeIfPresent(Int.self, forKey: .size)) ?? nil
        downloadURL = ((try? c.decodeIfPresent(String.self, forKey: .downloadURL)) ?? nil).flatMap(URL.init(string:))
    }
}

/// The latest published release from `GET /repos/<owner>/<repo>/releases/latest`
/// (spec 013 FR-004, research R1). `tag_name` and an https `html_url` are
/// required; malformed assets are skipped.
public struct GitHubRelease: Decodable, Equatable, Sendable {
    public static let releaseInfoAssetName = "release-info.json"

    public var tag: String
    public var pageURL: URL
    public var draft: Bool
    public var prerelease: Bool
    public var assets: [GitHubAsset]

    public init(tag: String, pageURL: URL, draft: Bool = false, prerelease: Bool = false, assets: [GitHubAsset]) {
        self.tag = tag
        self.pageURL = pageURL
        self.draft = draft
        self.prerelease = prerelease
        self.assets = assets
    }

    private enum CodingKeys: String, CodingKey {
        case tag = "tag_name"
        case pageURL = "html_url"
        case draft, prerelease, assets
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tag = try c.decode(String.self, forKey: .tag)
        let page = try c.decode(String.self, forKey: .pageURL)
        guard let url = URL(string: page), url.scheme?.lowercased() == "https", url.host != nil else {
            throw DecodingError.dataCorruptedError(forKey: .pageURL, in: c, debugDescription: "html_url is not an https URL")
        }
        pageURL = url
        // A missing flag counts as set, so an unexpected shape is ignored
        // rather than offered.
        draft = (try? c.decodeIfPresent(Bool.self, forKey: .draft)) ?? true
        prerelease = (try? c.decodeIfPresent(Bool.self, forKey: .prerelease)) ?? true
        assets = ((try? c.decodeIfPresent([LenientAsset].self, forKey: .assets)) ?? nil)?.compactMap(\.asset) ?? []
    }

    /// The asset named `release-info.json`, if any.
    public var releaseInfoAsset: GitHubAsset? {
        asset(named: Self.releaseInfoAssetName)
    }

    public func asset(named name: String) -> GitHubAsset? {
        assets.first { $0.name == name }
    }

    private struct LenientAsset: Decodable {
        let asset: GitHubAsset?
        init(from decoder: Decoder) throws {
            asset = try? GitHubAsset(from: decoder)
        }
    }
}

/// `release-info.json` of a release (spec 005 contracts/release-info.md).
/// Decoded leniently per field, so a valid version survives other bad
/// fields and the release can still be offered as "Download" (spec 013 FR-004).
public struct ReleaseInfo: Decodable, Equatable, Sendable {
    /// Larger bodies are not read (contracts/update-requests.md).
    public static let maximumBytes = 65_536

    public var version: String?
    public var dmg: String?
    public var sha256: String?
    public var tier: String?
    public var notarized: Bool?

    public init(version: String?, dmg: String?, sha256: String?, tier: String?, notarized: Bool?) {
        self.version = version
        self.dmg = dmg
        self.sha256 = sha256
        self.tier = tier
        self.notarized = notarized
    }

    private enum CodingKeys: String, CodingKey {
        case version, dmg, sha256, tier, notarized
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decodeIfPresent(String.self, forKey: .version)) ?? nil
        dmg = (try? c.decodeIfPresent(String.self, forKey: .dmg)) ?? nil
        sha256 = (try? c.decodeIfPresent(String.self, forKey: .sha256)) ?? nil
        tier = (try? c.decodeIfPresent(String.self, forKey: .tier)) ?? nil
        notarized = (try? c.decodeIfPresent(Bool.self, forKey: .notarized)) ?? nil
    }

    /// The decoded file, or nil when it is not a JSON object.
    public static func decode(_ data: Data) -> ReleaseInfo? {
        try? JSONDecoder().decode(ReleaseInfo.self, from: data)
    }
}
