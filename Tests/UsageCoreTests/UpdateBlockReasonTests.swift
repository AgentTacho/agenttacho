import Foundation
import Testing
@testable import UsageCore

/// spec 013 FR-017, FR-019, FR-023, US2 scenario 4: the reasons for failed
/// downloads and replacements, and which failures offer Try again.
@Suite struct UpdateBlockReasonTests {
    @Test func downloadFailuresAreToldApart() {
        #expect(UpdateBlockReason.forDownload(.tooLarge) == .downloadTooLarge)
        #expect(UpdateBlockReason.forDownload(.unexpectedHost) == .unexpectedHost)
        #expect(UpdateBlockReason.forDownload(.httpStatus(404)) == .downloadFailed("GitHub returned HTTP 404"))
        #expect(UpdateBlockReason.forDownload(.network("timed out")) == .downloadFailed("timed out"))
    }

    @Test func permissionErrorsMeanMacOSDenied() {
        #expect(UpdateBlockReason.forReplacement(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError,
                                                 underlyingDomain: nil, underlyingCode: nil, description: "d") == .replacementDenied)
        #expect(UpdateBlockReason.forReplacement(domain: NSPOSIXErrorDomain, code: Int(EPERM),
                                                 underlyingDomain: nil, underlyingCode: nil, description: "d") == .replacementDenied)
        #expect(UpdateBlockReason.forReplacement(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError,
                                                 underlyingDomain: NSPOSIXErrorDomain, underlyingCode: Int(EPERM),
                                                 description: "d") == .replacementDenied)
    }

    @Test func otherReplacementErrorsAreFailures() {
        #expect(UpdateBlockReason.forReplacement(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError,
                                                 underlyingDomain: NSPOSIXErrorDomain, underlyingCode: Int(ENOSPC),
                                                 description: "disk full") == .replacementFailed("disk full"))
        #expect(UpdateBlockReason.forReplacement(domain: NSPOSIXErrorDomain, code: Int(EACCES),
                                                 underlyingDomain: nil, underlyingCode: nil, description: "x") == .replacementFailed("x"))
    }

    @Test func onlyDownloadAndGatekeeperFailuresAllowRetry() {
        #expect(UpdateBlockReason.downloadFailed("x").allowsRetry)
        #expect(UpdateBlockReason.gatekeeperUnavailable.allowsRetry)
        for reason in [UpdateBlockReason.checksumMismatch, .signatureMismatch, .appNotNotarized, .diskImageNotNotarized,
                       .downloadTooLarge, .unexpectedHost, .unexpectedContents("x"), .replacementDenied,
                       .replacementFailed("x"), .previousVersionInTrash(nil), .notWritable, .runningNotNotarized,
                       .verificationFailed("x")] {
            #expect(!reason.allowsRetry, "\(reason)")
        }
    }

    /// A verification tool that could not run is a verification failure,
    /// not a replacement failure: nothing was replaced (FR-016, FR-019).
    @Test func verificationFailureNamesTheDetail() {
        #expect(UpdateBlockReason.verificationFailed("cannot run /usr/sbin/spctl").text
                == "The update could not be verified: cannot run /usr/sbin/spctl")
        #expect(UpdateBlockReason.verificationFailed("").text == "The update could not be verified")
    }

    @Test func previousVersionInTrashNamesThePath() {
        #expect(UpdateBlockReason.previousVersionInTrash("/Users/me/.Trash/AgentMeter.app").text
                == "Replacing the app failed; the previous version is in the Trash at /Users/me/.Trash/AgentMeter.app")
        #expect(UpdateBlockReason.previousVersionInTrash(nil).text == "Replacing the app failed; put the previous version back from the Trash")
    }

    @Test func retryAndDownloadCarryTheirReason() {
        let target = DownloadTarget(url: URL(string: "https://github.com/a/b.dmg")!, size: 1, sha256: String(repeating: "a", count: 64))
        #expect(UpdateAction.retry(target, .gatekeeperUnavailable).reason == .gatekeeperUnavailable)
        #expect(UpdateAction.retry(target, .gatekeeperUnavailable).installTarget == target)
        #expect(UpdateAction.download(.notWritable).reason == .notWritable)
        #expect(UpdateAction.download(.notWritable).installTarget == nil)
        #expect(UpdateAction.install(target).reason == nil)
        #expect(UpdateAction.homebrew.installTarget == nil)
    }
}
