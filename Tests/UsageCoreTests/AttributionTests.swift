import Foundation
import Testing
@testable import UsageCore

@Suite struct AttributionTests {
    let paths = Paths(home: URL(fileURLWithPath: "/Users/tester"))

    private func config(subscriptions: [(id: String, dir: String, marker: String?)] = [("acc-max", "~/.claude", nil)],
                        vertex: [(id: String, marker: String?)] = [("acc-vertex", nil)]) -> Configuration {
        var c = Configuration()
        c.accounts = subscriptions.map {
            Account(id: $0.id, displayName: $0.id,
                    kind: .subscription(SubscriptionSettings(credentialDirectory: $0.dir, shownInBar: true, thresholds: [])),
                    customMarker: $0.marker)
        } + vertex.map {
            // A marker of a token-based account is a condition of its Vertex
            // kind, "Anywhere contains" (spec 038 FR-011).
            Account(id: $0.id, displayName: $0.id,
                    kind: .tokenBased(TokenBasedSettings(groupId: "grp", harness: .claudeCode, sessionKind: .claudeCodeVertex,
                                                         condition: $0.marker.map { MatchCondition(field: .anywhere, operator: .contains, text: $0) })))
        }
        if !vertex.isEmpty {
            c.groups = [BudgetGroup(id: "grp", name: "Vertex", budgetUSD: 60)]
        }
        return c
    }

    private func attribute(_ config: Configuration, requestId: String, raw: String = "", directory: String = "/Users/tester/.claude") -> String? {
        let attributor = Attributor(configuration: config, paths: paths)
        let record = makeRaw(requestId: requestId)
        return attributor.accountId(for: record, rawLine: raw.isEmpty ? "{\"requestId\":\"\(requestId)\"}" : raw, fileConfigDirectory: directory)
    }

    @Test func vertexPrefixMapsToVertexAccount() {
        #expect(attribute(config(), requestId: "req_vrtx_011abc") == "acc-vertex")
    }

    @Test func directPrefixMapsToSubscriptionAccount() {
        #expect(attribute(config(), requestId: "req_011CUvtPYGLspKMhcV5rcWvh") == "acc-max")
    }

    @Test func customMarkerMatchesSubstringOfRawLine() throws {
        let c = config(vertex: [("acc-vertex", nil), ("acc-eu", "\"inference_geo\":\"eu\"")])
        let lines = try Fixtures.lines("custom-marker.jsonl")
        let attributor = Attributor(configuration: c, paths: paths)
        let parser = SessionRecordParser()
        let eu = try #require(parser.parse(line: lines[0]))
        let us = try #require(parser.parse(line: lines[1]))
        #expect(attributor.accountId(for: eu, rawLine: lines[0], fileConfigDirectory: "/Users/tester/.claude") == "acc-eu")
        #expect(attributor.accountId(for: us, rawLine: lines[1], fileConfigDirectory: "/Users/tester/.claude") == "acc-vertex")
    }

    @Test func noMatchYieldsUnassigned() {
        #expect(attribute(config(), requestId: "req_bdrk_123") == nil)
        #expect(attribute(config(), requestId: "") == nil)
    }

    @Test func multiMatchYieldsUnassigned() {
        // Two vertex accounts without distinguishing markers both match the prefix.
        let c = config(vertex: [("acc-v1", nil), ("acc-v2", nil)])
        #expect(attribute(c, requestId: "req_vrtx_1") == nil)
        // Two custom markers both present in the line.
        let d = config(vertex: [("acc-a", "alpha"), ("acc-b", "beta")])
        #expect(attribute(d, requestId: "req_vrtx_1", raw: "{\"x\":\"alpha beta\"}") == nil)
    }

    @Test func directoryTieBreakerBetweenSubscriptionAccounts() {
        let c = config(subscriptions: [("acc-max", "~/.claude", nil), ("acc-work", "~/.claude-personal", nil)])
        #expect(attribute(c, requestId: "req_011abc", directory: "/Users/tester/.claude") == "acc-max")
        #expect(attribute(c, requestId: "req_011abc", directory: "/Users/tester/.claude-personal") == "acc-work")
        #expect(attribute(c, requestId: "req_011abc", directory: "/Users/tester/.claude-personal/") == "acc-work")
        // A directory that belongs to neither account cannot decide.
        #expect(attribute(c, requestId: "req_011abc", directory: "/Users/tester/elsewhere") == nil)
    }

    /// Spec 034 FR-006a: a blank subscription directory ties on `~/.claude`.
    @Test func blankSubscriptionDirectoryTiesOnTheDefault() {
        let c = config(subscriptions: [("acc-max", "", nil), ("acc-work", "~/.claude-personal", nil)])
        #expect(attribute(c, requestId: "req_011abc", directory: "/Users/tester/.claude") == "acc-max")
        #expect(attribute(c, requestId: "req_011abc", directory: "/Users/tester/.claude-personal") == "acc-work")
    }

    /// Spec 034 FR-009: a Vertex account's directory adds sessions to read
    /// and changes no rule. A session found there is attributed by its
    /// request id; a direct session found there still needs the
    /// subscription tie-breaker, which a Vertex directory does not join.
    @Test func vertexDirectoryDoesNotChangeAttribution() {
        var c = config(subscriptions: [("acc-max", "~/.claude", nil), ("acc-work", "~/.claude-personal", nil)], vertex: [])
        c.accounts.append(Account(id: "acc-acme", displayName: "Acme",
                                  kind: .tokenBased(TokenBasedSettings(membership: .group(id: "grp", shownInBar: false), harness: .claudeCode,
                                                                       sessionKind: .claudeCodeVertex, sessionDirectory: "~/profiles/acme/claude"))))
        c.groups = [BudgetGroup(id: "grp", name: "Vertex", budgetUSD: 60)]
        let acme = "/Users/tester/profiles/acme/claude"
        #expect(attribute(c, requestId: "req_vrtx_011abc", directory: acme) == "acc-acme")
        #expect(attribute(c, requestId: "req_vrtx_011abc", directory: "/Users/tester/.claude") == "acc-acme")
        // A direct session in the Vertex directory belongs to neither
        // subscription's directory, so the tie stays undecided, as before.
        #expect(attribute(c, requestId: "req_011abc", directory: acme) == nil)
        #expect(attribute(c, requestId: "req_011abc", directory: "/Users/tester/.claude-personal") == "acc-work")
    }

    @Test func noSubscriptionAccountMeansDirectRecordIsUnassigned() {
        let c = config(subscriptions: [])
        #expect(attribute(c, requestId: "req_011abc") == nil)
        #expect(attribute(c, requestId: "req_vrtx_1") == "acc-vertex")
    }

    @Test func customMarkerOnSubscriptionAccountReplacesBuiltInRule() {
        let c = config(subscriptions: [("acc-max", "~/.claude", "\"version\":\"9.9\"")])
        #expect(attribute(c, requestId: "req_011abc") == nil)
        #expect(attribute(c, requestId: "req_011abc", raw: "{\"version\":\"9.9\",\"requestId\":\"req_011abc\"}") == "acc-max")
    }
}

// MARK: - Spec 006: harness-aware attribution (FR-011 to FR-015, research R5)

@Suite struct HarnessAttributionTests {
    let paths = Paths(home: URL(fileURLWithPath: "/Users/tester"))

