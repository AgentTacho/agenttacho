import Foundation
import Testing
@testable import UsageCore

/// The Codex reader decodes its relevant lines into typed values, leniently:
/// a field of the wrong type reads as absent, as the dictionary casts did
/// (spec 039 FR-016, FR-011, research R6).
@Suite struct CodexTypedLineTests {
    static func line(_ text: String) -> CodexLine? { CodexLine.decode(Data(text.utf8)) }

    @Test func aWrongTypedFieldReadsAsAbsent() throws {
        let decoded = try #require(Self.line(#"{"timestamp":123,"type":"turn_context","payload":{"type":5,"id":"s-1","cwd":7,"model":["gpt-5.5"]}}"#))
        #expect(decoded.timestamp == nil)
        let payload = try #require(decoded.payload)
        #expect(payload.type == nil)
        #expect(payload.id == "s-1")
        #expect(payload.cwd == nil)
        #expect(payload.model == nil)

        let usage = try #require(Self.line(#"{"timestamp":"2026-10-13T09:00:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":"many","output_tokens":20,"total_tokens":{"x":1}}}}}"#)?
            .payload?.info?.totalTokenUsage)
        #expect(usage.inputTokens == nil)
        #expect(usage.outputTokens == 20)
        #expect(usage.totalTokens == nil)
        let totals = CodexSessionParser.Totals(usage)
        #expect(totals.input == 0)
        #expect(totals.output == 20)
        #expect(totals.total == 0)
    }

    /// A boolean counts as 1 or 0, as `NSNumber` read it before (FR-011).
    @Test func aBooleanNumberReadsAsOneOrZero() throws {
        let usage = try #require(Self.line(#"{"payload":{"info":{"total_token_usage":{"input_tokens":true,"output_tokens":false,"total_tokens":null}}}}"#)?
            .payload?.info?.totalTokenUsage)
        #expect(usage.inputTokens == 1)
        #expect(usage.outputTokens == 0)
        #expect(usage.totalTokens == nil)
        #expect(CodexSessionParser.Totals(usage).input == 1)
        let window = try #require(Self.line(#"{"payload":{"rate_limits":{"primary":{"used_percent":true,"window_minutes":false,"resets_at":"soon"}}}}"#)?
            .payload?.rateLimits?.primary)
        #expect(window.usedPercent == 1)
        #expect(window.windowMinutes == 0)
        #expect(window.resetsAt == nil)
    }

    @Test func aLineThatIsNoObjectDoesNotDecode() {
        #expect(Self.line("not json") == nil)
        #expect(Self.line(#"["payload"]"#) == nil)
        #expect(Self.line(#"{"timestamp":"2026-10-13T09:00:00Z""#) == nil)
    }

    /// The finite, positive and `maxTokenValue` rules of `Totals`.
    @Test func tokenValuesAreClampedAsBefore() {
        let max = Double(CodexSessionParser.maxTokenValue)
        let usage = CodexTokenUsage(inputTokens: max * 4, cachedInputTokens: -5, cacheWriteInputTokens: .infinity,
                                    outputTokens: .nan, reasoningOutputTokens: 12.9, totalTokens: max)
        let totals = CodexSessionParser.Totals(usage)
        #expect(totals.input == CodexSessionParser.maxTokenValue)
        #expect(totals.cached == 0)
        #expect(totals.cacheWrite == 0)
        #expect(totals.output == 0)
        #expect(totals.reasoning == 12)
        #expect(totals.total == CodexSessionParser.maxTokenValue)
        let huge = Self.line(#"{"payload":{"info":{"total_token_usage":{"input_tokens":1e300,"output_tokens":-3}}}}"#)?.payload?.info?.totalTokenUsage
        #expect(huge.map { CodexSessionParser.Totals($0).input } == CodexSessionParser.maxTokenValue)
        #expect(huge.map { CodexSessionParser.Totals($0).output } == 0)
    }

    /// `rate_limit_reached_type` counts when present and not null, whatever
    /// its value.
    @Test func reachedTypeCountsWhenPresentAndNotNull() {
        func reached(_ value: String?) -> Bool? {
            let field = value.map { #","rate_limit_reached_type":\#($0)"# } ?? ""
            return Self.line(#"{"payload":{"type":"token_count","rate_limits":{"limit_id":"codex","plan_type":"plus"\#(field)}}}"#)?
                .payload?.rateLimits?.reached
        }
        #expect(reached(nil) == false)
        #expect(reached("null") == false)
        #expect(reached(#""rate_limit_reached""#) == true)
        #expect(reached(#"{"type":"rate_limit_reached"}"#) == true)
    }

    @Test func rateLimitFieldsAndWindows() throws {
        let limits = try #require(Self.line(#"{"payload":{"rate_limits":{"limit_id":"codex","plan_type":"plus","primary":{"used_percent":25.0,"window_minutes":300,"resets_at":1791999819},"secondary":null}}}"#)?
            .payload?.rateLimits)
        #expect(limits.limitId == "codex")
        #expect(limits.planType == "plus")
        #expect(limits.primary?.usedPercent == 25)
        #expect(limits.primary?.windowMinutes == 300)
        #expect(limits.primary?.resetsAt == 1_791_999_819)
        #expect(limits.secondary == nil)
        let wrong = try #require(Self.line(#"{"payload":{"rate_limits":{"limit_id":7,"plan_type":true,"primary":"x"}}}"#)?.payload?.rateLimits)
        #expect(wrong.limitId == nil)
        #expect(wrong.planType == nil)
        #expect(wrong.primary == nil)
    }

    /// A line without a payload adds nothing to the session.
    @Test func aMissingPayloadSkipsTheLine() throws {
        #expect(Self.line(#"{"timestamp":"2026-10-13T09:00:00Z","type":"event_msg"}"#)?.payload == nil)
        let meta = #"{"timestamp":"2026-10-13T09:00:00.000Z","type":"session_meta","payload":{"id":"s-typed","cwd":"/fixture/x"}}"#
        let noPayload = #"{"timestamp":"2026-10-13T09:00:01.000Z","type":"event_msg","payload_missing":{"type":"token_count","info":{"total_token_usage":{"input_tokens":5,"output_tokens":1,"total_tokens":6}}},"note":"\"type\":\"token_count\""}"#
        let counted = #"{"timestamp":"2026-10-13T09:00:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":5,"output_tokens":1,"total_tokens":6}}}}"#
        let session = CodexSessionParser().parse(data: Data([meta, noPayload, counted].joined(separator: "\n").utf8))
        #expect(session.sessionId == "s-typed")
        #expect(session.records.count == 1)
        #expect(session.records.first?.raw.inputTokens == 5)
    }

    /// The parent session as the dictionary walk found it: a thread spawn's
    /// parent, else the fork's; none for a subagent of another shape.
    @Test func parentSessionFieldsAreReadAsBefore() {
        func parent(_ fields: String) -> String? {
            Self.line(#"{"payload":{"id":"child"\#(fields)}}"#)?.payload?.parent
        }
        #expect(parent(#","source":{"subagent":{"thread_spawn":{"parent_thread_id":"p-1","depth":1}}},"forked_from_id":"f-1""#) == "p-1")
        #expect(parent(#","source":{"subagent":{"thread_spawn":{"depth":1}}},"forked_from_id":"f-1""#) == "f-1")
        #expect(parent(#","source":{"subagent":{"thread_spawn":{"parent_thread_id":""}}},"forked_from_id":"f-1""#) == "f-1")
        #expect(parent(#","source":{"subagent":"review"},"forked_from_id":"f-1""#) == nil)
        #expect(parent(#","source":{"subagent":null},"forked_from_id":"f-1""#) == nil)
        #expect(parent(#","source":{"subagent":{"thread_spawn":null}},"forked_from_id":"f-1""#) == nil)
        #expect(parent(#","source":"cli","forked_from_id":"f-1""#) == "f-1")
        #expect(parent(#","source":{"other":1},"forked_from_id":"f-1""#) == "f-1")
        #expect(parent(#","forked_from_id":"f-1""#) == "f-1")
        #expect(parent(#","forked_from_id":"""#) == nil)
        #expect(parent(#","forked_from_id":null"#) == nil)
        #expect(parent("") == nil)
    }
}
