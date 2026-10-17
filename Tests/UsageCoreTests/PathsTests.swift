import Foundation
import Testing
@testable import UsageCore

/// AgentTacho's data folders (spec 023 FR-007).
@Suite struct PathsTests {
    let paths = Paths(home: URL(fileURLWithPath: "/Users/someone"))

    @Test func agentTachoFolders() {
        #expect(paths.configFileURL.path == "/Users/someone/.config/agenttacho/config.json")
        #expect(paths.importedPricesFileURL.path == "/Users/someone/.config/agenttacho/imported-prices.json")
        #expect(paths.logFileURL.path == "/Users/someone/Library/Logs/agenttacho/usage.log")
        #expect(paths.lastGoodFileURL.path == "/Users/someone/Library/Application Support/agenttacho/last-good.json")
    }
}
