import Foundation
import Testing
@testable import UsageCore

/// spec 038 FR-001, FR-004, FR-014, edge cases "Kind change" and "Harness
/// change", research R10, data-model "TokenBasedSettings" transitions.
@Suite struct TokenBasedSessionsTests {
    static let glm = MatchCondition(field: .model, operator: .contains, text: "glm")
    static let alpha = MatchCondition(field: .anywhere, operator: .contains, text: "proj-alpha")

    private func settings(_ harness: Harness = .claudeCode, kind: SessionKind? = nil,
                          condition: MatchCondition? = nil) -> TokenBasedSettings {
        TokenBasedSettings(groupId: "grp", harness: harness, sessionKind: kind, condition: condition)
    }

    /// FR-001: a new account has its harness's default kind and no
    /// condition; a kind of another harness is not taken.
    @Test func initDefaults() {
        #expect(settings().sessionKind == .claudeCodeDirectoryOnly)
        #expect(settings(.codex).sessionKind == .codexAPIKey)
        #expect(settings(.openCode).sessionKind == .openCodeVertex)
        #expect(settings().condition == nil)
        #expect(settings(.codex, kind: .openCodeOpenAI).sessionKind == .codexAPIKey)
        #expect(settings(kind: .claudeCodeOtherProvider, condition: Self.glm).condition == Self.glm)
    }

    /// Edge case "Kind change": Directory only hides the condition and
    /// keeps it; it does not count.
    @Test func effectiveConditionHidesDirectoryOnly() {
        #expect(settings(kind: .claudeCodeDirectoryOnly, condition: Self.glm).effectiveCondition == nil)
        #expect(settings(kind: .claudeCodeDirectoryOnly, condition: Self.glm).condition == Self.glm)
        #expect(settings(kind: .claudeCodeVertex, condition: Self.glm).effectiveCondition == Self.glm)
        #expect(settings(.codex, condition: Self.glm).effectiveCondition == Self.glm)
        #expect(settings(kind: .claudeCodeVertex).effectiveCondition == nil)
    }

    /// FR-014, edge case "Kind change": choosing a kind keeps the condition
    /// as it is; Directory only keeps it hidden and the next kind brings it
    /// back.
    @Test func choosingKindKeepsTheCondition() {
        let other = settings(kind: .claudeCodeOtherProvider, condition: Self.glm)
        let directoryOnly = other.choosingKind(.claudeCodeDirectoryOnly, remembered: nil)
        #expect(directoryOnly.sessionKind == .claudeCodeDirectoryOnly)
        #expect(directoryOnly.condition == Self.glm)
        #expect(directoryOnly.effectiveCondition == nil)
        let vertex = directoryOnly.choosingKind(.claudeCodeVertex, remembered: nil)
        #expect(vertex.effectiveCondition == Self.glm)
        // Off stays off.
        let plain = settings(kind: .claudeCodeVertex).choosingKind(.claudeCodeOtherProvider, remembered: Self.glm)
        #expect(plain.condition == nil)
        // A kind of another harness is ignored.
        #expect(plain.choosingKind(.openCodeOpenAI, remembered: nil) == plain)
    }

    /// FR-014: choosing OpenCode Other provider turns the condition on with
    /// the remembered one or the initial one; choosing another kind
    /// afterwards leaves it on.
    @Test func otherProviderTurnsTheConditionOn() {
        let vertex = settings(.openCode, kind: .openCodeVertex)
        let remembered = vertex.choosingKind(.openCodeOtherProvider, remembered: Self.glm)
        #expect(remembered.condition == Self.glm)
        let initial = vertex.choosingKind(.openCodeOtherProvider, remembered: nil)
        #expect(initial.condition == .initial)
        let back = remembered.choosingKind(.openCodeOpenAI, remembered: nil)
        #expect(back.sessionKind == .openCodeOpenAI)
        #expect(back.condition == Self.glm)
        // An existing condition is kept, not replaced by the remembered one.
        let on = settings(.openCode, kind: .openCodeVertex, condition: Self.alpha)
        #expect(on.choosingKind(.openCodeOtherProvider, remembered: Self.glm).condition == Self.alpha)
    }

