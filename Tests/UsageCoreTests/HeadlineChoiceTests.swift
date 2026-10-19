import Foundation
import Testing
@testable import UsageCore

/// spec 027 FR-010, research R2: the stored form of the headline choice.
@Suite struct HeadlineChoiceTests {
    @Test(arguments: [
        (HeadlineChoice.claudeFiveHour, "fiveHour"),
        (.claudeSevenDay, "sevenDay"),
        (.claudeModel("Fable"), "model:Fable"),
        (.claudeModel("Opus 4.6"), "model:Opus 4.6"),
        (.claudeModel("a:b"), "model:a:b"),
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
        #expect(HeadlineChoice.parse("fiveHour", forCodex: false) == .claudeFiveHour)
        #expect(HeadlineChoice.parse("sevenDay", forCodex: false) == .claudeSevenDay)
        #expect(HeadlineChoice.parse("model:Fable", forCodex: false) == .claudeModel("Fable"))
    }

    @Test func parsesCodexValues() {
        #expect(HeadlineChoice.parse("window:5-hour", forCodex: true) == .codexWindow("5-hour"))
        #expect(HeadlineChoice.parse("window:weekly", forCodex: true) == .codexWindow("weekly"))
        #expect(HeadlineChoice.parse("window:30-day", forCodex: true) == .codexWindow("30-day"))
        #expect(HeadlineChoice.parse("window:2-hour", forCodex: true) == .codexWindow("2-hour"))
    }

    /// Model names keep their case (FR-006).
    @Test func modelNameKeepsCase() {
        #expect(HeadlineChoice.parse("model:fable", forCodex: false) == .claudeModel("fable"))
        #expect(HeadlineChoice.parse("model:fable", forCodex: false) != .claudeModel("Fable"))
    }

    @Test(arguments: ["model:", "FIVEHOUR", "", "fivehour", "window:5-hour", "weekly"])
    func rejectsInvalidClaudeValues(raw: String) {
        #expect(HeadlineChoice.parse(raw, forCodex: false) == nil)
    }

    @Test(arguments: ["window:week", "window:0-hour", "window:", "window:-1-day", "window:5-Hour",
                      "fiveHour", "sevenDay", "model:Fable", "", "5-hour"])
    func rejectsInvalidCodexValues(raw: String) {
        #expect(HeadlineChoice.parse(raw, forCodex: true) == nil)
    }

    @Test func claudeWindowOfEachCase() {
        #expect(HeadlineChoice.claudeFiveHour.claudeWindow == .fiveHour)
        #expect(HeadlineChoice.claudeSevenDay.claudeWindow == .sevenDay)
        #expect(HeadlineChoice.claudeModel("Fable").claudeWindow == .model("Fable"))
        #expect(HeadlineChoice.codexWindow("5-hour").claudeWindow == nil)
    }

    /// The single-value `Codable` conformance the settings types use:
    /// round trip through the stored string, an unknown value throws.
    @Test func codableRoundTrip() throws {
        for choice in [HeadlineChoice.claudeFiveHour, .claudeSevenDay, .claudeModel("Fable"), .codexWindow("5-hour")] {
            let data = try JSONEncoder().encode(choice)
            #expect(String(decoding: data, as: UTF8.self) == "\"\(choice.stored)\"")
            #expect(try JSONDecoder().decode(HeadlineChoice.self, from: data) == choice)
        }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(HeadlineChoice.self, from: Data("\"bogus\"".utf8)) }
    }
}
