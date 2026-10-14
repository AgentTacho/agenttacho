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

    func collect(_ source: CodexSessionSource, _ configuration: Configuration = Configuration()) async throws -> RecordBatch {
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
        var configuration = config([Self.codexAccount("acc-home", home: "~/.codex"),
                                    Self.codexAccount("acc-work", home: "~/.codex-work")])
        configuration.codexHomes = ["~/.codex-work"]
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

    @Test func extraHomeIsRead() async throws {
        let home = try makeTempDirectory("codex-extra")
        defer { try? FileManager.default.removeItem(at: home) }
        try CodexFixtures.install("apikey-session.jsonl", home: home.appendingPathComponent(".codex"))
        try CodexFixtures.install("review-subagent.jsonl", home: home.appendingPathComponent("work-codex"))
        let source = try CodexSessionSource(paths: Paths(home: home), builtInPrices: CodexSessionSourceTests.prices)
        var configuration = Configuration()
        configuration.codexHomes = ["~/work-codex"]
        let batch = try await collect(source, configuration)
        #expect(batch.issues.isEmpty)
        #expect(batch.records.count == 4)
    }

    @Test func fileReachableThroughTwoHomesCountsOnce() async throws {
        let home = try makeTempDirectory("codex-symlink")
        defer { try? FileManager.default.removeItem(at: home) }
        let real = home.appendingPathComponent(".codex")
        try CodexFixtures.install("apikey-session.jsonl", home: real)
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("codex-link"), withDestinationURL: real)
        let source = try CodexSessionSource(paths: Paths(home: home), builtInPrices: CodexSessionSourceTests.prices)
        var configuration = Configuration()
        configuration.codexHomes = ["~/codex-link", "~/.codex/"]
        let batch = try await collect(source, configuration)
        #expect(batch.issues.isEmpty)
        #expect(batch.records.count == 3)
    }

    @Test func missingConfiguredHomeIsAnIssueAndOthersStillCount() async throws {
        let home = try makeTempDirectory("codex-missing-extra")
        defer { try? FileManager.default.removeItem(at: home) }
        try CodexFixtures.install("apikey-session.jsonl", home: home.appendingPathComponent(".codex"))
        let source = try CodexSessionSource(paths: Paths(home: home), builtInPrices: CodexSessionSourceTests.prices)
        var configuration = Configuration()
        configuration.codexHomes = ["~/does-not-exist"]
        let batch = try await collect(source, configuration)
        #expect(batch.records.count == 3)
        #expect(batch.issues.count == 1)
        #expect(batch.issues.first?.contains("Codex") == true)
        #expect(batch.issues.first?.contains("does-not-exist") == true)
        #expect(batch.staleHarnesses.isEmpty)
    }

    /// FR-022: one diagnostic line per location, with counts or the reason.
    @Test func logNamesEveryLocation() async throws {
        let home = try makeTempDirectory("codex-log")
        defer { try? FileManager.default.removeItem(at: home) }
        try CodexFixtures.install("apikey-session.jsonl", home: home.appendingPathComponent(".codex"))
        let logURL = home.appendingPathComponent("usage.log")
        let source = try CodexSessionSource(paths: Paths(home: home), log: DiagnosticLog(fileURL: logURL),
                                            builtInPrices: CodexSessionSourceTests.prices)
        var configuration = Configuration()
        configuration.codexHomes = ["~/does-not-exist"]
        _ = try await collect(source, configuration)
        let text = try String(contentsOf: logURL, encoding: .utf8)
        #expect(text.contains("[codex] \(home.appendingPathComponent(".codex").path): 3 record(s) in window, 1 file(s) read"))
        #expect(text.contains("[codex] \(home.appendingPathComponent("does-not-exist").path): error: home not found"))
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
        #expect(configuration.codexHomes.isEmpty)
        #expect(source.homes(for: configuration).map(\.directory) == [home.appendingPathComponent(".codex").path,
                                                                     home.appendingPathComponent("work/codex").path])
        let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
        let output = try await source.collect(context: RefreshContext(configuration: configuration, window: window,
                                                                      now: isoDate("2026-10-13T12:00:00Z")))
        guard case .recordBatch(let batch) = output else { Issue.record("expected a record batch"); return }
        #expect(batch.issues.isEmpty)
        #expect(batch.records.count == 2)
        #expect(batch.records.allSatisfy { $0.accountId == "acc-work" })
    }
}
