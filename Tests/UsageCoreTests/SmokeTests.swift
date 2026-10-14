import Testing
@testable import UsageCore

@Suite struct SmokeTests {
    @Test func libraryLoadsBundledResources() throws {
        _ = try PriceTable.builtIn()
    }
}
