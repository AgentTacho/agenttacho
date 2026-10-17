import Foundation
import Security
import UsageCore

/// Gathers the facts about the running AgentTacho that `UpdatePolicy` judges
/// (spec 013 FR-012, FR-025; research R5, R6, R11). Reads only: the bundle's
/// Info.plist, the running code signature, the file system's view of the
/// bundle location, and Homebrew's record of the cask.
enum InstallEnvironment {
    static func current(bundle: Bundle = .main) -> InstallContext {
        let info = bundle.infoDictionary ?? [:]
        let stamps = AppVersionInfo(infoDictionary: info)
        // The X.Y.Z of CFBundleShortVersionString, not the display version
        // (which is X.Y.Z-dev for local builds).
        let shortVersion = info["CFBundleShortVersionString"] as? String
        let bundleURL = bundle.bundleURL.standardizedFileURL
        let path = bundleURL.path
        let parent = bundleURL.deletingLastPathComponent().path
        let fileManager = FileManager.default
        return InstallContext(
            runningVersion: shortVersion.flatMap { ReleaseVersion($0) },
            isReleaseBuild: stamps.releaseTag != nil,
            isUpdateTestBuild: isUpdateTestBuild,
            signing: stamps.signing,
            teamIdentifier: teamIdentifier(),
            bundleIdentifier: bundle.bundleIdentifier,
            bundlePath: path,
            // Homebrew's record of the cask, read only (FR-012, research R7).
            isHomebrewManaged: HomebrewDetector.isManagedLive(runningAppPath: bundleURL.resolvingSymlinksInPath().path),
            isTranslocated: InstallLocation.isTranslocated(path: path),
            isOnReadOnlyVolume: isOnReadOnlyOrDiskImageVolume(bundleURL),
            isBundleWritable: fileManager.isWritableFile(atPath: path),
            isParentWritable: fileManager.isWritableFile(atPath: parent))
    }

    /// Compiled with `-DAGENTTACHO_UPDATE_TEST` by `make app-update-test`
    /// only (FR-025).
    static var isUpdateTestBuild: Bool {
        #if AGENTTACHO_UPDATE_TEST
        return true
        #else
        return false
        #endif
    }

    /// `AgentTacho/agenttacho`. Only an update-test build reads another
    /// `owner/repo` from its Info.plist key `AgentTachoUpdateSource`, parsed
    /// by `UpdateSource`; a build without the flag never reads any setting
    /// that changes the source (FR-025).
    static var releaseSource: UpdateSource {
        #if AGENTTACHO_UPDATE_TEST
        return UpdateSource.resolve(Bundle.main.infoDictionary?["AgentTachoUpdateSource"] as? String)
        #else
        return .official
        #endif
    }

    /// The team identifier of the running code signature (research R5);
    /// `kSecCodeInfoTeamIdentifier` is only returned with
    /// `kSecCSSigningInformation`.
    static func teamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any] else { return nil }
        let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String
        return (team?.isEmpty ?? true) ? nil : team
    }

    /// The volume facts for `InstallLocation.isOnDiskImage` (research R6).
    private static func isOnReadOnlyOrDiskImageVolume(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey, .volumeIsRootFileSystemKey])
        return InstallLocation.isOnDiskImage(path: url.path, volumeIsReadOnly: values?.volumeIsReadOnly,
                                             volumeIsRootFileSystem: values?.volumeIsRootFileSystem)
    }
}
