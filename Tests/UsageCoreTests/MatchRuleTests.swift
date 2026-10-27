import Foundation
import Testing
@testable import UsageCore

/// spec 037 FR-007, FR-011, data-model "MatchPreset", "MatchField",
/// "MatchRule".
@Suite struct MatchRuleTests {
    private func record(_ harness: Harness = .claudeCode, model: String = "claude-opus-5-5", requestId: String = "",
                        messageId: String = "msg_1", hint: String? = nil) -> RawUsageRecord {
        var r = makeRaw(id: messageId, requestId: requestId, model: model)
        r.harness = harness
        r.providerHint = hint
        return r
    }

    @Test func presetsPerHarnessInOrder() {
        #expect(MatchPreset.presets(for: .claudeCode) == [.claudeCodeVertex])
        #expect(MatchPreset.presets(for: .codex) == [.codexAPIKey])
        #expect(MatchPreset.presets(for: .openCode) == [.openCodeVertex, .openCodeOpenAI])
        for preset in MatchPreset.allCases {
            #expect(MatchPreset.presets(for: preset.harness).contains(preset))
        }
    }

    @Test func fieldsPerHarnessWithAnywhereLast() {
        #expect(MatchField.fields(for: .claudeCode) == [.model, .requestId, .messageId, .anywhere])
        #expect(MatchField.fields(for: .codex) == [.model, .anywhere])
        #expect(MatchField.fields(for: .openCode) == [.model, .anywhere])
    }

    @Test func defaultIsTheFirstPreset() {
        #expect(MatchRule.default(for: .claudeCode) == .preset(.claudeCodeVertex))
        #expect(MatchRule.default(for: .codex) == .preset(.codexAPIKey))
        #expect(MatchRule.default(for: .openCode) == .preset(.openCodeVertex))
    }

    @Test func storedValuesAreReadTogetherWithTheHarness() {
        #expect(MatchPreset.preset(stored: "vertex", harness: .claudeCode) == .claudeCodeVertex)
        #expect(MatchPreset.preset(stored: "vertex", harness: .openCode) == .openCodeVertex)
        #expect(MatchPreset.preset(stored: "openai", harness: .openCode) == .openCodeOpenAI)
        #expect(MatchPreset.preset(stored: "apiKey", harness: .codex) == .codexAPIKey)
        #expect(MatchPreset.preset(stored: "vertex", harness: .codex) == nil)
        #expect(MatchPreset.preset(stored: "apiKey", harness: .claudeCode) == nil)
        #expect(MatchPreset.preset(stored: "Vertex", harness: .claudeCode) == nil)
    }

    @Test func offeredRulesFollowTheHarness() {
        #expect(MatchRule.preset(.claudeCodeVertex).isOffered(for: .claudeCode))
        #expect(!MatchRule.preset(.claudeCodeVertex).isOffered(for: .openCode))
        #expect(MatchRule.preset(.openCodeOpenAI).isOffered(for: .openCode))
        #expect(MatchRule.custom(field: .requestId, text: "req_").isOffered(for: .claudeCode))
        #expect(!MatchRule.custom(field: .requestId, text: "req_").isOffered(for: .codex))
        #expect(!MatchRule.custom(field: .messageId, text: "chatcmpl-").isOffered(for: .openCode))
        #expect(MatchRule.custom(field: .anywhere, text: "proj-alpha").isOffered(for: .openCode))
        #expect(MatchRule.none.isOffered(for: .claudeCode))
        #expect(!MatchRule.none.isOffered(for: .codex))
        #expect(!MatchRule.none.isOffered(for: .openCode))
    }

