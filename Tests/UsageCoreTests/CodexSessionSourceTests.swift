import Foundation
import Testing
@testable import UsageCore

/// Codex fixtures live under `<home>/sessions/YYYY/MM/DD/`, not under the
/// `projects/` tree that `Fixtures.install` writes.
enum CodexFixtures {
    @discardableResult
    static func install(_ name: String, home: URL, day: String = "2026/10/13", as fileName: String? = nil) throws -> URL {
        let dir = home.appendingPathComponent("sessions").appendingPathComponent(day)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let base = (name as NSString).deletingPathExtension
        let target = dir.appendingPathComponent(fileName ?? "rollout-2026-10-13T09-00-00-\(base).jsonl")
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: Fixtures.url("codex/\(name)"), to: target)
        return target
    }

    static func setModificationDate(_ date: Date, of url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
}

/// spec 006 FR-002, FR-004, FR-010, FR-012, FR-014.
@Suite struct CodexSessionSourceTests {
    let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
    let now = isoDate("2026-10-13T12:00:00Z")

    static let prices = PriceTable(entries: [
        PriceEntry(model: "gpt-5.5", inputPerMTok: 2, outputPerMTok: 10, cacheWrite5mPerMTok: 2.5, cacheWrite1hPerMTok: 4, cacheReadPerMTok: 0.2),
        PriceEntry(model: "gpt-5.5-mini", inputPerMTok: 1, outputPerMTok: 4, cacheWrite5mPerMTok: 1.25, cacheWrite1hPerMTok: 2, cacheReadPerMTok: 0.1),
    ])

    func makeSource(home: URL) throws -> CodexSessionSource {
        try CodexSessionSource(paths: Paths(home: home), log: DiagnosticLog(fileURL: home.appendingPathComponent("usage.log")),
                               builtInPrices: Self.prices)
    }