    /// Claude Max, Vertex (group), OpenAI (own budget) and the given Codex
    /// subscription accounts.
    private func config(codex: [(id: String, home: String)] = [("acc-codex", "~/.codex")],
                        openai: Bool = true, markers: [String: String] = [:]) -> Configuration {
        var c = Configuration()
        c.accounts = [
            Account(id: "acc-max", displayName: "Max",
                    kind: .subscription(SubscriptionSettings(credentialDirectory: "~/.claude")), customMarker: markers["acc-max"]),
            Account(id: "acc-vertex", displayName: "Vertex",
                    kind: .tokenBased(TokenBasedSettings(groupId: "grp", harness: .claudeCode, sessionKind: .claudeCodeVertex,
                                                         condition: markers["acc-vertex"].map { MatchCondition(field: .anywhere, operator: .contains, text: $0) }))),
            // Since spec 037 an account has one harness: OpenCode usage
            // needs its own accounts (FR-008).
            Account(id: "acc-oc-vertex", displayName: "OpenCode Vertex",
                    kind: .tokenBased(TokenBasedSettings(groupId: "grp", harness: .openCode))),
        ]
        if openai {
            c.accounts.append(Account(id: "acc-oai", displayName: "OpenAI",
                                      kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 50)), harness: .codex,
                                                                           condition: markers["acc-oai"].map { MatchCondition(field: .anywhere, operator: .contains, text: $0) }))))
            c.accounts.append(Account(id: "acc-oc-oai", displayName: "OpenCode OpenAI",
                                      kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 50)), harness: .openCode,
                                                                           sessionKind: .openCodeOpenAI))))
        }
        c.accounts += codex.map {
            Account(id: $0.id, displayName: $0.id, kind: .codexSubscription(CodexSubscriptionSettings(codexHome: $0.home)),
                    customMarker: markers[$0.id])
        }
        c.groups = [BudgetGroup(id: "grp", name: "Vertex", budgetUSD: 60)]
        return c
    }

    private func raw(_ harness: Harness, hint: String?, requestId: String = "") -> RawUsageRecord {
        var r = makeRaw(requestId: requestId)
        r.harness = harness
        r.providerHint = hint
        return r
    }

    private func attribute(_ c: Configuration, _ record: RawUsageRecord, line: String = "{}",
                           directory: String = "/Users/tester/.codex") -> String? {
        Attributor(configuration: c, paths: paths).accountId(for: record, rawLine: line, fileConfigDirectory: directory)
    }

    @Test func openCodeProvidersMapByProviderID() {
        let c = config()
        let dir = "/Users/tester/.local/share/opencode"
        #expect(attribute(c, raw(.openCode, hint: "google-vertex"), directory: dir) == "acc-oc-vertex")
        #expect(attribute(c, raw(.openCode, hint: "google-vertex-anthropic"), directory: dir) == "acc-oc-vertex")
        #expect(attribute(c, raw(.openCode, hint: "openai"), directory: dir) == "acc-oc-oai")
        #expect(attribute(c, raw(.openCode, hint: "anthropic"), directory: dir) == nil)
        #expect(attribute(c, raw(.openCode, hint: "litellm"), directory: dir) == nil)
        #expect(attribute(c, raw(.openCode, hint: nil), directory: dir) == nil)
    }

    /// spec 037 FR-008: a Claude Code Vertex account no longer counts
    /// OpenCode records, nor a Codex API-key account OpenCode records on
    /// OpenAI; without OpenCode accounts they stay Unassigned.
    @Test func presetsMatchTheirOwnHarnessOnly() {
        var c = config()
        c.accounts.removeAll { $0.id.hasPrefix("acc-oc-") }
        let dir = "/Users/tester/.local/share/opencode"
        #expect(attribute(c, raw(.openCode, hint: "google-vertex"), directory: dir) == nil)
        #expect(attribute(c, raw(.openCode, hint: "openai"), directory: dir) == nil)
        // A condition is scoped to its kind's harness too.
        c.accounts[1].kind = .tokenBased(TokenBasedSettings(groupId: "grp", harness: .claudeCode, sessionKind: .claudeCodeVertex,
                                                            condition: MatchCondition(field: .anywhere, operator: .contains, text: "proj-alpha")))
        #expect(attribute(c, raw(.openCode, hint: "google-vertex"), line: "{\"x\":\"proj-alpha\"}", directory: dir) == nil)
        #expect(attribute(c, raw(.claudeCode, hint: nil, requestId: "req_vrtx_1"), line: "{\"x\":\"proj-alpha\"}",
                          directory: "/Users/tester/.claude") == "acc-vertex")
    }

    @Test func codexAuthModeMapsToOpenAIOrCodexSubscription() {
        let c = config()
        #expect(attribute(c, raw(.codex, hint: "apikey")) == "acc-oai")
        #expect(attribute(c, raw(.codex, hint: "chatgpt")) == "acc-codex")
        // Without the matching account the record is Unassigned.
        #expect(attribute(config(openai: false), raw(.codex, hint: "apikey")) == nil)
        #expect(attribute(config(codex: []), raw(.codex, hint: "chatgpt")) == nil)
    }

    /// Spec 034 FR-006a: a blank Codex home ties on `~/.codex`.
    @Test func blankCodexHomeTiesOnTheDefault() {
        let c = config(codex: [("acc-plus", ""), ("acc-pro", "~/.codex-lab")])
        #expect(attribute(c, raw(.codex, hint: "chatgpt"), directory: "/Users/tester/.codex") == "acc-plus")
        #expect(attribute(c, raw(.codex, hint: "chatgpt"), directory: "/Users/tester/.codex-lab") == "acc-pro")
    }

    @Test func codexHomeSeparatesCodexSubscriptions() {
        let c = config(codex: [("acc-home", "~/.codex"), ("acc-work", "~/.codex-work")])
        #expect(attribute(c, raw(.codex, hint: "chatgpt"), directory: "/Users/tester/.codex") == "acc-home")
        #expect(attribute(c, raw(.codex, hint: "chatgpt"), directory: "/Users/tester/.codex-work") == "acc-work")
        #expect(attribute(c, raw(.codex, hint: "chatgpt"), directory: "/Users/tester/elsewhere") == nil)
    }

    /// spec 038 FR-006: a subscription's marker only decides among its own
    /// kind of records, so Codex and OpenCode records that contain it stay
    /// with their accounts (spec 006 FR-013 let it claim every harness).
    @Test func customMarkerNarrowsItsOwnKindOnly() {
        let c = config(markers: ["acc-max": "\"cwd\":\"/Users/tester/private\""])
        let codexLine = "{\"type\":\"session_meta\",\"payload\":{\"cwd\":\"/Users/tester/private\"}}\n{\"type\":\"event_msg\"}"
        #expect(attribute(c, raw(.codex, hint: "apikey"), line: codexLine) == "acc-oai")
        let openCodeLine = "{\"role\":\"assistant\",\"providerID\":\"google-vertex\",\"path\":{\"cwd\":\"/Users/tester/private\"}}"
        #expect(attribute(c, raw(.openCode, hint: "google-vertex"), line: openCodeLine,
                          directory: "/Users/tester/.local/share/opencode") == "acc-oc-vertex")
        #expect(attribute(c, raw(.claudeCode, hint: nil, requestId: "req_011abc"), line: "{\"cwd\":\"/Users/tester/private\"}",
                          directory: "/Users/tester/.claude") == "acc-max")
    }

    @Test func claudeCodeResultsAreUnchanged() {
        let c = config()
        let dir = "/Users/tester/.claude"
        #expect(attribute(c, raw(.claudeCode, hint: nil, requestId: "req_vrtx_011"), directory: dir) == "acc-vertex")
        #expect(attribute(c, raw(.claudeCode, hint: nil, requestId: "req_011abc"), directory: dir) == "acc-max")
        #expect(attribute(c, raw(.claudeCode, hint: nil, requestId: "req_bdrk_1"), directory: dir) == nil)
        // A Claude Code record never matches an OpenAI or Codex subscription account.
        let onlyNew = Configuration(accounts: [
            Account(id: "acc-oai", displayName: "OpenAI",
                    kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 5)), harness: .codex))),
            Account(id: "acc-codex", displayName: "Codex", kind: .codexSubscription(CodexSubscriptionSettings())),
        ])
        #expect(attribute(onlyNew, raw(.claudeCode, hint: nil, requestId: "req_011abc"), directory: dir) == nil)
        #expect(attribute(onlyNew, raw(.claudeCode, hint: nil, requestId: "req_vrtx_1"), directory: dir) == nil)
    }

    @Test func otherHarnessesNeverMatchClaudeSubscriptions() {
        let c = config(codex: [])
        #expect(attribute(c, raw(.codex, hint: "chatgpt", requestId: "req_011abc"), directory: "/Users/tester/.claude") == nil)
        #expect(attribute(c, raw(.openCode, hint: "anthropic", requestId: "req_011abc"), directory: "/Users/tester/.claude") == nil)
    }

    @Test func fingerprintChangesWithCodexSubscription() {
        let without = Attributor(configuration: config(codex: []), paths: paths).fingerprint
        let with = Attributor(configuration: config(), paths: paths).fingerprint
        let otherHome = Attributor(configuration: config(codex: [("acc-codex", "~/.codex-work")]), paths: paths).fingerprint
        #expect(without != with)
        #expect(with != otherHome)
    }
}

/// spec 035 FR-011, FR-012, research R5, contracts/directory-resolution.md
/// "Tie-breaker": additional directories rank below main directories.
@Suite struct AdditionalDirectoryAttributionTests {
    let paths = Paths(home: URL(fileURLWithPath: "/Users/tester"))
    typealias Make = AdditionalSessionDirectoryTests

