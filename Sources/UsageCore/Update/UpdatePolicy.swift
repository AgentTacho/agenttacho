import Foundation

/// Facts about the running AgentTacho that decide the update action (spec 013
/// FR-012, research R5, R6). Gathered app-side, judged by `UpdatePolicy`.
public struct InstallContext: Equatable, Sendable {
    /// `CFBundleShortVersionString` as `X.Y.Z`; nil disables checks.
    public var runningVersion: ReleaseVersion?
    /// The bundle carries `AgentTachoReleaseTag`.
    public var isReleaseBuild: Bool
    /// Compiled with `AGENTTACHO_UPDATE_TEST` (FR-025, research R11).
    public var isUpdateTestBuild: Bool
    /// The bundle's signing stamp.
    public var signing: AppVersionInfo.Signing?
    /// Team identifier from the running code signature.
    public var teamIdentifier: String?
    public var bundleIdentifier: String?
    public var bundlePath: String
    public var isHomebrewManaged: Bool
    public var isTranslocated: Bool
    public var isOnReadOnlyVolume: Bool
    public var isBundleWritable: Bool
    public var isParentWritable: Bool

    public init(runningVersion: ReleaseVersion?, isReleaseBuild: Bool, isUpdateTestBuild: Bool,
                signing: AppVersionInfo.Signing?, teamIdentifier: String?,
                bundleIdentifier: String?, bundlePath: String,
                isHomebrewManaged: Bool, isTranslocated: Bool, isOnReadOnlyVolume: Bool,
                isBundleWritable: Bool, isParentWritable: Bool) {
        self.runningVersion = runningVersion
        self.isReleaseBuild = isReleaseBuild
        self.isUpdateTestBuild = isUpdateTestBuild
        self.signing = signing
        self.teamIdentifier = teamIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.bundlePath = bundlePath
        self.isHomebrewManaged = isHomebrewManaged
        self.isTranslocated = isTranslocated
        self.isOnReadOnlyVolume = isOnReadOnlyVolume
        self.isBundleWritable = isBundleWritable
        self.isParentWritable = isParentWritable
    }

    /// A short summary for the diagnostic log (spec 013 FR-021).
    public var logSummary: String {
        let build = isUpdateTestBuild ? "update-test" : (isReleaseBuild ? "release" : "development")
        return [
            "build=\(build)",
            "version=\(runningVersion?.description ?? "none")",
            "signing=\(signing?.text ?? "none")",
            "team=\((teamIdentifier ?? "").isEmpty ? "absent" : "present")",
            "homebrew=\(isHomebrewManaged)",
            "translocated=\(isTranslocated)",
            "readOnly=\(isOnReadOnlyVolume)",
            "bundleWritable=\(isBundleWritable)",
            "parentWritable=\(isParentWritable)",
        ].joined(separator: " ")
    }
}

/// The one action the update line offers (spec 013 FR-012).
public enum UpdateAction: Equatable, Sendable {
    /// One-click install of the disk image.
    case install(DownloadTarget)
    /// Copy `brew upgrade --cask agenttacho` (FR-013).
    case homebrew
    /// Open the release page, with the reason why Install is not offered.
    case download(UpdateBlockReason)
    /// "Try again": an install failed for a reason that may pass on a
    /// second try; the reason is shown and the release notes link stays
    /// (spec 013 US2 scenario 4, FR-019). Only set by a failed install.
    case retry(DownloadTarget, UpdateBlockReason)

    /// The disk image an Install or Try again click downloads.
    public var installTarget: DownloadTarget? {
        switch self {
        case .install(let target), .retry(let target, _): return target
        case .homebrew, .download: return nil
        }
    }

    /// The reason shown after the middle dot, for Download and Try again.
    public var reason: UpdateBlockReason? {
        switch self {
        case .download(let reason), .retry(_, let reason): return reason
        case .install, .homebrew: return nil
        }
    }
}

/// Decides whether AgentTacho may check and which action it offers (spec 013
/// FR-008, FR-012, FR-019, FR-025).
public enum UpdatePolicy {
    /// Release builds and update-test builds with a parseable version check;
    /// development builds never do (FR-008).
    public static func checksAllowed(context: InstallContext) -> Bool {
        context.runningVersion != nil && (context.isReleaseBuild || context.isUpdateTestBuild)
    }

    /// Homebrew wins over every location fact; otherwise the first failing
    /// condition becomes the Download reason (FR-012, FR-019).
    public static func action(context: InstallContext, release: AvailableRelease) -> UpdateAction {
        if context.isHomebrewManaged { return .homebrew }
        if context.isTranslocated { return .download(.translocated) }
        if context.isOnReadOnlyVolume { return .download(.runsFromDiskImage) }
        if !context.isBundleWritable || !context.isParentWritable { return .download(.notWritable) }
        if !runningBuildCanVerify(context) { return .download(.runningNotNotarized) }
        guard let target = release.download else { return .download(release.infoProblem ?? .releaseInfoIncomplete) }
        return .install(target)
    }

    /// A release build needs the Developer ID notarized stamp; an
    /// update-test build only Developer ID signing (research R11). Both need
    /// the team identifier of the real signature, the anchor of the
    /// verification (research R5).
    private static func runningBuildCanVerify(_ context: InstallContext) -> Bool {
        guard let team = context.teamIdentifier, !team.isEmpty else { return false }
        if context.isReleaseBuild, context.signing == .developerID(notarized: true) { return true }
        if context.isUpdateTestBuild, case .developerID = context.signing { return true }
        return false
    }
}
