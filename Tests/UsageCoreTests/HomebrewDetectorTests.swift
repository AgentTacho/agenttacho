import Foundation
import Testing
@testable import UsageCore

/// spec 013 FR-012, research R7: an installation is Homebrew-managed when a
/// `Caskroom/agenttacho/<version>/AgentTacho.app` link points at the running
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
        tree.versions["/opt/homebrew/Caskroom/agenttacho"] = ["0.2.1"]
        tree.links["/opt/homebrew/Caskroom/agenttacho/0.2.1/AgentTacho.app"] = "/Applications/AgentTacho.app"
        #expect(tree.isManaged("/Applications/AgentTacho.app"))
        #expect(tree.isManaged("/Applications/AgentTacho.app/"))
        #expect(tree.isManaged("/Applications/./AgentTacho.app"))
    }

    @Test func usrLocalPrefixIsSearched() {
        var tree = FakeTree()
        tree.versions["/usr/local/Caskroom/agenttacho"] = [".metadata", "0.2.0"]
        tree.links["/usr/local/Caskroom/agenttacho/0.2.0/AgentTacho.app"] = "/Applications/AgentTacho.app/"
        #expect(tree.isManaged("/Applications/AgentTacho.app"))
    }

    @Test func privatePrefixIsIgnored() {
        var tree = FakeTree()
        tree.versions["/opt/homebrew/Caskroom/agenttacho"] = ["0.2.1"]
        tree.links["/opt/homebrew/Caskroom/agenttacho/0.2.1/AgentTacho.app"] = "/private/tmp/apps/AgentTacho.app"
        #expect(tree.isManaged("/tmp/apps/AgentTacho.app"))
    }

    @Test func relativeLinkIsResolvedAgainstItsFolder() {
        var tree = FakeTree()
        tree.versions["/opt/homebrew/Caskroom/agenttacho"] = ["0.2.1"]
        tree.links["/opt/homebrew/Caskroom/agenttacho/0.2.1/AgentTacho.app"] = "../../../../../Applications/AgentTacho.app"
        #expect(tree.isManaged("/Applications/AgentTacho.app"))
    }

    @Test func linkToAnotherCopyIsNotManaged() {
        var tree = FakeTree()
        tree.versions["/opt/homebrew/Caskroom/agenttacho"] = ["0.2.1"]
        tree.links["/opt/homebrew/Caskroom/agenttacho/0.2.1/AgentTacho.app"] = "/Users/me/Applications/AgentTacho.app"
        #expect(!tree.isManaged("/Applications/AgentTacho.app"))
    }

    @Test func noCaskroomIsNotManaged() {
        #expect(!FakeTree().isManaged("/Applications/AgentTacho.app"))
    }

    @Test func nonLinkEntryIsNotManaged() {
        var tree = FakeTree()
        tree.versions["/opt/homebrew/Caskroom/agenttacho"] = ["0.2.1"]
        #expect(!tree.isManaged("/Applications/AgentTacho.app"))
    }

    @Test func liveHelpersReadARealTree() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brew-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let caskroom = root.appendingPathComponent("Caskroom/agenttacho/0.2.1")
        try FileManager.default.createDirectory(at: caskroom, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: caskroom.appendingPathComponent("AgentTacho.app").path,
                                                   withDestinationPath: "/Applications/AgentTacho.app")
        #expect(HomebrewDetector.listVersionsLive(root.appendingPathComponent("Caskroom/agenttacho").path) == ["0.2.1"])
        #expect(HomebrewDetector.resolveLinkLive(caskroom.appendingPathComponent("AgentTacho.app").path) == "/Applications/AgentTacho.app")
        #expect(HomebrewDetector.resolveLinkLive(caskroom.path) == nil)
        #expect(HomebrewDetector.listVersionsLive(root.appendingPathComponent("missing").path) == nil)
    }
}
