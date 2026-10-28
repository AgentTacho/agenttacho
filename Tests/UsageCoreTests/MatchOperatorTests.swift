import Foundation
import Testing
@testable import UsageCore

/// spec 038 FR-001 to FR-004, SC-001, research R1: every offered field and
/// literal operator, case ignored in both directions, Unicode case, no
/// diacritics folding, literal metacharacters, blank texts.
@Suite struct MatchOperatorTests {
    private func record(model: String = "claude-opus-5-5", requestId: String = "req_1",
                        messageId: String = "msg_1") -> RawUsageRecord {
        makeRaw(id: messageId, requestId: requestId, model: model)
    }

    private func rule(_ field: MatchField, _ op: MatchOperator, _ text: String) -> MatchCondition {
        MatchCondition(field: field, operator: op, text: text)
    }

    /// A record whose `field` holds `value` (the raw line for Anywhere).
    private func matches(_ field: MatchField, _ op: MatchOperator, _ text: String, value: String) -> Bool {
        switch field {
        case .model: return rule(field, op, text).matches(record: record(model: value), rawLine: "{}")
        case .requestId: return rule(field, op, text).matches(record: record(requestId: value), rawLine: "{}")
        case .messageId: return rule(field, op, text).matches(record: record(messageId: value), rawLine: "{}")
        case .anywhere: return rule(field, op, text).matches(record: record(), rawLine: value)
        }
    }

    /// Every field with starts with (where offered) and contains, with
    /// matching and non-matching values.
    @Test(arguments: MatchField.allCases)
    func literalOperatorsOnEveryField(field: MatchField) {
        if MatchOperator.operators(for: field).contains(.startsWith) {
            #expect(matches(field, .startsWith, "intranet/", value: "intranet/glm-5"))
            #expect(!matches(field, .startsWith, "glm", value: "intranet/glm-5"))
            #expect(!matches(field, .startsWith, "intranet/", value: "gateway-a/intranet/glm-5"))
        }
        #expect(matches(field, .contains, "glm", value: "intranet/glm-5"))
        #expect(matches(field, .contains, "intranet/", value: "intranet/glm-5"))
        #expect(!matches(field, .contains, "gateway-a", value: "intranet/glm-5"))
    }

    /// US1 scenarios 1, 2, 4: case is ignored in both directions.
    @Test(arguments: MatchField.allCases)
    func literalOperatorsIgnoreCase(field: MatchField) {
        if MatchOperator.operators(for: field).contains(.startsWith) {
            #expect(matches(field, .startsWith, "intranet/", value: "INTRANET/glm-5"))
            #expect(matches(field, .startsWith, "INTRANET/", value: "intranet/glm-5"))
        }
        #expect(matches(field, .contains, "glm", value: "intranet/GLM-5-Air"))
        #expect(matches(field, .contains, "GLM", value: "intranet/glm-5"))
        #expect(matches(field, .contains, "gateway.example", value: "https://Gateway.Example/v1"))
    }

    /// FR-004: Unicode case is ignored, diacritics are not.
    @Test func unicodeCaseButNotDiacritics() {
        #expect(matches(.model, .contains, "Ä", value: "intranet/ä-model"))
        #expect(matches(.model, .startsWith, "ä", value: "Ä-model"))
        #expect(!matches(.model, .contains, "a", value: "ä-model"))
        #expect(!matches(.anywhere, .contains, "ä", value: "{\"model\":\"a-model\"}"))
    }

    /// Edge case: regex metacharacters are compared literally.
    @Test func metacharactersAreLiteral() {
        #expect(matches(.model, .contains, "a.b", value: "x-a.b-y"))
        #expect(!matches(.model, .contains, "a.b", value: "x-aXb-y"))
        #expect(!matches(.model, .startsWith, "^intranet", value: "intranet/glm-5"))
        #expect(!matches(.anywhere, .contains, "proj-(alpha|beta)", value: "proj-alpha"))
    }

    /// spec 037 FR-011: a blank text never matches, whatever the operator.
    @Test(arguments: MatchOperator.allCases)
    func blankTextNeverMatches(op: MatchOperator) {
        for field in MatchField.allCases where MatchOperator.operators(for: field).contains(op) {
            #expect(!matches(field, op, "", value: "intranet/glm-5"))
            #expect(!matches(field, op, "  ", value: "intranet/ glm-5"))
        }
    }

    /// FR-002: Anywhere compares the raw record line, not a field.
    @Test func anywhereUsesTheRawLine() {
        let gateway = record(model: "intranet/glm-5")
        let anywhere = rule(.anywhere, .contains, "proj-alpha")
        #expect(anywhere.matches(record: gateway, rawLine: "{\"cwd\":\"/Users/tester/PROJ-ALPHA\"}"))
        #expect(!anywhere.matches(record: gateway, rawLine: "{\"cwd\":\"/Users/tester/proj-beta\"}"))
        #expect(!rule(.anywhere, .contains, "intranet/").matches(record: gateway, rawLine: "{}"))
    }

    /// FR-005: kinds keep their exact, case-sensitive checks.
    @Test func kindsStayCaseSensitive() {
        let vertex = SessionKind.claudeCodeVertex
        #expect(vertex.matches(record: record(requestId: "req_vrtx_1")))
        #expect(!vertex.matches(record: record(requestId: "REQ_VRTX_1")))
    }

