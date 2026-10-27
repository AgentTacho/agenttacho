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
            // A marker of a token-based account is its custom rule
            // "Anywhere in the record line" (spec 037 FR-014).
            Account(id: $0.id, displayName: $0.id,
                    kind: .tokenBased(TokenBasedSettings(groupId: "grp", harness: .claudeCode,
                                                         matchRule: $0.marker.map { .custom(field: .anywhere, text: $0) })))
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
                    kind: .tokenBased(TokenBasedSettings(groupId: "grp", harness: .claudeCode,
                                                         matchRule: markers["acc-vertex"].map { .custom(field: .anywhere, text: $0) }))),
            // Since spec 037 an account has one harness: OpenCode usage
            // needs its own accounts (FR-008).
            Account(id: "acc-oc-vertex", displayName: "OpenCode Vertex",
                    kind: .tokenBased(TokenBasedSettings(groupId: "grp", harness: .openCode))),
        ]
        if openai {
            c.accounts.append(Account(id: "acc-oai", displayName: "OpenAI",
                                      kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 50)), harness: .codex,
                                                                           matchRule: markers["acc-oai"].map { .custom(field: .anywhere, text: $0) }))))
            c.accounts.append(Account(id: "acc-oc-oai", displayName: "OpenCode OpenAI",
                                      kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 50)), harness: .openCode,
                                                                           matchRule: .preset(.openCodeOpenAI)))))
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
        // A custom rule is scoped to its harness too.
        c.accounts[1].kind = .tokenBased(TokenBasedSettings(groupId: "grp", harness: .claudeCode,
                                                            matchRule: .custom(field: .anywhere, text: "proj-alpha")))
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

    @Test func customMarkerWinsForEveryHarness() {
        let c = config(markers: ["acc-max": "\"cwd\":\"/Users/tester/private\""])
        let codexLine = "{\"type\":\"session_meta\",\"payload\":{\"cwd\":\"/Users/tester/private\"}}\n{\"type\":\"event_msg\"}"
        #expect(attribute(c, raw(.codex, hint: "apikey"), line: codexLine) == "acc-max")
        let openCodeLine = "{\"role\":\"assistant\",\"providerID\":\"google-vertex\",\"path\":{\"cwd\":\"/Users/tester/private\"}}"
        #expect(attribute(c, raw(.openCode, hint: "google-vertex"), line: openCodeLine,
                          directory: "/Users/tester/.local/share/opencode") == "acc-max")
        // Lines without the marker keep the built-in rule.
        #expect(attribute(c, raw(.openCode, hint: "google-vertex"), line: "{}") == "acc-oc-vertex")
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
        var marked = c
        marked.accounts[1].kind = .tokenBased(TokenBasedSettings(membership: .group(id: "grp", shownInBar: false),
                                                                 matchRule: .custom(field: .anywhere, text: "acme-marker")))
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

    static func token(_ id: String, _ dir: String?, rule: MatchRule? = nil, harness: Harness = .claudeCode,
                      extra: [String] = []) -> Account {
        Account(id: id, displayName: id,
                kind: .tokenBased(TokenBasedSettings(membership: .group(id: "grp", shownInBar: false), harness: harness,
                                                     matchRule: rule, sessionDirectory: dir, additionalSessionDirectories: extra)))
    }

    static func config(_ accounts: [Account]) -> Configuration {
        Configuration(accounts: accounts, groups: [BudgetGroup(id: "grp", name: "Team", budgetUSD: 100)])
    }

    /// The reported setup: Max on the personal profile, Vertex on work, the
    /// gateway with no rule on lab.
    static let threeProfiles = config([
        subscription("max", "~/agent-profiles/personal/claude"),
        token("vertex", "~/agent-profiles/work/claude"),
        token("lab", "~/agent-profiles/lab/claude", rule: MatchRule.none),
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
        // Without a profile, the rules decide: the lab account has none.
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
                             Self.token("lab", "~/agent-profiles/lab/claude", rule: MatchRule.none)])
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
                             Self.token("other", "~/agent-profiles/lab/claude", rule: .custom(field: .model, text: "intranet/"))])
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
        rule.accounts[2] = Self.token("lab", "~/agent-profiles/lab/claude", rule: .custom(field: .model, text: "intranet/"))
        #expect(Attributor(configuration: rule, paths: paths).fingerprint != base)
        #expect(Attributor(configuration: Self.threeProfiles, paths: paths,
                           profileAdditionalDirectories: ["vertex": ["/Users/tester/x"]]).fingerprint == base)
    }
}

// MARK: - Spec 037: rule step

/// spec 037 FR-007, FR-009, FR-010, FR-011, SC-002, US2 scenarios 5 to 7:
/// records without a profile signal count as the match rules say.
@Suite struct RuleStepAttributionTests {
    let paths = Paths(home: URL(fileURLWithPath: "/Users/tester"))
    typealias Make = ProfileAttributionTests

