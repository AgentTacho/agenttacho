import Foundation
import Testing
@testable import UsageCore

/// spec 013 FR-008, FR-012, FR-019; User Story 5 scenarios 1 to 4.
@Suite struct UpdatePolicyTests {
    static let target = DownloadTarget(url: URL(string: "https://github.com/AgentTacho/agenttacho/releases/download/v0.3.0/AgentTacho-0.3.0.dmg")!,
                                       size: 10_485_760, sha256: String(repeating: "a", count: 64))
    static let page = URL(string: "https://github.com/AgentTacho/agenttacho/releases/tag/v0.3.0")!

    static func release(download: DownloadTarget? = target, problem: UpdateBlockReason? = nil) -> AvailableRelease {
        AvailableRelease(version: ReleaseVersion(major: 0, minor: 3, patch: 0), pageURL: page, download: download, infoProblem: problem)
    }

    /// A Developer ID notarized release build in a writable folder.
    static func eligible() -> InstallContext {
        InstallContext(runningVersion: ReleaseVersion(major: 0, minor: 2, patch: 1),
                       isReleaseBuild: true, isUpdateTestBuild: false,
                       signing: .developerID(notarized: true), teamIdentifier: "EC5BHUKA6K",
                       bundleIdentifier: "dev.rhuss.agenttacho", bundlePath: "/Applications/AgentTacho.app",
                       isHomebrewManaged: false, isTranslocated: false, isOnReadOnlyVolume: false,
                       isBundleWritable: true, isParentWritable: true)
    }

    // MARK: checksAllowed (FR-008)

    @Test func releaseBuildMayCheck() {
        #expect(UpdatePolicy.checksAllowed(context: Self.eligible()))
    }

    @Test func developmentBuildMayNotCheck() {
        var context = Self.eligible()
        context.isReleaseBuild = false
        #expect(!UpdatePolicy.checksAllowed(context: context))
    }

    @Test func updateTestBuildMayCheck() {
        var context = Self.eligible()
        context.isReleaseBuild = false
        context.isUpdateTestBuild = true
        #expect(UpdatePolicy.checksAllowed(context: context))
    }

    @Test func missingRunningVersionDisablesChecks() {
        var context = Self.eligible()
        context.runningVersion = nil
        #expect(!UpdatePolicy.checksAllowed(context: context))
        context.isUpdateTestBuild = true
        #expect(!UpdatePolicy.checksAllowed(context: context))
    }

    // MARK: action (FR-012, FR-019)

    @Test func eligibleBuildInstalls() {
        #expect(UpdatePolicy.action(context: Self.eligible(), release: Self.release()) == .install(Self.target))
    }

    @Test func homebrewWinsOverEveryLocationFact() {
        var context = Self.eligible()
        context.isHomebrewManaged = true
        #expect(UpdatePolicy.action(context: context, release: Self.release()) == .homebrew)
        context.isTranslocated = true
        context.isOnReadOnlyVolume = true
        context.isBundleWritable = false
        context.isParentWritable = false
        context.signing = .adHoc
        #expect(UpdatePolicy.action(context: context, release: Self.release(download: nil, problem: .releaseNotNotarized)) == .homebrew)
    }

    @Test func translocatedComesFirst() {
        var context = Self.eligible()
        context.isTranslocated = true
        context.isOnReadOnlyVolume = true
        context.isBundleWritable = false
        #expect(UpdatePolicy.action(context: context, release: Self.release()) == .download(.translocated))
    }

    @Test func readOnlyVolumeIsADiskImage() {
        var context = Self.eligible()
        context.isOnReadOnlyVolume = true
        context.isBundleWritable = false
        #expect(UpdatePolicy.action(context: context, release: Self.release()) == .download(.runsFromDiskImage))
    }

    @Test func unwritableBundleOrParent() {
        var bundle = Self.eligible()
        bundle.isBundleWritable = false
        #expect(UpdatePolicy.action(context: bundle, release: Self.release()) == .download(.notWritable))
        var parent = Self.eligible()
        parent.isParentWritable = false
        #expect(UpdatePolicy.action(context: parent, release: Self.release()) == .download(.notWritable))
    }

