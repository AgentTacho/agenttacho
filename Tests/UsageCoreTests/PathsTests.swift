import Foundation
import Testing
@testable import UsageCore

/// AgentTacho's data folders and AgentMeter's, which are only ever read
/// (spec 023 FR-007, FR-008).
@Suite struct PathsTests {
    let paths = Paths(home: URL(fileURLWithPath: "/Users/someone"))

    @Test func agentTachoFolders() {
        #expect(paths.configDirectoryURL.path == "/Users/someone/.config/agenttacho")
        #expect(paths.configFileURL.path == "/Users/someone/.config/agenttacho/config.json")
        #expect(paths.importedPricesFileURL.path == "/Users/someone/.config/agenttacho/imported-prices.json")
        #expect(paths.logFileURL.path == "/Users/someone/Library/Logs/agenttacho/usage.log")
        #expect(paths.lastGoodFileURL.path == "/Users/someone/Library/Application Support/agenttacho/last-good.json")
    }

    @Test func legacyAgentMeterFiles() {
        #expect(paths.legacyConfigFileURL.path == "/Users/someone/.config/agentmeter/config.json")
        #expect(paths.legacyImportedPricesFileURL.path == "/Users/someone/.config/agentmeter/imported-prices.json")
        #expect(paths.legacyLastGoodFileURL.path == "/Users/someone/Library/Application Support/agentmeter/last-good.json")
        #expect(paths.legacyLogDirectoryURL.path == "/Users/someone/Library/Logs/agentmeter")
    }

    @Test func theConfigurationFileLivesInTheConfigurationFolder() {
        #expect(paths.configFileURL.deletingLastPathComponent().path == paths.configDirectoryURL.path)
        #expect(paths.importedPricesFileURL.deletingLastPathComponent().path == paths.configDirectoryURL.path)
    }
}
