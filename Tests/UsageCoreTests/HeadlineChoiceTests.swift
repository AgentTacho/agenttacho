import Foundation
import Testing
@testable import UsageCore

/// spec 027 FR-010, research R2: the stored form of the headline choice.
@Suite struct HeadlineChoiceTests {
    @Test(arguments: [
        (HeadlineChoice.claude(.fiveHour), "fiveHour"),
        (.claude(.sevenDay), "sevenDay"),
        (.claude(.model("Fable")), "model:Fable"),
        (.claude(.model("Opus 4.6")), "model:Opus 4.6"),
        (.claude(.model("a:b")), "model:a:b"),
        (.claude(ClaudeWindow(rawValue: "model:Fable:daily_scoped")), "model:Fable:daily_scoped"),
        (.claude(ClaudeWindow(rawValue: "limit:daily_all")), "limit:daily_all"),
        (.codexWindow("5-hour"), "window:5-hour"),
        (.codexWindow("weekly"), "window:weekly"),
        (.codexWindow("30-day"), "window:30-day"),
    ])
    func storedRoundTrip(choice: HeadlineChoice, stored: String) {
        #expect(choice.stored == stored)
        let forCodex: Bool
        if case .codexWindow = choice { forCodex = true } else { forCodex = false }
        #expect(HeadlineChoice.parse(stored, forCodex: forCodex) == choice)
    }

    @Test func parsesClaudeValues() {
        #expect(HeadlineChoice.parse("fiveHour", forCodex: false) == .claude(.fiveHour))
        #expect(HeadlineChoice.parse("sevenDay", forCodex: false) == .claude(.sevenDay))
        #expect(HeadlineChoice.parse("model:Fable", forCodex: false) == .claude(.model("Fable")))
    }

    @Test func parsesCodexValues() {
        #expect(HeadlineChoice.parse("window:5-hour", forCodex: true) == .codexWindow("5-hour"))
        #expect(HeadlineChoice.parse("window:weekly", forCodex: true) == .codexWindow("weekly"))
        #expect(HeadlineChoice.parse("window:30-day", forCodex: true) == .codexWindow("30-day"))
        #expect(HeadlineChoice.parse("window:2-hour", forCodex: true) == .codexWindow("2-hour"))
    }

    /// Model names keep their case (FR-006).
    @Test func modelNameKeepsCase() {
        #expect(HeadlineChoice.parse("model:fable", forCodex: false) == .claude(.model("fable")))
        #expect(HeadlineChoice.parse("model:fable", forCodex: false) != .claude(.model("Fable")))
    }

    /// spec 040 FR-015: the values of spec 027 and the new identities.
    @Test func parsesTheNewClaudeIdentities() {
        #expect(HeadlineChoice.parse("limit:daily_all", forCodex: false) == .claude(ClaudeWindow(rawValue: "limit:daily_all")))
        #expect(HeadlineChoice.parse("model:Fable:daily_scoped", forCodex: false)
            == .claude(ClaudeWindow(rawValue: "model:Fable:daily_scoped")))
        #expect(HeadlineChoice.parse("fiveHour", forCodex: false)?.claudeWindow == .fiveHour)
        #expect(HeadlineChoice.parse("sevenDay", forCodex: false)?.claudeWindow == .sevenDay)
        #expect(HeadlineChoice.parse("model:Fable", forCodex: false)?.claudeWindow == .model("Fable"))
    }

    @Test(arguments: ["model:", "limit:", "FIVEHOUR", "", "fivehour", "window:5-hour", "window:weekly", "weekly", "Limit:x"])
    func rejectsInvalidClaudeValues(raw: String) {
        #expect(HeadlineChoice.parse(raw, forCodex: false) == nil)
    }

    @Test(arguments: ["window:week", "window:0-hour", "window:", "window:-1-day", "window:5-Hour",
                      "fiveHour", "sevenDay", "model:Fable", "limit:daily_all", "", "5-hour"])
    func rejectsInvalidCodexValues(raw: String) {
        #expect(HeadlineChoice.parse(raw, forCodex: true) == nil)
    }

    @Test func claudeWindowOfEachCase() {
        #expect(HeadlineChoice.claude(.fiveHour).claudeWindow == .fiveHour)
        #expect(HeadlineChoice.claude(.sevenDay).claudeWindow == .sevenDay)
        #expect(HeadlineChoice.claude(.model("Fable")).claudeWindow == .model("Fable"))
        #expect(HeadlineChoice.claude(ClaudeWindow(rawValue: "limit:daily_all")).claudeWindow == ClaudeWindow(rawValue: "limit:daily_all"))
        #expect(HeadlineChoice.codexWindow("5-hour").claudeWindow == nil)
    }

    /// The single-value `Codable` conformance the settings types use:
    /// round trip through the stored string, an unknown value throws.
    @Test func codableRoundTrip() throws {
        for choice in [HeadlineChoice.claude(.fiveHour), .claude(.sevenDay), .claude(.model("Fable")),
                       .claude(ClaudeWindow(rawValue: "limit:daily_all")), .codexWindow("5-hour")] {
            let data = try JSONEncoder().encode(choice)
            #expect(String(decoding: data, as: UTF8.self) == "\"\(choice.stored)\"")
            #expect(try JSONDecoder().decode(HeadlineChoice.self, from: data) == choice)
        }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(HeadlineChoice.self, from: Data("\"bogus\"".utf8)) }
    }
}