    static func openAIAccount() -> Account {
        Account(id: "acc-oai", displayName: "OpenAI",
                kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 50)), provider: .openai)))
    }

    /// A Codex subscription with an empty home, so `~/.codex` is read
    /// without an OpenAI account (spec 034 FR-008: only the accounts'
    /// homes are read).
    static let defaultHomeOnly = Configuration(accounts: [
        Account(id: "acc-plus", displayName: "Plus", harness: .codex, kind: .codexSubscription(CodexSubscriptionSettings(codexHome: ""))),
    ])

    func collect(_ source: CodexSessionSource, _ configuration: Configuration = Self.defaultHomeOnly) async throws -> RecordBatch {
        let output = try await source.collect(context: RefreshContext(configuration: configuration, window: window, now: now))
        guard case .recordBatch(let batch) = output else {
            Issue.record("expected a record batch")
            return RecordBatch()
        }
        return batch
    }

    @Test func apiKeySessionIsAttributedToOpenAIAndPriced() async throws {
        let home = try makeTempDirectory("codex-apikey")
        defer { try? FileManager.default.removeItem(at: home) }
        try CodexFixtures.install("apikey-session.jsonl", home: home.appendingPathComponent(".codex"))
        let source = try makeSource(home: home)
        let batch = try await collect(source, Configuration(accounts: [Self.openAIAccount()]))
        #expect(batch.issues.isEmpty)
        #expect(batch.records.count == 3)
        #expect(batch.records.allSatisfy { $0.accountId == "acc-oai" })
        #expect(batch.records.allSatisfy { $0.harness == .codex })
        let expected = Self.prices.cost(model: "gpt-5.5", input: 200, output: 100, cacheWrite5m: 800, cacheWrite1h: 0, cacheRead: 0)
        #expect(batch.records.first?.costUSD == expected)
        #expect(batch.records.allSatisfy { $0.costUSD != nil })
        #expect(await source.lastHints == ["019a0000-0000-7000-8000-0000000000a1": "apikey"])
    }

    /// FR-004: an unchanged file reuses its records; a price override
    /// re-prices them without reading the file again (FR-019).
    @Test func priceOverrideRepricesWithoutReparsing() async throws {
        let home = try makeTempDirectory("codex-reprice")
        defer { try? FileManager.default.removeItem(at: home) }
        try CodexFixtures.install("apikey-session.jsonl", home: home.appendingPathComponent(".codex"))
        let source = try makeSource(home: home)
        var configuration = Configuration(accounts: [Self.openAIAccount()])
        let before = try await collect(source, configuration)
        configuration.priceOverrides = [PriceEntry(model: "gpt-5.5", inputPerMTok: 20, outputPerMTok: 100,
                                                   cacheWrite5mPerMTok: 25, cacheWrite1hPerMTok: 40, cacheReadPerMTok: 2)]
        let after = try await collect(source, configuration)
        #expect(await source.lastFilesParsed == 0)
        #expect(after.records.count == 3)
        #expect(after.records.first?.costUSD == PriceTable.cost(input: 200, output: 100, cacheWrite5m: 800, cacheWrite1h: 0, cacheRead: 0,
                                                                price: configuration.priceOverrides[0]))
        #expect(after.records.first?.costUSD != before.records.first?.costUSD)
    }

    /// An account added later re-attributes the cached records without
    /// reading the file again.
    @Test func ruleChangeReattributesWithoutReparsing() async throws {
        let home = try makeTempDirectory("codex-rules")
        defer { try? FileManager.default.removeItem(at: home) }
        try CodexFixtures.install("apikey-session.jsonl", home: home.appendingPathComponent(".codex"))
        let source = try makeSource(home: home)
        let before = try await collect(source)
        #expect(before.records.count == 3)
        #expect(before.records.allSatisfy { $0.accountId == nil })
        let after = try await collect(source, Configuration(accounts: [Self.openAIAccount()]))
        #expect(await source.lastFilesParsed == 0)
        #expect(after.records.count == 3)
        #expect(after.records.allSatisfy { $0.accountId == "acc-oai" })
    }

    /// Edge case "Sessions crossing a window boundary" (spec 001 FR-023):
    /// only events inside the window count, measured from the running total
    /// before the window.
    @Test func sessionCrossingTheWindowStartCountsOnlyInsideUsage() async throws {
        let home = try makeTempDirectory("codex-crossing")
        defer { try? FileManager.default.removeItem(at: home) }
        let dir = home.appendingPathComponent(".codex/sessions/2026/10/11")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func line(_ time: String, _ input: Int, _ output: Int) -> String {
            """
            {"timestamp":"\(time)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(input),"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":\(output),"reasoning_output_tokens":0,"total_tokens":\(input + output)}},"rate_limits":null}}
            """
        }
        let text = [
            #"{"timestamp":"2026-10-11T22:00:00.000Z","type":"session_meta","payload":{"id":"cross","cwd":"/tmp/x","source":"cli"}}"#,
            #"{"timestamp":"2026-10-11T22:00:01.000Z","type":"turn_context","payload":{"cwd":"/tmp/x","model":"gpt-5.5"}}"#,
            line("2026-10-11T22:10:00.000Z", 1000, 100),
            line("2026-10-11T23:50:00.000Z", 3000, 300),
            line("2026-10-12T00:10:00.000Z", 3500, 350),
            line("2026-10-12T01:00:00.000Z", 4000, 400),
        ].joined(separator: "\n") + "\n"
        try text.write(to: dir.appendingPathComponent("rollout-2026-10-11T22-00-00-cross.jsonl"), atomically: true, encoding: .utf8)
        let batch = try await collect(try makeSource(home: home))
        #expect(batch.records.count == 2)
        #expect(batch.records.map(\.inputTokens) == [500, 500])
        #expect(batch.records.map(\.outputTokens) == [50, 50])
        #expect(batch.records.allSatisfy { $0.timestamp >= window.start })
    }

    /// Edge case "Harness removed": a deleted rollout file stops counting.
    @Test func deletedFileStopsCounting() async throws {
        let home = try makeTempDirectory("codex-deleted")
        defer { try? FileManager.default.removeItem(at: home) }
        let file = try CodexFixtures.install("apikey-session.jsonl", home: home.appendingPathComponent(".codex"))
        let source = try makeSource(home: home)
        #expect(try await collect(source).records.count == 3)
        try FileManager.default.removeItem(at: file)
        let batch = try await collect(source)
        #expect(batch.records.isEmpty)
        #expect(batch.issues.isEmpty)
    }

    @Test func withoutOpenAIAccountRecordsAreUnassigned() async throws {
        let home = try makeTempDirectory("codex-unassigned")
        defer { try? FileManager.default.removeItem(at: home) }
        try CodexFixtures.install("apikey-session.jsonl", home: home.appendingPathComponent(".codex"))
        let batch = try await collect(try makeSource(home: home))
        #expect(batch.records.count == 3)
        #expect(batch.records.allSatisfy { $0.accountId == nil })
    }

    @Test func unpricedModelStaysUnpriced() async throws {
        let home = try makeTempDirectory("codex-unpriced")
        defer { try? FileManager.default.removeItem(at: home) }
        try CodexFixtures.install("apikey-session.jsonl", home: home.appendingPathComponent(".codex"))
        let source = try CodexSessionSource(paths: Paths(home: home), builtInPrices: PriceTable(entries: []))
        let batch = try await collect(source, Configuration(accounts: [Self.openAIAccount()]))
        #expect(batch.records.count == 3)
        #expect(batch.records.allSatisfy { $0.costUSD == nil && $0.accountId == "acc-oai" })
    }

    @Test func missingDefaultHomeYieldsNothing() async throws {
        let home = try makeTempDirectory("codex-missing")
        defer { try? FileManager.default.removeItem(at: home) }
        let batch = try await collect(try makeSource(home: home))
        #expect(batch.records.isEmpty)
        #expect(batch.issues.isEmpty)
        #expect(batch.staleHarnesses.isEmpty)
    }

    /// FR-004: unchanged files are not parsed again.
    @Test func unchangedFilesAreNotReparsed() async throws {
        let home = try makeTempDirectory("codex-incremental")
        defer { try? FileManager.default.removeItem(at: home) }
        let codexHome = home.appendingPathComponent(".codex")
        try CodexFixtures.install("apikey-session.jsonl", home: codexHome)
        try CodexFixtures.install("review-subagent.jsonl", home: codexHome)
        let source = try makeSource(home: home)
        #expect(try await collect(source).records.count == 4)
        #expect(await source.lastFilesParsed == 2)
        #expect(try await collect(source).records.count == 4)
        #expect(await source.lastFilesParsed == 0)
    }

    @Test func filesModifiedBeforeTheWindowAreDropped() async throws {
        let home = try makeTempDirectory("codex-old")
        defer { try? FileManager.default.removeItem(at: home) }
        let codexHome = home.appendingPathComponent(".codex")
        let old = try CodexFixtures.install("review-subagent.jsonl", home: codexHome)
        try CodexFixtures.setModificationDate(isoDate("2026-10-01T00:00:00Z"), of: old)
        try CodexFixtures.install("apikey-session.jsonl", home: codexHome)
        let batch = try await collect(try makeSource(home: home))
        #expect(batch.records.count == 3)
        #expect(batch.records.allSatisfy { $0.messageId.contains("0000000000a1") })
    }

    /// FR-010: the session cwd resolves to its git repository.
    @Test func cwdInsideGitRepositoryResolvesToProject() async throws {
        let home = try makeTempDirectory("codex-git")
        defer { try? FileManager.default.removeItem(at: home) }
        let repo = home.appendingPathComponent("work/codexrepo")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("pkg"), withIntermediateDirectories: true)
        let file = try CodexFixtures.install("apikey-session.jsonl", home: home.appendingPathComponent(".codex"))
        let text = try String(contentsOf: file, encoding: .utf8)
            .replacingOccurrences(of: "/tmp/codex-apikey", with: repo.appendingPathComponent("pkg").path)
        try text.write(to: file, atomically: true, encoding: .utf8)
        let batch = try await collect(try makeSource(home: home))
        #expect(batch.records.count == 3)
        #expect(batch.records.allSatisfy { $0.project?.rootPath == repo.path })
    }
}

