import Foundation

/// The app's version as stamped into its `Info.plist` by the release build.
///
/// The display version comes from `AgentMeterVersionDisplay` (for example
/// "0.2.0-dev" for development builds) and falls back to
/// `CFBundleShortVersionString`; the build number is `CFBundleVersion`.
/// build-app.sh also stamps the release data shown on the About tab (commit,
/// build date, release tag for release builds only), and the signing tier and
/// whether the build gets notarized, which the update policy and the
/// diagnostic log read; the About tab does not show them (spec 020 FR-002).
/// A build without these stamps (`swift run`) reads `nil`.
public struct AppVersionInfo: Equatable, Sendable {
    public static let displayVersionKey = "AgentMeterVersionDisplay"
    public static let commitKey = "AgentMeterCommit"
    public static let buildDateKey = "AgentMeterBuildDate"
    public static let releaseTagKey = "AgentMeterReleaseTag"
    public static let signingKey = "AgentMeterSigning"
    public static let notarizedKey = "AgentMeterNotarized"

    /// How the build is signed, from the tier names of the release scripts.
    public enum Signing: Equatable, Sendable {
        case developerID(notarized: Bool)
        case selfSigned
        case adHoc

        /// "Developer ID, notarized", "Developer ID", "Self-signed" or "Ad-hoc".
        public var text: String {
            switch self {
            case .developerID(notarized: true): "Developer ID, notarized"
            case .developerID(notarized: false): "Developer ID"
            case .selfSigned: "Self-signed"
            case .adHoc: "Ad-hoc"
            }
        }
    }

    /// Display version, or `nil` when the bundle carries none.
    public let version: String?
    /// Build number, or `nil` when the bundle carries none.
    public let build: String?
    /// Full commit hash the app was built from.
    public let commit: String?
    /// Build time (ISO 8601 in the plist).
    public let buildDate: Date?
    /// "vX.Y.Z" for a release build, `nil` for a development build.
    public let releaseTag: String?
    public let signing: Signing?

    public init(infoDictionary: [String: Any]) {
        version = Self.nonEmptyString(infoDictionary[Self.displayVersionKey])
            ?? Self.nonEmptyString(infoDictionary["CFBundleShortVersionString"])
        build = Self.nonEmptyString(infoDictionary["CFBundleVersion"])
        commit = Self.nonEmptyString(infoDictionary[Self.commitKey])
        buildDate = Self.nonEmptyString(infoDictionary[Self.buildDateKey])
            .flatMap { ISO8601DateFormatter().date(from: $0) }
        releaseTag = Self.nonEmptyString(infoDictionary[Self.releaseTagKey])
        let notarized = infoDictionary[Self.notarizedKey] as? Bool ?? false
        switch Self.nonEmptyString(infoDictionary[Self.signingKey]) {
        case "developer-id": signing = .developerID(notarized: notarized)
        case "self-signed": signing = .selfSigned
        case "ad-hoc": signing = .adHoc
        default: signing = nil
        }
    }

    /// "AgentMeter 0.2.0-dev (build 120)", "AgentMeter 0.2.0" without a build
    /// number, or "AgentMeter unknown" without a version.
    public var label: String {
        "AgentMeter \(versionText)"
    }

    /// "0.2.0-dev (build 120)", "0.2.0" without a build number, or "unknown"
    /// without a version.
    public var versionText: String {
        guard let version else { return "unknown" }
        guard let build else { return version }
        return "\(version) (build \(build))"
    }

    /// The first 7 characters of the commit hash, as shown on the About tab.
    public var shortCommit: String? {
        commit.map { String($0.prefix(7)) }
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }
}