    private func attribute(_ config: Configuration, _ record: RawUsageRecord, directory: String,
                           additional: [String: Set<String>], line: String = "{}") -> String? {
        Attributor(configuration: config, paths: paths, additionalDirectories: additional)
            .accountId(for: record, rawLine: line, fileConfigDirectory: directory)
    }

    private func claudeRecord(_ requestId: String = "req_011abc") -> RawUsageRecord {
        makeRaw(requestId: requestId)
    }

    private func codexRecord(_ hint: String) -> RawUsageRecord {
        var r = makeRaw(requestId: "")
        r.harness = .codex
        r.providerHint = hint
        return r
    }

    /// The account whose main directory it is wins over one that lists it.
    @Test func mainBeatsAdditional() {
        let c = Make.config([Make.claude("max", "~/.claude", extra: ["~/.claude-lab"]), Make.claude("lab", "~/.claude-lab")])
        let additional = ["max": Set(["/Users/tester/.claude-lab"])]
        #expect(attribute(c, claudeRecord(), directory: "/Users/tester/.claude-lab", additional: additional) == "lab")
        #expect(attribute(c, claudeRecord(), directory: "/Users/tester/.claude", additional: additional) == "max")
    }

    /// Exactly one additional claim decides when no main directory does.
    @Test func oneAdditionalClaimWins() {
        let c = Make.config([Make.claude("max", "~/.claude", extra: ["~/agent-sessions/openshell/*/claude"]),
                             Make.claude("pro", "~/.claude-pro")])
        let box = "/Users/tester/agent-sessions/openshell/alpha/claude"
        let additional = ["max": Set([box])]
        #expect(attribute(c, claudeRecord(), directory: box, additional: additional) == "max")
        #expect(attribute(c, claudeRecord(), directory: box + "/", additional: additional) == "max")
        #expect(attribute(c, claudeRecord(), directory: "/Users/tester/elsewhere", additional: additional) == nil)
        // Codex subscriptions follow the same rule.
        let codex = Make.config([Make.codex("plus", "~/.codex-lab", extra: ["~/.codex"]), Make.codex("pro", "~/.codex-pro")])
        #expect(attribute(codex, codexRecord("chatgpt"), directory: "/Users/tester/.codex",
                          additional: ["plus": ["/Users/tester/.codex"]]) == "plus")
    }

    /// Two additional claims of the same rank leave the session Unassigned.
    @Test func twoAdditionalClaimsStayUnassigned() {
        let c = Make.config([Make.claude("max", "~/.claude", extra: ["~/.claude-lab"]),
                             Make.claude("pro", "~/.claude-pro", extra: ["~/.claude-lab"])])
        let lab = "/Users/tester/.claude-lab"
        #expect(attribute(c, claudeRecord(), directory: lab, additional: ["max": [lab], "pro": [lab]]) == nil)
    }

    /// Listing a directory never forces its sessions onto the account: the
    /// request id, the provider hint and custom markers still decide.
    @Test func listingDoesNotForceAttribution() {
        let c = Make.config([Make.claude("max", "~/.claude", extra: ["~/.claude-lab"]),
                             Make.token("vertex", .claudeCode),
                             Make.codex("plus", "~/.codex", extra: ["~/.codex-lab"]),
                             Make.token("openai", .codex)])
        let lab = "/Users/tester/.claude-lab"
        let additional = ["max": Set([lab]), "plus": ["/Users/tester/.codex-lab"]]
        #expect(attribute(c, claudeRecord("req_vrtx_011"), directory: lab, additional: additional) == "vertex")
        #expect(attribute(c, claudeRecord("req_bdrk_1"), directory: lab, additional: additional) == nil)
        #expect(attribute(c, codexRecord("apikey"), directory: "/Users/tester/.codex-lab", additional: additional) == "openai")
        // A condition never widens its kind: a direct record that contains
        // the text stays the subscription's (spec 038 FR-004).
        var marked = c
        marked.accounts[1].kind = .tokenBased(TokenBasedSettings(membership: .group(id: "grp", shownInBar: false),
                                                                 sessionKind: .claudeCodeVertex,
                                                                 condition: MatchCondition(field: .anywhere, operator: .contains, text: "acme-marker")))
        #expect(attribute(marked, claudeRecord(), directory: lab, additional: additional, line: "{\"x\":\"acme-marker\"}") == "max")
        #expect(attribute(marked, claudeRecord("req_vrtx_011"), directory: lab, additional: additional, line: "{\"x\":\"acme-marker\"}") == "vertex")
    }

    /// Two main claims stay Unassigned even when a third account lists the
    /// directory: an additional claim only counts without any main claim.
    @Test func twoMainClaimsStayUnassignedDespiteOneAdditional() {
        let c = Make.config([Make.claude("a", "~/.claude-lab"), Make.claude("b", "~/.claude-lab"),
                             Make.claude("c", "~/.claude", extra: ["~/.claude-lab"])])
        let lab = "/Users/tester/.claude-lab"
        #expect(attribute(c, claudeRecord(), directory: lab, additional: ["c": [lab]]) == nil)
    }

    /// Neither the entries nor their matches are in the fingerprint, so a
    /// new sandbox folder or an edited list never rereads the whole index;
    /// the claim key per directory changes instead (spec 035 FR-012).
    @Test func fingerprintIgnoresAdditionalDirectories() {
        let base = Make.config([Make.claude("max", extra: ["~/agent-sessions/openshell/*/claude"])])
        let one = Attributor(configuration: base, paths: paths, additionalDirectories: ["max": ["/Users/tester/a"]]).fingerprint
        let two = Attributor(configuration: base, paths: paths,
                             additionalDirectories: ["max": ["/Users/tester/a", "/Users/tester/b"]]).fingerprint
        #expect(one == two)
        let added = Make.config([Make.claude("max", extra: ["~/agent-sessions/openshell/*/claude", "~/.claude-lab"])])
        #expect(Attributor(configuration: added, paths: paths).fingerprint == one)
        let other = Make.config([Make.claude("max", "~/.claude-pro")])
        #expect(Attributor(configuration: other, paths: paths).fingerprint != one)
    }

    /// The claim key names the accounts that could use an additional claim
    /// on a directory in the tie-breaker; a single account of a kind never
    /// needs one.
    @Test func claimKeyFollowsTieBreakClaims() {
        let box = "/Users/tester/agent-sessions/openshell/alpha/claude"
        let single = Make.config([Make.claude("max", extra: ["~/agent-sessions/openshell/*/claude"])])
        #expect(Attributor(configuration: single, paths: paths, additionalDirectories: ["max": [box]])
            .claimKey(forDirectory: box) == "")
        let two = Make.config([Make.claude("max", extra: ["~/agent-sessions/openshell/*/claude"]),
                               Make.claude("pro", "~/.claude-pro", extra: ["~/agent-sessions/openshell/*/claude"])])
        #expect(Attributor(configuration: two, paths: paths, additionalDirectories: ["max": [box]])
            .claimKey(forDirectory: box) == "max")
        #expect(Attributor(configuration: two, paths: paths, additionalDirectories: ["max": [box], "pro": [box]])
            .claimKey(forDirectory: box + "/") == "max,pro")
        #expect(Attributor(configuration: two, paths: paths, additionalDirectories: ["max": [box]])
            .claimKey(forDirectory: "/Users/tester/elsewhere") == "")
    }
}

// MARK: - Spec 037: profile step

/// spec 037 FR-003, FR-005, FR-008, US1 scenarios 1 to 4 and 7: the
/// configuration directory a session ran under decides before the rules.
@Suite struct ProfileAttributionTests {
    let paths = Paths(home: URL(fileURLWithPath: "/Users/tester"))
    static let personal = "/Users/tester/agent-profiles/personal/claude"
    static let work = "/Users/tester/agent-profiles/work/claude"
    static let lab = "/Users/tester/agent-profiles/lab/claude"

    static func subscription(_ id: String, _ dir: String) -> Account {
        Account(id: id, displayName: id, kind: .subscription(SubscriptionSettings(credentialDirectory: dir)))
    }

