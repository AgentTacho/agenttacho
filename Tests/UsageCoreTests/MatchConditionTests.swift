import Foundation
import Testing
@testable import UsageCore

/// spec 038 FR-004, FR-005, FR-009, FR-014, data-model "MatchField",
/// "MatchOperator", "MatchCondition".
@Suite struct MatchConditionTests {
    private func record(_ harness: Harness = .claudeCode, model: String = "intranet/glm-5", requestId: String = "",
                        messageId: String = "msg_1", hint: String? = nil) -> RawUsageRecord {
        var r = makeRaw(id: messageId, requestId: requestId, model: model)
        r.harness = harness
        r.providerHint = hint
        return r
    }

    private func condition(_ field: MatchField, _ op: MatchOperator, _ text: String) -> MatchCondition {
        MatchCondition(field: field, operator: op, text: text)
    }

    @Test func fieldsPerHarnessWithAnywhereLast() {
        #expect(MatchField.fields(for: .claudeCode) == [.model, .requestId, .messageId, .anywhere])
        #expect(MatchField.fields(for: .codex) == [.model, .anywhere])
        #expect(MatchField.fields(for: .openCode) == [.model, .anywhere])
    }

    /// FR-005: named fields offer all three operators, Anywhere offers
    /// contains and regex only, in pop-up order.
    @Test func operatorsPerField() {
        for field in [MatchField.model, .requestId, .messageId] {
            #expect(MatchOperator.operators(for: field) == [.startsWith, .contains, .regex])
        }
        #expect(MatchOperator.operators(for: .anywhere) == [.contains, .regex])
    }

    /// FR-011: the default operator of a field.
    @Test func defaultOperatorPerField() {
        #expect(MatchOperator.default(for: .model) == .startsWith)
        #expect(MatchOperator.default(for: .requestId) == .startsWith)
        #expect(MatchOperator.default(for: .messageId) == .startsWith)
        #expect(MatchOperator.default(for: .anywhere) == .contains)
        for field in MatchField.allCases {
            #expect(MatchOperator.operators(for: field).contains(MatchOperator.default(for: field)))
        }
    }

    /// FR-010, contracts/configuration.md: the stored values.
    @Test func operatorStoredValues() {
        #expect(MatchOperator.startsWith.storedValue == "startsWith")
        #expect(MatchOperator.contains.storedValue == "contains")
        #expect(MatchOperator.regex.storedValue == "regex")
        #expect(MatchOperator(rawValue: "startsWith") == .startsWith)
        #expect(MatchOperator(rawValue: "StartsWith") == nil)
    }

    /// FR-014: a new condition is Model, starts with, empty text.
    @Test func initialCondition() {
        #expect(MatchCondition.initial == condition(.model, .startsWith, ""))
        #expect(MatchCondition.initial.hasBlankText)
    }

    /// FR-004: a condition is offered only with a field of the harness and
    /// an operator the field offers.
    @Test func offeredConditionsFollowHarnessAndField() {
        #expect(condition(.anywhere, .contains, "proj-alpha").isOffered(for: .claudeCode))
        #expect(condition(.anywhere, .regex, "proj-alpha").isOffered(for: .codex))
        #expect(!condition(.anywhere, .startsWith, "proj-alpha").isOffered(for: .claudeCode))
        #expect(condition(.model, .regex, "^intranet/").isOffered(for: .openCode))
        #expect(condition(.requestId, .startsWith, "req_").isOffered(for: .claudeCode))
        #expect(!condition(.requestId, .startsWith, "req_").isOffered(for: .codex))
        #expect(!condition(.messageId, .startsWith, "chatcmpl-").isOffered(for: .openCode))
    }

