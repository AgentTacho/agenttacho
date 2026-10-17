import Foundation
import Testing
@testable import UsageCore

@Suite struct AppVersionInfoTests {
    @Test func displayVersionAndBuildFormTheLabel() {
        let info = AppVersionInfo(infoDictionary: [
            "AgentTachoVersionDisplay": "0.2.0-dev",
            "CFBundleShortVersionString": "0.2.0",
            "CFBundleVersion": "120",
        ])
        #expect(info.label == "AgentTacho 0.2.0-dev (build 120)")
    }

    @Test func missingDisplayKeyFallsBackToShortVersion() {
        let info = AppVersionInfo(infoDictionary: [
            "CFBundleShortVersionString": "0.3.1",
            "CFBundleVersion": "7",
        ])
        #expect(info.label == "AgentTacho 0.3.1 (build 7)")
    }

    @Test func emptyDictionaryIsUnknown() {
        let info = AppVersionInfo(infoDictionary: [:])
        #expect(info.label == "AgentTacho unknown")
    }

    @Test func missingBuildOmitsBuildPart() {
        let info = AppVersionInfo(infoDictionary: ["AgentTachoVersionDisplay": "0.2.0"])
        #expect(info.label == "AgentTacho 0.2.0")
    }

    @Test func emptyStringsCountAsMissing() {
        let info = AppVersionInfo(infoDictionary: [
            "AgentTachoVersionDisplay": "",
            "CFBundleShortVersionString": "0.4.0",
            "CFBundleVersion": "",
        ])
        #expect(info.label == "AgentTacho 0.4.0")
    }

    // MARK: - Release data for the About tab

    @Test func versionTextShowsVersionAndBuild() {
        #expect(AppVersionInfo(infoDictionary: [
            "AgentTachoVersionDisplay": "0.2.3",
            "CFBundleVersion": "63",
        ]).versionText == "0.2.3 (build 63)")
        #expect(AppVersionInfo(infoDictionary: ["AgentTachoVersionDisplay": "0.2.3"]).versionText == "0.2.3")
        #expect(AppVersionInfo(infoDictionary: ["CFBundleVersion": "63"]).versionText == "unknown")
    }

    @Test func stampedReleaseDataIsRead() throws {
        let info = AppVersionInfo(infoDictionary: [
            "AgentTachoVersionDisplay": "0.2.3",
            "AgentTachoCommit": "7975e1b0123456789abcdef0123456789abcdef0",
            "AgentTachoBuildDate": "2026-10-15T08:30:00Z",
            "AgentTachoReleaseTag": "v0.2.3",
            "AgentTachoSigning": "developer-id",
            "AgentTachoNotarized": true,
        ])
        #expect(info.commit == "7975e1b0123456789abcdef0123456789abcdef0")
        #expect(info.shortCommit == "7975e1b")
        #expect(info.buildDate == Date(timeIntervalSince1970: 1_792_053_000))
        #expect(info.releaseTag == "v0.2.3")
        #expect(info.signing == .developerID(notarized: true))
    }

    @Test func missingReleaseDataIsNil() {
        let info = AppVersionInfo(infoDictionary: ["AgentTachoVersionDisplay": "0.2.3"])
        #expect(info.commit == nil)
        #expect(info.shortCommit == nil)
        #expect(info.buildDate == nil)
        #expect(info.releaseTag == nil)
        #expect(info.signing == nil)
    }

    @Test func malformedReleaseDataIsNil() {
        let info = AppVersionInfo(infoDictionary: [
            "AgentTachoCommit": "",
            "AgentTachoBuildDate": "yesterday",
            "AgentTachoReleaseTag": "",
            "AgentTachoSigning": "notarized-by-magic",
        ])
        #expect(info.commit == nil)
        #expect(info.buildDate == nil)
        #expect(info.releaseTag == nil)
        #expect(info.signing == nil)
    }

    @Test func signingTiersAndTheirText() {
        func signing(_ tier: String, notarized: Any? = nil) -> AppVersionInfo.Signing? {
            var dictionary: [String: Any] = ["AgentTachoSigning": tier]
            dictionary["AgentTachoNotarized"] = notarized
            return AppVersionInfo(infoDictionary: dictionary).signing
        }
        #expect(signing("developer-id", notarized: true)?.text == "Developer ID, notarized")
        #expect(signing("developer-id")?.text == "Developer ID")
        #expect(signing("developer-id", notarized: false)?.text == "Developer ID")
        #expect(signing("self-signed")?.text == "Self-signed")
        #expect(signing("ad-hoc")?.text == "Ad-hoc")
        // Only a Developer ID build can be notarized.
        #expect(signing("self-signed", notarized: true) == .selfSigned)
    }

    @Test func releaseDataLeavesTheLabelUnchanged() {
        let info = AppVersionInfo(infoDictionary: [
            "AgentTachoVersionDisplay": "0.2.3",
            "CFBundleVersion": "63",
            "AgentTachoCommit": "7975e1b0123456789abcdef0123456789abcdef0",
            "AgentTachoSigning": "developer-id",
        ])
        #expect(info.label == "AgentTacho 0.2.3 (build 63)")
    }
}