/// spec 006 FR-014, FR-015, US3.
@Suite struct CodexPlanSessionTests {
    let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
    let now = isoDate("2026-10-13T12:00:00Z")

    func collect(_ source: CodexSessionSource, _ configuration: Configuration) async throws -> [UsageRecord] {
        let output = try await source.collect(context: RefreshContext(configuration: configuration, window: window, now: now))
        guard case .recordBatch(let batch) = output else { return [] }
        return batch.records
    }

    static func codexAccount(_ id: String = "acc-codex", home: String = "~/.codex") -> Account {
        Account(id: id, displayName: id, kind: .codexSubscription(CodexSubscriptionSettings(codexHome: home)))
    }

    func config(_ accounts: [Account]) -> Configuration { Configuration(accounts: accounts) }

    @Test func planSessionAndItsSubagentGoToTheCodexSubscription() async throws {
        let home = try makeTempDirectory("codex-plan")
        defer { try? FileManager.default.removeItem(at: home) }
        let codexHome = home.appendingPathComponent(".codex")
        try CodexFixtures.install("plan-session.jsonl", home: codexHome)
        try CodexFixtures.install("subagent-session.jsonl", home: codexHome)
        try CodexFixtures.install("apikey-session.jsonl", home: codexHome)
        let source = try CodexSessionSource(paths: Paths(home: home), builtInPrices: CodexSessionSourceTests.prices)
        let records = try await collect(source, config([Self.codexAccount(), CodexSessionSourceTests.openAIAccount()]))
        let plan = records.filter { $0.messageId.contains("0000000000b1") || $0.messageId.contains("0000000000c1") }
        #expect(plan.count == 3)
        #expect(plan.allSatisfy { $0.accountId == "acc-codex" })
        let apiKey = records.filter { $0.messageId.contains("0000000000a1") }
        #expect(apiKey.count == 3)
        #expect(apiKey.allSatisfy { $0.accountId == "acc-oai" })
    }

    /// FR-014: a marker that appears later re-attributes the earlier turns.
    @Test func lateMarkerReattributesTheWholeSession() async throws {
        let home = try makeTempDirectory("codex-late-marker")
        defer { try? FileManager.default.removeItem(at: home) }
        let codexHome = home.appendingPathComponent(".codex")
        let lines = try Fixtures.lines("codex/plan-session.jsonl")
        let file = try CodexFixtures.install("plan-session.jsonl", home: codexHome)
        try (lines.dropLast().joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        let source = try CodexSessionSource(paths: Paths(home: home), builtInPrices: CodexSessionSourceTests.prices)
        let configuration = config([Self.codexAccount(), CodexSessionSourceTests.openAIAccount()])

        let before = try await collect(source, configuration)
        #expect(before.count == 1)
        #expect(before.allSatisfy { $0.accountId == "acc-oai" })

        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        try CodexFixtures.setModificationDate(Date().addingTimeInterval(5), of: file)
        let after = try await collect(source, configuration)
        #expect(after.count == 2)
        #expect(after.allSatisfy { $0.accountId == "acc-codex" })
    }

    /// FR-014: a parent found only in a file older than the window still
    /// decides the subagent's mode.
    @Test func subagentInheritsFromAParentOutsideTheWindow() async throws {
        let home = try makeTempDirectory("codex-old-parent")
        defer { try? FileManager.default.removeItem(at: home) }
        let codexHome = home.appendingPathComponent(".codex")
        let parent = try CodexFixtures.install("plan-session.jsonl", home: codexHome,
                                               as: "rollout-2026-10-01T10-00-00-019a0000-0000-7000-8000-0000000000b1.jsonl")
        try CodexFixtures.setModificationDate(isoDate("2026-10-01T12:00:00Z"), of: parent)
        try CodexFixtures.install("subagent-session.jsonl", home: codexHome)
        let source = try CodexSessionSource(paths: Paths(home: home), builtInPrices: CodexSessionSourceTests.prices)
        let records = try await collect(source, config([Self.codexAccount(), CodexSessionSourceTests.openAIAccount()]))
        #expect(records.count == 1)
        #expect(records.first?.accountId == "acc-codex")
    }

    /// FR-014: a subagent without a marker whose parent is not found is
    /// API-key usage.
    @Test func subagentWithoutKnownParentIsAPIKeyUsage() async throws {
        let home = try makeTempDirectory("codex-orphan")
        defer { try? FileManager.default.removeItem(at: home) }
        try CodexFixtures.install("subagent-session.jsonl", home: home.appendingPathComponent(".codex"))
        let source = try CodexSessionSource(paths: Paths(home: home), builtInPrices: CodexSessionSourceTests.prices)
        let records = try await collect(source, config([Self.codexAccount(), CodexSessionSourceTests.openAIAccount()]))
        #expect(records.count == 1)
        #expect(records.first?.accountId == "acc-oai")
    }

    @Test func codexHomeSeparatesTwoCodexSubscriptions() async throws {
        let home = try makeTempDirectory("codex-two-homes")
        defer { try? FileManager.default.removeItem(at: home) }
        try CodexFixtures.install("plan-session.jsonl", home: home.appendingPathComponent(".codex"))
        try CodexFixtures.install("subagent-session.jsonl", home: home.appendingPathComponent(".codex-work"))
        let source = try CodexSessionSource(paths: Paths(home: home), builtInPrices: CodexSessionSourceTests.prices)
        // Each account's home is read without being listed again (spec 034 FR-008).
        let configuration = config([Self.codexAccount("acc-home", home: "~/.codex"),
                                    Self.codexAccount("acc-work", home: "~/.codex-work")])
        let records = try await collect(source, configuration)
        let homeRecords = records.filter { $0.messageId.contains("0000000000b1") }
        #expect(homeRecords.count == 2)
        #expect(homeRecords.allSatisfy { $0.accountId == "acc-home" })
        #expect(records.filter { $0.messageId.contains("0000000000c1") }.map(\.accountId) == ["acc-work"])
    }

    @Test func withoutCodexSubscriptionPlanSessionsAreUnassigned() async throws {
        let home = try makeTempDirectory("codex-plan-unassigned")
        defer { try? FileManager.default.removeItem(at: home) }
        try CodexFixtures.install("plan-session.jsonl", home: home.appendingPathComponent(".codex"))
        let source = try CodexSessionSource(paths: Paths(home: home), builtInPrices: CodexSessionSourceTests.prices)
        let records = try await collect(source, config([CodexSessionSourceTests.openAIAccount()]))
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.accountId == nil })
    }
}