    private func record(_ harness: Harness, requestId: String = "", model: String = "claude-opus-5-5",
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

    /// One row per record: which of the harness's single-account
    /// configurations claims it (SC-002).
    struct Row: CustomTestStringConvertible, Sendable {
        let rule: MatchRule
        let harness: Harness
        let record: RawUsageRecord
        let line: String
        let matches: Bool
        var testDescription: String { "\(harness) \(rule) -> \(matches)" }
    }

    static let gatewayLine = #"{"type":"assistant","cwd":"/Users/tester/proj-alpha","message":{"id":"chatcmpl-1","model":"intranet/glm-5"}}"#

    static func rows() -> [Row] {
        func r(_ harness: Harness, requestId: String = "", model: String = "claude-opus-5-5", messageId: String = "msg_1",
               hint: String? = nil) -> RawUsageRecord {
            var raw = makeRaw(id: messageId, requestId: requestId, model: model)
            raw.harness = harness
            raw.providerHint = hint
            return raw
        }
        let vertexCC = r(.claudeCode, requestId: "req_vrtx_011")
        let gatewayCC = r(.claudeCode, model: "intranet/glm-5", messageId: "chatcmpl-1")
        let apiKey = r(.codex, model: "gpt-5.5", hint: "apikey")
        let plan = r(.codex, model: "gpt-5.5", hint: "chatgpt")
        let ocVertex = r(.openCode, hint: "google-vertex")
        let ocOpenAI = r(.openCode, model: "gpt-5.5", hint: "openai")
        let ocGateway = r(.openCode, model: "intranet/deepseek-v4", hint: "litellm")
        return [
            Row(rule: .preset(.claudeCodeVertex), harness: .claudeCode, record: vertexCC, line: "{}", matches: true),
            Row(rule: .preset(.claudeCodeVertex), harness: .claudeCode, record: gatewayCC, line: "{}", matches: false),
            Row(rule: .custom(field: .model, text: "intranet/"), harness: .claudeCode, record: gatewayCC, line: "{}", matches: true),
            Row(rule: .custom(field: .model, text: "intranet/"), harness: .claudeCode, record: vertexCC, line: "{}", matches: false),
            Row(rule: .custom(field: .requestId, text: "req_vrtx_"), harness: .claudeCode, record: vertexCC, line: "{}", matches: true),
            Row(rule: .custom(field: .messageId, text: "chatcmpl-"), harness: .claudeCode, record: gatewayCC, line: "{}", matches: true),
            Row(rule: .custom(field: .anywhere, text: "proj-alpha"), harness: .claudeCode, record: gatewayCC, line: gatewayLine, matches: true),
            Row(rule: .custom(field: .anywhere, text: "proj-alpha"), harness: .claudeCode, record: gatewayCC, line: "{}", matches: false),
            Row(rule: .none, harness: .claudeCode, record: vertexCC, line: "{}", matches: false),
            Row(rule: .preset(.codexAPIKey), harness: .codex, record: apiKey, line: "{}", matches: true),
            Row(rule: .preset(.codexAPIKey), harness: .codex, record: plan, line: "{}", matches: false),
            Row(rule: .custom(field: .model, text: "gpt-5"), harness: .codex, record: apiKey, line: "{}", matches: true),
            Row(rule: .custom(field: .anywhere, text: "proj-alpha"), harness: .codex, record: apiKey, line: gatewayLine, matches: true),
            Row(rule: .preset(.openCodeVertex), harness: .openCode, record: ocVertex, line: "{}", matches: true),
            Row(rule: .preset(.openCodeVertex), harness: .openCode, record: ocOpenAI, line: "{}", matches: false),
            Row(rule: .preset(.openCodeOpenAI), harness: .openCode, record: ocOpenAI, line: "{}", matches: true),
            Row(rule: .preset(.openCodeOpenAI), harness: .openCode, record: ocVertex, line: "{}", matches: false),
            Row(rule: .custom(field: .model, text: "intranet/"), harness: .openCode, record: ocGateway, line: "{}", matches: true),
            Row(rule: .custom(field: .anywhere, text: "proj-alpha"), harness: .openCode, record: ocGateway, line: gatewayLine, matches: true),
            // FR-008: a rule never claims a record of another harness.
            Row(rule: .preset(.claudeCodeVertex), harness: .claudeCode, record: ocVertex, line: "{}", matches: false),
            Row(rule: .custom(field: .model, text: "intranet/"), harness: .codex, record: ocGateway, line: "{}", matches: false),
            Row(rule: .preset(.openCodeOpenAI), harness: .openCode, record: apiKey, line: "{}", matches: false),
        ]
    }

    @Test(arguments: rows())
    func ruleTable(row: Row) {
        let account = Make.token("acc", nil, rule: row.rule, harness: row.harness)
        #expect((attribute([account], row.record, line: row.line) == "acc") == row.matches)
    }

    /// Clarification: custom texts compare case-sensitively.
    @Test func customTextsAreCaseSensitive() {
        let gateway = record(.claudeCode, model: "intranet/glm-5")
        #expect(attribute([Make.token("lab", nil, rule: .custom(field: .model, text: "INTRANET/"))], gateway) == nil)
        #expect(attribute([Make.token("lab", nil, rule: .custom(field: .model, text: "intranet/"))], gateway) == "lab")
    }

    /// FR-010: a custom rule beats a preset that also matches.
    @Test func customRuleBeatsAPreset() {
        let accounts = [Make.token("vertex", nil), Make.token("lab", "~/agent-profiles/lab/claude", rule: .custom(field: .requestId, text: "req_vrtx_"))]
        #expect(attribute(accounts, record(.claudeCode, requestId: "req_vrtx_1")) == "lab")
        // Two matching custom rules tie.
        let two = accounts + [Make.token("other", nil, rule: .custom(field: .model, text: "claude-"))]
        #expect(attribute(two, record(.claudeCode, requestId: "req_vrtx_1")) == nil)
    }

    /// US2 scenario 5: the gateway profile's older sessions find it through
    /// its custom rule.
    @Test func customModelRuleClaimsRecordsWithoutProfile() {
        let accounts = [Make.subscription("max", "~/agent-profiles/personal/claude"), Make.token("vertex", "~/agent-profiles/work/claude"),
                        Make.token("lab", "~/agent-profiles/lab/claude", rule: .custom(field: .model, text: "intranet/"))]
        #expect(attribute(accounts, record(.claudeCode, model: "intranet/deepseek-v4", messageId: "chatcmpl-3")) == "lab")
        #expect(attribute(accounts, record(.claudeCode, requestId: "req_vrtx_1")) == "vertex")
        #expect(attribute(accounts, record(.claudeCode, requestId: "req_011abc")) == "max")
    }

    /// US2 scenario 6: "None (profile only)" never claims a record without
    /// a profile signal.
    @Test func noneNeverClaimsWithoutProfile() {
        let accounts = [Make.token("lab", "~/agent-profiles/lab/claude", rule: MatchRule.none)]
        for r in [record(.claudeCode, requestId: "req_vrtx_1"), record(.claudeCode, model: "intranet/glm-5"), record(.claudeCode, requestId: "req_011a")] {
            #expect(attribute(accounts, r) == nil)
        }
    }

    /// FR-009: subscriptions keep their implicit rules and markers; the
    /// Claude rule still yields to a Claude Code preset.
    @Test func subscriptionsKeepTheirRules() {
        let accounts = [Make.subscription("max", "~/.claude"), Make.token("vertex", nil),
                        Account(id: "plus", displayName: "Plus", kind: .codexSubscription(CodexSubscriptionSettings()))]
        #expect(attribute(accounts, record(.claudeCode, requestId: "req_011abc")) == "max")
        #expect(attribute(accounts, record(.claudeCode, requestId: "req_vrtx_1")) == "vertex")
        #expect(attribute(accounts, record(.codex, hint: "chatgpt")) == "plus")
        var marked = accounts
        marked[0].customMarker = "proj-alpha"
        #expect(attribute(marked, record(.claudeCode, requestId: "req_vrtx_1"), line: "proj-alpha") == "max")
    }

    /// US2 scenario 7: a harness or rule change re-attributes (the
    /// fingerprint changes) and never asks the usage endpoint.
    @Test func ruleChangesReattributeWithoutANetworkRequest() {
        let base = Make.config([Make.subscription("max", "~/.claude"), Make.token("lab", nil)])
        var rule = base
        rule.accounts[1] = Make.token("lab", nil, rule: .custom(field: .model, text: "intranet/"))
        var harness = base
        harness.accounts[1] = Make.token("lab", nil, harness: .openCode)
        for edited in [rule, harness] {
            #expect(Attributor(configuration: edited, paths: paths).fingerprint != Attributor(configuration: base, paths: paths).fingerprint)
            #expect(edited.needsRefresh(comparedTo: base))
            #expect(!edited.needsNetworkRefresh(comparedTo: base))
        }
        // A custom text change counts too.
        var text = rule
        text.accounts[1] = Make.token("lab", nil, rule: .custom(field: .model, text: "intranet/glm"))
        #expect(Attributor(configuration: text, paths: paths).fingerprint != Attributor(configuration: rule, paths: paths).fingerprint)
    }

    /// `needsRawLine` is true only when some rule searches the raw line.
    @Test func needsRawLineFollowsTheRules() {
        #expect(!Attributor(configuration: Make.config([Make.token("a", nil)]), paths: paths).needsRawLine)
        #expect(!Attributor(configuration: Make.config([Make.token("a", nil, rule: .custom(field: .model, text: "x"))]), paths: paths).needsRawLine)
        #expect(Attributor(configuration: Make.config([Make.token("a", nil, rule: .custom(field: .anywhere, text: "x"))]), paths: paths).needsRawLine)
        var marked = Make.config([Make.subscription("max", "~/.claude")])
        marked.accounts[0].customMarker = "x"
        #expect(Attributor(configuration: marked, paths: paths).needsRawLine)
    }
}