    /// US2 scenario 2, FR-015: the pop-up items per harness; "None" shows
    /// for Codex and OpenCode only while a dropped rule is selected.
    @Test func popUpChoicesPerHarness() {
        let vertex = MatchRule.preset(.claudeCodeVertex)
        #expect(MatchRule.choices(for: .claudeCode, current: vertex) == [.preset(.claudeCodeVertex), .custom, .none])
        #expect(MatchRule.choices(for: .codex, current: .preset(.codexAPIKey)) == [.preset(.codexAPIKey), .custom])
        #expect(MatchRule.choices(for: .openCode, current: .preset(.openCodeVertex))
                == [.preset(.openCodeVertex), .preset(.openCodeOpenAI), .custom])
        #expect(MatchRule.choices(for: .codex, current: .none) == [.preset(.codexAPIKey), .custom, .none])
        #expect(MatchRule.choices(for: .openCode, current: .none).last == MatchRuleChoice.none)
        #expect(vertex.choice == .preset(.claudeCodeVertex))
        #expect(MatchRule.custom(field: .model, text: "intranet/").choice == .custom)
        #expect(MatchRule.none.choice == MatchRuleChoice.none)
    }

    /// Choosing an item: presets and "None" replace the rule; "Custom"
    /// keeps a custom rule, restores the last one when its field is offered,
    /// and otherwise starts with the harness's first field.
    @Test func choosingAnItem() {
        let custom = MatchRule.custom(field: .requestId, text: "req_gw_")
        #expect(custom.choosing(.preset(.claudeCodeVertex), harness: .claudeCode, lastCustom: nil) == .preset(.claudeCodeVertex))
        #expect(custom.choosing(.none, harness: .claudeCode, lastCustom: nil) == .none)
        #expect(custom.choosing(.custom, harness: .claudeCode, lastCustom: (.model, "x")) == custom)
        let vertex = MatchRule.preset(.claudeCodeVertex)
        #expect(vertex.choosing(.custom, harness: .claudeCode, lastCustom: nil) == .custom(field: .model, text: ""))
        #expect(vertex.choosing(.custom, harness: .claudeCode, lastCustom: (.requestId, "req_gw_")) == custom)
        // A field the harness does not offer falls back to its first field.
        #expect(MatchRule.preset(.codexAPIKey).choosing(.custom, harness: .codex, lastCustom: (.messageId, "chatcmpl-"))
                == .custom(field: .model, text: "chatcmpl-"))
    }

    @Test func presetsUseTheBuiltInDetectionRules() {
        #expect(MatchPreset.claudeCodeVertex.detectionRule == .requestIdPrefix("req_vrtx_"))
        #expect(MatchPreset.codexAPIKey.detectionRule == .providerHint(["apikey"]))
        #expect(MatchPreset.openCodeVertex.detectionRule == .providerHint(["google-vertex", "google-vertex-anthropic"]))
        #expect(MatchPreset.openCodeOpenAI.detectionRule == .providerHint(["openai"]))
    }

    /// FR-008: a preset matches records of its own harness only.
    @Test func presetMatchesItsOwnHarnessOnly() {
        let vertex = MatchRule.preset(.claudeCodeVertex)
        #expect(vertex.matches(record: record(requestId: "req_vrtx_011"), rawLine: "{}"))
        #expect(!vertex.matches(record: record(requestId: "req_011abc"), rawLine: "{}"))
        #expect(!vertex.matches(record: record(.openCode, requestId: "req_vrtx_011", hint: "google-vertex"), rawLine: "{}"))
        let openCodeVertex = MatchRule.preset(.openCodeVertex)
        #expect(openCodeVertex.matches(record: record(.openCode, hint: "google-vertex"), rawLine: "{}"))
        #expect(openCodeVertex.matches(record: record(.openCode, hint: "google-vertex-anthropic"), rawLine: "{}"))
        #expect(!openCodeVertex.matches(record: record(.openCode, hint: "openai"), rawLine: "{}"))
        #expect(!openCodeVertex.matches(record: record(.claudeCode, requestId: "req_vrtx_011"), rawLine: "{}"))
        let apiKey = MatchRule.preset(.codexAPIKey)
        #expect(apiKey.matches(record: record(.codex, hint: "apikey"), rawLine: "{}"))
        #expect(!apiKey.matches(record: record(.codex, hint: "chatgpt"), rawLine: "{}"))
        #expect(!apiKey.matches(record: record(.openCode, hint: "apikey"), rawLine: "{}"))
        #expect(MatchRule.preset(.openCodeOpenAI).matches(record: record(.openCode, hint: "openai"), rawLine: "{}"))
        #expect(!MatchRule.preset(.openCodeOpenAI).matches(record: record(.codex, hint: "openai"), rawLine: "{}"))
    }

    @Test func customFieldsMatchByPrefix() {
        let gateway = record(model: "intranet/glm-5", requestId: "", messageId: "chatcmpl-42")
        #expect(MatchRule.custom(field: .model, text: "intranet/").matches(record: gateway, rawLine: "{}"))
        #expect(!MatchRule.custom(field: .model, text: "glm-5").matches(record: gateway, rawLine: "{}"))
        #expect(MatchRule.custom(field: .messageId, text: "chatcmpl-").matches(record: gateway, rawLine: "{}"))
        #expect(!MatchRule.custom(field: .requestId, text: "req_").matches(record: gateway, rawLine: "{}"))
        #expect(MatchRule.custom(field: .requestId, text: "req_vrtx_").matches(record: record(requestId: "req_vrtx_9"), rawLine: "{}"))
    }

    @Test func anywhereSearchesTheRawLine() {
        let rule = MatchRule.custom(field: .anywhere, text: "proj-alpha")
        #expect(rule.matches(record: record(), rawLine: "{\"cwd\":\"/Users/tester/proj-alpha\"}"))
        #expect(!rule.matches(record: record(), rawLine: "{\"cwd\":\"/Users/tester/proj-beta\"}"))
        #expect(rule.needsRawLine)
        #expect(!MatchRule.custom(field: .model, text: "intranet/").needsRawLine)
        #expect(!MatchRule.preset(.claudeCodeVertex).needsRawLine)
        #expect(!MatchRule.none.needsRawLine)
    }

    /// Clarification: custom texts compare case-sensitively.
    @Test func customTextsAreCaseSensitive() {
        let gateway = record(model: "intranet/glm-5")
        #expect(!MatchRule.custom(field: .model, text: "Intranet/").matches(record: gateway, rawLine: "{}"))
        #expect(!MatchRule.custom(field: .anywhere, text: "PROJ-ALPHA").matches(record: gateway, rawLine: "proj-alpha"))
    }

    @Test func noneNeverMatches() {
        #expect(!MatchRule.none.matches(record: record(requestId: "req_vrtx_1"), rawLine: "req_vrtx_1"))
    }

    /// FR-011: a blank custom text is detected and never matches.
    @Test func blankCustomTextIsDetected() {
        #expect(MatchRule.custom(field: .model, text: "").hasBlankText)
        #expect(MatchRule.custom(field: .anywhere, text: "  \n").hasBlankText)
        #expect(!MatchRule.custom(field: .model, text: "intranet/").hasBlankText)
        #expect(!MatchRule.preset(.claudeCodeVertex).hasBlankText)
        #expect(!MatchRule.none.hasBlankText)
        #expect(!MatchRule.custom(field: .anywhere, text: " ").matches(record: record(), rawLine: "a b"))
        #expect(!MatchRule.custom(field: .model, text: "").matches(record: record(), rawLine: "{}"))
    }
}
