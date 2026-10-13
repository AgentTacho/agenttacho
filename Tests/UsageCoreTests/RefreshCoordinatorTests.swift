import Foundation
import Testing
@testable import UsageCore

/// A source whose `collect` blocks until `release()` is called.
actor GatedSource: UsageSource {
    nonisolated let name: String
    private let output: SourceOutput
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var open = false
    private(set) var calls = 0
    private(set) var contexts: [RefreshContext] = []

    init(name: String = "gated", output: SourceOutput = .records([])) {
        self.name = name
        self.output = output
    }

    func release() {
        open = true
        let w = waiters
        waiters = []
        w.forEach { $0.resume() }
    }

    func close() { open = false }

    func collect(context: RefreshContext) async throws -> SourceOutput {
        calls += 1
        contexts.append(context)
        if !open {
            await withCheckedContinuation { waiters.append($0) }
        }
        return output
    }
}

struct FailingSource: UsageSource {
    let name: String
    let message: String
    struct Failure: Error, CustomStringConvertible { let description: String }
    func collect(context: RefreshContext) async throws -> SourceOutput {
        throw Failure(description: message)
    }
}

final class StaticSource: UsageSource, @unchecked Sendable {
    let name: String
    var output: SourceOutput
    var calls = 0
    init(name: String, output: SourceOutput) {
        self.name = name
        self.output = output
    }
    func collect(context: RefreshContext) async throws -> SourceOutput {
        calls += 1
        return output
    }
}

/// A records source that remembers every context and reset, and can be told to fail.
final class FakeLogSource: WindowSensitiveSource, @unchecked Sendable {
    let name = "sessionLogs"
    var records: [UsageRecord] = []
    var fail = false
    var contexts: [RefreshContext] = []
    var resets = 0
    struct Failure: Error, CustomStringConvertible { let description = "log source down" }

    func collect(context: RefreshContext) async throws -> SourceOutput {
        contexts.append(context)
        if fail { throw Failure() }
        return .records(records)
    }

    func resetForEarlierWindow() async {
        resets += 1
    }
}

/// A network-bound source (like `SubscriptionSource`) that counts its calls
/// and can block until `release()` is called.
actor GatedNetworkSource: NetworkBoundSource {
    nonisolated let name = "subscription"
    private let output: SourceOutput
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var open: Bool
    private(set) var calls = 0

    init(output: SourceOutput, open: Bool = true) {
        self.output = output
        self.open = open
    }

    func release() {
        open = true
        let w = waiters
        waiters = []
        w.forEach { $0.resume() }
    }

    func collect(context: RefreshContext) async throws -> SourceOutput {
        calls += 1
        if !open {
            await withCheckedContinuation { waiters.append($0) }
        }
        return output
    }
}

/// A clock that moves forward by `step` seconds on every call.
final class AdvancingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    private let step: TimeInterval

    init(start: Date, step: TimeInterval) {
        self.current = start
        self.step = step
    }

    func next() -> Date {
        lock.lock(); defer { lock.unlock() }
        let value = current
        current = current.addingTimeInterval(step)
        return value
    }
}

func subscriptionOutput(percent: Double = 12) -> SourceOutput {
    let status = SubscriptionStatus(fiveHour: LimitWindow(utilizationPercent: percent, resetsAt: isoDate("2026-10-13T12:00:00Z")),
                                    sevenDay: nil, fetchedAt: isoDate("2026-10-13T08:00:00Z"))
    return .subscriptions(["acc-max": SubscriptionEntry(status: status, state: .ok)])
}

func makeCoordinator(configJSON: String = contractExampleJSON, name: String = "coord",
                     clock: @escaping @Sendable () -> Date = { Date() }) throws -> (RefreshCoordinator, URL) {
    let dir = try makeTempDirectory(name)
    let configURL = dir.appendingPathComponent("config.json")
    try Data(configJSON.utf8).write(to: configURL)
    let store = ConfigStore(fileURL: configURL)
    let log = DiagnosticLog(fileURL: dir.appendingPathComponent("usage.log"))
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let coordinator = RefreshCoordinator(configStore: store, log: log, resolver: WindowResolver(), aggregator: Aggregator(),
                                         calendar: utc, clock: clock)
    return (coordinator, dir)
}

func waitUntil(timeout: TimeInterval = 5, _ condition: () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return await condition()
}

