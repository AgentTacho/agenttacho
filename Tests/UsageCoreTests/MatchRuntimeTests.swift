import Foundation
import Testing
@testable import UsageCore

/// spec 038 FR-006, SC-004, research R3, R4: precompiled rules, the
/// per-record time limit and sitting out for the rest of the refresh.
/// Serialized: two tests measure wall-clock time.
@Suite(.serialized) struct MatchRuntimeTests {
    static let pathological = MatchCondition(field: .anywhere, operator: .regex, text: "(a+)+$")
    static let slowLine = String(repeating: "a", count: 40) + "b"

    private func record(model: String = "claude-opus-5-5") -> RawUsageRecord {
        // No request id: a record of Claude Code Other provider.
        makeRaw(id: "msg_1", requestId: "", model: model)
    }

    private func runtime(_ rules: [(String, MatchCondition)], limit: Duration = MatchCondition.regexLimit) -> MatchRuntime {
        MatchRuntime(rules: rules.map { MatchRuntime.Entry(id: $0.0, name: "Account \($0.0)", condition: $0.1) }, limit: limit)
    }

    /// A precompiled condition decides like `MatchCondition.matches`.
    @Test(arguments: [
        (MatchCondition(field: .model, operator: .regex, text: "^gateway-(a|b)/"), "GATEWAY-B/glm-5", "{}"),
        (MatchCondition(field: .model, operator: .regex, text: "^gateway-(a|b)/"), "gateway-c/glm-5", "{}"),
        (MatchCondition(field: .model, operator: .contains, text: "glm"), "intranet/GLM-5", "{}"),
        (MatchCondition(field: .model, operator: .startsWith, text: "intranet/"), "gateway-a/glm-5", "{}"),
        (MatchCondition(field: .anywhere, operator: .regex, text: #""provider":"gw-[0-9]+""#), "m", #"{"provider":"gw-42"}"#),
        (MatchCondition(field: .model, operator: .regex, text: "^gateway-(a"), "gateway-(a", "{}"),
    ])
    func precompiledMatchesLikeTheRule(rule: MatchCondition, model: String, line: String) {
        let r = record(model: model)
        #expect(runtime([("a", rule)]).matches(candidateId: "a", record: r, rawLine: line) == rule.matches(record: r, rawLine: line))
    }

    /// FR-006: a time-out counts as no match, and the rule sits out the
    /// rest of the runtime's life; other candidates are unaffected.
    @Test func timeOutSitsOutTheRule() {
        let runtime = runtime([("slow", Self.pathological),
                               ("other", MatchCondition(field: .anywhere, operator: .contains, text: "aaab"))],
                              limit: .milliseconds(20))
        #expect(runtime.timeOuts == 0)
        #expect(!runtime.matches(candidateId: "slow", record: record(), rawLine: Self.slowLine))
        #expect(runtime.timeOuts == 1)
        #expect(runtime.skippedDecisions == 1)
        // Later records return false without matching, even one that
        // would match, and each counts as a skipped decision.
        #expect(!runtime.matches(candidateId: "slow", record: record(), rawLine: "aaaa"))
        #expect(!runtime.matches(candidateId: "slow", record: record(), rawLine: "aa"))
        #expect(runtime.timeOuts == 1)
        #expect(runtime.skippedDecisions == 3)
        #expect(runtime.matches(candidateId: "other", record: record(), rawLine: Self.slowLine))
        #expect(runtime.skippedDecisions == 3)
        #expect(runtime.drainSitOutAccounts() == ["Account slow"])
        #expect(runtime.drainSitOutAccounts().isEmpty)
    }

    /// FR-006: the next refresh (a new runtime) tries the rule again.
    @Test func newRuntimeStartsActive() {
        let first = runtime([("slow", Self.pathological)], limit: .milliseconds(20))
        _ = first.matches(candidateId: "slow", record: record(), rawLine: Self.slowLine)
        let next = runtime([("slow", Self.pathological)], limit: .milliseconds(20))
        #expect(next.matches(candidateId: "slow", record: record(), rawLine: "aaaa"))
        #expect(next.timeOuts == 0)
        #expect(next.skippedDecisions == 0)
    }

    /// FR-006, SC-004: a skip marks the records for another attribution,
    /// per rule; a rule that times out in a retry is given up, and only its
    /// own skips stop marking.
    @Test func reattributionIsDecidedPerRule() {
        let runtime = runtime([("slow1", Self.pathological), ("slow2", Self.pathological)], limit: .milliseconds(20))
        let start = runtime.snapshot()
        // slow1 times out in this entry, outside a retry: marked.
        _ = runtime.matches(candidateId: "slow1", record: record(), rawLine: Self.slowLine)
        let afterOwn = runtime.snapshot()
        #expect(runtime.needsReattribution(from: start, to: afterOwn, retry: false))
        // In a retry slow1 only sits out: marked.
        _ = runtime.matches(candidateId: "slow1", record: record(), rawLine: "aaaa")
        let afterSkip = runtime.snapshot()
        #expect(runtime.needsReattribution(from: afterOwn, to: afterSkip, retry: true))
        // slow2 times out in a retry while slow1 sits out: slow2 is given up,
        // slow1's skip still marks.
        _ = runtime.matches(candidateId: "slow1", record: record(), rawLine: "aaaa")
        _ = runtime.matches(candidateId: "slow2", record: record(), rawLine: Self.slowLine)
        let afterBoth = runtime.snapshot()
        #expect(runtime.needsReattribution(from: afterSkip, to: afterBoth, retry: true))
        #expect(runtime.memory.givenUp == ["slow2"])
        // slow2's skips mark nothing any more.
        _ = runtime.matches(candidateId: "slow2", record: record(), rawLine: "aaaa")
        #expect(!runtime.needsReattribution(from: afterBoth, to: runtime.snapshot(), retry: false))
        #expect(runtime.timeOuts == 2)
        #expect(runtime.drainSitOutAccounts() == ["Account slow1", "Account slow2"])
    }

    /// FR-006, SC-004: the next runtime with the memory skips a value the
    /// rule ran out of time on, as no match and without a time-out, and
    /// still matches every other value; another fingerprint starts empty.
    @Test func memorySkipsKnownSlowValues() {
        let first = runtime([("slow", Self.pathological)], limit: .milliseconds(20))
        _ = first.matches(candidateId: "slow", record: record(), rawLine: Self.slowLine)
        #expect(first.timeOuts == 1)
        let memory = first.memory
        #expect(memory.slowValues["slow"]?.count == 1)

        let next = MatchRuntime(rules: [MatchRuntime.Entry(id: "slow", name: "Slow", condition: Self.pathological)],
                                limit: .milliseconds(20), memory: memory)
        let clock = ContinuousClock()
        var matched = true
        let elapsed = clock.measure { matched = next.matches(candidateId: "slow", record: record(), rawLine: Self.slowLine) }
        #expect(!matched)
        #expect(elapsed < .milliseconds(20))
        #expect(next.timeOuts == 0)
        #expect(next.skippedDecisions == 0)
        #expect(next.matches(candidateId: "slow", record: record(), rawLine: "aaaa"))

        // Through the attributor: a changed rule set starts without memory.
        var config = Configuration()
        config.accounts = [Account(id: "slow", displayName: "Slow", kind: .tokenBased(TokenBasedSettings(
            membership: .ownBudget(BudgetSettings(budgetUSD: 50)), harness: .claudeCode, sessionKind: .claudeCodeOtherProvider, condition: MatchCondition(field: .anywhere, operator: .regex, text: "(a+)+$"))))]
        let a1 = Attributor(configuration: config, matchTimeLimit: .milliseconds(20))
        _ = a1.accountId(for: record(), rawLine: Self.slowLine, fileConfigDirectory: "/Users/tester/.claude")
        #expect(a1.timeOuts == 1)
        let a2 = Attributor(configuration: config, matchTimeLimit: .milliseconds(20), matchMemory: a1.matchMemory)
        _ = a2.accountId(for: record(), rawLine: Self.slowLine, fileConfigDirectory: "/Users/tester/.claude")
        #expect(a2.timeOuts == 0)
        config.accounts[0].displayName = "Renamed"
        config.accounts.append(Account(id: "other", displayName: "Other", kind: .tokenBased(TokenBasedSettings(
            membership: .ownBudget(BudgetSettings(budgetUSD: 50)), harness: .claudeCode,
            sessionKind: .claudeCodeOtherProvider, condition: MatchCondition(field: .model, operator: .contains, text: "glm")))))
        let a3 = Attributor(configuration: config, matchTimeLimit: .milliseconds(20), matchMemory: a2.matchMemory)
        _ = a3.accountId(for: record(), rawLine: Self.slowLine, fileConfigDirectory: "/Users/tester/.claude")
        #expect(a3.timeOuts == 1)
    }

    /// An unknown candidate (no custom rule) never matches.
    @Test func unknownCandidateNeverMatches() {
        #expect(!runtime([]).matches(candidateId: "x", record: record(), rawLine: "x"))
    }

    /// 10,000 raw lines of about 2 KB each, the size of an assistant record
    /// with tool input and output.
    static let longLines: [String] = {
        let output = String(repeating: #"total 8 drwxr-xr-x  tester staff  proj-alpha/src/main.swift "#, count: 40)
        return (0..<10_000).map { i in
            #"{"type":"assistant","cwd":"/Users/tester/proj-alpha","toolResult":"\#(output)","provider":"\#(i % 2 == 0 ? "gw-\(i)" : "other")","message":{"id":"msg_\#(i)","model":"intranet/glm-5","usage":{"input_tokens":12,"output_tokens":34}}}"#
        }
    }()

    /// SC-004: 10,000 raw lines with an Anywhere regex, or with Anywhere
    /// contains, finish well under one second.
    @Test(arguments: [MatchCondition(field: .anywhere, operator: .regex, text: #""provider":"gw-[0-9]+""#),
                      MatchCondition(field: .anywhere, operator: .contains, text: #""PROVIDER":"GW-"#)])
    func tenThousandLinesStayFast(rule: MatchCondition) {
        let runtime = runtime([("gw", rule)])
        let lines = Self.longLines
        #expect(lines[0].utf8.count > 2_000)
        let r = record()
        let clock = ContinuousClock()
        var matched = 0
        let elapsed = clock.measure {
            for line in lines where runtime.matches(candidateId: "gw", record: r, rawLine: line) { matched += 1 }
        }
        #expect(matched == 5_000)
        #expect(elapsed < .seconds(1))
    }

    /// SC-005 through the attributor: 10,000 raw lines of an Other
    /// provider account's kind with an Anywhere regex condition finish well
    /// under one second.
    @Test func tenThousandLinesThroughTheKindFirstStep() {
        let config = Configuration(accounts: [Account(id: "gw", displayName: "Gateway", kind: .tokenBased(TokenBasedSettings(
            membership: .ownBudget(BudgetSettings(budgetUSD: 50)), harness: .claudeCode, sessionKind: .claudeCodeOtherProvider,
            condition: MatchCondition(field: .anywhere, operator: .regex, text: #""provider":"gw-[0-9]+""#))))])
        let attributor = Attributor(configuration: config)
        let lines = Self.longLines
        let r = record(model: "intranet/glm-5")
        let clock = ContinuousClock()
        var matched = 0
        let elapsed = clock.measure {
            for line in lines where attributor.accountId(for: r, rawLine: line, fileConfigDirectory: "/Users/tester/.claude") == "gw" {
                matched += 1
            }
        }
        #expect(matched == 5_000)
        #expect(elapsed < .seconds(1))
    }

    /// SC-004 second half: with the default 50 ms limit, a pathological
    /// pattern over 1,000 records costs about 50 ms in total.
    @Test func pathologicalPatternCostsAboutTheLimit() {
        let runtime = runtime([("slow", Self.pathological)])
        let r = record()
        let clock = ContinuousClock()
        var matched = 0
        let first = clock.measure {
            if runtime.matches(candidateId: "slow", record: r, rawLine: Self.slowLine) { matched += 1 }
        }
        let rest = clock.measure {
            for _ in 1..<1_000 where runtime.matches(candidateId: "slow", record: r, rawLine: Self.slowLine) { matched += 1 }
        }
        #expect(matched == 0)
        #expect(first >= .milliseconds(45))
        // SC-004 asks for 100 ms on the maintainer's Mac; the bound leaves
        // room for a loaded test machine. The sitting out itself is shown
        // by the counts below.
        #expect(first + rest < .milliseconds(150))
        #expect(runtime.timeOuts == 1)
        #expect(runtime.skippedDecisions == 1_000)
    }
}
