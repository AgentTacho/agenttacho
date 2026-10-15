import Foundation
import Testing
@testable import UsageCore

/// Spec 008 FR-001, FR-004, FR-011: the stored arrangement, its coding, and
/// the tolerant resolution into `arrangedEntries`.
@Suite struct ArrangementTests {
    /// Accounts list: sub-a, own-x, m1 (of g1), codex, m3 (of g1), sub-b,
    /// m2 (of g2), orphan (member of a group that does not exist).
    /// Groups list: g2, then g1.
    static func config(arrangement: Arrangement? = nil) -> Configuration {
        var c = Configuration()
        c.accounts = [
            Account(id: "sub-a", displayName: "Max", kind: .subscription(SubscriptionSettings(credentialDirectory: "~/.a"))),
            Account(id: "own-x", displayName: "Personal",
                    kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 100))))),
            Account(id: "m1", displayName: "Member one", kind: .tokenBased(TokenBasedSettings(groupId: "g1"))),
            Account(id: "codex", displayName: "ChatGPT", harness: .codex, kind: .codexSubscription(CodexSubscriptionSettings())),
            Account(id: "m3", displayName: "Member three", kind: .tokenBased(TokenBasedSettings(groupId: "g1"))),
            Account(id: "sub-b", displayName: "Work", kind: .subscription(SubscriptionSettings(credentialDirectory: "~/.b"))),
            Account(id: "m2", displayName: "Member two", kind: .tokenBased(TokenBasedSettings(groupId: "g2"))),
            Account(id: "orphan", displayName: "Orphan", kind: .tokenBased(TokenBasedSettings(groupId: "missing"))),
        ]
        c.groups = [
            BudgetGroup(id: "g2", name: "Team", budgetUSD: 300),
            BudgetGroup(id: "g1", name: "Vertex", budgetUSD: 10),
        ]
        c.arrangement = arrangement
        return c
    }

    static func ids(_ entries: [ArrangedEntry]) -> [String] { entries.map(\.id) }

    static func members(_ entries: [ArrangedEntry], of groupId: String) -> [String]? {
        for entry in entries {
            if case .group(let group, let members) = entry, group.id == groupId { return members.map(\.id) }
        }
        return nil
    }

    static let defaultIds = ["account:sub-a", "account:own-x", "account:codex", "account:sub-b", "group:g2", "group:g1"]

    // MARK: Coding

    @Test func arrangementRoundTrip() throws {
        let arrangement = Arrangement(entries: [EntryRef(kind: .group, id: "g1"), EntryRef(kind: .account, id: "sub-a")],
                                      members: ["g1": ["m3", "m1"]])
        let data = try JSONEncoder().encode(arrangement)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try #require(json["entries"] as? [[String: String]])
        #expect(entries == [["kind": "group", "id": "g1"], ["kind": "account", "id": "sub-a"]])
        #expect(json["members"] as? [String: [String]] == ["g1": ["m3", "m1"]])
        #expect(try JSONDecoder().decode(Arrangement.self, from: data) == arrangement)
    }

    /// FR-004: without the key nothing is stored, and encoding adds nothing.
    @Test func configurationWithoutArrangement() throws {
        let decoded = try JSONDecoder().decode(Configuration.self, from: Data(contractExampleJSON.utf8))
        #expect(decoded.arrangement == nil)
        let data = try JSONEncoder().encode(decoded)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["arrangement"] == nil)
        #expect(json["accounts"] != nil)
    }

    @Test func configurationWithArrangementRoundTrips() throws {
        let config = Self.config(arrangement: Arrangement(entries: [EntryRef(kind: .group, id: "g1")], members: ["g1": ["m3"]]))
        let data = try JSONEncoder().encode(config)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["arrangement"] != nil)
        #expect(try JSONDecoder().decode(Configuration.self, from: data) == config)
    }

    /// FR-011: malformed references are dropped one by one, never a
    /// configuration error.
    @Test func malformedReferencesAreDroppedWhenDecoding() throws {
        let json = """
        {
          "version": 1,
          "accounts": [
            { "id": "sub-a", "type": "subscription", "displayName": "A", "credentialDirectory": "~/.a" },
            { "id": "sub-b", "type": "subscription", "displayName": "B", "credentialDirectory": "~/.b" }
          ],
          "arrangement": {
            "entries": [
              { "kind": "widget", "id": "sub-a" },
              { "id": "sub-a" },
              42,
              { "kind": "account", "id": "sub-b" }
            ],
            "members": { "g": ["x", 7], "h": "not a list" }
          }
        }
        """
        let config = try JSONDecoder().decode(Configuration.self, from: Data(json.utf8))
        #expect(config.arrangement?.entries == [EntryRef(kind: .account, id: "sub-b")])
        #expect(config.arrangement?.members == ["g": ["x"]])
        #expect(Self.ids(config.arrangedEntries) == ["account:sub-b", "account:sub-a"])
        try config.validate()

        let missingParts = try JSONDecoder().decode(Arrangement.self, from: Data("{}".utf8))
        #expect(missingParts == Arrangement(entries: [], members: [:]))
    }

    /// FR-011: an arrangement of the wrong shape is no configuration error;
    /// the default order applies.
    @Test(arguments: [
        "42", "\"text\"", "[]", "null", "true",
        "{ \"entries\": \"x\" }", "{ \"entries\": null }", "{ \"entries\": {} }",
        "{ \"members\": [] }", "{ \"members\": 5 }", "{ \"entries\": [], \"members\": null }",
    ])
    func malformedArrangementShapesAreIgnored(arrangement: String) throws {
        let json = """
        {
          "version": 1,
          "accounts": [
            { "id": "sub-a", "type": "subscription", "displayName": "A", "credentialDirectory": "~/.a" },
            { "id": "sub-b", "type": "subscription", "displayName": "B", "credentialDirectory": "~/.b" }
          ],
          "arrangement": \(arrangement)
        }
        """
        let config = try JSONDecoder().decode(Configuration.self, from: Data(json.utf8))
        try config.validate()
        #expect(config.arrangement?.entries.isEmpty ?? true)
        #expect(Self.ids(config.arrangedEntries) == ["account:sub-a", "account:sub-b"])
    }

    // MARK: Resolution

    /// FR-011: nothing stored reproduces the spec 004 FR-020 bar order.
    @Test func defaultOrderMatchesThePreviousBarOrder() {
        let entries = Self.config().arrangedEntries
        #expect(Self.ids(entries) == Self.defaultIds)
        #expect(Self.members(entries, of: "g1") == ["m1", "m3"])
        #expect(Self.members(entries, of: "g2") == ["m2"])
    }

    @Test func storedOrderIsFollowed() {
        let stored = Arrangement(entries: [
            EntryRef(kind: .group, id: "g1"), EntryRef(kind: .account, id: "codex"), EntryRef(kind: .account, id: "sub-b"),
            EntryRef(kind: .account, id: "own-x"), EntryRef(kind: .account, id: "sub-a"), EntryRef(kind: .group, id: "g2"),
        ], members: ["g1": ["m3", "m1"], "g2": ["m2"]])
        let entries = Self.config(arrangement: stored).arrangedEntries
        #expect(Self.ids(entries) == ["group:g1", "account:codex", "account:sub-b", "account:own-x", "account:sub-a", "group:g2"])
        #expect(Self.members(entries, of: "g1") == ["m3", "m1"])
        #expect(Self.config(arrangement: stored).asArrangement(entries) == stored)
    }

    /// FR-011: unknown ids, duplicates and references at the wrong level are
    /// ignored; the missing items follow in default order.
    @Test func staleAndMisplacedReferencesAreIgnored() {
        let stored = Arrangement(entries: [
            EntryRef(kind: .group, id: "nope"),
            EntryRef(kind: .account, id: "m1"),        // a member among the entries
            EntryRef(kind: .account, id: "orphan"),    // neither entry nor member
            EntryRef(kind: .group, id: "g1"),
            EntryRef(kind: .account, id: "sub-b"),
            EntryRef(kind: .account, id: "sub-b"),     // duplicate
            EntryRef(kind: .group, id: "g1"),          // duplicate
            EntryRef(kind: .account, id: "g1"),        // no account g1
        ], members: [
            "g1": ["m3", "own-x", "m2", "ghost", "m3"], // entry as member, wrong group, unknown, duplicate
            "ghost-group": ["m1"],
        ])
        let entries = Self.config(arrangement: stored).arrangedEntries
        #expect(Self.ids(entries) == ["group:g1", "account:sub-b", "account:sub-a", "account:own-x", "account:codex", "group:g2"])
        #expect(Self.members(entries, of: "g1") == ["m3", "m1"])
        #expect(Self.members(entries, of: "g2") == ["m2"])
    }

    /// Research R1: a group and an account sharing an id are distinct entries.
    @Test func sharedIdsAreDistinctEntries() {
        var c = Configuration()
        c.accounts = [
            Account(id: "sub", displayName: "Max", kind: .subscription(SubscriptionSettings())),
            Account(id: "x", displayName: "Own x", kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 5))))),
            Account(id: "m", displayName: "Member", kind: .tokenBased(TokenBasedSettings(groupId: "x"))),
        ]
        c.groups = [BudgetGroup(id: "x", name: "Group x", budgetUSD: 10)]
        #expect(Self.ids(c.arrangedEntries) == ["account:sub", "account:x", "group:x"])

        c.arrangement = Arrangement(entries: [EntryRef(kind: .group, id: "x"), EntryRef(kind: .account, id: "sub")], members: [:])
        let entries = c.arrangedEntries
        #expect(Self.ids(entries) == ["group:x", "account:sub", "account:x"])
        #expect(Set(Self.ids(entries)).count == entries.count)
        #expect(entries.map(\.ref) == [EntryRef(kind: .group, id: "x"), EntryRef(kind: .account, id: "sub"), EntryRef(kind: .account, id: "x")])
    }

    /// Accounts that are neither entries nor members are not listed.
    @Test func accountsThatAreNeitherEntryNorMemberAreNotListed() {
        let c = Self.config()
        let listed = c.arrangedEntries.flatMap { entry -> [String] in
            switch entry {
            case .account(let account): return [account.id]
            case .group(_, let members): return members.map(\.id)
            }
        }
        #expect(!listed.contains("orphan"))
        #expect(c.isEntry(c.account(id: "sub-a")!))
        #expect(c.isEntry(c.account(id: "codex")!))
        #expect(c.isEntry(c.account(id: "own-x")!))
        #expect(!c.isEntry(c.account(id: "m1")!))
        #expect(!c.isEntry(c.account(id: "orphan")!))
    }

    @Test func defaultArrangementListsEveryEntryAndMember() {
        var c = Self.config(arrangement: Arrangement(entries: [EntryRef(kind: .group, id: "g1")], members: [:]))
        c.groups.append(BudgetGroup(id: "empty", name: "Empty", budgetUSD: 1))
        let expected = Arrangement(entries: [
            EntryRef(kind: .account, id: "sub-a"), EntryRef(kind: .account, id: "own-x"), EntryRef(kind: .account, id: "codex"),
            EntryRef(kind: .account, id: "sub-b"), EntryRef(kind: .group, id: "g2"), EntryRef(kind: .group, id: "g1"),
            EntryRef(kind: .group, id: "empty"),
        ], members: ["g2": ["m2"], "g1": ["m1", "m3"], "empty": []])
        #expect(c.defaultArrangement == expected)
    }
}
