import Foundation
import Testing
@testable import UsageCore

@Suite struct AttributionTests {
    let paths = Paths(home: URL(fileURLWithPath: "/Users/tester"))

    private func config(subscriptions: [(id: String, dir: String, marker: String?)] = [("acc-max", "~/.claude", nil)],
                        vertex: [(id: String, marker: String?)] = [("acc-vertex", nil)]) -> Configuration {
        var c = Configuration()
        c.accounts = subscriptions.map {
            Account(id: $0.id, label: String($0.id.suffix(2)), displayName: $0.id,
                    kind: .subscription(SubscriptionSettings(credentialDirectory: $0.dir, shownInBar: true, thresholds: [])),
                    customMarker: $0.marker)
        } + vertex.map {
            Account(id: $0.id, label: String($0.id.suffix(2)), displayName: $0.id,
                    kind: .tokenBased(TokenBasedSettings(groupId: "grp", provider: .vertex)), customMarker: $0.marker)
        }
        if !vertex.isEmpty {
            c.groups = [BudgetGroup(id: "grp", name: "Vertex", label: "G", budgetUSD: 60)]
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
        let c = config(subscriptions: [("acc-max", "~/.claude", nil), ("acc-work", "~/.local/share/cc-deck/profiles/work/claude", nil)])
        #expect(attribute(c, requestId: "req_011abc", directory: "/Users/tester/.claude") == "acc-max")
        #expect(attribute(c, requestId: "req_011abc", directory: "/Users/tester/.local/share/cc-deck/profiles/work/claude") == "acc-work")
        #expect(attribute(c, requestId: "req_011abc", directory: "/Users/tester/.local/share/cc-deck/profiles/work/claude/") == "acc-work")
        // A directory that belongs to neither account cannot decide.
        #expect(attribute(c, requestId: "req_011abc", directory: "/Users/tester/elsewhere") == nil)
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