/// spec 006 FR-003, FR-006, US4.
@Suite struct CodexLocationTests {
    let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
    let now = isoDate("2026-10-13T12:00:00Z")

    func collect(_ source: CodexSessionSource, _ configuration: Configuration) async throws -> RecordBatch {
        let output = try await source.collect(context: RefreshContext(configuration: configuration, window: window, now: now))
        guard case .recordBatch(let batch) = output else { return RecordBatch() }
        return batch
    }

    /// An OpenAI account with its own Codex home (spec 034 FR-007).
    static func openAIAccount(home: String?) -> Account {
        Account(id: "acc-oai", displayName: "OpenAI Lab", harness: .codex,
                kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 50)), provider: .openai,
                                                     sessionDirectory: home)))
    }

    /// Spec 034 SC-003: the sessions in an OpenAI account's Codex home count
    /// for that account, with the totals the extra home gave before.
    @Test func openAIAccountHomeIsRead() async throws {
        let home = try makeTempDirectory("codex-extra")
        defer { try? FileManager.default.removeItem(at: home) }
        try CodexFixtures.install("apikey-session.jsonl", home: home.appendingPathComponent(".codex"))
        try CodexFixtures.install("review-subagent.jsonl", home: home.appendingPathComponent(".codex-lab"))
        let source = try CodexSessionSource(paths: Paths(home: home), builtInPrices: CodexSessionSourceTests.prices)
        let batch = try await collect(source, Configuration(accounts: [Self.openAIAccount(home: "~/.codex-lab")]))
        #expect(batch.issues.isEmpty)
        // Only the account's home is read, not ~/.codex (spec 034 FR-008).
        #expect(batch.records.count == 1)
        #expect(batch.records.allSatisfy { $0.accountId == "acc-oai" })
        // An empty home reads the default instead.
        let fresh = try CodexSessionSource(paths: Paths(home: home), builtInPrices: CodexSessionSourceTests.prices)
        #expect(try await collect(fresh, Configuration(accounts: [Self.openAIAccount(home: nil)])).records.count == 3)
    }

    /// Spec 034 SC-003: the same session file gives the same account,
    /// models, tokens and costs from an OpenAI account's Codex home as from
    /// `~/.codex`.
    @Test func openAIAccountHomeCountsWithTheSameTotals() async throws {
        func summary(_ records: [UsageRecord]) -> [String] {
            records.map { "\($0.accountId ?? "-") \($0.model) \($0.inputTokens) \($0.outputTokens) \($0.costUSD.map { "\($0)" } ?? "-")" }.sorted()
        }
        let lab = try makeTempDirectory("codex-totals-lab")
        defer { try? FileManager.default.removeItem(at: lab) }
        try CodexFixtures.install("apikey-session.jsonl", home: lab.appendingPathComponent(".codex-lab"))
        let fromHome = try await collect(try CodexSessionSource(paths: Paths(home: lab), builtInPrices: CodexSessionSourceTests.prices),
                                         Configuration(accounts: [Self.openAIAccount(home: "~/.codex-lab")])).records
        let plain = try makeTempDirectory("codex-totals-default")
        defer { try? FileManager.default.removeItem(at: plain) }
        try CodexFixtures.install("apikey-session.jsonl", home: plain.appendingPathComponent(".codex"))
        let fromDefault = try await collect(try CodexSessionSource(paths: Paths(home: plain), builtInPrices: CodexSessionSourceTests.prices),
                                            Configuration(accounts: [Self.openAIAccount(home: nil)])).records
        #expect(fromHome.count == 3)
        #expect(fromHome.allSatisfy { $0.costUSD != nil })
        #expect(summary(fromHome) == summary(fromDefault))
    }

    /// An OpenAI home and a Codex subscription home are both read.
    @Test func openAIAndSubscriptionHomesAreBothRead() throws {
        let home = try makeTempDirectory("codex-both-homes")
        defer { try? FileManager.default.removeItem(at: home) }
        let source = try CodexSessionSource(paths: Paths(home: home), builtInPrices: CodexSessionSourceTests.prices)
        let configuration = Configuration(accounts: [CodexPlanSessionTests.codexAccount("acc-plus", home: "~/.codex-plus"),
                                                     Self.openAIAccount(home: "~/.codex-lab")])
        #expect(source.homes(for: configuration).map(\.directory)
                == [".codex-plus", ".codex-lab"].map { home.appendingPathComponent($0).path })
    }

    @Test func fileReachableThroughTwoHomesCountsOnce() async throws {
        let home = try makeTempDirectory("codex-symlink")
        defer { try? FileManager.default.removeItem(at: home) }
        let real = home.appendingPathComponent(".codex")
        try CodexFixtures.install("apikey-session.jsonl", home: real)
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("codex-link"), withDestinationURL: real)
        let source = try CodexSessionSource(paths: Paths(home: home), builtInPrices: CodexSessionSourceTests.prices)
        let configuration = Configuration(accounts: [Self.openAIAccount(home: "~/codex-link"),
                                                     CodexPlanSessionTests.codexAccount("acc-plus", home: "~/.codex/")])
        let batch = try await collect(source, configuration)
        #expect(batch.issues.isEmpty)
        #expect(batch.records.count == 3)
    }

    /// Homes are deduplicated by canonical path, keeping the first spelling
    /// (spec 034 FR-008).
    @Test func homesAreDeduplicatedByCanonicalPath() throws {
        let home = try makeTempDirectory("codex-canonical")
        defer { try? FileManager.default.removeItem(at: home) }
        let real = home.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("codex-link"), withDestinationURL: real)
        let lab = home.appendingPathComponent(".codex-lab")
        try FileManager.default.createDirectory(at: lab, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("lab-link"), withDestinationURL: lab)
        let source = try CodexSessionSource(paths: Paths(home: home), builtInPrices: CodexSessionSourceTests.prices)
        let configuration = Configuration(accounts: [
            CodexPlanSessionTests.codexAccount("acc-plus", home: "~/.codex/"),
            Self.openAIAccount(home: "~/codex-link"),
            CodexPlanSessionTests.codexAccount("acc-pro", home: "~/lab-link"),
            CodexPlanSessionTests.codexAccount("acc-team", home: "~/.codex-lab"),
        ])
        let homes = source.homes(for: configuration)
        #expect(homes.map(\.directory) == [real.path, home.appendingPathComponent("lab-link").path])
        #expect(homes.map(\.isDefault) == [true, false])
    }

    /// Research R8: an account home that does not exist reads nothing and
    /// fails nothing; the other homes still count.
    @Test func missingAccountHomeIsLoggedAndOthersStillCount() async throws {
        let home = try makeTempDirectory("codex-missing-extra")
        defer { try? FileManager.default.removeItem(at: home) }
        try CodexFixtures.install("apikey-session.jsonl", home: home.appendingPathComponent(".codex"))
        let source = try CodexSessionSource(paths: Paths(home: home), builtInPrices: CodexSessionSourceTests.prices)
        let batch = try await collect(source, Configuration(accounts: [CodexPlanSessionTests.codexAccount("acc-plus"), Self.openAIAccount(home: "~/does-not-exist")]))
        #expect(batch.records.count == 3)
        #expect(batch.issues.isEmpty)
        #expect(batch.staleHarnesses.isEmpty)
    }

    /// An account home that exists but cannot be read stays an issue.
    @Test func unreadableAccountHomeIsAnIssue() async throws {
        let home = try makeTempDirectory("codex-unreadable")
        let locked = home.appendingPathComponent("locked")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: home)
        }
        try CodexFixtures.install("apikey-session.jsonl", home: home.appendingPathComponent(".codex"))
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        let source = try CodexSessionSource(paths: Paths(home: home), builtInPrices: CodexSessionSourceTests.prices)
        let batch = try await collect(source, Configuration(accounts: [CodexPlanSessionTests.codexAccount("acc-plus"), Self.openAIAccount(home: "~/locked")]))
        #expect(batch.records.count == 3)
        #expect(batch.issues.count == 1)
        #expect(batch.issues.first?.contains("not readable") == true)
    }

    /// FR-022: one diagnostic line per location, with counts or the reason.
    @Test func logNamesEveryLocation() async throws {
        let home = try makeTempDirectory("codex-log")
        defer { try? FileManager.default.removeItem(at: home) }
        try CodexFixtures.install("apikey-session.jsonl", home: home.appendingPathComponent(".codex"))
        let logURL = home.appendingPathComponent("usage.log")
        let source = try CodexSessionSource(paths: Paths(home: home), log: DiagnosticLog(fileURL: logURL),
                                            builtInPrices: CodexSessionSourceTests.prices)
        _ = try await collect(source, Configuration(accounts: [CodexPlanSessionTests.codexAccount("acc-plus"), Self.openAIAccount(home: "~/does-not-exist")]))
        let text = try String(contentsOf: logURL, encoding: .utf8)
        #expect(text.contains("[codex] \(home.appendingPathComponent(".codex").path): 3 record(s) in window, 1 file(s) read"))
        #expect(text.contains("[codex] \(home.appendingPathComponent("does-not-exist").path): skipped, home not found"))
    }
}