    /// FR-014: switching the field keeps the text and the operator when
    /// the new field offers it; starts with on Anywhere becomes contains.
    @Test func withFieldKeepsTextAndFixesTheOperator() {
        let startsWith = condition(.model, .startsWith, "intranet/")
        #expect(startsWith.withField(.anywhere) == condition(.anywhere, .contains, "intranet/"))
        #expect(startsWith.withField(.requestId) == condition(.requestId, .startsWith, "intranet/"))
        let regex = condition(.model, .regex, "^gateway-(a|b)/")
        #expect(regex.withField(.anywhere) == condition(.anywhere, .regex, "^gateway-(a|b)/"))
        #expect(condition(.anywhere, .contains, "proj-alpha").withField(.model) == condition(.model, .contains, "proj-alpha"))
    }

    @Test func namedFieldsMatchByPrefix() {
        let gateway = record(model: "intranet/glm-5", requestId: "", messageId: "chatcmpl-42")
        #expect(condition(.model, .startsWith, "intranet/").matches(record: gateway, rawLine: "{}"))
        #expect(!condition(.model, .startsWith, "glm-5").matches(record: gateway, rawLine: "{}"))
        #expect(condition(.messageId, .startsWith, "chatcmpl-").matches(record: gateway, rawLine: "{}"))
        #expect(!condition(.requestId, .startsWith, "req_").matches(record: gateway, rawLine: "{}"))
        #expect(condition(.requestId, .startsWith, "req_vrtx_").matches(record: record(requestId: "req_vrtx_9"), rawLine: "{}"))
    }

    @Test func anywhereSearchesTheRawLine() {
        let anywhere = condition(.anywhere, .contains, "proj-alpha")
        #expect(anywhere.matches(record: record(), rawLine: "{\"cwd\":\"/Users/tester/proj-alpha\"}"))
        #expect(!anywhere.matches(record: record(), rawLine: "{\"cwd\":\"/Users/tester/proj-beta\"}"))
        #expect(anywhere.needsRawLine)
        #expect(condition(.anywhere, .regex, "proj-").needsRawLine)
        #expect(!condition(.model, .startsWith, "intranet/").needsRawLine)
    }

    /// FR-005: conditions ignore case.
    @Test func conditionsIgnoreCase() {
        let gateway = record(model: "intranet/glm-5")
        #expect(condition(.model, .startsWith, "Intranet/").matches(record: gateway, rawLine: "{}"))
        #expect(condition(.anywhere, .contains, "PROJ-ALPHA").matches(record: gateway, rawLine: "proj-alpha"))
    }

    /// Edge case "Blank condition text": detected and never matches.
    @Test func blankTextIsDetected() {
        #expect(condition(.model, .startsWith, "").hasBlankText)
        #expect(condition(.anywhere, .contains, "  \n").hasBlankText)
        #expect(!condition(.model, .startsWith, "intranet/").hasBlankText)
        #expect(!condition(.anywhere, .contains, " ").matches(record: record(), rawLine: "a b"))
        #expect(!condition(.model, .startsWith, "").matches(record: record(), rawLine: "{}"))
    }

    /// FR-008: the note of an invalid regex; nil for valid patterns,
    /// literal operators and blank texts.
    @Test func patternProblemOnlyForInvalidRegex() {
        #expect(condition(.model, .regex, "^gateway-(a").patternProblem != nil)
        #expect(condition(.model, .regex, "^gateway-(a|b)/").patternProblem == nil)
        #expect(condition(.model, .contains, "^gateway-(a").patternProblem == nil)
        #expect(condition(.model, .regex, "  ").patternProblem == nil)
    }

    /// FR-009: literal texts compare ignoring case, patterns as written.
    @Test func overlapKeyFoldsLiteralTextsOnly() {
        #expect(condition(.model, .contains, "GLM").overlapKey == condition(.model, .contains, "glm").overlapKey)
        #expect(condition(.model, .startsWith, "Intranet/").overlapKey == condition(.model, .startsWith, "intranet/").overlapKey)
        #expect(condition(.model, .regex, "GLM").overlapKey != condition(.model, .regex, "glm").overlapKey)
        #expect(condition(.model, .contains, "glm").overlapKey != condition(.model, .startsWith, "glm").overlapKey)
        #expect(condition(.model, .contains, "glm").overlapKey != condition(.anywhere, .contains, "glm").overlapKey)
    }
}
