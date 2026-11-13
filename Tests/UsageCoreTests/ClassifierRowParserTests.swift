import Foundation
import Testing
@testable import UsageCore

/// spec 045 FR-004, FR-008, FR-009, FR-015: one decision log line becomes a
/// classifier row, a row without usage, or a malformed line.
@Suite struct ClassifierRowParserTests {
    let path = "/fixture/W/.automode_decisions.jsonl"

    func parse(_ line: String, offset: Int = 0) -> ClassifierLineResult {
        ClassifierRowParser.parse(line: Data(line.utf8), offset: offset, logPath: path)
    }

    @Test func contractLineYieldsARow() throws {
        let lines = try Fixtures.lines("classifier/probe-decisions.jsonl")
        guard case .row(let row) = parse(lines[0], offset: 0) else {
            Issue.record("expected a row")
            return
        }
        #expect(row.id == "\(path)#0")
        #expect(row.timestamp == Date(timeIntervalSince1970: 1794505114575.0 / 1000))
        #expect(row.model == "rits/zai-org/glm-5-3")
        #expect(row.inputTokens == 484)
        #expect(row.cacheReadTokens == 34304)
        #expect(row.cacheWrite5mTokens == 0)
        #expect(row.outputTokens == 23)
    }

    /// A counter no classifier call can reach is malformed, so a hostile or
    /// corrupt log cannot overflow the totals and crash every refresh (US4,
    /// FR-004). The limit itself still counts.
    @Test func counterAboveTheLimitIsMalformed() {
        let limit = ClassifierRowParser.maximumCounter
        #expect(parse(#"{"ts":1,"classifierModel":"m","inputTokens":\#(Int.max),"outputTokens":1}"#) == .malformed)
        #expect(parse(#"{"ts":1,"classifierModel":"m","cacheReadInputTokens":\#(limit + 1)}"#) == .malformed)
        guard case .row(let row) = parse(#"{"ts":1,"classifierModel":"m","outputTokens":\#(limit)}"#) else {
            Issue.record("expected a row at the limit")
            return
        }
        #expect(row.outputTokens == limit)
    }

    @Test func idCarriesTheLineOffset() {
        let line = #"{"ts":1794505114575,"classifierModel":"m","inputTokens":1}"#
        guard case .row(let row) = parse(line, offset: 1234) else {
            Issue.record("expected a row")
            return
        }
        #expect(row.id == "\(path)#1234")
    }

    @Test func countersMapAndAbsentOnesCountAsZero() {
        let line = #"{"ts":1000,"classifierModel":"claude-haiku-4-5","cacheCreationInputTokens":7,"outputTokens":3}"#
        guard case .row(let row) = parse(line) else {
            Issue.record("expected a row")
            return
        }
        #expect(row.inputTokens == 0)
        #expect(row.cacheReadTokens == 0)
        #expect(row.cacheWrite5mTokens == 7)
        #expect(row.outputTokens == 3)
        #expect(row.timestamp == Date(timeIntervalSince1970: 1))
    }

    @Test func onlyOneTrailingContextMarkerIsRemoved() {
        func model(_ name: String) -> String? {
            if case .row(let row) = parse(#"{"ts":1,"classifierModel":"\#(name)","outputTokens":1}"#) { return row.model }
            return nil
        }
        #expect(model("rits/zai-org/glm-5-3[1m]") == "rits/zai-org/glm-5-3")
        #expect(model("claude-opus-5-5") == "claude-opus-5-5")
        #expect(model("x[a][1m]") == "x[a]")
    }

    @Test func unknownFieldsAreIgnored() {
        let line = #"{"ts":1,"classifierModel":"m","outputTokens":1,"somethingNew":{"nested":[1,2]},"tool":"Bash"}"#
        guard case .row = parse(line) else {
            Issue.record("expected a row")
            return
        }
    }

    /// FR-015: only `ts`, `classifierModel` and the four counters are decoded;
    /// tool, decision, reason and cost never are.
    @Test func decodesOnlyTheSixFields() {
        #expect(Set(ClassifierRowParser.decodedFieldNames) == [
            "ts", "classifierModel", "inputTokens", "cacheReadInputTokens", "cacheCreationInputTokens", "outputTokens",
        ])
    }

    /// FR-015: nothing of the other fields survives in the parsed result.
    @Test func otherFieldsLeaveNoTraceInTheRow() {
        let line = #"{"ts":1,"classifierModel":"m","outputTokens":1,"tool":"SENTINEL-7f3","decision":"SENTINEL-7f3","reason":"SENTINEL-7f3"}"#
        let result = parse(line)
        guard case .row = result else {
            Issue.record("expected a row")
            return
        }
        #expect(!String(reflecting: result).contains("SENTINEL"))
    }

    // MARK: Skipped lines (US4, FR-004, FR-013)

    /// US4 scenarios 1 and 2: a valid line without a counter above zero.
    @Test func linesWithoutUsageAreToldApart() {
        #expect(parse(#"{"ts":1,"classifierModel":"m","tool":"Read","decision":"allowed"}"#) == .withoutUsage)
        #expect(parse(#"{"ts":1,"classifierModel":"m","inputTokens":0,"cacheReadInputTokens":0,"cacheCreationInputTokens":0,"outputTokens":0}"#)
                == .withoutUsage)
    }

    /// US4 scenario 4 and FR-004: anything else invalid is malformed.
    @Test(arguments: [
        "not json at all",
        #"{"ts":1,"classifierModel":"m","outputTokens":1"#,
        #"[{"ts":1,"classifierModel":"m","outputTokens":1}]"#,
        #"{"classifierModel":"m","outputTokens":1}"#,
        #"{"ts":"1794505114575","classifierModel":"m","outputTokens":1}"#,
        #"{"ts":null,"classifierModel":"m","outputTokens":1}"#,
        #"{"ts":1,"outputTokens":1}"#,
        #"{"ts":1,"classifierModel":"","outputTokens":1}"#,
        #"{"ts":1,"classifierModel":"[1m]","outputTokens":1}"#,
        #"{"ts":1,"classifierModel":7,"outputTokens":1}"#,
        #"{"ts":1,"classifierModel":"m","inputTokens":-1,"outputTokens":1}"#,
        #"{"ts":1,"classifierModel":"m","inputTokens":1.5,"outputTokens":1}"#,
        #"{"ts":1,"classifierModel":"m","inputTokens":"12","outputTokens":1}"#,
        #"{"ts":1,"classifierModel":"m","inputTokens":null,"outputTokens":1}"#,
        #"{"ts":1,"classifierModel":"m","cacheReadInputTokens":-5}"#,
    ])
    func malformedLines(_ line: String) {
        #expect(parse(line) == .malformed)
    }
}