/// spec 007 research R10: a Codex subscription account's home is read for
/// tokens even when it is not among the extra Codex homes.
@Suite struct CodexAccountHomeTests {
    @Test func accountHomeIsReadAndAttributedToTheAccount() async throws {
        let home = try makeTempDirectory("codex-account-home")
        defer { try? FileManager.default.removeItem(at: home) }
        try CodexFixtures.install("plan-session.jsonl", home: home.appendingPathComponent("work/codex"))
        let source = try CodexSessionSource(paths: Paths(home: home), builtInPrices: CodexSessionSourceTests.prices)
        let configuration = Configuration(accounts: [CodexPlanSessionTests.codexAccount("acc-work", home: "~/work/codex")])
        #expect(source.homes(for: configuration).map(\.directory) == [home.appendingPathComponent("work/codex").path])
        let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
        let output = try await source.collect(context: RefreshContext(configuration: configuration, window: window,
                                                                      now: isoDate("2026-10-13T12:00:00Z")))
        guard case .recordBatch(let batch) = output else { Issue.record("expected a record batch"); return }
        #expect(batch.issues.isEmpty)
        #expect(batch.records.count == 2)
        #expect(batch.records.allSatisfy { $0.accountId == "acc-work" })
    }
}

/// Spec 034 FR-008 (walkthrough 2026-10-22): only the Codex homes the
/// accounts name are read; an empty field means `~/.codex`, and without a
/// Codex account no Codex session is read.
@Suite struct CodexAccountHomesOnlyTests {
    let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
    let now = isoDate("2026-10-13T12:00:00Z")

    func collect(_ source: CodexSessionSource, _ configuration: Configuration) async throws -> RecordBatch {
        let output = try await source.collect(context: RefreshContext(configuration: configuration, window: window, now: now))
        guard case .recordBatch(let batch) = output else { return RecordBatch() }
        return batch
    }

    /// A home with an API-key session in `~/.codex` and in each invented home.
    func fixture(_ name: String) throws -> URL {
        let home = try makeTempDirectory(name)
        for dir in [".codex", ".codex-lab", ".codex-plus"] {
            try CodexFixtures.install("apikey-session.jsonl", home: home.appendingPathComponent(dir))
        }
        return home
    }

    func source(_ home: URL) throws -> CodexSessionSource {
        try CodexSessionSource(paths: Paths(home: home), builtInPrices: CodexSessionSourceTests.prices)
    }

