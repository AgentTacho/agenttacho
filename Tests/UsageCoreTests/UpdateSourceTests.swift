import Foundation
import Testing
@testable import UsageCore

/// spec 013 FR-025, contracts/make-targets.md: the release source of an
/// update-test build is `owner/repo` matching
/// `^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$`; anything else falls back to
/// `AgentTacho/agenttacho`.
@Suite struct UpdateSourceTests {
    @Test func officialSource() {
        #expect(UpdateSource.official == UpdateSource(owner: "AgentTacho", repo: "agenttacho"))
    }

    @Test(arguments: ["AgentTacho/agenttacho", "some-user/scratch.repo_1", "A1/b", "o/.-_"])
    func acceptsOwnerSlashRepo(_ text: String) throws {
        let source = try #require(UpdateSource.parse(text))
        #expect("\(source.owner)/\(source.repo)" == text)
    }

    @Test(arguments: ["", "rhuss", "/agenttacho", "rhuss/", "a/b/c", "rh_uss/agenttacho", "rh.uss/agenttacho",
                      "rhuss/agent tacho", " AgentTacho/agenttacho", "AgentTacho/agenttacho\n", "rhüss/agenttacho",
                      "AgentTacho/agenttacho?x=1", "rhuss/../x", "https://github.com/AgentTacho/agenttacho"])
    func rejectsAnythingElse(_ text: String) {
        #expect(UpdateSource.parse(text) == nil)
    }

    @Test func fallsBackToTheOfficialSource() {
        #expect(UpdateSource.resolve(nil) == .official)
        #expect(UpdateSource.resolve("not a source") == .official)
        #expect(UpdateSource.resolve("me/scratch") == UpdateSource(owner: "me", repo: "scratch"))
    }
}
