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
            Account(id: $0.id, displayName: $0.id,
                    kind: .tokenBased(TokenBasedSettings(groupId: "grp", provider: .vertex)), customMarker: $0.marker)
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
                                  kind: .tokenBased(TokenBasedSettings(membership: .group(id: "grp", shownInBar: false), provider: .vertex,
                                                                       sessionDirectory: "~/profiles/acme/claude"))))
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
                    kind: .tokenBased(TokenBasedSettings(groupId: "grp", provider: .vertex)), customMarker: markers["acc-vertex"]),
        ]
        if openai {
            c.accounts.append(Account(id: "acc-oai", displayName: "OpenAI",
                                      kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 50)), provider: .openai)),
                                      customMarker: markers["acc-oai"]))
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
        #expect(attribute(c, raw(.openCode, hint: "google-vertex"), directory: dir) == "acc-vertex")
        #expect(attribute(c, raw(.openCode, hint: "google-vertex-anthropic"), directory: dir) == "acc-vertex")
        #expect(attribute(c, raw(.openCode, hint: "openai"), directory: dir) == "acc-oai")
        #expect(attribute(c, raw(.openCode, hint: "anthropic"), directory: dir) == nil)
        #expect(attribute(c, raw(.openCode, hint: "litellm"), directory: dir) == nil)
        #expect(attribute(c, raw(.openCode, hint: nil), directory: dir) == nil)
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

    @Test func customMarkerWinsForEveryHarness() {
        let c = config(markers: ["acc-max": "\"cwd\":\"/Users/tester/private\""])
        let codexLine = "{\"type\":\"session_meta\",\"payload\":{\"cwd\":\"/Users/tester/private\"}}\n{\"type\":\"event_msg\"}"
        #expect(attribute(c, raw(.codex, hint: "apikey"), line: codexLine) == "acc-max")
        let openCodeLine = "{\"role\":\"assistant\",\"providerID\":\"google-vertex\",\"path\":{\"cwd\":\"/Users/tester/private\"}}"
        #expect(attribute(c, raw(.openCode, hint: "google-vertex"), line: openCodeLine,
                          directory: "/Users/tester/.local/share/opencode") == "acc-max")
        // Lines without the marker keep the built-in rule.
        #expect(attribute(c, raw(.openCode, hint: "google-vertex"), line: "{}") == "acc-vertex")
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
                    kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 5)), provider: .openai))),
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
                             Make.token("vertex", .vertex),
                             Make.codex("plus", "~/.codex", extra: ["~/.codex-lab"]),
                             Make.token("openai", .openai)])
        let lab = "/Users/tester/.claude-lab"
        let additional = ["max": Set([lab]), "plus": ["/Users/tester/.codex-lab"]]
        #expect(attribute(c, claudeRecord("req_vrtx_011"), directory: lab, additional: additional) == "vertex")
        #expect(attribute(c, claudeRecord("req_bdrk_1"), directory: lab, additional: additional) == nil)
        #expect(attribute(c, codexRecord("apikey"), directory: "/Users/tester/.codex-lab", additional: additional) == "openai")
        var marked = c
        marked.accounts[1].customMarker = "acme-marker"
        #expect(attribute(marked, claudeRecord(), directory: lab, additional: additional, line: "{\"x\":\"acme-marker\"}") == "vertex")
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
