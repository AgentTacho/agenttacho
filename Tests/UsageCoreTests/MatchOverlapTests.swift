import Foundation
import Testing
@testable import UsageCore

/// spec 038 FR-009, US1 scenario 4, research R12: overlap warnings appear
/// for exactly the token-based accounts that neither the Claude Code
/// directory nor kind and condition can separate.
@Suite struct MatchOverlapTests {
    static let paths = Paths(home: URL(fileURLWithPath: "/Users/tester"))
    typealias Make = ProfileAttributionTests

    static func overlaps(_ accounts: [Account]) -> [MatchOverlap] {
        Make.config(accounts).matchOverlaps(paths: paths)
    }

    /// Same harness, kind, no condition and directory (empty is
    /// `~/.claude`) warn on both accounts, each naming the other.
    @Test func sameKindAndDirectoryOverlap() {
        let result = Self.overlaps([Make.token("a", nil), Make.token("b", "~/.claude")])
        #expect(result == [MatchOverlap(accountId: "a", otherNames: ["b"]), MatchOverlap(accountId: "b", otherNames: ["a"])])
        #expect(Make.config([Make.token("a", nil), Make.token("b", nil)]).matchOverlap(forAccount: "a", paths: Self.paths)
                == MatchOverlap(accountId: "a", otherNames: ["b"]))
        #expect(Self.overlaps([Make.token("a", nil, kind: .claudeCodeOtherProvider),
                               Make.token("b", nil, kind: .claudeCodeOtherProvider)]).count == 2)
    }

    /// Different Claude Code directories separate them.
    @Test func differentDirectoriesDoNotOverlap() {
        #expect(Self.overlaps([Make.token("a", "~/agent-profiles/work/claude"), Make.token("b", "~/agent-profiles/lab/claude")]).isEmpty)
        #expect(Self.overlaps([Make.token("a", nil), Make.token("b", "~/agent-profiles/lab/claude")]).isEmpty)
    }

    /// US1 scenario 4: two Codex API key accounts without a condition warn,
    /// whatever their Codex homes; OpenCode accounts of one kind too.
    @Test func codexAndOpenCodeOverlapOnKindAndCondition() {
        #expect(Self.overlaps([Make.token("a", "~/.codex", harness: .codex), Make.token("b", "~/.codex-lab", harness: .codex)])
                == [MatchOverlap(accountId: "a", otherNames: ["b"]), MatchOverlap(accountId: "b", otherNames: ["a"])])
        #expect(Self.overlaps([Make.token("a", nil, harness: .openCode), Make.token("b", nil, harness: .openCode)]).count == 2)
        #expect(Self.overlaps([Make.token("a", nil, harness: .openCode),
                               Make.token("b", nil, kind: .openCodeOpenAI, harness: .openCode)]).isEmpty)
    }

    /// Subscriptions never appear; a Claude subscription and a Vertex
    /// account on `~/.claude` are separated by their kinds.
    @Test func subscriptionsNeverOverlap() {
        #expect(Self.overlaps([Make.subscription("max", ""), Make.token("vertex", nil)]).isEmpty)
        #expect(Self.overlaps([Make.subscription("max", "~/.claude"), Make.subscription("pro", "~/.claude-pro")]).isEmpty)
    }

    /// Different kinds, conditions or harnesses separate accounts; equal
    /// conditions do not.
    @Test func kindsConditionsAndHarnessesSeparate() {
        #expect(Self.overlaps([Make.token("a", nil), Make.token("b", nil, kind: .claudeCodeOtherProvider)]).isEmpty)
        #expect(Self.overlaps([Make.token("a", nil), Make.token("b", nil, condition: Make.model(.startsWith, "intranet/"))]).isEmpty)
        #expect(Self.overlaps([Make.token("a", nil, condition: Make.model(.startsWith, "intranet/")),
                               Make.token("b", nil, condition: Make.model(.startsWith, "intranet/glm"))]).isEmpty)
        #expect(Self.overlaps([Make.token("a", nil, condition: Make.model(.startsWith, "intranet/")),
                               Make.token("b", nil, condition: MatchCondition(field: .anywhere, operator: .contains, text: "intranet/"))]).isEmpty)
        #expect(Self.overlaps([Make.token("a", nil, condition: Make.model(.startsWith, "intranet/")),
                               Make.token("b", nil, condition: Make.model(.startsWith, "intranet/"))]).count == 2)
        // The same condition on different kinds does not overlap.
        #expect(Self.overlaps([Make.token("a", nil, condition: Make.model(.contains, "glm")),
                               Make.token("b", nil, kind: .claudeCodeOtherProvider, condition: Make.model(.contains, "glm"))]).isEmpty)
        #expect(Self.overlaps([Make.token("a", nil), Make.token("b", nil, harness: .openCode)]).isEmpty)
    }

    /// research R12: Directory only accounts never appear; their directory
    /// alone separates them (their own warning is `directoryOnlyConflict`).
    @Test func directoryOnlyNeverOverlaps() {
        #expect(Self.overlaps([Make.token("a", nil, kind: .claudeCodeDirectoryOnly),
                               Make.token("b", "~/.claude/", kind: .claudeCodeDirectoryOnly)]).isEmpty)
        #expect(Self.overlaps([Make.token("a", nil, kind: .claudeCodeDirectoryOnly, condition: Make.model(.contains, "glm")),
                               Make.token("b", nil, kind: .claudeCodeDirectoryOnly, condition: Make.model(.contains, "glm"))]).isEmpty)
    }

    /// Three accounts in one group: each names the two others, in account
    /// order; an account outside the group gets nothing.
    @Test func groupsOfThreeNameBothOthers() {
        let result = Self.overlaps([Make.token("a", nil), Make.token("x", "~/agent-profiles/lab/claude"), Make.token("b", nil),
                                    Make.token("c", nil)])
        #expect(result.map(\.accountId) == ["a", "b", "c"])
        #expect(result[0].otherNames == ["b", "c"])
        #expect(result[1].otherNames == ["a", "c"])
        #expect(Make.config([Make.token("x", nil)]).matchOverlap(forAccount: "x", paths: Self.paths) == nil)
    }

    /// FR-009: equal field and operator with literal texts equal ignoring
    /// case overlap; regex patterns compare exactly; a different operator
    /// or text does not.
    @Test func overlapComparesOperatorAndTextIgnoringCase() {
        func token(_ id: String, _ op: MatchOperator, _ text: String) -> Account {
            Make.token(id, nil, kind: .claudeCodeOtherProvider, condition: Make.model(op, text))
        }
        #expect(Self.overlaps([token("a", .contains, "GLM"), token("b", .contains, "glm")]).count == 2)
        #expect(Self.overlaps([token("a", .startsWith, "Gateway-A/"), token("b", .startsWith, "gateway-a/")]).count == 2)
        // Case is meaningful in a pattern (`\d` is not `\D`), so patterns compare as written.
        #expect(Self.overlaps([token("a", .regex, "\\d+"), token("b", .regex, "\\D+")]).isEmpty)
        #expect(Self.overlaps([token("a", .regex, "^gateway-a/"), token("b", .regex, "^gateway-a/")]).count == 2)
        #expect(Self.overlaps([token("a", .contains, "glm"), token("b", .startsWith, "glm")]).isEmpty)
        #expect(Self.overlaps([token("a", .contains, "glm"), token("b", .regex, "glm")]).isEmpty)
        // Different texts that match the same records get no warning.
        #expect(Self.overlaps([token("a", .contains, "glm"), token("b", .contains, "gl")]).isEmpty)
    }

    @Test func overlapKeyFoldsUnicodeCase() {
        #expect(MatchCondition(field: .anywhere, operator: .contains, text: "PROJ-Ä").overlapKey
                == MatchCondition(field: .anywhere, operator: .contains, text: "proj-ä").overlapKey)
        #expect(MatchCondition(field: .anywhere, operator: .contains, text: "proj-a").overlapKey
                != MatchCondition(field: .anywhere, operator: .contains, text: "proj-ä").overlapKey)
    }

    // MARK: - Shared Claude Code directory (walkthrough feedback)

    /// Any token-based Claude Code account learns which other accounts use
    /// its main Claude Code directory, for its directory note.
    @Test func sharedDirectoryNamesTheOtherAccountsOfAnyKind() {
        let accounts = [Make.subscription("max", "~/.claude"), Make.token("vtx", nil, kind: .claudeCodeVertex),
                        Make.token("gw", "~/.claude-gateway", kind: .claudeCodeOtherProvider)]
        let config = Make.config(accounts)
        #expect(config.sharedClaudeCodeDirectory(forAccount: "vtx", paths: Self.paths) == ["max"])
        #expect(config.sharedClaudeCodeDirectory(forAccount: "gw", paths: Self.paths).isEmpty)
        #expect(config.sharedClaudeCodeDirectory(forAccount: "missing", paths: Self.paths).isEmpty)
    }

    // MARK: - Directory only conflict (FR-013 item 6, research R12)

    static func conflict(_ accounts: [Account], _ id: String) -> DirectoryOnlyConflict? {
        Make.config(accounts).directoryOnlyConflict(forAccount: id, paths: paths)
    }

    /// An empty field is `~/.claude`, shared with a Claude subscription.
    @Test func directoryOnlyNextToASubscriptionNamesIt() {
        let accounts = [Make.subscription("max", "~/.claude"), Make.token("lab", nil, kind: .claudeCodeDirectoryOnly)]
        #expect(Self.conflict(accounts, "lab") == DirectoryOnlyConflict(accountId: "lab", otherNames: ["max"]))
        #expect(Self.conflict(accounts, "max") == nil)
    }

    @Test func directoryOnlyNextToAVertexAccountNamesIt() {
        let accounts = [Make.token("vertex", "~/.claude-gateway"), Make.token("lab", "~/.claude-gateway", kind: .claudeCodeDirectoryOnly)]
        #expect(Self.conflict(accounts, "lab") == DirectoryOnlyConflict(accountId: "lab", otherNames: ["vertex"]))
        // The Vertex account is not Directory only: no conflict of its own.
        #expect(Self.conflict(accounts, "vertex") == nil)
    }

    @Test func twoDirectoryOnlyAccountsNameEachOther() {
        let accounts = [Make.token("a", "~/.claude-gateway", kind: .claudeCodeDirectoryOnly),
                        Make.token("b", "~/.claude-gateway/", kind: .claudeCodeDirectoryOnly),
                        Make.subscription("max", "~/.claude-gateway")]
        #expect(Self.conflict(accounts, "a") == DirectoryOnlyConflict(accountId: "a", otherNames: ["b", "max"]))
        #expect(Self.conflict(accounts, "b") == DirectoryOnlyConflict(accountId: "b", otherNames: ["a", "max"]))
    }

    /// A symlinked alias of the directory counts as the same directory.
    @Test func symlinkedAliasCountsAsTheSameDirectory() throws {
        let root = try makeTempDirectory("directory-only-alias")
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("claude-real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let alias = root.appendingPathComponent("claude-alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
        let accounts = [Make.subscription("max", real.path), Make.token("lab", alias.path, kind: .claudeCodeDirectoryOnly)]
        #expect(Self.conflict(accounts, "lab") == DirectoryOnlyConflict(accountId: "lab", otherNames: ["max"]))
    }

    /// Different directories, other harnesses and other kinds give none.
    @Test func noConflictOtherwise() {
        #expect(Self.conflict([Make.subscription("max", "~/.claude"),
                               Make.token("lab", "~/.claude-gateway", kind: .claudeCodeDirectoryOnly)], "lab") == nil)
        #expect(Self.conflict([Make.token("oai", nil, harness: .codex), Make.token("oc", nil, harness: .openCode),
                               Make.token("lab", nil, kind: .claudeCodeDirectoryOnly)], "lab") == nil)
        #expect(Self.conflict([Make.token("oai", "~/.codex", harness: .codex), Make.token("other", "~/.codex", harness: .codex)], "oai") == nil)
        #expect(Self.conflict([Make.subscription("max", "~/.claude"), Make.token("gw", nil, kind: .claudeCodeOtherProvider)], "gw") == nil)
        #expect(Self.conflict([Make.token("lab", nil, kind: .claudeCodeDirectoryOnly)], "missing") == nil)
    }
}
