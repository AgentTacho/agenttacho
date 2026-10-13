import Testing
@testable import UsageCore

@Suite struct SmokeTests {
    @Test func libraryLoads() {
        #expect(UsageCore.version == "0.1.0")
    }
}
