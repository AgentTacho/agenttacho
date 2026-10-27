import Foundation
import Testing
@testable import UsageCore

/// spec 037 FR-013, SC-006, US3 scenarios 1 to 4: overlap warnings appear
/// for exactly the token-based accounts neither step can separate.
@Suite struct MatchOverlapTests {
    static let paths = Paths(home: URL(fileURLWithPath: "/Users/tester"))
    typealias Make = ProfileAttributionTests

    static func overlaps(_ accounts: [Account]) -> [MatchOverlap] {
        Make.config(accounts).matchOverlaps(paths: paths)
    }

    /// US3 scenario 1: same harness, rule and directory (empty is
    /// `~/.claude`) warn on both accounts, each naming the other.
    @Test func sameRuleAndDirectoryOverlap() {
        let result = Self.overlaps([Make.token("a", nil), Make.token("b", "~/.claude")])
        #expect(result == [MatchOverlap(accountId: "a", otherNames: ["b"]), MatchOverlap(accountId: "b", otherNames: ["a"])])
        #expect(Make.config([Make.token("a", nil), Make.token("b", nil)]).matchOverlap(forAccount: "a", paths: Self.paths)
                == MatchOverlap(accountId: "a", otherNames: ["b"]))
    }

    /// US3 scenario 2: different Claude Code directories separate them.
    @Test func differentDirectoriesDoNotOverlap() {
        #expect(Self.overlaps([Make.token("a", "~/agent-profiles/work/claude"), Make.token("b", "~/agent-profiles/lab/claude")]).isEmpty)
        #expect(Self.overlaps([Make.token("a", nil), Make.token("b", "~/agent-profiles/lab/claude")]).isEmpty)
    }

    /// US3 scenario 3: Codex and OpenCode accounts overlap on the rule
    /// alone, since no profile separates them.
    @Test func codexAndOpenCodeOverlapOnTheRule() {
        #expect(Self.overlaps([Make.token("a", "~/.codex", harness: .codex), Make.token("b", "~/.codex-lab", harness: .codex)]).count == 2)
        #expect(Self.overlaps([Make.token("a", nil, harness: .openCode), Make.token("b", nil, harness: .openCode)]).count == 2)
        #expect(Self.overlaps([Make.token("a", nil, harness: .openCode),
                               Make.token("b", nil, rule: .preset(.openCodeOpenAI), harness: .openCode)]).isEmpty)
    }

    /// US3 scenario 4: subscriptions never appear; a Claude subscription and
    /// a Vertex account on `~/.claude` are separated by their rules.
    @Test func subscriptionsNeverOverlap() {
        #expect(Self.overlaps([Make.subscription("max", ""), Make.token("vertex", nil)]).isEmpty)
        #expect(Self.overlaps([Make.subscription("max", "~/.claude"), Make.subscription("pro", "~/.claude-pro")]).isEmpty)
    }

    /// Different rules or harnesses separate accounts; equal custom rules,
    /// and two "None" rules on one directory, do not.
    @Test func rulesAndHarnessesSeparate() {
        #expect(Self.overlaps([Make.token("a", nil), Make.token("b", nil, rule: .custom(field: .model, text: "intranet/"))]).isEmpty)
        #expect(Self.overlaps([Make.token("a", nil, rule: .custom(field: .model, text: "intranet/")),
                               Make.token("b", nil, rule: .custom(field: .model, text: "intranet/glm"))]).isEmpty)
        #expect(Self.overlaps([Make.token("a", nil, rule: .custom(field: .model, text: "intranet/")),
                               Make.token("b", nil, rule: .custom(field: .anywhere, text: "intranet/"))]).isEmpty)
        #expect(Self.overlaps([Make.token("a", nil, rule: .custom(field: .model, text: "intranet/")),
                               Make.token("b", nil, rule: .custom(field: .model, text: "intranet/"))]).count == 2)
        #expect(Self.overlaps([Make.token("a", nil, rule: MatchRule.none), Make.token("b", "~/.claude/", rule: MatchRule.none)]).count == 2)
        #expect(Self.overlaps([Make.token("a", nil), Make.token("b", nil, harness: .openCode)]).isEmpty)
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
}
