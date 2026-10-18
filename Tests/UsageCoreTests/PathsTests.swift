import Foundation
import Testing
@testable import UsageCore

/// AgentTacho's data folders (spec 023 FR-007), and the demo build's own
/// folders (spec 024 FR-005).
@Suite struct PathsTests {
    let paths = Paths(home: URL(fileURLWithPath: "/Users/someone"))

    @Test func agentTachoFolders() {
        #expect(paths.configFileURL.path == "/Users/someone/.config/agenttacho/config.json")
        #expect(paths.importedPricesFileURL.path == "/Users/someone/.config/agenttacho/imported-prices.json")
        #expect(paths.logFileURL.path == "/Users/someone/Library/Logs/agenttacho/usage.log")
        #expect(paths.lastGoodFileURL.path == "/Users/someone/Library/Application Support/agenttacho/last-good.json")
    }

    @Test func demoFolders() {
        let demo = Paths(home: URL(fileURLWithPath: "/Users/someone"), appFolder: "agenttacho-demo")
        #expect(demo.configFileURL.path == "/Users/someone/.config/agenttacho-demo/config.json")
        #expect(demo.importedPricesFileURL.path == "/Users/someone/.config/agenttacho-demo/imported-prices.json")
        #expect(demo.logFileURL.path == "/Users/someone/Library/Logs/agenttacho-demo/usage.log")
        #expect(demo.lastGoodFileURL.path == "/Users/someone/Library/Application Support/agenttacho-demo/last-good.json")
    }

    @Test(arguments: [("~", "/Users/someone"), ("~/.claude", "/Users/someone/.claude"), ("~/.claude/", "/Users/someone/.claude"),
                      ("~/a/b//", "/Users/someone/a/b"), ("/opt/x/", "/opt/x"), ("/", "/"), ("rel/dir", "rel/dir")])
    func expandsTildeAndStripsTrailingSlashes(input: String, expected: String) {
        #expect(paths.expand(input) == expected)
    }

    /// The result is the same whether the folder exists or not: `expand`
    /// only builds a string and never looks at the disk, so the demo build
    /// does not even stat `~/.claude` (spec 024 SC-002, checked with
    /// `fs_usage` in quickstart Q5).
    @Test func expandIgnoresWhatExistsOnDisk() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("paths-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let real = Paths(home: home)
        let missing = real.expand("~/.claude")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude", isDirectory: true), withIntermediateDirectories: true)
        #expect(real.expand("~/.claude") == missing)
        #expect(missing == real.home.path + "/.claude")
    }
}
