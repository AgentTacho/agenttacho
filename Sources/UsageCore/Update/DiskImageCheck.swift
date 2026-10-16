import Foundation

/// One top-level entry of the mounted disk image, as read app-side. For an
/// `.app` folder, its Info.plist's bundle identifier and short version
/// (spec 013 FR-016).
public struct DiskImageEntry: Equatable, Sendable {
    public let name: String
    public let isDirectory: Bool
    public let bundleIdentifier: String?
    public let shortVersion: String?

    public init(name: String, isDirectory: Bool, bundleIdentifier: String? = nil, shortVersion: String? = nil) {
        self.name = name
        self.isDirectory = isDirectory
        self.bundleIdentifier = bundleIdentifier
        self.shortVersion = shortVersion
    }
}

/// The contents rule of the verification (spec 013 FR-016, research R4 step
/// 4): exactly one top-level `*.app`, a folder, with the running app's bundle
/// identifier and the release's version. Everything else (the Applications
/// link, the background folder, Finder files) is ignored.
public enum DiskImageCheck {
    /// The app's name, or `.unexpectedContents` naming the problem.
    public static func check(entries: [DiskImageEntry], expectedBundleID: String,
                             expectedVersion: ReleaseVersion) -> Result<String, UpdateBlockReason> {
        let apps = entries.filter { $0.name.lowercased().hasSuffix(".app") }
        guard !apps.isEmpty else { return .failure(.unexpectedContents("no app in the disk image")) }
        guard apps.count == 1, let app = apps.first else {
            return .failure(.unexpectedContents("\(apps.count) apps in the disk image"))
        }
        // The name reaches tool output that is parsed line by line: no
        // control, format or line breaking characters (U+2028, U+0085).
        guard !app.name.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0) || Character($0).isNewline
        }) else {
            return .failure(.unexpectedContents("the app name contains control characters"))
        }
        guard app.isDirectory else { return .failure(.unexpectedContents("\(app.name) is not an app bundle")) }
        guard let identifier = app.bundleIdentifier, !identifier.isEmpty else {
            return .failure(.unexpectedContents("\(app.name) has no bundle identifier"))
        }
        guard identifier == expectedBundleID else {
            return .failure(.unexpectedContents("bundle identifier \(identifier) instead of \(expectedBundleID)"))
        }
        guard let version = app.shortVersion, !version.isEmpty else {
            return .failure(.unexpectedContents("\(app.name) has no version"))
        }
        guard version == expectedVersion.description else {
            return .failure(.unexpectedContents("version \(version) instead of \(expectedVersion)"))
        }
        return .success(app.name)
    }
}