    /// A token-based account; without a kind, Claude Code accounts are
    /// Vertex and the others have their harness's default kind.
    static func token(_ id: String, _ dir: String?, kind: SessionKind? = nil, condition: MatchCondition? = nil,
                      harness: Harness = .claudeCode, extra: [String] = []) -> Account {
        let resolved = kind ?? (harness == .claudeCode ? .claudeCodeVertex : SessionKind.default(for: harness))
        return Account(id: id, displayName: id,
                       kind: .tokenBased(TokenBasedSettings(membership: .group(id: "grp", shownInBar: false), harness: harness,
                                                            sessionKind: resolved, condition: condition,
                                                            sessionDirectory: dir, additionalSessionDirectories: extra)))
    }

    /// A condition on Model, for brevity.
    static func model(_ op: MatchOperator, _ text: String) -> MatchCondition {
        MatchCondition(field: .model, operator: op, text: text)
    }

    static func config(_ accounts: [Account]) -> Configuration {
        Configuration(accounts: accounts, groups: [BudgetGroup(id: "grp", name: "Team", budgetUSD: 100)])
    }

    /// The reported setup: Max on the personal profile, Vertex on work, the
    /// gateway as Directory only on lab.
    static let threeProfiles = config([
        subscription("max", "~/agent-profiles/personal/claude"),
        token("vertex", "~/agent-profiles/work/claude"),
        token("lab", "~/agent-profiles/lab/claude", kind: .claudeCodeDirectoryOnly),
    ])

    private func record(requestId: String = "", model: String = "claude-opus-5-5", messageId: String = "msg_1",
                        harness: Harness = .claudeCode, hint: String? = nil) -> RawUsageRecord {
        var r = makeRaw(id: messageId, requestId: requestId, model: model)
        r.harness = harness
        r.providerHint = hint
        return r
    }

    private func attribute(_ config: Configuration, _ record: RawUsageRecord, profile: String?,
                           directory: String = "/Users/tester/.claude", line: String = "{}",
                           additional: [String: Set<String>] = [:], profileAdditional: [String: Set<String>] = [:]) -> String? {
        Attributor(configuration: config, paths: paths, additionalDirectories: additional,
                   profileAdditionalDirectories: profileAdditional)
            .accountId(for: record, rawLine: line, fileConfigDirectory: directory, profileDirectory: profile)
    }

    /// US1 scenario 1: every record of a profile's file counts for its
    /// account, whatever its request id, message id or model.
    @Test func profileDecidesWhateverTheRecordSays() {
        let c = Self.threeProfiles
        for r in [record(requestId: "req_vrtx_1"), record(requestId: "req_011abc"), record(model: "intranet/glm-5", messageId: "chatcmpl-1"),
                  record(requestId: "req_bdrk_1")] {
            #expect(attribute(c, r, profile: Self.work) == "vertex")
            #expect(attribute(c, r, profile: Self.lab) == "lab")
            #expect(attribute(c, r, profile: Self.personal) == "max")
        }
    }

    /// US1 scenario 2: two Vertex accounts on different profiles each count
    /// their own records.
    @Test func twoVertexAccountsOnDifferentProfiles() {
        let c = Self.config([Self.token("work", "~/agent-profiles/work/claude"), Self.token("lab", "~/agent-profiles/lab/claude")])
        #expect(attribute(c, record(requestId: "req_vrtx_1"), profile: Self.work) == "work")
        #expect(attribute(c, record(requestId: "req_vrtx_1"), profile: Self.lab) == "lab")
        // Without a profile signal the same rule ties (spec edge case).
        #expect(attribute(c, record(requestId: "req_vrtx_1"), profile: nil) == nil)
    }

    /// US1 scenarios 3 and 4: gateway and Vertex records in the lab file
    /// count for lab; Vertex records in the personal profile count for the
    /// subscription.
    @Test func profileBeatsTheRule() {
        let c = Self.threeProfiles
        #expect(attribute(c, record(model: "intranet/glm-5", messageId: "chatcmpl-9"), profile: Self.lab) == "lab")
        #expect(attribute(c, record(requestId: "req_vrtx_1"), profile: Self.lab) == "lab")
        #expect(attribute(c, record(requestId: "req_vrtx_1"), profile: Self.personal) == "max")
        // Without a profile, the kinds decide: the lab account is Directory only.
        #expect(attribute(c, record(requestId: "req_vrtx_1"), profile: nil) == "vertex")
        #expect(attribute(c, record(model: "intranet/glm-5", messageId: "chatcmpl-9"), profile: nil) == nil)
    }

    /// US1 scenario 7: a subscription and a Vertex account share
    /// `~/.claude`; only they compete for its records, not the Vertex
    /// account on another profile.
    @Test func sharedDirectoryRestrictsTheRulesToItsAccounts() {
        let c = Self.config([Self.subscription("max", ""), Self.token("vertex", nil),
                             Self.token("work", "~/agent-profiles/work/claude")])
        let home = "/Users/tester/.claude"
        #expect(attribute(c, record(requestId: "req_vrtx_1"), profile: home) == "vertex")
        #expect(attribute(c, record(requestId: "req_011abc"), profile: home) == "max")
        #expect(attribute(c, record(requestId: "req_bdrk_1"), profile: home) == nil)
        #expect(attribute(c, record(requestId: "req_vrtx_1"), profile: Self.work) == "work")
    }

    /// A profile that belongs to no account leaves the rules to decide,
    /// among all accounts (spec edge case).
    @Test func unknownProfileFallsBackToTheRules() {
        let c = Self.threeProfiles
        #expect(attribute(c, record(requestId: "req_vrtx_1"), profile: "/sandbox/.claude") == "vertex")
        #expect(attribute(c, record(requestId: "req_011abc"), profile: "/sandbox/.claude") == "max")
    }

    /// An additional directory of a token-based account claims a profile
    /// when no main directory does, literal or by wildcard match (spec 037
    /// FR-003, spec 035 ranking).
    @Test func additionalDirectoryOfATokenAccountClaimsTheProfile() {
        let box = "/Users/tester/agent-sessions/openshell/alpha/claude"
        let c = Self.config([Self.subscription("max", "~/.claude"),
                             Self.token("vertex", nil, extra: ["~/.claude-lab", "~/agent-sessions/openshell/*/claude"]),
                             Self.token("lab", "~/agent-profiles/lab/claude", kind: .claudeCodeDirectoryOnly)])
        let profileAdditional = ["vertex": Set(["/Users/tester/.claude-lab", box])]
        #expect(attribute(c, record(requestId: "req_011abc"), profile: "/Users/tester/.claude-lab",
                          profileAdditional: profileAdditional) == "vertex")
        #expect(attribute(c, record(requestId: "req_011abc"), profile: box, profileAdditional: profileAdditional) == "vertex")
        // A main claim beats an additional claim.
        let mainClaim = ["vertex": Set([Self.lab])]
        #expect(attribute(c, record(requestId: "req_vrtx_1"), profile: Self.lab, profileAdditional: mainClaim) == "lab")
    }

    /// Two additional claimants leave the rules to decide among them.
    @Test func twoAdditionalClaimantsFallBackToTheRulesAmongThem() {
        let shared = "/Users/tester/.claude-lab"
        let c = Self.config([Self.subscription("max", "~/.claude"), Self.token("vertex", "~/agent-profiles/work/claude"),
                             Self.token("other", "~/agent-profiles/lab/claude", kind: .claudeCodeOtherProvider,
                                        condition: Self.model(.startsWith, "intranet/"))])
        let profileAdditional: [String: Set<String>] = ["max": [shared], "other": [shared]]
        // The Vertex account does not compete: it does not claim the profile.
        #expect(attribute(c, record(requestId: "req_vrtx_1"), profile: shared, profileAdditional: profileAdditional) == nil)
        #expect(attribute(c, record(requestId: "req_011abc"), profile: shared, profileAdditional: profileAdditional) == "max")
        #expect(attribute(c, record(model: "intranet/glm-5"), profile: shared, profileAdditional: profileAdditional) == "other")
    }

    /// FR-005, FR-008: the profile step applies to Claude Code records only,
    /// and a Claude Code account never claims an OpenCode record.
    @Test func otherHarnessesIgnoreTheProfile() {
        var c = Self.threeProfiles
        c.accounts.append(Self.token("oc", nil, harness: .openCode))
        let openCode = record(harness: .openCode, hint: "google-vertex")
        #expect(attribute(c, openCode, profile: Self.work, directory: "/Users/tester/.local/share/opencode") == "oc")
        c.accounts.removeLast()
        #expect(attribute(c, openCode, profile: Self.work, directory: "/Users/tester/.local/share/opencode") == nil)
        let codex = record(harness: .codex, hint: "apikey")
        #expect(attribute(c, codex, profile: Self.work, directory: "/Users/tester/.codex") == nil)
    }

    /// The token-based main directory is part of the fingerprint (spec 037
    /// plan "Attribution").
    @Test func fingerprintCoversHarnessRuleAndMainDirectory() {
        let base = Attributor(configuration: Self.threeProfiles, paths: paths).fingerprint
        var moved = Self.threeProfiles
        moved.accounts[1] = Self.token("vertex", "~/agent-profiles/other/claude")
        #expect(Attributor(configuration: moved, paths: paths).fingerprint != base)
        var rule = Self.threeProfiles
        rule.accounts[2] = Self.token("lab", "~/agent-profiles/lab/claude", kind: .claudeCodeOtherProvider,
                                      condition: Self.model(.startsWith, "intranet/"))
        #expect(Attributor(configuration: rule, paths: paths).fingerprint != base)
        #expect(Attributor(configuration: Self.threeProfiles, paths: paths,
                           profileAdditionalDirectories: ["vertex": ["/Users/tester/x"]]).fingerprint == base)
    }
}

