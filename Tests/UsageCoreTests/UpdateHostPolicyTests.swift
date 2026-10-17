import Foundation
import Testing
@testable import UsageCore

/// spec 013 FR-005: every starting URL and every redirect must be https on
/// one of four GitHub hosts.
@Suite struct UpdateHostPolicyTests {
    @Test(arguments: [
        "https://api.github.com/repos/AgentTacho/agenttacho/releases/latest",
        "https://github.com/AgentTacho/agenttacho/releases/download/v0.3.0/release-info.json",
        "https://objects.githubusercontent.com/github-production-release-asset/1?x=y",
        "https://release-assets.githubusercontent.com/github-production-release-asset/1",
        "https://GitHub.com/AgentTacho/agenttacho",
        "https://API.GITHUB.COM/repos/x/y",
    ])
    func allowsHttpsOnTheListedHosts(_ text: String) throws {
        #expect(UpdateHostPolicy.allows(try #require(URL(string: text))))
    }

    @Test(arguments: [
        "http://github.com/AgentTacho/agenttacho",
        "https://raw.githubusercontent.com/AgentTacho/agenttacho/main/README.md",
        "https://evil-github.com/x",
        "https://github.com.evil.com/x",
        "https://example.com/AgentTacho-0.3.0.dmg",
        "ftp://github.com/x",
        "https://github.com:8443/x",
        "file:///tmp/x",
        "https:///nohost",
        "/relative/path",
    ])
    func rejectsEverythingElse(_ text: String) throws {
        let url = try #require(URL(string: text))
        #expect(!UpdateHostPolicy.allows(url))
    }

    @Test func listsExactlyTheFourHosts() {
        #expect(UpdateHostPolicy.allowedHosts == ["api.github.com", "github.com",
                                                  "objects.githubusercontent.com", "release-assets.githubusercontent.com"])
    }
}
