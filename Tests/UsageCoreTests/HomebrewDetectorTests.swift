import Foundation
import Testing
@testable import UsageCore

/// spec 013 FR-012, research R7: an installation is Homebrew-managed when a
/// `Caskroom/agentmeter/<version>/AgentMeter.app` link points at the running
/// app.
@Suite struct HomebrewDetectorTests {
    /// A fake file system: Caskroom folders with versions, and link targets.
    struct FakeTree {
        var versions: [String: [String]] = [:]
        var links: [String: String] = [:]

        func isManaged(_ running: String) -> Bool {
            HomebrewDetector.isManaged(runningAppPath: running,
                                       listVersions: { versions[$0] },
                                       resolveLink: { links[$0] })
        }
    }

    @Test func prefixes() {
        #expect(HomebrewDetector.prefixes == ["/opt/homebrew", "/usr/local"])
    }

    @Test func linkToTheRunningAppIsManaged() {
        var tree = FakeTree()
        tree.versions["/opt/homebrew/Caskroom/agentmeter"] = ["0.2.1"]
        tree.links["/opt/homebrew/Caskroom/agentmeter/0.2.1/AgentMeter.app"] = "/Applications/AgentMeter.app"
        #expect(tree.isManaged("/Applications/AgentMeter.app"))
        #expect(tree.isManaged("/Applications/AgentMeter.app/"))
        #expect(tree.isManaged("/Applications/./AgentMeter.app"))
    }

    @Test func usrLocalPrefixIsSearched() {
        var tree = FakeTree()
        tree.versions["/usr/local/Caskroom/agentmeter"] = [".metadata", "0.2.0"]
        tree.links["/usr/local/Caskroom/agentmeter/0.2.0/AgentMeter.app"] = "/Applications/AgentMeter.app/"
        #expect(tree.isManaged("/Applications/AgentMeter.app"))
    }

    @Test func privatePrefixIsIgnored() {
        var tree = FakeTree()
        tree.versions["/opt/homebrew/Caskroom/agentmeter"] = ["0.2.1"]
        tree.links["/opt/homebrew/Caskroom/agentmeter/0.2.1/AgentMeter.app"] = "/private/tmp/apps/AgentMeter.app"
        #expect(tree.isManaged("/tmp/apps/AgentMeter.app"))
    }

    @Test func relativeLinkIsResolvedAgainstItsFolder() {
        var tree = FakeTree()
        tree.versions["/opt/homebrew/Caskroom/agentmeter"] = ["0.2.1"]
        tree.links["/opt/homebrew/Caskroom/agentmeter/0.2.1/AgentMeter.app"] = "../../../../../Applications/AgentMeter.app"
        #expect(tree.isManaged("/Applications/AgentMeter.app"))
    }

    @Test func linkToAnotherCopyIsNotManaged() {
        var tree = FakeTree()
        tree.versions["/opt/homebrew/Caskroom/agentmeter"] = ["0.2.1"]
        tree.links["/opt/homebrew/Caskroom/agentmeter/0.2.1/AgentMeter.app"] = "/Users/me/Applications/AgentMeter.app"
        #expect(!tree.isManaged("/Applications/AgentMeter.app"))
    }

    @Test func noCaskroomIsNotManaged() {
        #expect(!FakeTree().isManaged("/Applications/AgentMeter.app"))
    }

    @Test func nonLinkEntryIsNotManaged() {
        var tree = FakeTree()
        tree.versions["/opt/homebrew/Caskroom/agentmeter"] = ["0.2.1"]
        #expect(!tree.isManaged("/Applications/AgentMeter.app"))
    }

    @Test func liveHelpersReadARealTree() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brew-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let caskroom = root.appendingPathComponent("Caskroom/agentmeter/0.2.1")
        try FileManager.default.createDirectory(at: caskroom, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: caskroom.appendingPathComponent("AgentMeter.app").path,
                                                   withDestinationPath: "/Applications/AgentMeter.app")
        #expect(HomebrewDetector.listVersionsLive(root.appendingPathComponent("Caskroom/agentmeter").path) == ["0.2.1"])
        #expect(HomebrewDetector.resolveLinkLive(caskroom.appendingPathComponent("AgentMeter.app").path) == "/Applications/AgentMeter.app")
        #expect(HomebrewDetector.resolveLinkLive(caskroom.path) == nil)
        #expect(HomebrewDetector.listVersionsLive(root.appendingPathComponent("missing").path) == nil)
    }
}