// MARK: - Spec 038: rule step (kind, then condition)

/// spec 038 FR-002 to FR-006, SC-002, research R11: records without a
/// profile signal count by kind first, then by condition.
@Suite struct RuleStepAttributionTests {
    let paths = Paths(home: URL(fileURLWithPath: "/Users/tester"))
    typealias Make = ProfileAttributionTests

    private func record(_ harness: Harness, requestId: String = "", model: String = "model-x",
                        messageId: String = "msg_1", hint: String? = nil) -> RawUsageRecord {
        var r = makeRaw(id: messageId, requestId: requestId, model: model)
        r.harness = harness
        r.providerHint = hint
        return r
    }

    private func attribute(_ accounts: [Account], _ record: RawUsageRecord, line: String = "{}") -> String? {
        Attributor(configuration: Make.config(accounts), paths: paths)
            .accountId(for: record, rawLine: line, fileConfigDirectory: "/Users/tester/.claude", profileDirectory: nil)
    }

    /// One row per record: whether a single account of the kind, with or
    /// without a condition, claims it (SC-002).
    struct Row: CustomTestStringConvertible, Sendable {
        let kind: SessionKind
        let condition: MatchCondition?
        let record: RawUsageRecord
        let line: String
        let matches: Bool
        var testDescription: String { "\(kind) \(condition.map { "\($0.field) \($0.operator) \($0.text)" } ?? "plain") -> \(matches)" }
    }

    static let gatewayLine = #"{"type":"assistant","cwd":"/Users/tester/proj-alpha","message":{"id":"chatcmpl-1","model":"intranet/glm-5"}}"#

    static func rows() -> [Row] {
        func r(_ harness: Harness, requestId: String = "", model: String = "model-x", messageId: String = "msg_1",
               hint: String? = nil) -> RawUsageRecord {
            var raw = makeRaw(id: messageId, requestId: requestId, model: model)
            raw.harness = harness
            raw.providerHint = hint
            return raw
        }
        func c(_ field: MatchField, _ op: MatchOperator, _ text: String) -> MatchCondition {
            MatchCondition(field: field, operator: op, text: text)
        }
        let vertexCC = r(.claudeCode, requestId: "req_vrtx_011")
        let directCC = r(.claudeCode, requestId: "req_011abc")
        let gatewayCC = r(.claudeCode, model: "intranet/glm-5", messageId: "chatcmpl-1")
        let apiKey = r(.codex, model: "model-a", hint: "apikey")
        let plan = r(.codex, model: "model-a", hint: "chatgpt")
        let ocVertex = r(.openCode, hint: "google-vertex")
        let ocOpenAI = r(.openCode, model: "model-a", hint: "openai")
        let ocGateway = r(.openCode, model: "intranet/glm-5", hint: "openrouter-like-x")
        return [
            Row(kind: .claudeCodeVertex, condition: nil, record: vertexCC, line: "{}", matches: true),
            Row(kind: .claudeCodeVertex, condition: nil, record: gatewayCC, line: "{}", matches: false),
            Row(kind: .claudeCodeVertex, condition: nil, record: directCC, line: "{}", matches: false),
            Row(kind: .claudeCodeVertex, condition: c(.requestId, .startsWith, "req_vrtx_"), record: vertexCC, line: "{}", matches: true),
            Row(kind: .claudeCodeOtherProvider, condition: nil, record: gatewayCC, line: "{}", matches: true),
            Row(kind: .claudeCodeOtherProvider, condition: nil, record: vertexCC, line: "{}", matches: false),
            Row(kind: .claudeCodeOtherProvider, condition: nil, record: directCC, line: "{}", matches: false),
            Row(kind: .claudeCodeOtherProvider, condition: c(.model, .startsWith, "intranet/"), record: gatewayCC, line: "{}", matches: true),
            Row(kind: .claudeCodeOtherProvider, condition: c(.messageId, .startsWith, "chatcmpl-"), record: gatewayCC, line: "{}", matches: true),
            Row(kind: .claudeCodeOtherProvider, condition: c(.anywhere, .contains, "proj-alpha"), record: gatewayCC, line: gatewayLine, matches: true),
            Row(kind: .claudeCodeOtherProvider, condition: c(.anywhere, .contains, "proj-alpha"), record: gatewayCC, line: "{}", matches: false),
            // A condition never widens its kind (FR-004).
            Row(kind: .claudeCodeOtherProvider, condition: c(.requestId, .startsWith, "req_vrtx_"), record: vertexCC, line: "{}", matches: false),
            Row(kind: .claudeCodeVertex, condition: c(.model, .startsWith, "intranet/"), record: gatewayCC, line: "{}", matches: false),
            Row(kind: .claudeCodeDirectoryOnly, condition: nil, record: vertexCC, line: "{}", matches: false),
            Row(kind: .claudeCodeDirectoryOnly, condition: nil, record: gatewayCC, line: "{}", matches: false),
            Row(kind: .codexAPIKey, condition: nil, record: apiKey, line: "{}", matches: true),
            Row(kind: .codexAPIKey, condition: nil, record: plan, line: "{}", matches: false),
            Row(kind: .codexAPIKey, condition: c(.model, .startsWith, "model-a"), record: apiKey, line: "{}", matches: true),
            Row(kind: .codexAPIKey, condition: c(.model, .startsWith, "model-a"), record: plan, line: "{}", matches: false),
            Row(kind: .codexAPIKey, condition: c(.anywhere, .contains, "proj-alpha"), record: apiKey, line: gatewayLine, matches: true),
            Row(kind: .openCodeVertex, condition: nil, record: ocVertex, line: "{}", matches: true),
            Row(kind: .openCodeVertex, condition: nil, record: ocOpenAI, line: "{}", matches: false),
            Row(kind: .openCodeOpenAI, condition: nil, record: ocOpenAI, line: "{}", matches: true),
            Row(kind: .openCodeOpenAI, condition: nil, record: ocVertex, line: "{}", matches: false),
            Row(kind: .openCodeOtherProvider, condition: c(.model, .startsWith, "intranet/"), record: ocGateway, line: "{}", matches: true),
            Row(kind: .openCodeOtherProvider, condition: c(.anywhere, .contains, "proj-alpha"), record: ocGateway, line: gatewayLine, matches: true),
            Row(kind: .openCodeOtherProvider, condition: c(.model, .startsWith, "intranet/"), record: ocVertex, line: "{}", matches: false),
            // FR-002: a kind never claims a record of another harness.
            Row(kind: .claudeCodeVertex, condition: nil, record: ocVertex, line: "{}", matches: false),
            Row(kind: .codexAPIKey, condition: c(.model, .startsWith, "intranet/"), record: ocGateway, line: "{}", matches: false),
            Row(kind: .openCodeOpenAI, condition: nil, record: apiKey, line: "{}", matches: false),
            Row(kind: .claudeCodeOtherProvider, condition: nil, record: ocGateway, line: "{}", matches: false),
        ]
    }

    @Test(arguments: rows())
    func kindTable(row: Row) {
        let account = Make.token("acc", nil, kind: row.kind, condition: row.condition, harness: row.kind.harness)
        #expect((attribute([account], row.record, line: row.line) == "acc") == row.matches)
    }

    /// FR-005: conditions ignore case.
    @Test func conditionsIgnoreCase() {
        let gateway = record(.claudeCode, model: "intranet/glm-5")
        #expect(attribute([Make.token("lab", nil, kind: .claudeCodeOtherProvider, condition: Make.model(.startsWith, "INTRANET/"))], gateway) == "lab")
        #expect(attribute([Make.token("lab", nil, kind: .claudeCodeOtherProvider, condition: Make.model(.startsWith, "intranet/"))], gateway) == "lab")
    }