    @Test func accountsWithOwnHomesDoNotReadTheDefault() async throws {
        let home = try fixture("codex-own-homes")
        defer { try? FileManager.default.removeItem(at: home) }
        let configuration = Configuration(accounts: [CodexPlanSessionTests.codexAccount("acc-plus", home: "~/.codex-plus"),
                                                     CodexLocationTests.openAIAccount(home: "~/.codex-lab")])
        let codex = try source(home)
        #expect(codex.homes(for: configuration).map(\.directory)
                == [".codex-plus", ".codex-lab"].map { home.appendingPathComponent($0).path })
        let batch = try await collect(codex, configuration)
        #expect(batch.issues.isEmpty)
        #expect(batch.records.count == 6)
    }

    @Test func emptySubscriptionHomeReadsTheDefault() throws {
        let home = try makeTempDirectory("codex-empty-subscription")
        defer { try? FileManager.default.removeItem(at: home) }
        let configuration = Configuration(accounts: [CodexPlanSessionTests.codexAccount("acc-plus", home: ""),
                                                     CodexLocationTests.openAIAccount(home: "~/.codex-lab")])
        let homes = try source(home).homes(for: configuration)
        #expect(homes.map(\.directory) == [".codex", ".codex-lab"].map { home.appendingPathComponent($0).path })
        #expect(homes.map(\.isDefault) == [true, false])
    }

    @Test func emptyOpenAIHomeReadsTheDefault() async throws {
        let home = try fixture("codex-empty-openai")
        defer { try? FileManager.default.removeItem(at: home) }
        let codex = try source(home)
        for entry in [nil, "", "  "] as [String?] {
            let configuration = Configuration(accounts: [CodexLocationTests.openAIAccount(home: entry)])
            #expect(codex.homes(for: configuration).map(\.directory) == [home.appendingPathComponent(".codex").path])
        }
        let batch = try await collect(codex, Configuration(accounts: [CodexLocationTests.openAIAccount(home: nil)]))
        #expect(batch.records.count == 3)
        #expect(batch.records.allSatisfy { $0.accountId == "acc-oai" })
    }

    @Test func noCodexAccountReadsNoCodexSessions() async throws {
        let home = try fixture("codex-no-account")
        defer { try? FileManager.default.removeItem(at: home) }
        let claudeOnly = Configuration(accounts: [
            Account(id: "acc-max", displayName: "Max", kind: .subscription(SubscriptionSettings(credentialDirectory: ""))),
            Account(id: "acc-acme", displayName: "Acme", kind: .tokenBased(TokenBasedSettings(
                membership: .ownBudget(BudgetSettings(budgetUSD: 50)), provider: .vertex))),
        ])
        for configuration in [Configuration(), claudeOnly] {
            let codex = try source(home)
            #expect(codex.homes(for: configuration).isEmpty)
            let batch = try await collect(codex, configuration)
            #expect(batch.records.isEmpty)
            #expect(batch.issues.isEmpty)
        }
    }

    @Test func homeNamedByTwoAccountsIsReadOnce() async throws {
        let home = try fixture("codex-duplicate-homes")
        defer { try? FileManager.default.removeItem(at: home) }
        let lab = home.appendingPathComponent(".codex-lab")
        let configuration = Configuration(accounts: [CodexLocationTests.openAIAccount(home: "~/.codex-lab"),
                                                     CodexPlanSessionTests.codexAccount("acc-plus", home: lab.path + "/"),
                                                     CodexPlanSessionTests.codexAccount("acc-pro", home: "~/.codex-plus/../.codex-lab")])
        let codex = try source(home)
        #expect(codex.homes(for: configuration).map(\.directory) == [lab.path])
        #expect(try await collect(codex, configuration).records.count == 3)
    }
}

/// spec 035 FR-008, FR-009, FR-010, FR-016, US1 scenarios 3 and 5, SC-001,
/// SC-003, SC-004: literal additional Codex homes.
@Suite struct CodexAdditionalHomeTests {
    let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
    let now = isoDate("2026-10-13T12:00:00Z")

    static func plus(_ home: String, extra: [String]) -> Account {
        Account(id: "acc-plus", displayName: "Plus", harness: .codex,
                kind: .codexSubscription(CodexSubscriptionSettings(codexHome: home, additionalSessionDirectories: extra)))
    }

    static func openAI(_ home: String? = nil, extra: [String]) -> Account {
        Account(id: "acc-oai", displayName: "OpenAI", harness: .codex,
                kind: .tokenBased(TokenBasedSettings(membership: .ownBudget(BudgetSettings(budgetUSD: 50)), provider: .openai,
                                                     sessionDirectory: home, additionalSessionDirectories: extra)))
    }

    func run(_ home: URL, _ configuration: Configuration, log: URL? = nil) async throws -> RecordBatch {
        let source = try CodexSessionSource(paths: Paths(home: home), log: log.map { DiagnosticLog(fileURL: $0) },
                                            builtInPrices: CodexSessionSourceTests.prices)
        let output = try await source.collect(context: RefreshContext(configuration: configuration, window: window, now: now))
        guard case .recordBatch(let batch) = output else { return RecordBatch() }
        return batch
    }

    static func summary(_ records: [UsageRecord]) -> [String] {
        records.map { "\($0.accountId ?? "-") \($0.model) \($0.inputTokens) \($0.outputTokens) \($0.costUSD.map { "\($0)" } ?? "-")" }.sorted()
    }

    /// US1 scenario 3: main `~/.codex-lab`, additional `~/.codex`; the
    /// ChatGPT-plan sessions of both count, with main-home totals.
    @Test func subscriptionCountsItsAdditionalHome() async throws {
        let home = try makeTempDirectory("codex-additional-plus")
        defer { try? FileManager.default.removeItem(at: home) }
        try CodexFixtures.install("plan-session.jsonl", home: home.appendingPathComponent(".codex"))
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex-lab"), withIntermediateDirectories: true)
        let batch = try await run(home, Configuration(accounts: [Self.plus("~/.codex-lab", extra: ["~/.codex"])]))
        #expect(batch.issues.isEmpty)
        #expect(batch.records.count == 2)
        #expect(batch.records.allSatisfy { $0.accountId == "acc-plus" })
        let asMain = try await run(home, Configuration(accounts: [Self.plus("~/.codex", extra: [])]))
        #expect(Self.summary(batch.records) == Self.summary(asMain.records))
        #expect(try await run(home, Configuration(accounts: [Self.plus("~/.codex-lab", extra: [])])).records.isEmpty)
    }

