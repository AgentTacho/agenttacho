import Foundation
import Testing
@testable import UsageCore

/// spec 038 FR-010, FR-011, SC-004, research R6, R7,
/// contracts/configuration.md: the written form and every earlier form.
@Suite struct SessionKindStorageTests {
    /// One token-based account "Lab gateway" with the given keys.
    static func json(_ keys: String) -> String {
        #"""
        { "groups": [ { "id": "grp", "name": "Team", "budgetUSD": 100 } ],
          "accounts": [ { "id": "acc-lab", "type": "tokenBased", "displayName": "Lab gateway", "groupId": "grp", \#(keys) } ] }
        """#
    }

    static func decode(_ json: String) throws -> (settings: TokenBasedSettings, notes: [String], config: Configuration) {
        let notes = ConfigurationLoadNotes()
        let decoder = JSONDecoder()
        decoder.userInfo[ConfigurationLoadNotes.userInfoKey] = notes
        let config = try decoder.decode(Configuration.self, from: Data(json.utf8))
        return (try #require(config.accounts.first?.kind.tokenBased), notes.notes, config)
    }

    /// The first account object of the encoded configuration.
    static func encodedAccount(_ config: Configuration) throws -> [String: Any] {
        let data = try JSONEncoder().encode(config)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let accounts = try #require(object["accounts"] as? [[String: Any]])
        return try #require(accounts.first)
    }

    static func config(_ settings: TokenBasedSettings) -> Configuration {
        Configuration(accounts: [Account(id: "acc-lab", displayName: "Lab gateway", kind: .tokenBased(settings))],
                      groups: [BudgetGroup(id: "grp", name: "Team", budgetUSD: 100)])
    }

    static let glm = MatchCondition(field: .model, operator: .contains, text: "glm")

    // MARK: - Written form

    /// FR-010: every kind with and without a condition round-trips;
    /// `sessionKind` is always written, `condition` only when effective,
    /// never `matchRule`, `provider` or a token-based `customMarker`.
    @Test(arguments: SessionKind.allCases)
    func everyKindRoundTrips(kind: SessionKind) throws {
        for condition in [nil, Self.glm, MatchCondition(field: .anywhere, operator: .regex, text: "proj-(alpha|beta)")] {
            let settings = TokenBasedSettings(groupId: "grp", harness: kind.harness, sessionKind: kind, condition: condition)
            let config = Self.config(settings)
            let account = try Self.encodedAccount(config)
            #expect(account["sessionKind"] as? String == kind.storedValue)
            #expect(account["harness"] as? String == kind.harness.rawValue)
            #expect(account["matchRule"] == nil)
            #expect(account["provider"] == nil)
            #expect(account["customMarker"] == nil)
            if let effective = settings.effectiveCondition {
                let stored = try #require(account["condition"] as? [String: Any])
                #expect(stored["field"] as? String == effective.field.storedValue)
                #expect(stored["operator"] as? String == effective.operator.storedValue)
                #expect(stored["text"] as? String == effective.text)
            } else {
                #expect(account["condition"] == nil)
            }
            let (decoded, notes, _) = try Self.decode(String(decoding: try JSONEncoder().encode(config), as: UTF8.self))
            #expect(notes.isEmpty)
            #expect(decoded.sessionKind == kind)
            #expect(decoded.effectiveCondition == settings.effectiveCondition)
        }
    }

    /// Edge case "Kind change": a Directory only account with a kept
    /// condition writes no `condition`.
    @Test func directoryOnlyWritesNoCondition() throws {
        let settings = TokenBasedSettings(groupId: "grp", sessionKind: .claudeCodeDirectoryOnly, condition: Self.glm)
        let account = try Self.encodedAccount(Self.config(settings))
        #expect(account["sessionKind"] as? String == "directoryOnly")
        #expect(account["condition"] == nil)
    }

    /// `sessionKind` is read together with `harness`.
    @Test func sessionKindIsReadWithTheHarness() throws {
        #expect(try Self.decode(Self.json(#""harness": "openCode", "sessionKind": "vertex""#)).settings.sessionKind == .openCodeVertex)
        #expect(try Self.decode(Self.json(#""harness": "claudeCode", "sessionKind": "vertex""#)).settings.sessionKind == .claudeCodeVertex)
        #expect(try Self.decode(Self.json(#""sessionKind": "otherProvider""#)).settings.sessionKind == .claudeCodeOtherProvider)
        let regex = try Self.decode(Self.json(#""harness": "codex", "sessionKind": "apiKey", "condition": { "field": "model", "operator": "regex", "text": "^model-a" }"#))
        #expect(regex.settings.sessionKind == .codexAPIKey)
        #expect(regex.settings.condition == MatchCondition(field: .model, operator: .regex, text: "^model-a"))
    }

    // MARK: - spec 037/038 `matchRule`

    @Test(arguments: [
        ("claudeCode", "vertex", SessionKind.claudeCodeVertex),
        ("codex", "apiKey", .codexAPIKey),
        ("openCode", "vertex", .openCodeVertex),
        ("openCode", "openai", .openCodeOpenAI),
    ])
    func matchRulePresetBecomesItsKind(harness: String, preset: String, kind: SessionKind) throws {
        let (settings, _, _) = try Self.decode(Self.json(#""harness": "\#(harness)", "matchRule": { "type": "preset", "preset": "\#(preset)" }"#))
        #expect(settings.sessionKind == kind)
        #expect(settings.condition == nil)
    }

    @Test func matchRuleNonePerHarness() throws {
        #expect(try Self.decode(Self.json(#""harness": "claudeCode", "matchRule": { "type": "none" }"#)).settings.sessionKind == .claudeCodeDirectoryOnly)
        #expect(try Self.decode(Self.json(#""harness": "codex", "matchRule": { "type": "none" }"#)).settings.sessionKind == .codexAPIKey)
        let openCode = try Self.decode(Self.json(#""harness": "openCode", "matchRule": { "type": "none" }"#)).settings
        #expect(openCode.sessionKind == .openCodeOtherProvider)
        #expect(openCode.condition == nil)
    }

    @Test(arguments: [
        ("claudeCode", SessionKind.claudeCodeOtherProvider),
        ("codex", .codexAPIKey),
        ("openCode", .openCodeOtherProvider),
    ])
    func matchRuleCustomBecomesAKindWithACondition(harness: String, kind: SessionKind) throws {
        let withOperator = try Self.decode(Self.json(
            #""harness": "\#(harness)", "matchRule": { "type": "custom", "field": "model", "operator": "contains", "text": "glm" }"#)).settings
        #expect(withOperator.sessionKind == kind)
        #expect(withOperator.condition == Self.glm)
        let without = try Self.decode(Self.json(
            #""harness": "\#(harness)", "matchRule": { "type": "custom", "field": "model", "text": "intranet/" }"#)).settings
        #expect(without.condition == MatchCondition(field: .model, operator: .startsWith, text: "intranet/"))
        let anywhere = try Self.decode(Self.json(
            #""harness": "\#(harness)", "matchRule": { "type": "custom", "field": "anywhere", "text": "proj-alpha" }"#)).settings
        #expect(anywhere.condition == MatchCondition(field: .anywhere, operator: .contains, text: "proj-alpha"))
        let startsWithAnywhere = try Self.decode(Self.json(
            #""harness": "\#(harness)", "matchRule": { "type": "custom", "field": "anywhere", "operator": "startsWith", "text": "proj-alpha" }"#)).settings
        #expect(startsWithAnywhere.condition == MatchCondition(field: .anywhere, operator: .contains, text: "proj-alpha"))
    }

    // MARK: - v0.8.0 `provider`

    @Test func providerForms() throws {
        let vertex = try Self.decode(Self.json(#""provider": "vertex""#)).settings
        #expect(vertex.harness == .claudeCode)
        #expect(vertex.sessionKind == .claudeCodeVertex)
        #expect(vertex.condition == nil)
        let none = try Self.decode(Self.json(#""harness": "claudeCode""#)).settings
        #expect(none.sessionKind == .claudeCodeVertex)
        let marked = try Self.decode(Self.json(#""provider": "vertex", "customMarker": "proj-alpha""#))
        #expect(marked.settings.sessionKind == .claudeCodeVertex)
        #expect(marked.settings.condition == MatchCondition(field: .anywhere, operator: .contains, text: "proj-alpha"))
        #expect(marked.config.accounts[0].customMarker == nil)
        let openai = try Self.decode(Self.json(#""provider": "openai""#)).settings
        #expect(openai.harness == .codex)
        #expect(openai.sessionKind == .codexAPIKey)
        #expect(openai.condition == nil)
        let openaiMarked = try Self.decode(Self.json(#""provider": "openai", "customMarker": "proj-alpha""#)).settings
        #expect(openaiMarked.condition == MatchCondition(field: .anywhere, operator: .contains, text: "proj-alpha"))
    }

    /// research R6: `sessionKind` comes before `matchRule`, which comes
    /// before `provider`.
    @Test func precedenceOfTheForms() throws {
        let all = try Self.decode(Self.json(
            #""harness": "claudeCode", "sessionKind": "otherProvider", "matchRule": { "type": "preset", "preset": "vertex" }, "provider": "openai""#)).settings
        #expect(all.sessionKind == .claudeCodeOtherProvider)
        let ruleAndProvider = try Self.decode(Self.json(
            #""harness": "claudeCode", "matchRule": { "type": "none" }, "provider": "openai""#)).settings
        #expect(ruleAndProvider.sessionKind == .claudeCodeDirectoryOnly)
        #expect(ruleAndProvider.harness == .claudeCode)
    }

    // MARK: - Log notes (contracts/configuration.md "Log notes", US5)

    static func unreadable(_ kind: String) -> String {
        #"account "Lab gateway": which sessions count could not be read; it counts \#(kind) until you choose in Settings"#
    }

    /// US5 scenario 1: a v0.8.0 Vertex account with a marker gets one line
    /// with the gateway hint.
    @Test func providerVertexWithMarkerNote() throws {
        let (_, notes, _) = try Self.decode(Self.json(#""provider": "vertex", "customMarker": "proj-alpha""#))
        #expect(notes == [#"account "Lab gateway" migrated from provider vertex to Claude Code, sessions Vertex; its marker became the condition "Anywhere contains proj-alpha" of Vertex sessions, a company gateway needs Other provider"#])
    }

    /// US5 scenario 2: a v0.8.0 OpenAI account, with or without a marker,
    /// gets one line without the hint.
    @Test func providerOpenAINote() throws {
        for keys in [#""provider": "openai""#, #""provider": "openai", "customMarker": "proj-alpha""#] {
            let (_, notes, _) = try Self.decode(Self.json(keys))
            #expect(notes == [#"account "Lab gateway" migrated from provider openai to Codex, sessions API key"#])
        }
        let (_, plain, _) = try Self.decode(Self.json(#""provider": "vertex""#))
        #expect(plain == [#"account "Lab gateway" migrated from provider vertex to Claude Code, sessions Vertex"#])
    }

    /// US5 scenarios 3 to 6: one line per `matchRule` account.
    @Test(arguments: [
        (#""harness": "claudeCode", "matchRule": { "type": "preset", "preset": "vertex" }"#, "match rule migrated to sessions Vertex"),
        (#""harness": "claudeCode", "matchRule": { "type": "none" }"#, "match rule migrated to sessions Directory only"),
        (#""harness": "codex", "matchRule": { "type": "none" }"#, "match rule migrated to sessions API key"),
        (#""harness": "claudeCode", "matchRule": { "type": "custom", "field": "model", "text": "intranet/" }"#,
         "match rule migrated to sessions Other provider with a condition"),
        (#""harness": "codex", "matchRule": { "type": "custom", "field": "model", "operator": "regex", "text": "^model-a" }"#,
         "match rule migrated to sessions API key with a condition"),
        (#""harness": "openCode", "matchRule": { "type": "custom", "field": "anywhere", "text": "proj-alpha" }"#,
         "match rule migrated to sessions Other provider with a condition"),
    ])
    func matchRuleNotes(keys: String, line: String) throws {
        let (_, notes, _) = try Self.decode(Self.json(keys))
        #expect(notes == [#"account "Lab gateway": "# + line])
    }

    /// FR-011: unreadable settings give the harness fallback without a
    /// condition and one note naming it.
    @Test(arguments: [
        ("claudeCode", #""sessionKind": "gateway""#, "Directory only"),
        ("claudeCode", #""sessionKind": "apiKey""#, "Directory only"),
        ("codex", #""sessionKind": "vertex""#, "API key"),
        ("openCode", #""sessionKind": 3"#, "Other provider"),
        ("claudeCode", #""matchRule": { "type": "regex", "text": "x" }"#, "Directory only"),
        ("claudeCode", #""matchRule": { "type": "preset", "preset": "apiKey" }"#, "Directory only"),
        ("openCode", #""matchRule": { "type": "none" }"#, "Other provider"),
        ("codex", #""matchRule": { "type": "custom", "field": "model", "operator": "endsWith", "text": "x" }"#, "API key"),
        ("claudeCode", #""sessionKind": "vertex", "condition": "glm""#, "Directory only"),
        ("claudeCode", #""sessionKind": "vertex", "condition": { "field": "path", "operator": "contains", "text": "x" }"#, "Directory only"),
        ("claudeCode", #""sessionKind": "vertex", "condition": { "field": "model", "operator": "Contains", "text": "x" }"#, "Directory only"),
        ("codex", #""sessionKind": "apiKey", "condition": { "field": "requestId", "operator": "contains", "text": "x" }"#, "API key"),
        ("openCode", #""sessionKind": "openai", "condition": { "field": "model", "operator": "contains", "text": "  " }"#, "Other provider"),
        ("openCode", #""sessionKind": "openai", "condition": { "field": "model", "operator": "contains" }"#, "Other provider"),
    ])
    func unreadableSettingsFallBack(harness: String, keys: String, fallback: String) throws {
        let (settings, notes, config) = try Self.decode(Self.json(#""harness": "\#(harness)", \#(keys)"#))
        #expect(notes == [Self.unreadable(fallback)])
        #expect(settings.sessionKind == SessionKind.fallback(for: settings.harness))
        #expect(settings.harness.rawValue == harness)
        #expect(settings.condition == nil)
        try config.validate()
    }

    /// A condition next to Directory only is ignored with its line and not
    /// kept for a later kind.
    @Test func conditionOnDirectoryOnlyIsIgnored() throws {
        let (settings, notes, _) = try Self.decode(Self.json(
            #""sessionKind": "directoryOnly", "condition": { "field": "model", "operator": "contains", "text": "glm" }"#))
        #expect(notes == [#"condition of account "Lab gateway" does not apply to Directory only, ignored"#])
        #expect(settings.sessionKind == .claudeCodeDirectoryOnly)
        #expect(settings.condition == nil)
    }

    /// Names and markers are clipped like every load note.
    @Test func namesAndMarkersAreClipped() throws {
        let name = String(repeating: "n", count: 40)
        let marker = String(repeating: "m", count: 40)
        let json = Self.json(#""provider": "vertex", "customMarker": "\#(marker)""#).replacingOccurrences(of: "Lab gateway", with: name)
        let (_, notes, _) = try Self.decode(json)
        #expect(notes.count == 1)
        #expect(notes[0].hasPrefix("account \"\(Configuration.clipped(name))\" migrated"))
        #expect(notes[0].contains("\"Anywhere contains \(Configuration.clipped(marker))\""))
        let unreadable = Self.json(#""sessionKind": "x""#).replacingOccurrences(of: "Lab gateway", with: name)
        #expect(try Self.decode(unreadable).notes == ["account \"\(Configuration.clipped(name))\": which sessions count could not be read; it counts Directory only until you choose in Settings"])
    }

    /// US5 scenario 7, SC-004: one file with one account per earlier form
    /// loads with every account's kind, condition and note; the next save
    /// writes the new form only and reloads without a note.
    @Test func oneFileWithEveryEarlierForm() throws {
        let json = #"""
        { "groups": [ { "id": "grp", "name": "Team", "budgetUSD": 100 } ],
          "accounts": [
            { "id": "v8", "type": "tokenBased", "displayName": "V8 Vertex", "provider": "vertex", "groupId": "grp", "customMarker": "proj-alpha" },
            { "id": "v8o", "type": "tokenBased", "displayName": "V8 OpenAI", "provider": "openai", "groupId": "grp" },
            { "id": "p", "type": "tokenBased", "displayName": "Preset", "harness": "openCode", "groupId": "grp", "matchRule": { "type": "preset", "preset": "openai" } },
            { "id": "n", "type": "tokenBased", "displayName": "None", "harness": "claudeCode", "groupId": "grp", "claudeCodeDirectory": "~/.claude-gateway", "matchRule": { "type": "none" } },
            { "id": "c", "type": "tokenBased", "displayName": "Custom", "harness": "claudeCode", "groupId": "grp", "matchRule": { "type": "custom", "field": "model", "text": "intranet/" } },
            { "id": "o", "type": "tokenBased", "displayName": "Operator", "harness": "openCode", "groupId": "grp", "matchRule": { "type": "custom", "field": "model", "operator": "contains", "text": "glm" } },
            { "id": "k", "type": "tokenBased", "displayName": "Kind", "harness": "codex", "groupId": "grp", "sessionKind": "apiKey" }
          ] }
        """#
        let notes = ConfigurationLoadNotes()
        let decoder = JSONDecoder()
        decoder.userInfo[ConfigurationLoadNotes.userInfoKey] = notes
        let config = try decoder.decode(Configuration.self, from: Data(json.utf8))
        func settings(_ id: String) -> TokenBasedSettings? { config.account(id: id)?.kind.tokenBased }
        #expect(settings("v8")?.sessionKind == .claudeCodeVertex)
        #expect(settings("v8")?.condition == MatchCondition(field: .anywhere, operator: .contains, text: "proj-alpha"))
        #expect(settings("v8o")?.sessionKind == .codexAPIKey)
        #expect(settings("p")?.sessionKind == .openCodeOpenAI)
        #expect(settings("n")?.sessionKind == .claudeCodeDirectoryOnly)
        #expect(settings("c")?.sessionKind == .claudeCodeOtherProvider)
        #expect(settings("c")?.condition == MatchCondition(field: .model, operator: .startsWith, text: "intranet/"))
        #expect(settings("o")?.sessionKind == .openCodeOtherProvider)
        #expect(settings("o")?.condition == Self.glm)
        #expect(settings("k")?.sessionKind == .codexAPIKey)
        #expect(notes.notes.count == 6)
        #expect(notes.notes.allSatisfy { !$0.contains("\"Kind\"") })
        let saved = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
        #expect(!saved.contains("matchRule"))
        #expect(!saved.contains("\"provider\""))
        let (reloaded, again) = try TimeFormatConfigurationTests.decodeWithNotes(saved)
        #expect(again.isEmpty)
        #expect(reloaded == config)
    }
}