    /// FR-014: "Only when" on restores the remembered condition or the
    /// initial one; off clears it, except for a kind that requires one.
    @Test func settingConditionOnAndOff() {
        let vertex = settings(kind: .claudeCodeVertex)
        #expect(vertex.settingConditionOn(true, remembered: Self.glm).condition == Self.glm)
        #expect(vertex.settingConditionOn(true, remembered: nil).condition == .initial)
        let on = settings(kind: .claudeCodeVertex, condition: Self.alpha)
        #expect(on.settingConditionOn(true, remembered: Self.glm).condition == Self.alpha)
        #expect(on.settingConditionOn(false, remembered: nil).condition == nil)
        let required = settings(.openCode, kind: .openCodeOtherProvider, condition: Self.glm)
        #expect(required.settingConditionOn(false, remembered: nil).condition == Self.glm)
        #expect(settings(.codex).settingConditionOn(true, remembered: nil).effectiveCondition == .initial)
    }

    /// FR-004, edge case "Harness change": a condition remembered on a
    /// Claude Code account with a field the new harness does not offer
    /// comes back with Model, both for "Only when" and for the condition
    /// OpenCode Other provider turns on; the operator follows the field.
    @Test func rememberedConditionFollowsTheHarness() {
        let requestId = MatchCondition(field: .requestId, operator: .startsWith, text: "req_x")
        let model = MatchCondition(field: .model, operator: .startsWith, text: "req_x")
        #expect(settings(.codex).settingConditionOn(true, remembered: requestId).condition == model)
        #expect(settings(.openCode).choosingKind(.openCodeOtherProvider, remembered: requestId).condition == model)
        let offered = MatchCondition(field: .anywhere, operator: .startsWith, text: "proj-alpha")
        #expect(settings(.codex).settingConditionOn(true, remembered: offered).condition
                == MatchCondition(field: .anywhere, operator: .contains, text: "proj-alpha"))
        // A Claude Code account keeps the remembered field.
        #expect(settings(kind: .claudeCodeVertex).settingConditionOn(true, remembered: requestId).condition == requestId)
    }

    /// FR-004, FR-008: a condition whose field the harness does not offer
    /// is refused on save, as a hand-built draft could hold one.
    @Test func unofferedFieldIsRefusedOnSave() throws {
        var config = Configuration()
        config.groups = [BudgetGroup(id: "grp", name: "Lab", budgetUSD: 60)]
        config.accounts = [Account(id: "c", displayName: "Codex lab", kind: .tokenBased(settings(
            .codex, condition: MatchCondition(field: .requestId, operator: .startsWith, text: "req_x"))))]
        #expect(throws: ConfigurationError.self) { try config.validateForSaving() }
        config.accounts[0].kind = .tokenBased(settings(.codex, condition: MatchCondition(field: .model, operator: .startsWith, text: "gpt-5")))
        try config.validateForSaving()
    }

    /// Edge case "Harness change": directories cleared, the kind becomes
    /// the new harness's default, the condition is kept, a field the
    /// harness does not offer becomes Model.
    @Test func harnessChange() {
        var s = TokenBasedSettings(membership: .group(id: "grp", shownInBar: false), harness: .claudeCode,
                                   sessionKind: .claudeCodeOtherProvider,
                                   condition: MatchCondition(field: .requestId, operator: .regex, text: "^gw-"),
                                   sessionDirectory: "~/.claude-gateway", additionalSessionDirectories: ["~/.claude-lab"])
        s.harness = .codex
        #expect(s.sessionKind == .codexAPIKey)
        #expect(s.enteredSessionDirectory == nil)
        #expect(s.additionalSessionDirectories.isEmpty)
        #expect(s.condition == MatchCondition(field: .model, operator: .regex, text: "^gw-"))
        s.condition = MatchCondition(field: .model, operator: .startsWith, text: "intranet/")
        s.harness = .openCode
        #expect(s.sessionKind == .openCodeVertex)
        #expect(s.condition == MatchCondition(field: .model, operator: .startsWith, text: "intranet/"))
        s.condition = Self.alpha
        s.harness = .claudeCode
        #expect(s.sessionKind == .claudeCodeDirectoryOnly)
        #expect(s.condition == Self.alpha)
        #expect(s.effectiveCondition == nil)
        // Setting the same harness changes nothing.
        var same = settings(kind: .claudeCodeVertex, condition: Self.glm)
        same.harness = .claudeCode
        #expect(same.sessionKind == .claudeCodeVertex)
    }

    /// Edge case "OpenCode Other provider without a condition": the row
    /// shows the initial condition, and writing through it sets one.
    @Test func conditionForEditing() {
        var s = settings(.openCode, kind: .openCodeOtherProvider)
        #expect(s.condition == nil)
        #expect(s.conditionForEditing == .initial)
        s.conditionForEditing.text = "glm"
        #expect(s.condition == MatchCondition(field: .model, operator: .startsWith, text: "glm"))
        #expect(settings(kind: .claudeCodeVertex, condition: Self.glm).conditionForEditing == Self.glm)
    }
}