    /// US1 scenario 5: an OpenAI account's additional `~/.codex` counts its
    /// API-key sessions, and an unreadable `auth.json` there causes no
    /// problem. That no credential is read is shown by the recording reader
    /// in `CodexLimitsAdditionalHomeTests` (SC-004).
    @Test func openAICountsItsAdditionalHomeWithoutOpeningAuthJSON() async throws {
        let home = try makeTempDirectory("codex-additional-openai")
        let auth = home.appendingPathComponent(".codex/auth.json")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: auth.path)
            try? FileManager.default.removeItem(at: home)
        }
        try CodexFixtures.install("apikey-session.jsonl", home: home.appendingPathComponent(".codex"))
        try Data(#"{"OPENAI_API_KEY":"SECRET"}"#.utf8).write(to: auth)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: auth.path)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex-api"), withIntermediateDirectories: true)
        let batch = try await run(home, Configuration(accounts: [Self.openAI("~/.codex-api", extra: ["~/.codex"])]))
        #expect(batch.issues.isEmpty)
        #expect(batch.records.count == 3)
        #expect(batch.records.allSatisfy { $0.accountId == "acc-oai" })
        let asMain = try await run(home, Configuration(accounts: [Self.openAI(nil, extra: [])]))
        #expect(Self.summary(batch.records) == Self.summary(asMain.records))
    }

    /// SC-003: one home as a main home and a literal entry counts once.
    @Test func homeNamedAsMainAndEntryCountsOnce() async throws {
        let home = try makeTempDirectory("codex-additional-once")
        defer { try? FileManager.default.removeItem(at: home) }
        try CodexFixtures.install("apikey-session.jsonl", home: home.appendingPathComponent(".codex"))
        let configuration = Configuration(accounts: [Self.plus("~/.codex", extra: ["~/.codex/"]),
                                                     Self.openAI(nil, extra: [home.appendingPathComponent(".codex").path])])
        let source = try CodexSessionSource(paths: Paths(home: home), builtInPrices: CodexSessionSourceTests.prices)
        #expect(source.homes(for: configuration).map(\.directory) == [home.appendingPathComponent(".codex").path])
        #expect(source.homes(for: configuration).map(\.origin) == [.main])
        #expect(try await run(home, configuration).records.count == 3)
    }

    /// FR-008, FR-016: a missing or unreadable additional home is logged
    /// and adds no issue; main and literal homes keep their per-home line.
    @Test func additionalProblemsAreOnlyLogged() async throws {
        let home = try makeTempDirectory("codex-additional-problems")
        let locked = home.appendingPathComponent("locked")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: home)
        }
        try CodexFixtures.install("apikey-session.jsonl", home: home.appendingPathComponent(".codex-lab"))
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        let logURL = home.appendingPathComponent("usage.log")
        let batch = try await run(home, Configuration(accounts: [Self.openAI(nil, extra: ["~/.codex-lab", "~/gone", "~/locked"])]), log: logURL)
        #expect(batch.issues.isEmpty)
        #expect(batch.records.count == 3)
        let text = try String(contentsOf: logURL, encoding: .utf8)
        let path = { (name: String) in home.appendingPathComponent(name).path }
        // The missing default main home keeps its spec 006 line.
        #expect(text.contains("[codex] \(path(".codex")): skipped, Codex not installed"))
        #expect(text.contains("[codex] \(path(".codex-lab")): 3 record(s) in window, 1 file(s) read"))
        #expect(text.contains("[codex] \(path("gone")): skipped, not found"))
        #expect(text.contains("[codex] \(path("locked")): error: "))
    }

    /// The additional `~/.codex` is no default home: missing, it is
    /// "not found", not "Codex not installed".
    @Test func additionalDefaultHomeIsNoDefaultLocation() throws {
        let home = try makeTempDirectory("codex-additional-default")
        defer { try? FileManager.default.removeItem(at: home) }
        let source = try CodexSessionSource(paths: Paths(home: home), builtInPrices: CodexSessionSourceTests.prices)
        let homes = source.homes(for: Configuration(accounts: [Self.plus("~/.codex-lab", extra: ["~/.codex"])]))
        #expect(homes.map(\.isDefault) == [false, false])
        #expect(homes.map(\.origin) == [.main, .literal(entry: "~/.codex")])
    }

    static func pro(_ home: String, extra: [String]) -> Account {
        Account(id: "acc-pro", displayName: "Pro", harness: .codex,
                kind: .codexSubscription(CodexSubscriptionSettings(codexHome: home, additionalSessionDirectories: extra)))
    }

    /// FR-012 end to end: two Codex subscriptions keep apart the plan
    /// sessions of the home one of them lists; listed on both, Unassigned.
    @Test func additionalClaimSeparatesTwoSubscriptionsEndToEnd() async throws {
        let home = try makeTempDirectory("codex-additional-two")
        defer { try? FileManager.default.removeItem(at: home) }
        try CodexFixtures.install("plan-session.jsonl", home: home.appendingPathComponent(".codex"))
        for dir in [".codex-lab", ".codex-pro"] {
            try FileManager.default.createDirectory(at: home.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        let source = try CodexSessionSource(paths: Paths(home: home), builtInPrices: CodexSessionSourceTests.prices)
        func collect(_ configuration: Configuration) async throws -> [UsageRecord] {
            let output = try await source.collect(context: RefreshContext(configuration: configuration, window: window, now: now))
            guard case .recordBatch(let batch) = output else { return [] }
            return batch.records
        }
        let one = try await collect(Configuration(accounts: [Self.plus("~/.codex-lab", extra: ["~/.codex"]), Self.pro("~/.codex-pro", extra: [])]))
        #expect(one.count == 2)
        #expect(one.allSatisfy { $0.accountId == "acc-plus" })
        // Both list it: the claim key changes and the records are rebuilt.
        let both = try await collect(Configuration(accounts: [Self.plus("~/.codex-lab", extra: ["~/.codex"]),
                                                              Self.pro("~/.codex-pro", extra: ["~/.codex"])]))
        #expect(both.count == 2)
        #expect(both.allSatisfy { $0.accountId == nil })
        #expect(await source.lastFilesParsed == 0)
    }

    /// FR-006, FR-009: a `sessions` link in an additional home that leads
    /// outside it is not followed.
    @Test func sessionsLinkOutsideAnAdditionalHomeIsSkipped() async throws {
        let home = try makeTempDirectory("codex-additional-link")
        defer { try? FileManager.default.removeItem(at: home) }
        try CodexFixtures.install("apikey-session.jsonl", home: home.appendingPathComponent("outside"))
        let box = home.appendingPathComponent("box")
        try FileManager.default.createDirectory(at: box, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: box.appendingPathComponent("sessions"),
                                                   withDestinationURL: home.appendingPathComponent("outside/sessions"))
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex-api"), withIntermediateDirectories: true)
        let logURL = home.appendingPathComponent("usage.log")
        let batch = try await run(home, Configuration(accounts: [Self.openAI("~/.codex-api", extra: ["~/box"])]), log: logURL)
        #expect(batch.records.isEmpty)
        #expect(batch.issues.isEmpty)
        let text = try String(contentsOf: logURL, encoding: .utf8)
        #expect(text.contains("[codex] \(box.path): skipped, sessions is a link outside the directory"))
    }

    /// FR-008: a rollout file under an additional home that cannot be read
    /// is logged and adds no issue.
    @Test func unreadableRolloutUnderAdditionalHomeIsOnlyLogged() async throws {
        let home = try makeTempDirectory("codex-additional-unreadable")
        let file = try CodexFixtures.install("apikey-session.jsonl", home: home.appendingPathComponent("box"))
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
            try? FileManager.default.removeItem(at: home)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex-api"), withIntermediateDirectories: true)
        let logURL = home.appendingPathComponent("usage.log")
        let batch = try await run(home, Configuration(accounts: [Self.openAI("~/.codex-api", extra: ["~/box"])]), log: logURL)
        #expect(batch.issues.isEmpty)
        let text = try String(contentsOf: logURL, encoding: .utf8)
        #expect(text.contains("[codex] \(home.appendingPathComponent("box").path): error: cannot read"))
    }
}

/// spec 035 FR-008, FR-010, FR-016, SC-005: wildcard entries on Codex
/// accounts share one log line per entry.
@Suite struct CodexWildcardHomeTests {
    static let entry = "~/agent-sessions/openshell/*/codex"
    let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
    let now = isoDate("2026-10-13T12:00:00Z")

    func collect(_ source: CodexSessionSource, _ configuration: Configuration) async throws -> RecordBatch {
        let output = try await source.collect(context: RefreshContext(configuration: configuration, window: window, now: now))
        guard case .recordBatch(let batch) = output else { return RecordBatch() }
        return batch
    }

    @Test func matchedHomesShareOneLine() async throws {
        let home = try makeTempDirectory("codex-wildcard")
        let base = home.appendingPathComponent("agent-sessions/openshell")
        let locked = base.appendingPathComponent("gamma/codex")
        let auth = base.appendingPathComponent("beta/codex/auth.json")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: auth.path)
            try? FileManager.default.removeItem(at: home)
        }
        try CodexFixtures.install("plan-session.jsonl", home: base.appendingPathComponent("alpha/codex"))
        try CodexFixtures.install("apikey-session.jsonl", home: base.appendingPathComponent("beta/codex"))
        // An unreadable sign-in file in a matched home causes no problem
        // (credential reads: `CodexLimitsAdditionalHomeTests`, SC-004).
        try Data(#"{"tokens":{"access_token":"SECRET"}}"#.utf8).write(to: auth)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: auth.path)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex-lab"), withIntermediateDirectories: true)
        let configuration = Configuration(accounts: [CodexAdditionalHomeTests.plus("~/.codex-lab", extra: [Self.entry]),
                                                     CodexAdditionalHomeTests.openAI("~/.codex-lab", extra: [Self.entry])])
        let logURL = home.appendingPathComponent("usage.log")
        let source = try CodexSessionSource(paths: Paths(home: home), log: DiagnosticLog(fileURL: logURL),
                                            builtInPrices: CodexSessionSourceTests.prices)
        let batch = try await collect(source, configuration)
        #expect(batch.issues.isEmpty)
        // The auth mode of each session decides its account.
        #expect(batch.records.filter { $0.accountId == "acc-plus" }.count == 2)
        #expect(batch.records.filter { $0.accountId == "acc-oai" }.count == 3)
        #expect(batch.records.count == 5)
        let text = try String(contentsOf: logURL, encoding: .utf8)
        #expect(text.contains(#"[codex] wildcard "~/agent-sessions/openshell/*/codex": 3 folder(s) matched, 5 record(s) in window, 2 file(s) read"#))
        #expect(text.components(separatedBy: "wildcard \"").count - 1 == 1)
        #expect(!text.contains(base.appendingPathComponent("alpha/codex").path + ":"))
        #expect(text.contains("[codex] \(locked.path): error: home not readable"))
        #expect(text.contains("[codex] 3 home(s) read, 2 session(s), 5 record(s) since collection start, 2 file(s) parsed"))

        // SC-005: unchanged matches parse nothing again.
        _ = try await collect(source, configuration)
        let again = try String(contentsOf: logURL, encoding: .utf8)
        #expect(again.contains("[codex] 3 home(s) read, 2 session(s), 5 record(s) since collection start, 0 file(s) parsed"))
        #expect(await source.lastFilesParsed == 0)
    }
}
