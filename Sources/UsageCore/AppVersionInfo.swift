import Foundation

/// The app's version as stamped into its `Info.plist` by the release build.
///
/// The display version comes from `AgentMeterVersionDisplay` (for example
/// "0.2.0-dev" for development builds) and falls back to
/// `CFBundleShortVersionString`; the build number is `CFBundleVersion`.
public struct AppVersionInfo: Equatable, Sendable {
    public static let displayVersionKey = "AgentMeterVersionDisplay"

    /// Display version, or `nil` when the bundle carries none.
    public let version: String?
    /// Build number, or `nil` when the bundle carries none.
    public let build: String?

    public init(infoDictionary: [String: Any]) {
        version = Self.nonEmptyString(infoDictionary[Self.displayVersionKey])
            ?? Self.nonEmptyString(infoDictionary["CFBundleShortVersionString"])
        build = Self.nonEmptyString(infoDictionary["CFBundleVersion"])
    }

    /// "AgentMeter 0.2.0-dev (build 120)", "AgentMeter 0.2.0" without a build
    /// number, or "AgentMeter unknown" without a version.
    public var label: String {
        guard let version else { return "AgentMeter unknown" }
        guard let build else { return "AgentMeter \(version)" }
        return "AgentMeter \(version) (build \(build))"
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }
}
