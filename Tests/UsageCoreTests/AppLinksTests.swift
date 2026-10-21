import Foundation
import Testing
@testable import UsageCore

@Suite struct AppLinksTests {
    @Test func fixedLinks() {
        #expect(AppLinks.repository.absoluteString == "https://github.com/AgentTacho/agenttacho")
        #expect(AppLinks.newIssue.absoluteString == "https://github.com/AgentTacho/agenttacho/issues/new")
        #expect(AppLinks.sponsor.absoluteString == "https://github.com/sponsors/rhuss")
        #expect(AppLinks.author.absoluteString == "https://ro14nd.de")
    }

    @Test func securityStatementLinksTheReadmeSection() {
        #expect(AppLinks.securityStatement.absoluteString
            == "https://github.com/AgentTacho/agenttacho#security-and-privacy")
    }

    @Test func releasePageOfATaggedBuild() {
        #expect(AppLinks.releasePage(for: "v0.2.3").absoluteString
            == "https://github.com/AgentTacho/agenttacho/releases/tag/v0.2.3")
    }

    @Test func developmentBuildsLinkTheLatestRelease() {
        #expect(AppLinks.releasePage(for: nil).absoluteString
            == "https://github.com/AgentTacho/agenttacho/releases/latest")
        #expect(AppLinks.releasePage(for: "").absoluteString
            == "https://github.com/AgentTacho/agenttacho/releases/latest")
    }

    @Test func commitLinkUsesTheFullHash() {
        #expect(AppLinks.commit("7975e1b0123456789abcdef0123456789abcdef0").absoluteString
            == "https://github.com/AgentTacho/agenttacho/commit/7975e1b0123456789abcdef0123456789abcdef0")
    }
}

/// spec 033 FR-010a, research R6: the usage pages a gift glyph opens.
@Suite struct UsagePageLinksTests {
    @Test func usagePages() {
        #expect(AppLinks.claudeUsagePage.absoluteString == "https://claude.ai/settings/usage")
        #expect(AppLinks.codexUsagePage.absoluteString == "https://chatgpt.com/settings/usage?tab=overview")
    }
}
