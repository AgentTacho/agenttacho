import Foundation
import Testing
@testable import UsageCore

/// spec 013 FR-004, FR-006, FR-014: decoding the GitHub release and
/// release-info.json, and deciding ignored / not newer / available.
@Suite struct ReleaseEvaluatorTests {
    static let sha = "3f7a1c9e5b2d4f6081a3c5e7f9b1d3e5a7c9e1f3b5d7f9a1c3e5b7d9f1a3c5e7"

    private func release(_ name: String = "releases-latest.json") throws -> GitHubRelease {
        try JSONDecoder().decode(GitHubRelease.self, from: Data(contentsOf: Fixtures.url("update/\(name)")))
    }

    private func info(_ name: String = "release-info.json") throws -> ReleaseInfo {
        try #require(ReleaseInfo.decode(Data(contentsOf: Fixtures.url("update/\(name)"))))
    }

    private func version(_ text: String) throws -> ReleaseVersion {
        try #require(ReleaseVersion(text))
    }

    private func availableRelease(_ result: ReleaseCheckResult) throws -> AvailableRelease {
        guard case .available(let release) = result else {
            Issue.record("expected available, got \(result)")
            throw CancellationError()
        }
        return release
    }

    // MARK: Decoding

    @Test func decodesTheGitHubRelease() throws {
        let release = try release()
        #expect(release.tag == "v0.3.0")
        #expect(release.pageURL.absoluteString == "https://github.com/rhuss/agentmeter/releases/tag/v0.3.0")
        #expect(!release.draft && !release.prerelease)
        #expect(release.assets.map(\.name) == ["AgentMeter-0.3.0.dmg", "AgentMeter-0.3.0.dmg.sha256", "release-info.json"])
        #expect(release.assets.first?.size == 10_485_760)
        #expect(release.releaseInfoAsset?.downloadURL?.absoluteString
                == "https://github.com/rhuss/agentmeter/releases/download/v0.3.0/release-info.json")
    }

    @Test func releaseWithoutTagOrPageFailsToDecode() {
        let noTag = #"{"html_url":"https://github.com/x/y/releases/tag/v1.0.0","draft":false,"prerelease":false,"assets":[]}"#
        let httpPage = #"{"tag_name":"v1.0.0","html_url":"http://github.com/x","draft":false,"prerelease":false,"assets":[]}"#
        #expect(throws: (any Error).self) { try JSONDecoder().decode(GitHubRelease.self, from: Data(noTag.utf8)) }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(GitHubRelease.self, from: Data(httpPage.utf8)) }
    }

    @Test func malformedAssetsAreSkippedNotFatal() throws {
        let json = #"{"tag_name":"v1.0.0","html_url":"https://github.com/x/y","draft":false,"prerelease":false,"assets":[{"size":"x"},{"name":"a","size":3,"browser_download_url":"https://github.com/a"}]}"#
        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
        #expect(release.assets.map(\.name) == ["a"])
    }

    @Test func releaseInfoDecodingIsLenientPerField() throws {
        let decoded = try #require(ReleaseInfo.decode(Data(#"{"version":"0.3.0","sha256":42,"notarized":"yes"}"#.utf8)))
        #expect(decoded.version == "0.3.0")
        #expect(decoded.sha256 == nil)
        #expect(decoded.notarized == nil)
        #expect(ReleaseInfo.decode(Data("not json".utf8)) == nil)
        #expect(ReleaseInfo.decode(Data("[1,2]".utf8)) == nil)
    }

    @Test func limitsAreAsSpecified() {
        #expect(ReleaseInfo.maximumBytes == 65_536)
        #expect(DownloadTarget.maximumBytes == 104_857_600)
    }

    // MARK: Evaluation

    @Test func newerValidReleaseIsAvailableWithADownloadTarget() throws {
        let result = ReleaseEvaluator.evaluate(release: try release(), info: try info(), runningVersion: try version("0.2.1"))
        let available = try availableRelease(result)
        #expect(available.version == (try version("0.3.0")))
        #expect(available.pageURL.absoluteString == "https://github.com/rhuss/agentmeter/releases/tag/v0.3.0")
        #expect(available.infoProblem == nil)
        let target = try #require(available.download)
        #expect(target.url.absoluteString == "https://github.com/rhuss/agentmeter/releases/download/v0.3.0/AgentMeter-0.3.0.dmg")
        #expect(target.size == 10_485_760)
        #expect(target.sha256 == Self.sha)
    }

    @Test func uppercaseChecksumIsLowercased() throws {
        var info = try info()
        info.sha256 = Self.sha.uppercased()
        let available = try availableRelease(ReleaseEvaluator.evaluate(release: try release(), info: info, runningVersion: try version("0.2.1")))
        #expect(available.download?.sha256 == Self.sha)
    }

    @Test(arguments: ["0.3.0", "0.4.0"])
    func equalOrOlderReleaseIsNotNewer(_ running: String) throws {
        #expect(ReleaseEvaluator.evaluate(release: try release(), info: try info(), runningVersion: try version(running)) == .notNewer)
    }

    @Test func missingReleaseInfoAssetIsIgnored() throws {
        let result = ReleaseEvaluator.evaluate(release: try release("releases-latest-no-info.json"), info: nil, runningVersion: try version("0.2.1"))
        #expect(result == .ignored(.noReleaseInfo))
    }

    @Test func unreadableReleaseInfoIsIgnored() throws {
        let result = ReleaseEvaluator.evaluate(release: try release(), info: nil, runningVersion: try version("0.2.1"))
        #expect(result == .ignored(.releaseInfoUnreadable))
    }

    @Test func badInfoVersionIsIgnored() throws {
        let result = ReleaseEvaluator.evaluate(release: try release(), info: try info("release-info-bad-version.json"), runningVersion: try version("0.2.1"))
        #expect(result == .ignored(.invalidVersion))
        var noVersion = try info()
        noVersion.version = nil
        #expect(ReleaseEvaluator.evaluate(release: try release(), info: noVersion, runningVersion: try version("0.2.1")) == .ignored(.invalidVersion))
    }

    @Test func infoVersionDifferentFromTagIsIgnored() throws {
        var info = try info()
        info.version = "0.3.1"
        info.dmg = "AgentMeter-0.3.1.dmg"
        #expect(ReleaseEvaluator.evaluate(release: try release(), info: info, runningVersion: try version("0.2.1")) == .ignored(.versionMismatch))
    }

    /// FR-004: the version must equal the tag without "v" as text.
    @Test func tagWithOtherNumberFormattingIsIgnored() throws {
        var release = try release()
        release.tag = "v0.3.00"
        #expect(ReleaseEvaluator.evaluate(release: release, info: try info(), runningVersion: try version("0.2.1")) == .ignored(.versionMismatch))
        release.tag = "0.3.0"
        let available = try availableRelease(ReleaseEvaluator.evaluate(release: release, info: try info(), runningVersion: try version("0.2.1")))
        #expect(available.version == (try version("0.3.0")))
    }

    /// A release without the draft and prerelease flags has an unexpected
    /// shape: it is ignored rather than offered (FR-004, US1 scenario 3).
    @Test func missingDraftAndPrereleaseFlagsCountAsSet() throws {
        let json = #"{"tag_name":"v0.3.0","html_url":"https://github.com/rhuss/agentmeter/releases/tag/v0.3.0","assets":[]}"#
        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
        #expect(release.draft && release.prerelease)
        #expect(ReleaseEvaluator.evaluate(release: release, info: try info(), runningVersion: try version("0.2.1")) == .ignored(.draftOrPrerelease))
    }

    @Test func draftAndPrereleaseAreIgnored() throws {
        var draft = try release()
        draft.draft = true
        #expect(ReleaseEvaluator.evaluate(release: draft, info: try info(), runningVersion: try version("0.2.1")) == .ignored(.draftOrPrerelease))
        var pre = try release()
        pre.prerelease = true
        #expect(ReleaseEvaluator.evaluate(release: pre, info: try info(), runningVersion: try version("0.2.1")) == .ignored(.draftOrPrerelease))
    }

    @Test func selfSignedReleaseIsAvailableWithoutDownload() throws {
        let available = try availableRelease(ReleaseEvaluator.evaluate(
            release: try release(), info: try info("release-info-self-signed.json"), runningVersion: try version("0.2.1")))
        #expect(available.download == nil)
        #expect(available.infoProblem == .releaseNotNotarized)
    }

    @Test func developerIDButNotNotarizedIsNotNotarized() throws {
        var info = try info()
        info.notarized = false
        let available = try availableRelease(ReleaseEvaluator.evaluate(release: try release(), info: info, runningVersion: try version("0.2.1")))
        #expect(available.infoProblem == .releaseNotNotarized)
    }

    @Test(arguments: ["release-info-bad-sha.json", "release-info-wrong-dmg.json"])
    func unusableInfoFieldsGiveDownloadOnly(_ name: String) throws {
        let available = try availableRelease(ReleaseEvaluator.evaluate(release: try release(), info: try info(name), runningVersion: try version("0.2.1")))
        #expect(available.download == nil)
        #expect(available.infoProblem == .releaseInfoIncomplete)
    }

    @Test func missingTierOrNotarizedIsIncomplete() throws {
        var noTier = try info()
        noTier.tier = nil
        #expect(try availableRelease(ReleaseEvaluator.evaluate(release: try release(), info: noTier, runningVersion: try version("0.2.1"))).infoProblem
                == .releaseInfoIncomplete)
        var noFlag = try info()
        noFlag.notarized = nil
        #expect(try availableRelease(ReleaseEvaluator.evaluate(release: try release(), info: noFlag, runningVersion: try version("0.2.1"))).infoProblem
                == .releaseInfoIncomplete)
    }

    @Test func missingDiskImageAssetIsIncomplete() throws {
        var release = try release()
        release.assets.removeAll { $0.name == "AgentMeter-0.3.0.dmg" }
        let available = try availableRelease(ReleaseEvaluator.evaluate(release: release, info: try info(), runningVersion: try version("0.2.1")))
        #expect(available.download == nil)
        #expect(available.infoProblem == .releaseInfoIncomplete)
    }

    @Test func diskImageAboveLimitIsTooLarge() throws {
        var release = try release()
        release.assets[0].size = DownloadTarget.maximumBytes + 1
        let available = try availableRelease(ReleaseEvaluator.evaluate(release: release, info: try info(), runningVersion: try version("0.2.1")))
        #expect(available.download == nil)
        #expect(available.infoProblem == .downloadTooLarge)
        release.assets[0].size = DownloadTarget.maximumBytes
        #expect(try availableRelease(ReleaseEvaluator.evaluate(release: release, info: try info(), runningVersion: try version("0.2.1"))).download != nil)
    }

    @Test(arguments: ["https://example.com/AgentMeter-0.3.0.dmg", "http://github.com/rhuss/agentmeter/releases/download/v0.3.0/AgentMeter-0.3.0.dmg"])
    func diskImageURLOutsideTheAllowlistCountsAsMissing(_ url: String) throws {
        var release = try release()
        release.assets[0].downloadURL = URL(string: url)
        let available = try availableRelease(ReleaseEvaluator.evaluate(release: release, info: try info(), runningVersion: try version("0.2.1")))
        #expect(available.download == nil)
        #expect(available.infoProblem == .releaseInfoIncomplete)
    }
}
