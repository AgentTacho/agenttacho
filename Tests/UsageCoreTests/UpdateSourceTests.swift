import Foundation
import Testing
@testable import UsageCore

/// spec 013 FR-025, contracts/make-targets.md: the release source of an
/// update-test build is `owner/repo` matching
/// `^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$`; anything else falls back to
/// `rhuss/agentmeter`.
@Suite struct UpdateSourceTests {
    @Test func officialSource() {
        #expect(UpdateSource.official == UpdateSource(owner: "rhuss", repo: "agentmeter"))
    }

    @Test(arguments: ["rhuss/agentmeter", "some-user/scratch.repo_1", "A1/b", "o/.-_"])
    func acceptsOwnerSlashRepo(_ text: String) throws {
        let source = try #require(UpdateSource.parse(text))
        #expect("\(source.owner)/\(source.repo)" == text)
    }

    @Test(arguments: ["", "rhuss", "/agentmeter", "rhuss/", "a/b/c", "rh_uss/agentmeter", "rh.uss/agentmeter",
                      "rhuss/agent meter", " rhuss/agentmeter", "rhuss/agentmeter\n", "rhüss/agentmeter",
                      "rhuss/agentmeter?x=1", "rhuss/../x", "https://github.com/rhuss/agentmeter"])
    func rejectsAnythingElse(_ text: String) {
        #expect(UpdateSource.parse(text) == nil)
    }

    @Test func fallsBackToTheOfficialSource() {
        #expect(UpdateSource.resolve(nil) == .official)
        #expect(UpdateSource.resolve("not a source") == .official)
        #expect(UpdateSource.resolve("me/scratch") == UpdateSource(owner: "me", repo: "scratch"))
    }
}