    /// FR-004: an Other provider account whose condition would match the
    /// text of a Vertex or direct record never takes it.
    @Test func conditionOnlyNarrowsItsKind() {
        let gateway = Make.token("gw", nil, kind: .claudeCodeOtherProvider, condition: Make.model(.contains, "claude"))
        #expect(attribute([gateway], record(.claudeCode, requestId: "req_vrtx_1", model: "claude-model-x")) == nil)
        #expect(attribute([gateway], record(.claudeCode, requestId: "req_011abc", model: "claude-model-x")) == nil)
        #expect(attribute([gateway], record(.claudeCode, model: "claude-model-x")) == "gw")
    }

    /// FR-006: among accounts of one kind, a matching condition beats no
    /// condition; two matching conditions tie.
    @Test func conditionBeatsPlainWithinAKind() {
        let accounts = [Make.token("vertex", nil),
                        Make.token("lab", "~/agent-profiles/lab/claude", condition: MatchCondition(field: .requestId, operator: .startsWith, text: "req_vrtx_"))]
        #expect(attribute(accounts, record(.claudeCode, requestId: "req_vrtx_1")) == "lab")
        let two = accounts + [Make.token("other", nil, condition: Make.model(.startsWith, "model-"))]
        #expect(attribute(two, record(.claudeCode, requestId: "req_vrtx_1")) == nil)
        // A condition that does not match leaves the plain account.
        let narrow = [Make.token("vertex", nil), Make.token("lab", nil, condition: Make.model(.contains, "glm"))]
        #expect(attribute(narrow, record(.claudeCode, requestId: "req_vrtx_9", model: "model-x")) == "vertex")
    }

    /// FR-006, FR-009: two plain accounts of one token-based kind tie.
    @Test func twoPlainAccountsOfOneKindStayUnassigned() {
        let codex = [Make.token("a", nil, harness: .codex), Make.token("b", nil, harness: .codex)]
        #expect(attribute(codex, record(.codex, hint: "apikey")) == nil)
        let gateways = [Make.token("a", nil, kind: .claudeCodeOtherProvider), Make.token("b", nil, kind: .claudeCodeOtherProvider)]
        #expect(attribute(gateways, record(.claudeCode, model: "intranet/glm-5")) == nil)
    }

    /// Edge case "OpenCode Other provider without a condition": it takes no
    /// record, even as the only OpenCode account.
    @Test func openCodeOtherProviderNeedsACondition() {
        let bare = Make.token("oc", nil, kind: .openCodeOtherProvider, harness: .openCode)
        #expect(attribute([bare], record(.openCode, hint: "openrouter-like-x")) == nil)
        let narrowed = Make.token("oc", nil, kind: .openCodeOtherProvider, condition: Make.model(.contains, "glm"), harness: .openCode)
        #expect(attribute([narrowed], record(.openCode, model: "intranet/glm-5", hint: "openrouter-like-x")) == "oc")
    }

    /// US2 scenarios 3 and 4: Directory only never wins in the rule step,
    /// but wins through the profile step; the profile step decides first
    /// whatever kind and condition say.
    @Test func profileStepDecidesFirst() {
        let lab = Make.token("lab", "~/agent-profiles/lab/claude", kind: .claudeCodeDirectoryOnly)
        let gateway = Make.token("gw", "~/agent-profiles/work/claude", kind: .claudeCodeOtherProvider, condition: Make.model(.contains, "glm"))
        let attributor = Attributor(configuration: Make.config([lab, gateway]), paths: paths)
        func account(_ r: RawUsageRecord, _ profile: String?) -> String? {
            attributor.accountId(for: r, rawLine: "{}", fileConfigDirectory: "/Users/tester/.claude", profileDirectory: profile)
        }
        for r in [record(.claudeCode, requestId: "req_vrtx_1"), record(.claudeCode, model: "intranet/glm-5"), record(.claudeCode, requestId: "req_011a")] {
            #expect(account(r, Make.lab) == "lab")
            // The gateway's directory decides even for records of another
            // kind or that fail its condition (US2 scenario 4).
            #expect(account(r, Make.work) == "gw")
        }
        #expect(account(record(.claudeCode, model: "intranet/glm-5"), nil) == "gw")
        #expect(account(record(.claudeCode, requestId: "req_vrtx_1"), nil) == nil)
    }