@Suite struct RefreshCoordinatorTests {
    @Test func zeroSourcesProducesEmptySnapshot() async throws {
        let (coordinator, dir) = try makeCoordinator(name: "empty")
        defer { try? FileManager.default.removeItem(at: dir) }
        let snapshot = await coordinator.refreshAndWait()
        #expect(snapshot.subscriptions.isEmpty)
        #expect(snapshot.groups["grp-vertex"]?.spentUSD == 0)
        #expect(snapshot.groups["grp-vertex"]?.percent == 0)
        #expect(snapshot.unassigned.breakdown.isEmpty)
        #expect(snapshot.sourceErrors.isEmpty)
        #expect(snapshot.configError == nil)
        #expect(snapshot.lastSuccessfulRefreshAt == snapshot.generatedAt)
        #expect(snapshot.window.duration == 7 * 24 * 3600)
    }

    @Test func singleInFlightWithOnePendingFollowUp() async throws {
        let (coordinator, dir) = try makeCoordinator(name: "inflight")
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = GatedSource()
        await coordinator.register(source)

        await coordinator.requestRefresh()
        let started = await waitUntil { await source.calls == 1 }
        #expect(started)
        #expect(await coordinator.isRunning)

        // Three more requests while running: all collapse into one follow-up.
        await coordinator.requestRefresh()
        await coordinator.requestRefresh()
        await coordinator.requestRefresh()
        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(await source.calls == 1)

        await source.release()
        let finished = await waitUntil { await !coordinator.isRunning }
        #expect(finished)
        #expect(await source.calls == 2)
        #expect(await coordinator.refreshCount == 2)

        // Idle again: a new request starts a new refresh.
        await coordinator.requestRefresh()
        let third = await waitUntil {
            let running = await coordinator.isRunning
            let count = await coordinator.refreshCount
            return !running && count == 3
        }
        #expect(third)
        #expect(await source.calls == 3)
    }

    @Test func failingSourceDoesNotBlockOthers() async throws {
        let (coordinator, dir) = try makeCoordinator(name: "isolation")
        defer { try? FileManager.default.removeItem(at: dir) }
        let status = SubscriptionStatus(fiveHour: LimitWindow(utilizationPercent: 12, resetsAt: Date()),
                                        sevenDay: LimitWindow(utilizationPercent: 40, resetsAt: Date()),
                                        fetchedAt: Date())
        let good = StaticSource(name: "subscription", output: .subscriptions(["acc-max": SubscriptionEntry(status: status, state: .ok)]))
        let bad = FailingSource(name: "sessionLogs", message: "disk on fire")
        await coordinator.register(good)
        await coordinator.register(bad)

        let first = await coordinator.refreshAndWait()
        #expect(first.subscriptions["acc-max"]?.status == status)
        #expect(first.sourceErrors.count == 1)
        #expect(first.sourceErrors[0].sourceName == "sessionLogs")
        #expect(first.sourceErrors[0].message.contains("disk on fire"))
        #expect(first.lastSuccessfulRefreshAt == nil)
        #expect(first.isStale)

        let logText = try String(contentsOf: dir.appendingPathComponent("usage.log"), encoding: .utf8)
        #expect(logText.contains("[sessionLogs]"))
        #expect(logText.contains("disk on fire"))
        #expect(logText.contains("[subscription]"))
    }

    @Test func lastSuccessfulRefreshIsCarriedOverAcrossFailures() async throws {
        let (coordinator, dir) = try makeCoordinator(name: "lastok")
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = StaticSource(name: "sessionLogs", output: .records([]))
        await coordinator.register(source)
        let ok = await coordinator.refreshAndWait()
        #expect(ok.lastSuccessfulRefreshAt == ok.generatedAt)

        await coordinator.register(FailingSource(name: "subscription", message: "offline"))
        let failed = await coordinator.refreshAndWait()
        #expect(failed.lastSuccessfulRefreshAt == ok.generatedAt)
        #expect(failed.sourceErrors.map(\.sourceName) == ["subscription"])
        #expect(failed.isStale)
    }

