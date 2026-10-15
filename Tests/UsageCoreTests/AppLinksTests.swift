import Foundation
import Testing
@testable import UsageCore

@Suite struct AppLinksTests {
    @Test func fixedLinks() {
        #expect(AppLinks.repository.absoluteString == "https://github.com/rhuss/agentmeter")
        #expect(AppLinks.newIssue.absoluteString == "https://github.com/rhuss/agentmeter/issues/new")
        #expect(AppLinks.sponsor.absoluteString == "https://github.com/sponsors/rhuss")
        #expect(AppLinks.author.absoluteString == "https://github.com/rhuss")
    }

    @Test func releasePageOfATaggedBuild() {
        #expect(AppLinks.releasePage(for: "v0.2.3").absoluteString
            == "https://github.com/rhuss/agentmeter/releases/tag/v0.2.3")
    }

    @Test func developmentBuildsLinkTheLatestRelease() {
        #expect(AppLinks.releasePage(for: nil).absoluteString
            == "https://github.com/rhuss/agentmeter/releases/latest")
        #expect(AppLinks.releasePage(for: "").absoluteString
            == "https://github.com/rhuss/agentmeter/releases/latest")
    }

    @Test func commitLinkUsesTheFullHash() {
        #expect(AppLinks.commit("7975e1b0123456789abcdef0123456789abcdef0").absoluteString
            == "https://github.com/rhuss/agentmeter/commit/7975e1b0123456789abcdef0123456789abcdef0")
    }
}
