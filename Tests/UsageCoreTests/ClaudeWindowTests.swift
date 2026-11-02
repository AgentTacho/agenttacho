import Foundation
import Testing
@testable import UsageCore

/// spec 040 FR-004, research R2: the identity of a Claude window, a
/// string-backed value that the configuration, the threshold state and the
/// burn keys share.
@Suite struct ClaudeWindowTests {
    @Test func rawValues() {
        #expect(ClaudeWindow.fiveHour.rawValue == "fiveHour")
        #expect(ClaudeWindow.sevenDay.rawValue == "sevenDay")
        #expect(ClaudeWindow.model("Fable").rawValue == "model:Fable")
        #expect(ClaudeWindow(rawValue: "limit:daily_all").rawValue == "limit:daily_all")
    }

    @Test func equalityByRawValue() {
        #expect(ClaudeWindow(rawValue: "fiveHour") == .fiveHour)
        #expect(ClaudeWindow(rawValue: "sevenDay") == .sevenDay)
        #expect(ClaudeWindow(rawValue: "model:Fable") == .model("Fable"))
        #expect(ClaudeWindow.model("Fable") != .model("fable"))
        #expect(ClaudeWindow.fiveHour != .sevenDay)
        #expect(Set([ClaudeWindow.model("Fable"), ClaudeWindow(rawValue: "model:Fable")]).count == 1)
    }

}