    // MARK: - matches regex (spec 038 FR-003 to FR-005, US2, research R2)

    /// US2 scenario 1: anchors work and case is ignored.
    @Test func regexWithAnchorsIgnoresCase() {
        let gateways = rule(.model, .regex, "^gateway-(a|b)/")
        #expect(gateways.matches(record: record(model: "gateway-a/glm-5"), rawLine: "{}"))
        #expect(gateways.matches(record: record(model: "GATEWAY-B/glm-5"), rawLine: "{}"))
        #expect(!gateways.matches(record: record(model: "gateway-c/glm-5"), rawLine: "{}"))
        #expect(!gateways.matches(record: record(model: "intranet/gateway-a/glm-5"), rawLine: "{}"))
        #expect(rule(.model, .regex, "glm-5$").matches(record: record(model: "intranet/GLM-5"), rawLine: "{}"))
        #expect(!rule(.model, .regex, "glm-5$").matches(record: record(model: "intranet/glm-5-air"), rawLine: "{}"))
    }

    /// SC-001, FR-004: matches regex on every field, case ignored in both
    /// directions, Unicode case ignored, diacritics not.
    @Test(arguments: MatchField.allCases)
    func regexOnEveryFieldIgnoresCase(field: MatchField) {
        #expect(matches(field, .regex, "^intranet/", value: "INTRANET/glm-5"))
        #expect(matches(field, .regex, "^INTRANET/", value: "intranet/glm-5"))
        #expect(matches(field, .regex, "GLM-[0-9]", value: "intranet/glm-5"))
        #expect(!matches(field, .regex, "^glm", value: "intranet/glm-5"))
        #expect(matches(field, .regex, "Ä", value: "intranet/ä-model"))
        #expect(!matches(field, .regex, "/a-model", value: "intranet/ä-model"))
    }

    /// US2 scenario 2, FR-003: the pattern is found anywhere unless
    /// anchored.
    @Test func regexSearchesUnanchored() {
        #expect(rule(.requestId, .regex, "vrtx").matches(record: record(requestId: "req_vrtx_123"), rawLine: "{}"))
        #expect(rule(.messageId, .regex, "[0-9]{3}$").matches(record: record(messageId: "chatcmpl-123"), rawLine: "{}"))
        #expect(!rule(.requestId, .regex, "^vrtx").matches(record: record(requestId: "req_vrtx_123"), rawLine: "{}"))
    }

    /// FR-004: an inline option turns case sensitivity back on.
    @Test func inlineOptionRestoresCase() {
        #expect(!rule(.model, .regex, "(?-i)^GLM").matches(record: record(model: "glm-5"), rawLine: "{}"))
        #expect(rule(.model, .regex, "(?-i)^glm").matches(record: record(model: "glm-5"), rawLine: "{}"))
    }

    /// US2 scenario 5: Anywhere searches the raw line.
    @Test func anywhereRegexOnTheRawLine() {
        let provider = rule(.anywhere, .regex, #""provider":"gw-[0-9]+""#)
        #expect(provider.matches(record: record(), rawLine: #"{"provider":"gw-42","model":"intranet/glm-5"}"#))
        #expect(!provider.matches(record: record(), rawLine: #"{"provider":"gw-x","model":"intranet/glm-5"}"#))
    }

    /// FR-005: an invalid pattern never matches.
    @Test func invalidPatternNeverMatches() {
        let invalid = rule(.model, .regex, "^gateway-(a")
        #expect(!invalid.matches(record: record(model: "gateway-(a"), rawLine: "{}"))
        #expect(!invalid.matches(record: record(model: "gateway-a/glm-5"), rawLine: "{}"))
        #expect(!rule(.anywhere, .regex, "[").matches(record: record(), rawLine: "[{}]"))
    }

    /// Edge case: a pattern that matches the empty string matches every
    /// record that has the field, and not one whose field is empty.
    @Test func emptyMatchingPatternNeedsAField() {
        let any = rule(.messageId, .regex, "x*")
        #expect(any.matches(record: record(messageId: "msg_1"), rawLine: "{}"))
        #expect(!any.matches(record: record(messageId: ""), rawLine: "{}"))
        #expect(!rule(.requestId, .regex, "x*").matches(record: record(requestId: ""), rawLine: "{}"))
    }

    /// FR-005, data-model "patternProblem": the footer message for an
    /// invalid regex, nil for every other condition.
    @Test func patternProblemOnlyForInvalidRegex() {
        #expect(rule(.model, .regex, "^gateway-(a").patternProblem == SessionMatchText.invalidPattern)
        #expect(rule(.anywhere, .regex, "proj-(alpha").patternProblem == SessionMatchText.invalidPattern)
        #expect(rule(.model, .regex, "^gateway-(a|b)/").patternProblem == nil)
        #expect(rule(.model, .contains, "^gateway-(a").patternProblem == nil)
        #expect(rule(.model, .startsWith, "(").patternProblem == nil)
        #expect(rule(.model, .regex, "  ").patternProblem == nil)
    }
}