    /// FR-005: a record whose profile names the account's directory counts
    /// for it whatever the condition says.
    @Test func profileDecidesBeforeTheOperator() {
        let lab = Make.token("lab", "~/agent-profiles/lab/claude", kind: .claudeCodeOtherProvider, condition: Make.model(.contains, "glm"))
        let other = Make.token("other", "~/agent-profiles/work/claude", kind: .claudeCodeOtherProvider, condition: Make.model(.contains, "model"))
        let attributor = Attributor(configuration: Make.config([lab, other]), paths: paths)
        #expect(attributor.accountId(for: record(.claudeCode, model: "model-x"), rawLine: "{}",
                                     fileConfigDirectory: "/Users/tester/.claude", profileDirectory: Make.lab) == "lab")
        #expect(attributor.accountId(for: record(.claudeCode, model: "model-x"), rawLine: "{}",
                                     fileConfigDirectory: "/Users/tester/.claude", profileDirectory: nil) == "other")
    }

    /// FR-007: a condition that timed out sits out the rest of the
    /// attributor's life, and its records go through the remaining
    /// accounts; a new attributor tries it again.
    @Test func timedOutConditionFallsThroughToTheOtherAccounts() {
        let slowLine = String(repeating: "a", count: 40) + "bzz"
        let accounts = [Make.token("slow", nil, kind: .claudeCodeOtherProvider, condition: MatchCondition(field: .anywhere, operator: .regex, text: "(a+)+$")),
                        Make.token("other", nil, kind: .claudeCodeOtherProvider, condition: MatchCondition(field: .anywhere, operator: .contains, text: "zz"))]
        let attributor = Attributor(configuration: Make.config(accounts), paths: paths, matchTimeLimit: .milliseconds(20))
        func account(_ line: String) -> String? {
            attributor.accountId(for: record(.claudeCode), rawLine: line, fileConfigDirectory: "/Users/tester/.claude")
        }
        // Before any time-out both conditions match: neither wins.
        #expect(account("aaaazz-aaaa") == nil)
        #expect(attributor.timeOuts == 0)
        #expect(account(slowLine) == "other")
        #expect(attributor.timeOuts == 1)
        #expect(account("aaaazz-aaaa") == "other")
        #expect(account("aaaa") == nil)
        #expect(attributor.skippedDecisions == 3)
        #expect(attributor.drainSitOutAccounts() == ["slow"])
        let next = Attributor(configuration: Make.config(accounts), paths: paths, matchTimeLimit: .milliseconds(20))
        #expect(next.accountId(for: record(.claudeCode), rawLine: "aaaa", fileConfigDirectory: "/Users/tester/.claude") == "slow")
    }

    /// FR-007: a condition only runs, and only times out, on records of its
    /// kind; kinds never go through the time limit.
    @Test func conditionOnlyRunsOnItsKind() {
        let slowLine = String(repeating: "a", count: 40) + "b"
        let accounts = [Make.token("slow", nil, condition: MatchCondition(field: .anywhere, operator: .regex, text: "(a+)+$"), harness: .codex),
                        Make.token("gw", nil, kind: .claudeCodeOtherProvider, condition: MatchCondition(field: .anywhere, operator: .regex, text: "(a+)+$")),
                        Make.token("vertex", nil)]
        let attributor = Attributor(configuration: Make.config(accounts), paths: paths, matchTimeLimit: .milliseconds(20))
        #expect(attributor.accountId(for: record(.claudeCode, requestId: "req_vrtx_1"), rawLine: slowLine,
                                     fileConfigDirectory: "/Users/tester/.claude") == "vertex")
        #expect(attributor.timeOuts == 0)
        #expect(attributor.skippedDecisions == 0)
    }

    /// US2 scenario 1: the gateway account's older sessions find it through
    /// its kind; Vertex and direct records go to their accounts.
    @Test func otherProviderClaimsRecordsWithoutProfile() {
        let accounts = [Make.subscription("max", "~/agent-profiles/personal/claude"), Make.token("vertex", "~/agent-profiles/work/claude"),
                        Make.token("lab", "~/agent-profiles/lab/claude", kind: .claudeCodeOtherProvider)]
        #expect(attribute(accounts, record(.claudeCode, model: "intranet/glm-5", messageId: "chatcmpl-3")) == "lab")
        #expect(attribute(accounts, record(.claudeCode, requestId: "req_vrtx_1")) == "vertex")
        #expect(attribute(accounts, record(.claudeCode, requestId: "req_011abc")) == "max")
    }

    /// US2 scenario 3: Directory only never claims a record without a
    /// profile signal.
    @Test func directoryOnlyNeverClaimsWithoutProfile() {
        let accounts = [Make.token("lab", "~/agent-profiles/lab/claude", kind: .claudeCodeDirectoryOnly)]
        for r in [record(.claudeCode, requestId: "req_vrtx_1"), record(.claudeCode, model: "intranet/glm-5"), record(.claudeCode, requestId: "req_011a")] {
            #expect(attribute(accounts, r) == nil)
        }
    }

    /// FR-006: subscriptions keep their implicit rules and markers.
    @Test func subscriptionsKeepTheirRules() {
        let accounts = [Make.subscription("max", "~/.claude"), Make.token("vertex", nil),
                        Account(id: "plus", displayName: "Plus", kind: .codexSubscription(CodexSubscriptionSettings()))]
        #expect(attribute(accounts, record(.claudeCode, requestId: "req_011abc")) == "max")
        #expect(attribute(accounts, record(.claudeCode, requestId: "req_vrtx_1")) == "vertex")
        #expect(attribute(accounts, record(.codex, hint: "chatgpt")) == "plus")
        // A marker narrows the subscription's own kind; a Vertex record
        // that contains it stays the Vertex account's (FR-006).
        var marked = accounts
        marked[0].customMarker = "proj-alpha"
        #expect(attribute(marked, record(.claudeCode, requestId: "req_vrtx_1"), line: "proj-alpha") == "vertex")
        #expect(attribute(marked, record(.claudeCode, requestId: "req_011abc"), line: "proj-alpha") == "max")
    }

    /// A harness, kind or condition change re-attributes (the fingerprint
    /// changes) and never asks the usage endpoint; a hidden Directory only
    /// condition does not count.
    @Test func ruleChangesReattributeWithoutANetworkRequest() {
        let base = Make.config([Make.subscription("max", "~/.claude"), Make.token("lab", nil)])
        var condition = base
        condition.accounts[1] = Make.token("lab", nil, condition: Make.model(.startsWith, "intranet/"))
        var kind = base
        kind.accounts[1] = Make.token("lab", nil, kind: .claudeCodeOtherProvider)
        var harness = base
        harness.accounts[1] = Make.token("lab", nil, harness: .openCode)
        for edited in [condition, kind, harness] {
            #expect(Attributor(configuration: edited, paths: paths).fingerprint != Attributor(configuration: base, paths: paths).fingerprint)
            #expect(edited.needsRefresh(comparedTo: base))
            #expect(!edited.needsNetworkRefresh(comparedTo: base))
        }
        // A condition text change counts too.
        var text = condition
        text.accounts[1] = Make.token("lab", nil, condition: Make.model(.startsWith, "intranet/glm"))
        #expect(Attributor(configuration: text, paths: paths).fingerprint != Attributor(configuration: condition, paths: paths).fingerprint)
        // A hidden condition of a Directory only account does not.
        let hidden = Make.config([Make.token("lab", nil, kind: .claudeCodeDirectoryOnly)])
        let hiddenCondition = Make.config([Make.token("lab", nil, kind: .claudeCodeDirectoryOnly, condition: Make.model(.contains, "glm"))])
        #expect(Attributor(configuration: hidden, paths: paths).fingerprint == Attributor(configuration: hiddenCondition, paths: paths).fingerprint)
    }

    /// `needsRawLine` is true only for an effective Anywhere condition or a
    /// subscription marker.
    @Test func needsRawLineFollowsTheConditions() {
        func needs(_ accounts: [Account]) -> Bool { Attributor(configuration: Make.config(accounts), paths: paths).needsRawLine }
        let anywhere = MatchCondition(field: .anywhere, operator: .contains, text: "x")
        #expect(!needs([Make.token("a", nil)]))
        #expect(!needs([Make.token("a", nil, condition: Make.model(.startsWith, "x"))]))
        #expect(needs([Make.token("a", nil, condition: anywhere)]))
        #expect(!needs([Make.token("a", nil, kind: .claudeCodeDirectoryOnly, condition: anywhere)]))
        var marked = Make.config([Make.subscription("max", "~/.claude")])
        marked.accounts[0].customMarker = "x"
        #expect(Attributor(configuration: marked, paths: paths).needsRawLine)
    }
}

// MARK: - Spec 038 US1: token-based accounts never take subscription sessions

/// spec 038 US1, FR-004, FR-006, SC-001: no kind and condition makes a
/// token-based account take a ChatGPT-plan session or a direct Anthropic
/// record; subscription markers narrow to their subscription's own kind.
@Suite struct SubscriptionSafetyAttributionTests {
    let paths = Paths(home: URL(fileURLWithPath: "/Users/tester"))
    typealias Make = ProfileAttributionTests

    private func record(_ harness: Harness, requestId: String = "", model: String = "model-x", hint: String? = nil) -> RawUsageRecord {
        var r = makeRaw(id: "msg_1", requestId: requestId, model: model)
        r.harness = harness
        r.providerHint = hint
        return r
    }

    private func attribute(_ accounts: [Account], _ record: RawUsageRecord, line: String = "{}",
                           directory: String = "/Users/tester/.claude") -> String? {
        Attributor(configuration: Make.config(accounts), paths: paths)
            .accountId(for: record, rawLine: line, fileConfigDirectory: directory, profileDirectory: nil)
    }

    static let plus = Account(id: "plus", displayName: "Plus", kind: .codexSubscription(CodexSubscriptionSettings()))

    /// US1 scenarios 1 and 2: a Codex subscription and a token-based Codex
    /// account with Model starts with `model-a`.
    @Test func codexPlanSessionsStayWithTheSubscription() {
        let token = Make.token("tok", nil, condition: Make.model(.startsWith, "model-a"), harness: .codex)
        let accounts = [Self.plus, token]
        #expect(attribute(accounts, record(.codex, model: "model-a", hint: "chatgpt"), directory: "/Users/tester/.codex") == "plus")
        #expect(attribute(accounts, record(.codex, model: "model-a-mini", hint: "apikey"), directory: "/Users/tester/.codex") == "tok")
        // Without the subscription the plan session stays Unassigned.
        #expect(attribute([token], record(.codex, model: "model-a", hint: "chatgpt"), directory: "/Users/tester/.codex") == nil)
    }

    /// US1 scenario 3: a Vertex account with Model contains `model-x` does
    /// not take a direct Anthropic record.
    @Test func directRecordsStayWithTheSubscription() {
        let vertex = Make.token("tok", nil, condition: Make.model(.contains, "model-x"))
        let direct = record(.claudeCode, requestId: "req_011abc", model: "claude-model-x")
        #expect(attribute([vertex], direct) == nil)
        #expect(attribute([Make.subscription("max", "~/.claude"), vertex], direct) == "max")
    }

