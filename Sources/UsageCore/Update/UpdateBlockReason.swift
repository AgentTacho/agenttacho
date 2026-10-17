import Foundation

/// Why one-click install is not offered or did not complete (spec 013
/// FR-019). Each case has a short user text for the update line and Settings.
/// Used by `ReleaseEvaluator`, `UpdatePolicy`, `DiskImageCheck` and
/// `UpdateVerification`.
public enum UpdateBlockReason: Error, Equatable, Sendable {
    /// The app runs from a mounted disk image or another read-only volume.
    case runsFromDiskImage
    /// macOS runs the app from a translocated (randomized, read-only) path.
    case translocated
    /// The app bundle or its folder is not writable by the user.
    case notWritable
    /// The running build is not Developer ID signed and notarized, or has no
    /// team identifier, so it cannot prove a new build is from the same team.
    case runningNotNotarized
    /// The release information does not say Developer ID and notarized.
    case releaseNotNotarized
    /// The release information is incomplete or inconsistent (FR-004).
    case releaseInfoIncomplete
    case downloadFailed(String)
    /// The disk image is larger than 100 MB (FR-014).
    case downloadTooLarge
    /// A request or redirect left the GitHub host allowlist (FR-005).
    case unexpectedHost
    /// The download does not match the published SHA-256 (FR-015).
    case checksumMismatch
    /// Gatekeeper does not report the disk image as notarized Developer ID.
    case diskImageNotNotarized
    /// The disk image does not contain exactly one app with the expected
    /// bundle identifier and version (FR-016).
    case unexpectedContents(String)
    /// The app's signature is invalid or from a different team (FR-016).
    case signatureMismatch
    /// Gatekeeper does not report the app as notarized (FR-016).
    case appNotNotarized
    /// Gatekeeper could not give an answer (offline, or assessments off).
    case gatekeeperUnavailable
    /// A verification step could not run at all (a tool such as `spctl`,
    /// `hdiutil` or `ditto` could not be launched, or the staged copy could
    /// not be made); nothing was replaced (FR-015, FR-016).
    case verificationFailed(String)
    /// macOS refused to let AgentTacho replace its own bundle (FR-017).
    case replacementDenied
    /// Replacing the bundle failed and was rolled back (FR-017).
    case replacementFailed(String)
    /// Replacing the bundle failed and the previous app could not be put
    /// back; it is in the Trash, at the path when known (FR-017).
    case previousVersionInTrash(String?)

    /// Short user text (spec 013 FR-019, contracts/update-ui.md).
    public var text: String {
        switch self {
        case .runsFromDiskImage, .translocated:
            return "Move AgentTacho to Applications to install updates"
        case .notWritable:
            return "AgentTacho cannot replace itself in this folder"
        case .runningNotNotarized:
            return "This build cannot verify updates"
        case .releaseNotNotarized:
            return "This release is not notarized with Developer ID"
        case .releaseInfoIncomplete:
            return "Release information incomplete"
        case .downloadFailed(let detail):
            return detail.isEmpty ? "The download failed" : "The download failed: \(detail)"
        case .downloadTooLarge:
            return "The download is larger than 100 MB"
        case .unexpectedHost:
            return "The download was redirected to an unexpected host"
        case .checksumMismatch:
            return "The download could not be verified (checksum mismatch)"
        case .diskImageNotNotarized:
            return "The downloaded disk image is not notarized"
        case .unexpectedContents(let detail):
            return "The disk image has unexpected contents: \(detail)"
        case .signatureMismatch:
            return "The new app is not signed by the same developer"
        case .appNotNotarized:
            return "The new app is not notarized"
        case .gatekeeperUnavailable:
            return "Gatekeeper could not confirm the notarization; check your connection, or Gatekeeper may be turned off"
        case .verificationFailed(let detail):
            return detail.isEmpty ? "The update could not be verified" : "The update could not be verified: \(detail)"
        case .replacementDenied:
            return "macOS did not allow AgentTacho to replace itself"
        case .replacementFailed(let detail):
            return detail.isEmpty ? "Replacing the app failed" : "Replacing the app failed: \(detail)"
        case .previousVersionInTrash(let path):
            guard let path, !path.isEmpty else {
                return "Replacing the app failed; put the previous version back from the Trash"
            }
            return "Replacing the app failed; the previous version is in the Trash at \(path)"
        }
    }

    /// A failure that may pass on a second try (a failed download, or
    /// Gatekeeper not reachable): the line offers "Try again" next to the
    /// release notes (spec 013 US2 scenario 4). Every other reason offers
    /// only the release page.
    public var allowsRetry: Bool {
        switch self {
        case .downloadFailed, .gatekeeperUnavailable: return true
        default: return false
        }
    }

    /// The reason for a failed download (FR-014, FR-019): too large and an
    /// unexpected host are told apart from other failures.
    public static func forDownload(_ error: UpdateClientError) -> UpdateBlockReason {
        switch error {
        case .tooLarge: return .downloadTooLarge
        case .unexpectedHost: return .unexpectedHost
        default: return .downloadFailed(error.description)
        }
    }

    /// The reason for a failed move of the app bundle (FR-017, FR-019): a
    /// write permission error or `EPERM`, directly or as the underlying
    /// error, means macOS refused (App Management); anything else is a plain
    /// failure with the error's description.
    public static func forReplacement(domain: String, code: Int, underlyingDomain: String?, underlyingCode: Int?,
                                      description: String) -> UpdateBlockReason {
        let denied = (domain == NSCocoaErrorDomain && code == NSFileWriteNoPermissionError)
            || (domain == NSPOSIXErrorDomain && code == Int(EPERM))
            || (underlyingDomain == NSPOSIXErrorDomain && underlyingCode == Int(EPERM))
        return denied ? .replacementDenied : .replacementFailed(description)
    }
}