    @Test(arguments: [AppVersionInfo.Signing.selfSigned, .adHoc, .developerID(notarized: false)])
    func runningBuildWithoutNotarizedDeveloperID(_ signing: AppVersionInfo.Signing) {
        var context = Self.eligible()
        context.signing = signing
        #expect(UpdatePolicy.action(context: context, release: Self.release()) == .download(.runningNotNotarized))
    }

    @Test func runningBuildWithoutSigningStampOrTeam() {
        var noStamp = Self.eligible()
        noStamp.signing = nil
        #expect(UpdatePolicy.action(context: noStamp, release: Self.release()) == .download(.runningNotNotarized))
        var noTeam = Self.eligible()
        noTeam.teamIdentifier = nil
        #expect(UpdatePolicy.action(context: noTeam, release: Self.release()) == .download(.runningNotNotarized))
        noTeam.teamIdentifier = ""
        #expect(UpdatePolicy.action(context: noTeam, release: Self.release()) == .download(.runningNotNotarized))
    }

    @Test func updateTestBuildNeedsOnlyDeveloperIDAndTeam() {
        var context = Self.eligible()
        context.isReleaseBuild = false
        context.isUpdateTestBuild = true
        context.signing = .developerID(notarized: false)
        #expect(UpdatePolicy.action(context: context, release: Self.release()) == .install(Self.target))
        context.signing = .selfSigned
        #expect(UpdatePolicy.action(context: context, release: Self.release()) == .download(.runningNotNotarized))
        context.signing = .developerID(notarized: false)
        context.teamIdentifier = nil
        #expect(UpdatePolicy.action(context: context, release: Self.release()) == .download(.runningNotNotarized))
    }

    @Test func releaseWithoutDownloadTargetGivesItsProblem() {
        #expect(UpdatePolicy.action(context: Self.eligible(), release: Self.release(download: nil, problem: .releaseNotNotarized))
                == .download(.releaseNotNotarized))
        #expect(UpdatePolicy.action(context: Self.eligible(), release: Self.release(download: nil, problem: .downloadTooLarge))
                == .download(.downloadTooLarge))
        #expect(UpdatePolicy.action(context: Self.eligible(), release: Self.release(download: nil, problem: nil))
                == .download(.releaseInfoIncomplete))
    }

    // MARK: Reason texts (FR-019, contracts/update-ui.md)

    @Test func userStory5Texts() {
        #expect(UpdateBlockReason.runsFromDiskImage.text == "Move AgentTacho to Applications to install updates")
        #expect(UpdateBlockReason.translocated.text == "Move AgentTacho to Applications to install updates")
        #expect(UpdateBlockReason.notWritable.text == "AgentTacho cannot replace itself in this folder")
        #expect(UpdateBlockReason.runningNotNotarized.text == "This build cannot verify updates")
        #expect(UpdateBlockReason.gatekeeperUnavailable.text
                == "Gatekeeper could not confirm the notarization; check your connection, or Gatekeeper may be turned off")
        #expect(UpdateBlockReason.replacementDenied.text == "macOS did not allow AgentTacho to replace itself")
    }

    @Test func otherReasonsHaveDistinctShortTexts() {
        let reasons: [UpdateBlockReason] = [
            .runsFromDiskImage, .notWritable, .runningNotNotarized, .releaseNotNotarized, .releaseInfoIncomplete,
            .downloadFailed("offline"), .downloadTooLarge, .unexpectedHost, .checksumMismatch, .diskImageNotNotarized,
            .unexpectedContents("2 apps"), .signatureMismatch, .appNotNotarized, .gatekeeperUnavailable,
            .replacementDenied, .replacementFailed("disk full"), .previousVersionInTrash("/Users/x/.Trash/AgentTacho.app"),
        ]
        let texts = reasons.map(\.text)
        #expect(Set(texts).count == texts.count)
        #expect(texts.allSatisfy { !$0.isEmpty && !$0.contains("\u{2014}") && !$0.contains("\u{2013}") })
        #expect(UpdateBlockReason.releaseInfoIncomplete.text == "Release information incomplete")
        #expect(UpdateBlockReason.checksumMismatch.text.contains("could not be verified"))
        #expect(UpdateBlockReason.downloadFailed("offline").text.contains("offline"))
        #expect(UpdateBlockReason.unexpectedContents("2 apps").text.contains("2 apps"))
        #expect(UpdateBlockReason.replacementFailed("disk full").text.contains("disk full"))
    }
}