    @Test func staleSubscriptionEntryCountsAsSourceError() async throws {
        let (coordinator, dir) = try makeCoordinator(name: "stale-entry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let status = SubscriptionStatus(fiveHour: nil, sevenDay: LimitWindow(utilizationPercent: 40, resetsAt: Date()), fetchedAt: Date())
        let source = StaticSource(name: "subscription", output: .subscriptions([
            "acc-max": SubscriptionEntry(status: status, state: .stale(lastGoodAt: status.fetchedAt, error: "HTTP 503")),
            "acc-two": SubscriptionEntry(status: nil, state: .notSignedIn),
        ]))
        await coordinator.register(source)
        let snapshot = await coordinator.refreshAndWait()
        #expect(snapshot.sourceErrors.count == 1)
        #expect(snapshot.sourceErrors[0].sourceName == "subscription")
        #expect(snapshot.sourceErrors[0].message.contains("acc-max"))
        #expect(snapshot.sourceErrors[0].message.contains("HTTP 503"))
        #expect(snapshot.lastSuccessfulRefreshAt == nil)
        #expect(snapshot.isStale)
        #expect(snapshot.subscriptions["acc-max"]?.status == status)

        source.output = .subscriptions(["acc-max": SubscriptionEntry(status: status, state: .ok)])
        let recovered = await coordinator.refreshAndWait()
        #expect(recovered.sourceErrors.isEmpty)
        #expect(recovered.lastSuccessfulRefreshAt == recovered.generatedAt)
    }

    @Test func thrownSubscriptionSourceCarriesPreviousEntriesAsStale() async throws {
        let (coordinator, dir) = try makeCoordinator(name: "thrown-sub")
        defer { try? FileManager.default.removeItem(at: dir) }
        let fetched = Date(timeIntervalSince1970: 1_700_000_000)
        let status = SubscriptionStatus(fiveHour: nil, sevenDay: LimitWindow(utilizationPercent: 40, resetsAt: Date()), fetchedAt: fetched)
        let source = StaticSource(name: "subscription", output: .subscriptions(["acc-max": SubscriptionEntry(status: status, state: .ok)]))
        await coordinator.register(source)
        let first = await coordinator.refreshAndWait()
        #expect(first.subscriptions["acc-max"]?.state == .ok)

        await coordinator.register(FailingSource(name: "subscription-2", message: "boom"))
        source.output = .records([])  // the subscription source produces nothing this time
        let second = await coordinator.refreshAndWait()
        #expect(second.subscriptions["acc-max"]?.state == .stale(lastGoodAt: fetched, error: "boom"))
        #expect(second.subscriptions["acc-max"]?.status == status)
        #expect(second.lastSuccessfulRefreshAt == first.generatedAt)
    }

    @Test func earlierAlignedWindowRerunsLogSourceWithinTheSameRefresh() async throws {
        // Tuesday 2026-10-13 08:00 UTC: the Monday fallback starts Oct 12 00:00,
        // the aligned window from a reset on Oct 16 07:00 starts Oct 9 07:00.
        let now = isoDate("2026-10-13T08:00:00Z")
        let (coordinator, dir) = try makeCoordinator(name: "rerun", clock: { now })
        defer { try? FileManager.default.removeItem(at: dir) }
        let reset = isoDate("2026-10-16T07:00:00Z")
        let status = SubscriptionStatus(fiveHour: nil, sevenDay: LimitWindow(utilizationPercent: 30, resetsAt: reset), fetchedAt: now)
        let subscription = StaticSource(name: "subscription", output: .subscriptions(["acc-max": SubscriptionEntry(status: status, state: .ok)]))
        let logs = FakeLogSource()
        logs.records = [makeRecord(id: "a", accountId: "acc-vertex", timestamp: isoDate("2026-10-10T10:00:00Z"), cost: 6)]
        await coordinator.register(subscription)
        await coordinator.register(logs)

        let first = await coordinator.refreshAndWait()
        #expect(logs.contexts.count == 2)
        #expect(logs.resets == 1)
        #expect(logs.contexts[0].window.start == isoDate("2026-10-12T00:00:00Z"))
        #expect(logs.contexts[1].window.start == isoDate("2026-10-09T07:00:00Z"))
        #expect(first.window == DateInterval(start: isoDate("2026-10-09T07:00:00Z"), end: reset))
        #expect(first.windowSource == .aligned(accountId: "acc-max"))
        #expect(first.groups["grp-vertex"]?.spentUSD == 6)
        #expect(first.groups["grp-vertex"]?.percent == 10)
        #expect(first.groups["grp-vertex"]?.resetAt == reset)

        // Second refresh: the window is already known at the start, no re-run.
        let second = await coordinator.refreshAndWait()
        #expect(logs.contexts.count == 3)
        #expect(logs.resets == 1)
        #expect(logs.contexts[2].window.start == isoDate("2026-10-09T07:00:00Z"))
        #expect(second.windowSource == .aligned(accountId: "acc-max"))
    }

    @Test func alignmentSurvivesProviderOutage() async throws {
        let now = isoDate("2026-10-13T08:00:00Z")
        let (coordinator, dir) = try makeCoordinator(name: "align-outage", clock: { now })
        defer { try? FileManager.default.removeItem(at: dir) }
        let reset = isoDate("2026-10-16T07:00:00Z")
        let status = SubscriptionStatus(fiveHour: nil, sevenDay: LimitWindow(utilizationPercent: 30, resetsAt: reset), fetchedAt: now)
        let subscription = StaticSource(name: "subscription", output: .subscriptions(["acc-max": SubscriptionEntry(status: status, state: .ok)]))
        await coordinator.register(subscription)
        let first = await coordinator.refreshAndWait()
        #expect(first.windowSource == .aligned(accountId: "acc-max"))

        subscription.output = .subscriptions(["acc-max": SubscriptionEntry(status: status, state: .stale(lastGoodAt: now, error: "offline"))])
        let stale = await coordinator.refreshAndWait()
        #expect(stale.windowSource == .aligned(accountId: "acc-max"))
        #expect(stale.window.end == reset)

        // No status at all this time: only the coordinator's memory of the
        // last fetched reset can keep the window aligned.
        subscription.output = .subscriptions(["acc-max": SubscriptionEntry(status: nil, state: .stale(lastGoodAt: now, error: "offline"))])
        let silent = await coordinator.refreshAndWait()
        #expect(silent.windowSource == .aligned(accountId: "acc-max"))
        #expect(silent.window == DateInterval(start: isoDate("2026-10-09T07:00:00Z"), end: reset))
    }

    @Test func designatedAlignmentAccountDecidesBetweenTwoSubscriptions() async throws {
        let now = isoDate("2026-10-13T08:00:00Z")
        var config = try decodeConfig(contractExampleJSON)
        config.accounts.append(Account(
            id: "acc-two", label: "M2", displayName: "Second", harness: .claudeCode,
            kind: .subscription(SubscriptionSettings(credentialDirectory: "~/other", shownInBar: false, thresholds: [])),
            customMarker: nil))
        config.alignmentAccountId = "acc-two"
        let encoder = JSONEncoder()
        let (coordinator, dir) = try makeCoordinator(configJSON: String(decoding: try encoder.encode(config), as: UTF8.self),
                                                     name: "two-subs", clock: { now })
        defer { try? FileManager.default.removeItem(at: dir) }

        let resetMax = isoDate("2026-10-16T07:00:00Z")
        let resetTwo = isoDate("2026-10-17T09:00:00Z")
        func entry(_ reset: Date) -> SubscriptionEntry {
            SubscriptionEntry(status: SubscriptionStatus(fiveHour: nil, sevenDay: LimitWindow(utilizationPercent: 10, resetsAt: reset), fetchedAt: now), state: .ok)
        }
        await coordinator.register(StaticSource(name: "subscription", output: .subscriptions(["acc-max": entry(resetMax), "acc-two": entry(resetTwo)])))

        let designated = await coordinator.refreshAndWait()
        #expect(designated.windowSource == .aligned(accountId: "acc-two"))
        #expect(designated.window.end == resetTwo)

        // Without an explicit choice the first configured subscription account aligns the window.
        config.alignmentAccountId = nil
        let configURL = dir.appendingPathComponent("config.json")
        try encoder.encode(config).write(to: configURL)
        let mtime = try FileManager.default.attributesOfItem(atPath: configURL.path)[.modificationDate] as! Date
        try FileManager.default.setAttributes([.modificationDate: mtime.addingTimeInterval(5)], ofItemAtPath: configURL.path)
        let defaulted = await coordinator.refreshAndWait()
        #expect(defaulted.configError == nil)
        #expect(defaulted.windowSource == .aligned(accountId: "acc-max"))
        #expect(defaulted.window.end == resetMax)
    }

    @Test func failedLogSourceCarriesPreviousGroupsAsStale() async throws {
        let now = isoDate("2026-10-13T08:00:00Z")
        let (coordinator, dir) = try makeCoordinator(name: "stale-groups", clock: { now })
        defer { try? FileManager.default.removeItem(at: dir) }
        let logs = FakeLogSource()
        logs.records = [
            makeRecord(id: "a", accountId: "acc-vertex", timestamp: isoDate("2026-10-12T10:00:00Z"), input: 10, cost: 12),
            makeRecord(id: "b", accountId: nil, timestamp: isoDate("2026-10-12T10:00:00Z"), input: 7, cost: nil),
        ]
        await coordinator.register(logs)
        let first = await coordinator.refreshAndWait()
        #expect(first.groups["grp-vertex"]?.spentUSD == 12)
        #expect(first.groups["grp-vertex"]?.stale == false)
        #expect(first.unassigned.breakdown.inputTokens == 7)

        logs.fail = true
        let second = await coordinator.refreshAndWait()
        #expect(second.sourceErrors.map(\.sourceName) == ["sessionLogs"])
        #expect(second.groups["grp-vertex"]?.spentUSD == 12)
        #expect(second.groups["grp-vertex"]?.percent == 20)
        #expect(second.groups["grp-vertex"]?.stale == true)
        #expect(second.tokenAccounts["acc-vertex"]?.stale == true)
        #expect(second.unassigned.stale == true)
        #expect(second.unassigned.breakdown.inputTokens == 7)
        #expect(second.lastSuccessfulRefreshAt == first.generatedAt)

        logs.fail = false
        let third = await coordinator.refreshAndWait()
        #expect(third.groups["grp-vertex"]?.stale == false)
        #expect(third.sourceErrors.isEmpty)
    }

    @Test func failedLogSourceOnFirstRefreshMarksEmptyGroupsStale() async throws {
        let (coordinator, dir) = try makeCoordinator(name: "stale-first")
        defer { try? FileManager.default.removeItem(at: dir) }
        let logs = FakeLogSource()
        logs.fail = true
        await coordinator.register(logs)
        let snapshot = await coordinator.refreshAndWait()
        #expect(snapshot.groups["grp-vertex"]?.spentUSD == 0)
        #expect(snapshot.groups["grp-vertex"]?.stale == true)
        #expect(snapshot.tokenAccounts["acc-vertex"]?.stale == true)
        #expect(snapshot.unassigned.stale == true)
        #expect(snapshot.lastSuccessfulRefreshAt == nil)
    }

    @Test func configErrorIsSurfacedAndLastValidConfigurationUsed() async throws {
        let (coordinator, dir) = try makeCoordinator(name: "configerr")
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = GatedSource(name: "sessionLogs")
        await source.release()
        await coordinator.register(source)
        _ = await coordinator.refreshAndWait()

        let configURL = dir.appendingPathComponent("config.json")
        try Data("{ broken".utf8).write(to: configURL)
        let attrs = try FileManager.default.attributesOfItem(atPath: configURL.path)
        let mtime = attrs[.modificationDate] as! Date
        try FileManager.default.setAttributes([.modificationDate: mtime.addingTimeInterval(5)], ofItemAtPath: configURL.path)

        let snapshot = await coordinator.refreshAndWait()
        #expect(snapshot.configError != nil)
        let contexts = await source.contexts
        #expect(contexts.last?.configuration.refreshIntervalSeconds == 300)
        #expect(contexts.last?.configuration.accounts.count == 2)
    }
    // MARK: Reprice without the usage endpoint (FR-023a)

    @Test func repriceReusesNetworkResultsAndRecomputesRecords() async throws {
        // An advancing clock, so that a reprice that wrongly counted as a
        // successful refresh would move `lastSuccessfulRefreshAt`.
        let ticks = AdvancingClock(start: isoDate("2026-10-13T08:00:00Z"), step: 60)
        let (coordinator, dir) = try makeCoordinator(name: "reprice", clock: { ticks.next() })
        defer { try? FileManager.default.removeItem(at: dir) }
        let network = GatedNetworkSource(output: subscriptionOutput())
        let logs = FakeLogSource()
        logs.records = [makeRecord(id: "a", accountId: "acc-vertex", timestamp: isoDate("2026-10-12T10:00:00Z"), input: 10, cost: 6)]
        await coordinator.register(network)
        await coordinator.register(logs)

        let first = await coordinator.refreshAndWait()
        #expect(first.groups["grp-vertex"]?.spentUSD == 6)
        #expect(await network.calls == 1)

        logs.records = [makeRecord(id: "a", accountId: "acc-vertex", timestamp: isoDate("2026-10-12T10:00:00Z"), input: 10, cost: 12)]
        let second = await coordinator.repriceAndWait()
        #expect(second.groups["grp-vertex"]?.spentUSD == 12)
        #expect(second.subscriptions["acc-max"]?.status == first.subscriptions["acc-max"]?.status)
        #expect(second.subscriptions["acc-max"]?.state.isOk == true)
        #expect(second.sourceErrors.isEmpty)
        #expect(second.generatedAt != first.generatedAt)
        #expect(first.lastSuccessfulRefreshAt == first.generatedAt)
        #expect(second.lastSuccessfulRefreshAt == first.generatedAt)
        #expect(await network.calls == 1)
        #expect(logs.contexts.count == 2)
        #expect(await coordinator.refreshCount == 2)

        let logText = try String(contentsOf: dir.appendingPathComponent("usage.log"), encoding: .utf8)
        #expect(logText.contains("reused"))
    }

    /// The coordinator decides reuse only through the `NetworkBoundSource`
    /// marker, so the real usage endpoint source must carry it and the log
    /// source must not (FR-023a).
    @Test func realSourcesCarryTheNetworkBoundMarkerAsExpected() throws {
        let dir = try makeTempDirectory("marker")
        defer { try? FileManager.default.removeItem(at: dir) }
        let subscription: UsageSource = SubscriptionSource(credentialReader: FakeCredentialReader(),
                                                           client: UsageEndpointClient(session: StubURLProtocol.makeSession()))
        let logs: UsageSource = try SessionLogSource(paths: Paths(home: dir), builtInPrices: PriceTable(entries: []))
        #expect(subscription is NetworkBoundSource)
        #expect(!(logs is NetworkBoundSource))
    }

    @Test func repriceBeforeAnyRefreshIsAFullRefresh() async throws {
        let (coordinator, dir) = try makeCoordinator(name: "reprice-first")
        defer { try? FileManager.default.removeItem(at: dir) }
        let network = GatedNetworkSource(output: subscriptionOutput())
        let logs = FakeLogSource()
        await coordinator.register(network)
        await coordinator.register(logs)
        let snapshot = await coordinator.repriceAndWait()
        #expect(await network.calls == 1)
        #expect(snapshot.subscriptions["acc-max"] != nil)
        #expect(logs.contexts.count == 1)
    }

    @Test func repriceDuringRunningRefreshRunsOneFollowUpReprice() async throws {
        let (coordinator, dir) = try makeCoordinator(name: "reprice-running")
        defer { try? FileManager.default.removeItem(at: dir) }
        let network = GatedNetworkSource(output: subscriptionOutput(), open: false)
        let logs = FakeLogSource()
        await coordinator.register(network)
        await coordinator.register(logs)

        await coordinator.requestRefresh()
        #expect(await waitUntil { await network.calls == 1 })
        await coordinator.requestReprice()
        await coordinator.requestReprice()
        await network.release()
        #expect(await waitUntil {
            let running = await coordinator.isRunning
            let count = await coordinator.refreshCount
            return !running && count == 2
        })
        #expect(await network.calls == 1)
        #expect(logs.contexts.count == 2)
    }

    @Test func pendingFullRefreshWinsOverPendingReprice() async throws {
        let (coordinator, dir) = try makeCoordinator(name: "reprice-full-wins")
        defer { try? FileManager.default.removeItem(at: dir) }
        let network = GatedNetworkSource(output: subscriptionOutput(), open: false)
        let logs = FakeLogSource()
        await coordinator.register(network)
        await coordinator.register(logs)

        await coordinator.requestRefresh()
        #expect(await waitUntil { await network.calls == 1 })
        await coordinator.requestRefresh()
        await coordinator.requestReprice()
        await network.release()
        #expect(await waitUntil {
            let running = await coordinator.isRunning
            let count = await coordinator.refreshCount
            return !running && count == 2
        })
        #expect(await network.calls == 2)
        #expect(logs.contexts.count == 2)
    }
}
