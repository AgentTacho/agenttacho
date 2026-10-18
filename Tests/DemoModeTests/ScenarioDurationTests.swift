import Foundation
import Testing
@testable import DemoMode

/// Durations relative to launch (spec 024 FR-011, data-model "Durations").
@Suite struct ScenarioDurationTests {
    @Test(arguments: [
        ("2h10m", 7800.0),
        ("-3d", -259_200.0),
        ("12s", 12.0),
        ("1d2h3m4s", 93_784.0),
        ("-1m", -60.0),
        ("0s", 0.0),
    ])
    func parses(text: String, seconds: TimeInterval) throws {
        #expect(try ScenarioDuration(parsing: text).seconds == seconds)
    }

    @Test(arguments: ["", "2x", "3m2h", "--1d", "-", "h", "2h2h", "1.5h", " 2h", "2h "])
    func rejects(text: String) {
        #expect(throws: ScenarioError.self) { try ScenarioDuration(parsing: text) }
    }
}
