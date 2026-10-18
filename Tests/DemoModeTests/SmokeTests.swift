import Testing
@testable import DemoMode

/// The demo target builds and its tests run with `make test` (spec 024 FR-016).
@Suite struct SmokeTests {
    @Test func demoTargetIsTested() {
        #expect(Bool(true))
    }
}