    /// SC-001: for every token-based kind of every harness and every field
    /// it offers, a condition whose text matches a ChatGPT-plan session or
    /// a direct Anthropic record never makes that record count for it.
    @Test(arguments: SessionKind.allCases)
    func noConditionTakesASubscriptionRecord(kind: SessionKind) {
        let line = #"{"cwd":"/Users/tester/proj-alpha","model":"model-a"}"#
        let samples: [(RawUsageRecord, Account, String)] = [
            (record(.codex, requestId: "", model: "model-a", hint: "chatgpt"), Self.plus, "/Users/tester/.codex"),
            (record(.claudeCode, requestId: "req_011abc", model: "model-a"), Make.subscription("max", "~/.claude"), "/Users/tester/.claude"),
        ]
        for (sample, subscription, directory) in samples {
            for field in MatchField.fields(for: kind.harness) {
                let text: String
                switch field {
                case .model: text = sample.model
                case .requestId: text = sample.requestId.isEmpty ? "req_" : sample.requestId
                case .messageId: text = sample.messageId
                case .anywhere: text = "proj-alpha"
                }
                let token = Make.token("tok", nil, kind: kind, condition: MatchCondition(field: field, operator: .contains, text: text),
                                       harness: kind.harness)
                #expect(attribute([token], sample, line: line, directory: directory) == nil, "\(kind) \(field) alone")
                #expect(attribute([subscription, token], sample, line: line, directory: directory) == subscription.id,
                        "\(kind) \(field) with \(subscription.id)")
            }
        }
    }

    /// FR-006: a Claude subscription's marker no longer claims a Vertex,
    /// gateway, Codex or OpenCode record that contains it.
    @Test func claudeMarkerOnlyNarrowsDirectRecords() {
        var max = Make.subscription("max", "~/.claude")
        max.customMarker = "proj-alpha"
        let accounts = [max, Make.token("vertex", nil), Make.token("gw", "~/.claude-gateway", kind: .claudeCodeOtherProvider),
                        Make.token("oai", nil, harness: .codex), Make.token("oc", nil, harness: .openCode)]
        let line = "proj-alpha"
        #expect(attribute(accounts, record(.claudeCode, requestId: "req_vrtx_1"), line: line) == "vertex")
        #expect(attribute(accounts, record(.claudeCode, model: "intranet/glm-5"), line: line) == "gw")
        #expect(attribute(accounts, record(.codex, hint: "apikey"), line: line, directory: "/Users/tester/.codex") == "oai")
        #expect(attribute(accounts, record(.openCode, hint: "google-vertex"), line: line,
                          directory: "/Users/tester/.local/share/opencode") == "oc")
        // Without those accounts the records stay Unassigned.
        #expect(attribute([max], record(.claudeCode, requestId: "req_vrtx_1"), line: line) == nil)
        #expect(attribute([max], record(.codex, hint: "chatgpt"), line: line, directory: "/Users/tester/.codex") == nil)
        // A direct record with the marker counts; one without it does not.
        #expect(attribute([max], record(.claudeCode, requestId: "req_011abc"), line: line) == "max")
        #expect(attribute([max], record(.claudeCode, requestId: "req_011abc"), line: "{}") == nil)
    }

    /// FR-006: a Codex subscription's marker only decides among
    /// ChatGPT-plan sessions.
    @Test func codexMarkerOnlyNarrowsPlanSessions() {
        var plus = Self.plus
        plus.customMarker = "proj-alpha"
        let codex = "/Users/tester/.codex"
        #expect(attribute([plus], record(.codex, hint: "apikey"), line: "proj-alpha", directory: codex) == nil)
        #expect(attribute([plus], record(.codex, hint: "chatgpt"), line: "proj-alpha", directory: codex) == "plus")
        #expect(attribute([plus, Make.token("oai", nil, harness: .codex)], record(.codex, hint: "apikey"), line: "proj-alpha",
                          directory: codex) == "oai")
    }

    /// FR-006: a marker still separates two subscriptions of the same kind
    /// and beats one of that kind without a marker.
    @Test func markerSeparatesSubscriptionsOfOneKind() {
        var max = Make.subscription("max", "~/.claude")
        max.customMarker = "proj-alpha"
        let pro = Make.subscription("pro", "~/.claude-pro")
        var team = Make.subscription("team", "~/.claude-team")
        team.customMarker = "proj-beta"
        let direct = record(.claudeCode, requestId: "req_011abc")
        #expect(attribute([max, pro], direct, line: "proj-alpha", directory: "/Users/tester/.claude-pro") == "max")
        #expect(attribute([max, pro], direct, line: "{}", directory: "/Users/tester/.claude-pro") == "pro")
        #expect(attribute([max, team], direct, line: "proj-beta") == "team")
        #expect(attribute([max, team], direct, line: "proj-alpha proj-beta", directory: "/Users/tester/elsewhere") == nil)
    }
}

// MARK: - Spec 038 US3: narrow a kind with operators

/// spec 038 US3 scenarios 1 to 4, FR-005, FR-007: conditions on Other
/// provider accounts, case ignored both ways.
@Suite struct ConditionOperatorAttributionTests {
    let paths = Paths(home: URL(fileURLWithPath: "/Users/tester"))
    typealias Make = ProfileAttributionTests

    private func gateway(_ model: String) -> RawUsageRecord { makeRaw(id: "msg_1", requestId: "", model: model) }

    private func attribute(_ accounts: [Account], _ record: RawUsageRecord, line: String = "{}") -> String? {
        Attributor(configuration: Make.config(accounts), paths: paths)
            .accountId(for: record, rawLine: line, fileConfigDirectory: "/Users/tester/.claude", profileDirectory: nil)
    }

    private func account(_ id: String, _ field: MatchField, _ op: MatchOperator, _ text: String) -> Account {
        Make.token(id, nil, kind: .claudeCodeOtherProvider, condition: MatchCondition(field: field, operator: op, text: text))
    }

    /// US3 scenario 1 and the independent test: two gateway accounts.
    @Test func twoGatewayAccountsSplitTheModels() {
        let accounts = [account("glm", .model, .contains, "glm"), account("ab", .model, .regex, "^gateway-(a|b)/")]
        #expect(attribute(accounts, gateway("intranet/glm-5")) == "glm")
        #expect(attribute(accounts, gateway("intranet/GLM-5-Air")) == "glm")
        #expect(attribute(accounts, gateway("gateway-a/x")) == "ab")
        #expect(attribute(accounts, gateway("GATEWAY-B/y")) == "ab")
        #expect(attribute(accounts, gateway("gateway-c/z")) == nil)
    }

    /// US3 scenario 2: starts with ignores case and anchors at the start.
    @Test func startsWithIgnoresCase() {
        #expect(attribute([account("a", .model, .startsWith, "intranet/")], gateway("INTRANET/glm-5")) == "a")
        #expect(attribute([account("a", .model, .startsWith, "glm")], gateway("intranet/glm-5")) == nil)
    }

    /// US3 scenario 3: a regex matches case-insensitively and anchors.
    @Test func regexAnchorsAndIgnoresCase() {
        let ab = [account("ab", .model, .regex, "^gateway-(a|b)/")]
        #expect(attribute(ab, gateway("gateway-a/glm-5")) == "ab")
        #expect(attribute(ab, gateway("GATEWAY-B/glm-5")) == "ab")
        #expect(attribute(ab, gateway("gateway-c/glm-5")) == nil)
    }

    /// US3 scenario 4: Anywhere contains searches the raw line, case ignored.
    @Test func anywhereContainsIgnoresCase() {
        let host = [account("host", .anywhere, .contains, "gateway.example")]
        #expect(attribute(host, gateway("intranet/glm-5"), line: #"{"baseURL":"https://Gateway.Example/v1"}"#) == "host")
        #expect(attribute(host, gateway("intranet/glm-5"), line: #"{"baseURL":"https://other.example/v1"}"#) == nil)
    }

    /// FR-007: a slow condition never runs on a record of another kind: a
    /// Vertex record never reaches an Other provider condition.
    @Test func slowConditionRunsOnlyOnItsKind() {
        let slowLine = String(repeating: "a", count: 40) + "b"
        let accounts = [account("slow", .anywhere, .regex, "(a+)+$"), Make.token("vertex", nil)]
        let attributor = Attributor(configuration: Make.config(accounts), paths: paths, matchTimeLimit: .milliseconds(20))
        for _ in 0..<3 {
            #expect(attributor.accountId(for: makeRaw(id: "msg_1", requestId: "req_vrtx_1"), rawLine: slowLine,
                                         fileConfigDirectory: "/Users/tester/.claude") == "vertex")
        }
        #expect(attributor.timeOuts == 0)
        #expect(attributor.skippedDecisions == 0)
        // A gateway record reaches it, times out and the condition sits out.
        #expect(attributor.accountId(for: gateway("intranet/glm-5"), rawLine: slowLine, fileConfigDirectory: "/Users/tester/.claude") == nil)
        #expect(attributor.timeOuts == 1)
        #expect(attributor.drainSitOutAccounts() == ["slow"])
        // The retry memory carries over through the kind-first step.
        let next = Attributor(configuration: Make.config(accounts), paths: paths, matchTimeLimit: .milliseconds(20),
                              matchMemory: attributor.matchMemory)
        #expect(next.accountId(for: gateway("intranet/glm-5"), rawLine: slowLine, fileConfigDirectory: "/Users/tester/.claude") == nil)
        #expect(next.timeOuts == 0)
        #expect(next.accountId(for: gateway("intranet/glm-5"), rawLine: "aaaa", fileConfigDirectory: "/Users/tester/.claude") == "slow")
    }
}
