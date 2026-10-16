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
    private var output: SourceOutput
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var open: Bool
    private(set) var calls = 0

    init(output: SourceOutput, open: Bool = true) {
        self.output = output
        self.open = open
    }

    func setOutput(_ output: SourceOutput) { self.output = output }

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

/// A clock tests move by hand.
final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date) { current = start }
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return current }
    func advance(_ seconds: TimeInterval) { lock.lock(); current += seconds; lock.unlock() }
}

/// Stands in for the retry sleep: records each requested delay and waits
/// until `open()`.
actor SleepGate {
    private(set) var delays: [TimeInterval] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func sleep(_ delay: TimeInterval) async {
        delays.append(delay)
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        let w = waiters
        waiters = []
        w.forEach { $0.resume() }
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

func subscriptionOutput(percent: Double = 12, outcome: FetchOutcome? = .success) -> SourceOutput {
    let status = SubscriptionStatus(fiveHour: LimitWindow(utilizationPercent: percent, resetsAt: isoDate("2026-10-13T12:00:00Z")),
                                    sevenDay: nil, fetchedAt: isoDate("2026-10-13T08:00:00Z"))
    let state: SubscriptionState = outcome?.isRateLimited == true
        ? .stale(lastGoodAt: nil, error: "usage endpoint returned HTTP 429") : .ok
    return .subscriptions(["acc-max": SubscriptionEntry(status: status, state: state, fetchOutcome: outcome)])
}

func makeCoordinator(configJSON: String = contractExampleJSON, name: String = "coord",
                     clock: @escaping @Sendable () -> Date = { Date() },
                     retrySleep: @escaping @Sendable (TimeInterval) async -> Void = { _ in try? await Task.sleep(for: .seconds(3600)) },
                     quickRetrySleep: @escaping @Sendable (TimeInterval) async -> Void = { _ in try? await Task.sleep(for: .seconds(3600)) }) throws -> (RefreshCoordinator, URL) {
    let dir = try makeTempDirectory(name)
    let configURL = dir.appendingPathComponent("config.json")
    try Data(configJSON.utf8).write(to: configURL)
    let store = ConfigStore(fileURL: configURL)
    let log = DiagnosticLog(fileURL: dir.appendingPathComponent("usage.log"))
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let coordinator = RefreshCoordinator(configStore: store, log: log, resolver: WindowResolver(), aggregator: Aggregator(),
                                         calendar: utc, clock: clock, retrySleep: retrySleep, quickRetrySleep: quickRetrySleep)
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

    /// An account whose credential directory changed has no successful
    /// request in this run for the new sign-in: a passed 7-day reset no
    /// longer aligns the window through it (spec 010 FR-020).
    @Test func changedCredentialDirectoryEndsTheFetchedThisRunAlignment() async throws {
        let now = isoDate("2026-10-13T08:00:00Z")
        let clock = MutableClock(now)
        let (coordinator, dir) = try makeCoordinator(name: "align-dir-change", clock: { clock.now() })
        defer { try? FileManager.default.removeItem(at: dir) }
        let reset = now.addingTimeInterval(600)
        let status = SubscriptionStatus(fiveHour: nil, sevenDay: LimitWindow(utilizationPercent: 30, resetsAt: reset), fetchedAt: now)
        let subscription = StaticSource(name: "subscription", output: .subscriptions(["acc-max": SubscriptionEntry(status: status, state: .ok)]))
        await coordinator.register(subscription)
        let first = await coordinator.refreshAndWait()
        #expect(first.windowSource == .aligned(accountId: "acc-max"))

        let moved = contractExampleJSON.replacingOccurrences(of: "\"credentialDirectory\": \"~/.claude\"",
                                                             with: "\"credentialDirectory\": \"~/.claude-other\"")
        try Data(moved.utf8).write(to: dir.appendingPathComponent("config.json"))
        subscription.output = .subscriptions(["acc-max": SubscriptionEntry(status: status, state: .stale(lastGoodAt: now, error: "offline"))])
        clock.advance(700)
        let later = await coordinator.refreshAndWait()
        #expect(later.windowSource == .fallback)
    }

    @Test func designatedAlignmentAccountDecidesBetweenTwoSubscriptions() async throws {
        let now = isoDate("2026-10-13T08:00:00Z")
        var config = try decodeConfig(contractExampleJSON)
        config.accounts.append(Account(
            id: "acc-two", displayName: "Second", harness: .claudeCode,
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

    /// Spec 012 FR-003: an unknown level color is noted once in the
    /// diagnostic log with source `config`, without a configuration error.
    @Test func unknownLevelColorIsLoggedOnceAsConfigNote() async throws {
        let json = contractExampleJSON.replacingOccurrences(of: "\"startAtLogin\": false,",
                                                            with: "\"startAtLogin\": false,\n  \"levelColor\": \"rainbow\",")
        let (coordinator, dir) = try makeCoordinator(configJSON: json, name: "confignote")
        defer { try? FileManager.default.removeItem(at: dir) }
        let snapshot = await coordinator.refreshAndWait()
        _ = await coordinator.refreshAndWait()
        #expect(snapshot.configError == nil)
        let log = DiagnosticLog(fileURL: dir.appendingPathComponent("usage.log"))
        let notes = log.tail(lines: 200).filter { $0.contains("[config]") }
        #expect(notes.count == 1)
        #expect(notes.first?.contains("levelColor \"rainbow\" is not known") == true)
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
        // The Codex limits source gates its own requests (spec 007 research R5).
        let codexLimits: UsageSource = CodexLimitsSource(credentialReader: FileCodexCredentialReader(paths: Paths(home: dir)),
                                                         client: CodexUsageClient(session: StubURLProtocol.makeSession()))
        #expect(!(codexLimits is NetworkBoundSource))
        #expect(codexLimits.name == CodexLimitsSource.sourceName)
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

    @Test func manualTwiceWithinSpacingCallsTheEndpointOnce() async throws {
        let clock = MutableClock(isoDate("2026-10-13T08:00:00Z"))
        let (coordinator, dir) = try makeCoordinator(name: "spacing", clock: { clock.now() })
        defer { try? FileManager.default.removeItem(at: dir) }
        let network = GatedNetworkSource(output: subscriptionOutput())
        await coordinator.register(network)
        await coordinator.register(FakeLogSource())

        _ = await coordinator.refreshAndWait(trigger: .launch)
        clock.advance(30)
        _ = await coordinator.refreshAndWait(trigger: .manual)
        #expect(await network.calls == 1)
        clock.advance(30)
        _ = await coordinator.refreshAndWait(trigger: .manual)
        #expect(await network.calls == 2)

        let logText = try String(contentsOf: dir.appendingPathComponent("usage.log"), encoding: .utf8)
        #expect(logText.contains("trigger manual, endpoint reused (last fetch 30 s ago)"))
    }

    @Test func localTriggerNeverCallsTheEndpoint() async throws {
        let (coordinator, dir) = try makeCoordinator(name: "local")
        defer { try? FileManager.default.removeItem(at: dir) }
        let network = GatedNetworkSource(output: subscriptionOutput())
        await coordinator.register(network)
        await coordinator.register(FakeLogSource())
        _ = await coordinator.refreshAndWait(trigger: .launch)
        _ = await coordinator.refreshAndWait(trigger: .local)
        _ = await coordinator.repriceAndWait()
        #expect(await network.calls == 1)
    }

    @Test func rateLimitBlocksAndRetriesOnceAtTheBlockEnd() async throws {
        let start = isoDate("2026-10-13T08:00:00Z")
        let clock = MutableClock(start)
        let gate = SleepGate()
        let (coordinator, dir) = try makeCoordinator(name: "retry", clock: { clock.now() },
                                                     retrySleep: { await gate.sleep($0) })
        defer { try? FileManager.default.removeItem(at: dir) }
        let network = GatedNetworkSource(output: subscriptionOutput(outcome: .rateLimited(retryAfter: 120)))
        await coordinator.register(network)
        await coordinator.register(FakeLogSource())

        let first = await coordinator.refreshAndWait(trigger: .launch)
        #expect(first.endpointBlockedUntil == start.addingTimeInterval(120))
        #expect(first.nextRetryAt == start.addingTimeInterval(120))
        #expect(await waitUntil { await gate.delays.count == 1 })
        #expect(await gate.delays.first == 121)

        // A scheduled tick and a wake inside the block reuse the last result.
        clock.advance(60)
        let blocked = await coordinator.refreshAndWait(trigger: .scheduled)
        _ = await coordinator.refreshAndWait(trigger: .wake)
        #expect(await network.calls == 1)
        #expect(blocked.subscriptions["acc-max"]?.state.isOk == false)
        #expect(blocked.nextRetryAt == start.addingTimeInterval(120))

        // The block ends; the retry fetches fresh data.
        await network.setOutput(subscriptionOutput(percent: 20))
        clock.advance(61)
        let before = await coordinator.refreshCount
        await gate.open()
        #expect(await waitUntil {
            let count = await coordinator.refreshCount
            let running = await coordinator.isRunning
            return count == before + 1 && !running
        })
        #expect(await network.calls == 2)
        let fresh = try #require(await coordinator.latestSnapshot)
        #expect(fresh.subscriptions["acc-max"]?.state.isOk == true)
        #expect(fresh.endpointBlockedUntil == nil)
        #expect(fresh.nextRetryAt == nil)
    }

    @Test func aRetryThatHitsAnotherLimitIsNotRetriedAgain() async throws {
        let start = isoDate("2026-10-13T08:00:00Z")
        let clock = MutableClock(start)
        let gate = SleepGate()
        let (coordinator, dir) = try makeCoordinator(name: "retry-twice", clock: { clock.now() },
                                                     retrySleep: { await gate.sleep($0) })
        defer { try? FileManager.default.removeItem(at: dir) }
        let network = GatedNetworkSource(output: subscriptionOutput(outcome: .rateLimited(retryAfter: 120)))
        await coordinator.register(network)
        await coordinator.register(FakeLogSource())

        _ = await coordinator.refreshAndWait(trigger: .launch)
        #expect(await waitUntil { await gate.delays.count == 1 })
        clock.advance(121)
        await gate.open()
        #expect(await waitUntil {
            let calls = await network.calls
            let running = await coordinator.isRunning
            return calls == 2 && !running
        })
        let snapshot = try #require(await coordinator.latestSnapshot)
        #expect(snapshot.nextRetryAt == nil)
        #expect(snapshot.endpointBlockedUntil == start.addingTimeInterval(241))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await gate.delays.count == 1)
    }

    @Test func pendingScheduledWinsOverPendingLocalReprice() async throws {
        let (coordinator, dir) = try makeCoordinator(name: "pending-rank")
        defer { try? FileManager.default.removeItem(at: dir) }
        let network = GatedNetworkSource(output: subscriptionOutput(), open: false)
        await coordinator.register(network)
        await coordinator.register(FakeLogSource())

        await coordinator.requestRefresh(trigger: .launch)
        #expect(await waitUntil { await network.calls == 1 })
        await coordinator.requestRefresh(trigger: .local)
        await coordinator.requestRefresh(trigger: .scheduled)
        await coordinator.requestRefresh(trigger: .local)
        await network.release()
        #expect(await waitUntil {
            let running = await coordinator.isRunning
            let count = await coordinator.refreshCount
            return !running && count == 2
        })
        #expect(await network.calls == 2)
    }

    @Test func reusedResultsDropRemovedSubscriptionAccounts() async throws {
        let (coordinator, dir) = try makeCoordinator(name: "reuse-filter")
        defer { try? FileManager.default.removeItem(at: dir) }
        await coordinator.register(GatedNetworkSource(output: subscriptionOutput()))
        await coordinator.register(FakeLogSource())
        let first = await coordinator.refreshAndWait(trigger: .launch)
        #expect(first.subscriptions["acc-max"] != nil)

        var config = try decodeConfig(contractExampleJSON)
        config.accounts.removeAll { $0.id == "acc-max" }
        config.alignmentAccountId = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: dir.appendingPathComponent("config.json"), options: .atomic)

        let second = await coordinator.repriceAndWait()
        #expect(second.subscriptions["acc-max"] == nil)
    }

    @Test func settingsEditWithinSpacingFetchesWhenTheSpacingEnds() async throws {
        let start = isoDate("2026-10-13T08:00:00Z")
        let clock = MutableClock(start)
        let gate = SleepGate()
        let (coordinator, dir) = try makeCoordinator(name: "settings-defer", clock: { clock.now() },
                                                     retrySleep: { await gate.sleep($0) })
        defer { try? FileManager.default.removeItem(at: dir) }
        let network = GatedNetworkSource(output: subscriptionOutput())
        await coordinator.register(network)
        await coordinator.register(FakeLogSource())

        _ = await coordinator.refreshAndWait(trigger: .launch)
        clock.advance(30)
        _ = await coordinator.refreshAndWait(trigger: .settings)
        #expect(await network.calls == 1)
        #expect(await waitUntil { await gate.delays == [31] })

        clock.advance(31)
        await gate.open()
        #expect(await waitUntil {
            let calls = await network.calls
            let running = await coordinator.isRunning
            return calls == 2 && !running
        })
    }

    @Test func reusedEntryWithAChangedCredentialDirectoryIsDropped() async throws {
        let (coordinator, dir) = try makeCoordinator(name: "reuse-dir")
        defer { try? FileManager.default.removeItem(at: dir) }
        await coordinator.register(GatedNetworkSource(output: subscriptionOutput()))
        await coordinator.register(FakeLogSource())
        let first = await coordinator.refreshAndWait(trigger: .launch)
        #expect(first.subscriptions["acc-max"] != nil)

        var config = try decodeConfig(contractExampleJSON)
        let index = try #require(config.accounts.firstIndex { $0.id == "acc-max" })
        if case .subscription(var settings) = config.accounts[index].kind {
            settings.credentialDirectory = "~/.claude-other"
            config.accounts[index].kind = .subscription(settings)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: dir.appendingPathComponent("config.json"), options: .atomic)

        let second = await coordinator.repriceAndWait()
        #expect(second.subscriptions["acc-max"] == nil)
    }

    @Test func pendingScheduledReplacesPendingRetry() async throws {
        let (coordinator, dir) = try makeCoordinator(name: "pending-retry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let network = GatedNetworkSource(output: subscriptionOutput(), open: false)
        await coordinator.register(network)
        await coordinator.register(FakeLogSource())

        await coordinator.requestRefresh(trigger: .launch)
        #expect(await waitUntil { await network.calls == 1 })
        await coordinator.requestRefresh(trigger: .retry)
        await coordinator.requestRefresh(trigger: .scheduled)
        await network.release()
        #expect(await waitUntil {
            let running = await coordinator.isRunning
            let count = await coordinator.refreshCount
            return !running && count == 2
        })
        #expect(await network.calls == 2)
    }
}

/// Spec 003: the record source collects over a window spanning every group
/// window, while the snapshot keeps the weekly window (FR-006, research R2).
@Suite struct MonthlyRefreshCoordinatorTests {
    /// Tuesday 2026-10-13 08:00 UTC; the Monday fallback week is Oct 12 to Oct 19.
    let now = isoDate("2026-10-13T08:00:00Z")
    let weekly = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
    let month = DateInterval(start: isoDate("2026-10-01T00:00:00Z"), end: isoDate("2026-11-01T00:00:00Z"))

    static let monthlyJSON = contractExampleJSON.replacingOccurrences(of: "\"weeklyBudgetUSD\": 60", with: "\"period\": \"monthly\", \"budgetUSD\": 400")

    @Test func weeklyOnlyCollectsOverTheWeeklyWindow() async throws {
        let now = self.now
        let (coordinator, dir) = try makeCoordinator(name: "collect-weekly", clock: { now })
        defer { try? FileManager.default.removeItem(at: dir) }
        let logs = FakeLogSource()
        await coordinator.register(logs)
        let snapshot = await coordinator.refreshAndWait()
        #expect(logs.contexts.map(\.window) == [weekly])
        #expect(snapshot.window == weekly)
        #expect(snapshot.groups["grp-vertex"]?.window == weekly)
        #expect(snapshot.groups["grp-vertex"]?.period == .weekly)
    }

    @Test func monthlyGroupWidensTheCollectionWindow() async throws {
        let now = self.now
        let (coordinator, dir) = try makeCoordinator(configJSON: Self.monthlyJSON, name: "collect-monthly", clock: { now })
        defer { try? FileManager.default.removeItem(at: dir) }
        let logs = FakeLogSource()
        logs.records = [
            makeRecord(id: "prev", accountId: "acc-vertex", timestamp: isoDate("2026-09-30T23:00:00Z"), cost: 500),
            makeRecord(id: "early", accountId: "acc-vertex", timestamp: isoDate("2026-10-05T10:00:00Z"), cost: 60),
            makeRecord(id: "week", accountId: "acc-vertex", timestamp: isoDate("2026-10-12T10:00:00Z"), cost: 40),
        ]
        await coordinator.register(logs)
        let snapshot = await coordinator.refreshAndWait()
        #expect(logs.contexts.map(\.window) == [month])
        #expect(snapshot.window == weekly)
        let group = snapshot.groups["grp-vertex"]
        #expect(group?.period == .monthly)
        #expect(group?.window == month)
        #expect(group?.resetAt == month.end)
        #expect(group?.spentUSD == 100)
        #expect(group?.percent == 25)
    }

    /// Spec US1 scenario 4: a new 7-day reset moves the weekly window only.
    @Test func monthlyWindowIgnoresAFreshSevenDayReset() async throws {
        let now = self.now
        let (coordinator, dir) = try makeCoordinator(configJSON: Self.monthlyJSON, name: "collect-reset", clock: { now })
        defer { try? FileManager.default.removeItem(at: dir) }
        let reset = isoDate("2026-10-16T07:00:00Z")
        let status = SubscriptionStatus(fiveHour: nil, sevenDay: LimitWindow(utilizationPercent: 30, resetsAt: reset), fetchedAt: now)
        await coordinator.register(StaticSource(name: "subscription", output: .subscriptions(["acc-max": SubscriptionEntry(status: status, state: .ok)])))
        let logs = FakeLogSource()
        await coordinator.register(logs)
        let snapshot = await coordinator.refreshAndWait()
        #expect(snapshot.windowSource == .aligned(accountId: "acc-max"))
        #expect(snapshot.window == DateInterval(start: isoDate("2026-10-09T07:00:00Z"), end: reset))
        #expect(snapshot.groups["grp-vertex"]?.window == month)
        #expect(snapshot.groups["grp-vertex"]?.resetAt == month.end)
        // The aligned week starts after the 1st, so the collection start did
        // not move earlier and the log source is not re-run.
        #expect(logs.contexts.map(\.window.start) == [month.start])
        #expect(logs.resets == 0)
    }

    /// Early in a month the aligned week can start before the 1st: the
    /// collection start moves earlier within the refresh, the log source is
    /// re-run over `[aligned start, month end)`, and the monthly group still
    /// counts only the current month.
    @Test func alignedWeekBeforeTheFirstRerunsWithTheWidenedCollection() async throws {
        // Tuesday 2026-10-06 08:00 UTC: the Monday fallback week is Oct 5 to
        // Oct 12, so the initial collection starts on Oct 1. A reset on Oct 7
        // 07:00 aligns the week to Sep 30 07:00.
        let now = isoDate("2026-10-06T08:00:00Z")
        let (coordinator, dir) = try makeCoordinator(configJSON: Self.monthlyJSON, name: "collect-rerun", clock: { now })
        defer { try? FileManager.default.removeItem(at: dir) }
        let reset = isoDate("2026-10-07T07:00:00Z")
        let alignedStart = isoDate("2026-09-30T07:00:00Z")
        let status = SubscriptionStatus(fiveHour: nil, sevenDay: LimitWindow(utilizationPercent: 30, resetsAt: reset), fetchedAt: now)
        await coordinator.register(StaticSource(name: "subscription", output: .subscriptions(["acc-max": SubscriptionEntry(status: status, state: .ok)])))
        let logs = FakeLogSource()
        logs.records = [
            makeRecord(id: "sep30", accountId: "acc-vertex", timestamp: isoDate("2026-09-30T10:00:00Z"), cost: 300),
            makeRecord(id: "oct2", accountId: "acc-vertex", timestamp: isoDate("2026-10-02T10:00:00Z"), cost: 100),
        ]
        await coordinator.register(logs)

        let snapshot = await coordinator.refreshAndWait()
        #expect(logs.resets == 1)
        #expect(logs.contexts.map(\.window.start) == [month.start, alignedStart])
        #expect(logs.contexts.last?.window.end == month.end)
        #expect(snapshot.window == DateInterval(start: alignedStart, end: reset))
        #expect(snapshot.windowSource == .aligned(accountId: "acc-max"))
        let group = snapshot.groups["grp-vertex"]
        #expect(group?.window == month)
        #expect(group?.spentUSD == 100)
        #expect(group?.percent == 25)
    }

    /// Adding a monthly group between refreshes widens the next collection
    /// window to the 1st (LogIndex resets itself on an earlier start).
    @Test func addingAMonthlyGroupCollectsFromTheFirst() async throws {
        let now = self.now
        let (coordinator, dir) = try makeCoordinator(name: "collect-switch", clock: { now })
        defer { try? FileManager.default.removeItem(at: dir) }
        let logs = FakeLogSource()
        logs.records = [
            makeRecord(id: "early", accountId: "acc-vertex", timestamp: isoDate("2026-10-05T10:00:00Z"), cost: 60),
            makeRecord(id: "week", accountId: "acc-vertex", timestamp: isoDate("2026-10-12T10:00:00Z"), cost: 6),
        ]
        await coordinator.register(logs)
        let first = await coordinator.refreshAndWait()
        #expect(first.groups["grp-vertex"]?.spentUSD == 6)
        #expect(logs.contexts.last?.window.start == weekly.start)

        let configURL = dir.appendingPathComponent("config.json")
        try Data(Self.monthlyJSON.utf8).write(to: configURL)
        let mtime = try FileManager.default.attributesOfItem(atPath: configURL.path)[.modificationDate] as! Date
        try FileManager.default.setAttributes([.modificationDate: mtime.addingTimeInterval(5)], ofItemAtPath: configURL.path)

        let second = await coordinator.refreshAndWait()
        #expect(second.configError == nil)
        #expect(logs.contexts.last?.window.start == month.start)
        #expect(second.groups["grp-vertex"]?.period == .monthly)
        #expect(second.groups["grp-vertex"]?.spentUSD == 66)
        #expect(second.window == weekly)
    }
}

/// Spec 004: accounts with their own budget in the refresh pipeline.
@Suite struct OwnBudgetRefreshCoordinatorTests {
    /// Tuesday 2026-10-13 08:00 UTC; the Monday fallback week is Oct 12 to Oct 19.
    let now = isoDate("2026-10-13T08:00:00Z")
    let weekly = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))
    let month = DateInterval(start: isoDate("2026-10-01T00:00:00Z"), end: isoDate("2026-11-01T00:00:00Z"))

    /// The contract example (a weekly group) plus `acc-own` with its own budget.
    static func json(period: String) -> String {
        contractExampleJSON.replacingOccurrences(of: """
              "groupId": "grp-vertex",
              "customMarker": null
            }
        """, with: """
              "groupId": "grp-vertex",
              "customMarker": null
            },
            {
              "id": "acc-own",
              "type": "tokenBased",
              "displayName": "Personal Vertex",
              "provider": "vertex",
              "customMarker": "personal",
              "budget": { "period": "\(period)", "budgetUSD": 100, "thresholds": [50] }
            }
        """)
    }

    /// Spec 001 FR-007: a failed record source carries the previous own-budget
    /// entries over, marked stale, so the threshold tracker skips them.
    @Test func failedLogSourceCarriesOwnBudgetsAsStale() async throws {
        let now = self.now
        let json = Self.json(period: "weekly")
        #expect(json.contains("acc-own"))
        let (coordinator, dir) = try makeCoordinator(configJSON: json, name: "stale-own", clock: { now })
        defer { try? FileManager.default.removeItem(at: dir) }
        let logs = FakeLogSource()
        logs.records = [makeRecord(id: "a", accountId: "acc-own", timestamp: isoDate("2026-10-12T10:00:00Z"), cost: 25)]
        await coordinator.register(logs)
        let first = await coordinator.refreshAndWait()
        #expect(first.configError == nil)
        #expect(first.accountBudgets["acc-own"]?.spentUSD == 25)
        #expect(first.accountBudgets["acc-own"]?.stale == false)

        logs.fail = true
        let second = await coordinator.refreshAndWait()
        #expect(second.accountBudgets["acc-own"]?.spentUSD == 25)
        #expect(second.accountBudgets["acc-own"]?.percent == 25)
        #expect(second.accountBudgets["acc-own"]?.stale == true)

        logs.fail = false
        let third = await coordinator.refreshAndWait()
        #expect(third.accountBudgets["acc-own"]?.stale == false)
    }

    /// Spec 004 FR-009: a monthly own budget widens the collection window
    /// even when every group is weekly.
    @Test func monthlyOwnBudgetWidensTheCollectionWindow() async throws {
        let now = self.now
        let (coordinator, dir) = try makeCoordinator(configJSON: Self.json(period: "monthly"), name: "collect-own", clock: { now })
        defer { try? FileManager.default.removeItem(at: dir) }
        let logs = FakeLogSource()
        logs.records = [
            makeRecord(id: "early", accountId: "acc-own", timestamp: isoDate("2026-10-05T10:00:00Z"), cost: 15),
            makeRecord(id: "week", accountId: "acc-own", timestamp: isoDate("2026-10-12T10:00:00Z"), cost: 10),
        ]
        await coordinator.register(logs)
        let snapshot = await coordinator.refreshAndWait()
        #expect(logs.contexts.map(\.window) == [month])
        #expect(snapshot.window == weekly)
        #expect(snapshot.groups["grp-vertex"]?.window == weekly)
        let own = snapshot.accountBudgets["acc-own"]
        #expect(own?.window == month)
        #expect(own?.spentUSD == 25)
        #expect(own?.percent == 25)
    }
}

// MARK: - Spec 006: record batches (FR-005, FR-006, SC-004)

@Suite struct RecordBatchCoordinatorTests {
    @Test func batchIssueBecomesSourceErrorAndStaleStaysWithItsHarness() async throws {
        let now = isoDate("2026-10-13T08:00:00Z")
        let (coordinator, dir) = try makeCoordinator(name: "record-batch", clock: { now })
        defer { try? FileManager.default.removeItem(at: dir) }
        let logs = FakeLogSource()
        logs.records = [makeRecord(id: "a", accountId: "acc-vertex", timestamp: isoDate("2026-10-12T10:00:00Z"), input: 10, cost: 12)]
        let batch = RecordBatch(records: [makeRecord(id: "oc", accountId: nil, timestamp: isoDate("2026-10-12T11:00:00Z"),
                                                     input: 5, cost: nil, harness: .openCode)],
                                issues: ["opencode: /data/opencode.db: database is locked"],
                                staleHarnesses: [.openCode])
        let openCode = StaticSource(name: "opencode", output: .recordBatch(batch))
        await coordinator.register(logs)
        await coordinator.register(openCode)

        let snapshot = await coordinator.refreshAndWait()
        #expect(snapshot.sourceErrors.count == 1)
        #expect(snapshot.sourceErrors.first?.sourceName == "opencode")
        #expect(snapshot.sourceErrors.first?.message == "opencode: /data/opencode.db: database is locked")
        // The Claude-Code-only group stays fresh; Unassigned holds the stale harness.
        #expect(snapshot.groups["grp-vertex"]?.spentUSD == 12)
        #expect(snapshot.groups["grp-vertex"]?.stale == false)
        #expect(snapshot.tokenAccounts["acc-vertex"]?.stale == false)
        #expect(snapshot.unassigned.stale == true)
        #expect(snapshot.unassigned.breakdown.inputTokens == 5)
        // A batch issue does not hold back the refresh time.
        #expect(snapshot.lastSuccessfulRefreshAt == snapshot.generatedAt)

        let logText = try String(contentsOf: dir.appendingPathComponent("usage.log"), encoding: .utf8)
        #expect(logText.contains("[opencode] ok: 1 record(s)"))
    }
}

// MARK: - Spec 007: Codex plan limits (plan Design Note 6)

/// A Codex limits source that can be told to fail as a whole.
final class ToggleCodexLimitsSource: UsageSource, @unchecked Sendable {
    let name = CodexLimitsSource.sourceName
    var entries: [String: CodexLimitsEntry]
    var fail = false
    struct Failure: Error, CustomStringConvertible { let description = "codex limits down" }

    init(entries: [String: CodexLimitsEntry]) {
        self.entries = entries
    }

    func collect(context: RefreshContext) async throws -> SourceOutput {
        if fail { throw Failure() }
        return .codexLimits(entries)
    }
}

@Suite struct CodexLimitsCoordinatorTests {
    static let json = """
    {
      "accounts": [
        { "id": "acc-max", "type": "subscription", "displayName": "Claude Max", "credentialDirectory": "~/.claude" },
        { "id": "acc-codex", "type": "codexSubscription", "displayName": "ChatGPT Plus", "harness": "codex", "codexHome": "~/.codex" }
      ]
    }
    """

    static func entry(_ state: CodexLimitsState = .live, sourceError: String? = nil) -> CodexLimitsEntry {
        let window = CodexLimitWindow(lengthMinutes: 10080, usedPercent: 42, resetsAt: isoDate("2026-10-20T00:00:00Z"))
        return CodexLimitsEntry(observation: CodexLimitObservation(planType: "plus", observedAt: isoDate("2026-10-14T08:00:00Z"),
                                                                   origin: .live, windows: [window]),
                                state: state, sourceError: sourceError)
    }

    @Test func codexLimitsOutputLandsInTheSnapshot() async throws {
        let (coordinator, dir) = try makeCoordinator(configJSON: Self.json, name: "codex-limits")
        defer { try? FileManager.default.removeItem(at: dir) }
        await coordinator.register(StaticSource(name: CodexLimitsSource.sourceName, output: .codexLimits(["acc-codex": Self.entry()])))
        let snapshot = await coordinator.refreshAndWait()
        #expect(snapshot.codexLimits["acc-codex"] == Self.entry())
        #expect(snapshot.sourceErrors.isEmpty)
        #expect(snapshot.lastSuccessfulRefreshAt == snapshot.generatedAt)
    }

    /// FR-006: an unreadable answer or a rejected sign-in is a source error.
    @Test func entrySourceErrorBecomesASourceError() async throws {
        let (coordinator, dir) = try makeCoordinator(configJSON: Self.json, name: "codex-limits-error")
        defer { try? FileManager.default.removeItem(at: dir) }
        let entry = Self.entry(.stale(reason: "usage service changed"), sourceError: "usage service changed")
        await coordinator.register(StaticSource(name: CodexLimitsSource.sourceName, output: .codexLimits(["acc-codex": entry])))
        let snapshot = await coordinator.refreshAndWait()
        #expect(snapshot.sourceErrors.count == 1)
        #expect(snapshot.sourceErrors.first?.sourceName == CodexLimitsSource.sourceName)
        #expect(snapshot.sourceErrors.first?.message == "acc-codex: usage service changed")
        #expect(snapshot.codexLimits["acc-codex"] == entry)
        // One account's error does not fail the refresh (FR-006, FR-021).
        #expect(snapshot.lastSuccessfulRefreshAt == snapshot.generatedAt)
    }

    /// FR-021: a failing limits source keeps the previous limits (stale)
    /// and never marks the Claude subscription stale.
    @Test func failingSourceCarriesPreviousEntriesOverAsStale() async throws {
        let (coordinator, dir) = try makeCoordinator(configJSON: Self.json, name: "codex-limits-fail")
        defer { try? FileManager.default.removeItem(at: dir) }
        let status = SubscriptionStatus(fiveHour: nil, sevenDay: LimitWindow(utilizationPercent: 40, resetsAt: Date()), fetchedAt: Date())
        await coordinator.register(StaticSource(name: "subscription", output: .subscriptions(["acc-max": SubscriptionEntry(status: status, state: .ok)])))
        let codex = ToggleCodexLimitsSource(entries: ["acc-codex": Self.entry()])
        await coordinator.register(codex)
        let first = await coordinator.refreshAndWait()
        #expect(first.codexLimits["acc-codex"]?.state == .live)

        codex.fail = true
        let second = await coordinator.refreshAndWait()
        #expect(second.codexLimits["acc-codex"]?.state == .stale(reason: "refresh failed"))
        #expect(second.codexLimits["acc-codex"]?.observation == Self.entry().observation)
        #expect(second.subscriptions["acc-max"]?.state == .ok)
        #expect(second.sourceErrors.map(\.sourceName) == [CodexLimitsSource.sourceName])
    }

    /// FR-005, FR-021: the carried copy drops its source error, a newer
    /// snapshot turns stale too, and accounts no longer configured are not
    /// carried over.
    @Test func failingSourceCarriesOnlyConfiguredAccountsWithoutTheirErrors() async throws {
        let (coordinator, dir) = try makeCoordinator(configJSON: Self.json, name: "codex-limits-fail-carry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let codex = ToggleCodexLimitsSource(entries: ["acc-codex": Self.entry(.newerSnapshot, sourceError: "usage service changed"),
                                                      "acc-gone": Self.entry()])
        await coordinator.register(codex)
        _ = await coordinator.refreshAndWait()

        codex.fail = true
        let second = await coordinator.refreshAndWait()
        #expect(second.codexLimits["acc-codex"]?.state == .stale(reason: "refresh failed"))
        #expect(second.codexLimits["acc-codex"]?.sourceError == nil)
        #expect(second.codexLimits["acc-gone"] == nil)
        #expect(second.sourceErrors.map(\.message) == ["codex limits down"])
    }

    @Test func contextCarriesTheTrigger() async throws {
        let (coordinator, dir) = try makeCoordinator(configJSON: Self.json, name: "codex-trigger")
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = GatedSource()
        await source.release()
        await coordinator.register(source)
        _ = await coordinator.refreshAndWait(trigger: .manual)
        _ = await coordinator.repriceAndWait()
        #expect(await source.contexts.map(\.trigger) == [.manual, .local])
    }
}

// MARK: - Spec 010: quick retry (FR-005, FR-007 to FR-010)

/// A network-bound source with a settable output that records the trigger
/// of every call.
actor ScriptedNetworkSource: NetworkBoundSource {
    nonisolated let name = SubscriptionSource.sourceName
    private var output: SourceOutput
    private(set) var triggers: [RefreshTrigger] = []
    /// The times the coordinator reported a suppressed quick retry.
    private(set) var suppressedAt: [Date] = []
    /// Moves a clock while a collect runs, like a slow request.
    private var slow: (clock: MutableClock, seconds: TimeInterval)?

    init(_ output: SourceOutput) { self.output = output }

    func setOutput(_ output: SourceOutput) { self.output = output }

    func setSlow(_ clock: MutableClock, seconds: TimeInterval) { slow = (clock, seconds) }

    var calls: Int { triggers.count }

    func collect(context: RefreshContext) async throws -> SourceOutput {
        triggers.append(context.trigger)
        if let slow { slow.clock.advance(slow.seconds) }
        return output
    }

    func quickRetrySuppressed(now: Date) async {
        suppressedAt.append(now)
    }
}

@Suite struct QuickRetryCoordinatorTests {
    static let start = isoDate("2026-10-13T08:00:00Z")
    static let lastGood = start.addingTimeInterval(-300)

    static let twoAccountsJSON = """
    {
      "accounts": [
        { "id": "acc-max", "type": "subscription", "displayName": "Claude Max", "credentialDirectory": "~/.claude" },
        { "id": "acc-b", "type": "subscription", "displayName": "Claude B", "credentialDirectory": "~/.claude-b" }
      ]
    }
    """

    static let status = SubscriptionStatus(fiveHour: nil, sevenDay: LimitWindow(utilizationPercent: 40, resetsAt: isoDate("2026-10-16T08:00:00Z")),
                                           fetchedAt: lastGood)

    static func ok(_ id: String = "acc-max") -> SubscriptionEntry {
        SubscriptionEntry(status: status, state: .ok, fetchOutcome: .success)
    }

    static func retrying(at retryAt: Date, outcome: FetchOutcome? = .otherError) -> SubscriptionEntry {
        SubscriptionEntry(status: status, state: .retrying(lastGoodAt: lastGood, error: "offline", retryAt: retryAt),
                          fetchOutcome: outcome, quickRetryAt: retryAt)
    }

    static func output(_ entries: [String: SubscriptionEntry]) -> SourceOutput { .subscriptions(entries) }

    struct Setup {
        let coordinator: RefreshCoordinator
        let dir: URL
        let clock: MutableClock
        let retryGate: SleepGate
        let quickGate: SleepGate
        let network: ScriptedNetworkSource

        func logText() -> String {
            (try? String(contentsOf: dir.appendingPathComponent("usage.log"), encoding: .utf8)) ?? ""
        }

        /// Opens the quick-retry sleep and waits for the refresh it starts.
        func fireQuickRetry(after seconds: TimeInterval) async -> Bool {
            clock.advance(seconds)
            let before = await coordinator.refreshCount
            await quickGate.open()
            return await waitUntil {
                let count = await coordinator.refreshCount
                let running = await coordinator.isRunning
                return count == before + 1 && !running
            }
        }
    }

    static func setup(_ name: String, json: String = twoAccountsJSON, output: SourceOutput) async throws -> Setup {
        let clock = MutableClock(start)
        let retryGate = SleepGate()
        let quickGate = SleepGate()
        let (coordinator, dir) = try makeCoordinator(configJSON: json, name: name, clock: { clock.now() },
                                                     retrySleep: { await retryGate.sleep($0) },
                                                     quickRetrySleep: { await quickGate.sleep($0) })
        let network = ScriptedNetworkSource(output)
        await coordinator.register(network)
        await coordinator.register(FakeLogSource())
        return Setup(coordinator: coordinator, dir: dir, clock: clock, retryGate: retryGate, quickGate: quickGate, network: network)
    }

    @Test func retryingEntrySchedulesOneQuickRetry() async throws {
        let s = try await Self.setup("qr-schedule", output: Self.output(["acc-max": Self.ok()]))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        let first = await s.coordinator.refreshAndWait(trigger: .launch)
        #expect(first.lastSuccessfulRefreshAt == Self.start)

        s.clock.advance(300)
        let retryAt = s.clock.now().addingTimeInterval(30)
        await s.network.setOutput(Self.output(["acc-max": Self.retrying(at: retryAt)]))
        let grace = await s.coordinator.refreshAndWait(trigger: .scheduled)
        // FR-005: no source error, but the refresh time stays the last good one.
        #expect(grace.sourceErrors.isEmpty)
        #expect(!grace.isStale)
        #expect(grace.lastSuccessfulRefreshAt == Self.start)
        #expect(await waitUntil { await s.quickGate.delays == [31] })

        await s.network.setOutput(Self.output(["acc-max": Self.ok()]))
        #expect(await s.fireQuickRetry(after: 31))
        #expect(await s.network.triggers == [.launch, .scheduled, .quickRetry])
        let fresh = try #require(await s.coordinator.latestSnapshot)
        #expect(fresh.subscriptions["acc-max"]?.state == .ok)
        #expect(s.logText().contains("quick retry sent"))
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await s.quickGate.delays == [31])
    }

    /// A retry time that passed while a slow refresh ran, but is still in
    /// its due window, fires at once instead of being lost (FR-004).
    @Test func retryTimeThatPassedDuringTheRefreshFiresAtOnce() async throws {
        let s = try await Self.setup("qr-slow", output: Self.output(["acc-max": Self.ok()]))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        _ = await s.coordinator.refreshAndWait(trigger: .launch)
        s.clock.advance(300)
        let retryAt = s.clock.now().addingTimeInterval(30)
        await s.network.setOutput(Self.output(["acc-max": Self.retrying(at: retryAt)]))
        await s.network.setSlow(s.clock, seconds: 35)
        _ = await s.coordinator.refreshAndWait(trigger: .scheduled)
        #expect(await waitUntil { await s.quickGate.delays == [1] })
        #expect(s.logText().contains("quick retry timer set for"))
    }

    @Test func earliestQuickRetryWinsAndAnUnchangedTimeIsNotRescheduled() async throws {
        let s = try await Self.setup("qr-earliest", json: CodexLimitsCoordinatorTests.json,
                                     output: Self.output(["acc-max": Self.retrying(at: Self.start.addingTimeInterval(40))]))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        var codex = CodexLimitsCoordinatorTests.entry(.retrying(reason: "offline", retryAt: Self.start.addingTimeInterval(30)))
        codex.quickRetryAt = Self.start.addingTimeInterval(30)
        await s.coordinator.register(StaticSource(name: CodexLimitsSource.sourceName, output: .codexLimits(["acc-codex": codex])))
        _ = await s.coordinator.refreshAndWait(trigger: .launch)
        #expect(await waitUntil { await s.quickGate.delays == [31] })
        s.clock.advance(5)
        _ = await s.coordinator.repriceAndWait()
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await s.quickGate.delays == [31])
    }

    @Test func scheduledRefreshThatFetchesTakesTheRetrysPlace() async throws {
        let s = try await Self.setup("qr-scheduled", output: Self.output(["acc-max": Self.retrying(at: Self.start.addingTimeInterval(30))]))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        _ = await s.coordinator.refreshAndWait(trigger: .launch)
        #expect(await waitUntil { await s.quickGate.delays.count == 1 })
        s.clock.advance(10)
        await s.network.setOutput(Self.output(["acc-max": Self.ok()]))
        let scheduled = await s.coordinator.refreshAndWait(trigger: .scheduled)
        #expect(scheduled.subscriptions["acc-max"]?.state == .ok)
        #expect(s.logText().contains("quick retry dropped"))
        // The cancelled timer never starts a refresh.
        s.clock.advance(30)
        await s.quickGate.open()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await s.network.triggers == [.launch, .scheduled])
    }

    @Test func wakeThatFetchesTakesTheRetrysPlace() async throws {
        // A retry far enough out that a wake after the 60 s spacing comes first.
        let s = try await Self.setup("qr-wake-fetch", output: Self.output(["acc-max": Self.retrying(at: Self.start.addingTimeInterval(120))]))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        _ = await s.coordinator.refreshAndWait(trigger: .launch)
        #expect(await waitUntil { await s.quickGate.delays.count == 1 })
        s.clock.advance(61)
        await s.network.setOutput(Self.output(["acc-max": Self.ok()]))
        _ = await s.coordinator.refreshAndWait(trigger: .wake)
        s.clock.advance(60)
        await s.quickGate.open()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await s.network.triggers == [.launch, .wake])
    }

    @Test func wakeReusedBySpacingLeavesTheRetryPending() async throws {
        let s = try await Self.setup("qr-wake-reuse", output: Self.output(["acc-max": Self.retrying(at: Self.start.addingTimeInterval(30))]))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        _ = await s.coordinator.refreshAndWait(trigger: .launch)
        #expect(await waitUntil { await s.quickGate.delays.count == 1 })
        s.clock.advance(10)
        let reused = await s.coordinator.refreshAndWait(trigger: .wake)
        guard case .retrying? = reused.subscriptions["acc-max"]?.state else {
            Issue.record("expected the reused entry to stay in grace")
            return
        }
        await s.network.setOutput(Self.output(["acc-max": Self.ok()]))
        #expect(await s.fireQuickRetry(after: 21))
        #expect(await s.network.triggers == [.launch, .quickRetry])
        #expect(await s.quickGate.delays.count == 1)
    }

    @Test func quickRetryWhileRateLimitedIsReusedAndEndsTheGracePeriod() async throws {
        let retryAt = Self.start.addingTimeInterval(30)
        let limited = SubscriptionEntry(status: nil, state: .stale(lastGoodAt: nil, error: "usage endpoint returned HTTP 429"),
                                        fetchOutcome: .rateLimited(retryAfter: 600))
        let s = try await Self.setup("qr-blocked", output: Self.output(["acc-max": Self.retrying(at: retryAt), "acc-b": limited]))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        let first = await s.coordinator.refreshAndWait(trigger: .launch)
        #expect(first.endpointBlockedUntil == Self.start.addingTimeInterval(600))
        #expect(await waitUntil { await s.quickGate.delays == [31] })
        #expect(await s.fireQuickRetry(after: 31))
        #expect(await s.network.calls == 1)
        // The source is told once, at the retry run (FR-007).
        #expect(await s.network.suppressedAt == [Self.start.addingTimeInterval(31)])
        let snapshot = try #require(await s.coordinator.latestSnapshot)
        #expect(snapshot.subscriptions["acc-max"]?.state == .stale(lastGoodAt: Self.lastGood, error: "offline"))
        #expect(snapshot.subscriptions["acc-max"]?.quickRetryAt == nil)
        #expect(s.logText().contains("quick retry suppressed (rate limited)"))
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await s.quickGate.delays == [31])
    }

    /// A timer that fires while a scheduled refresh runs, which requests the
    /// account and so takes the retry's place, leaves no quick retry behind:
    /// the queued one is dropped and logged (spec 010 FR-003, FR-008).
    @Test func queuedQuickRetryIsDroppedWhenARefreshTakesItsPlace() async throws {
        let retryAt = Self.start.addingTimeInterval(30)
        let s = try await Self.setup("qr-queued-drop", output: Self.output(["acc-max": Self.retrying(at: retryAt)]))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        _ = await s.coordinator.refreshAndWait(trigger: .launch)
        #expect(await waitUntil { await s.quickGate.delays == [31] })
        let gated = GatedSource(name: "slow-log")
        await s.coordinator.register(gated)
        await s.network.setOutput(Self.output(["acc-max": Self.ok()]))
        s.clock.advance(29)
        await s.coordinator.requestRefresh(trigger: .scheduled)
        #expect(await waitUntil { await gated.calls == 1 })
        s.clock.advance(2)
        await s.quickGate.open()
        try? await Task.sleep(for: .milliseconds(30))
        await gated.release()
        #expect(await waitUntil {
            let running = await s.coordinator.isRunning
            let count = await s.coordinator.refreshCount
            return !running && count >= 2
        })
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await s.coordinator.refreshCount == 2)
        #expect(await s.network.triggers == [.launch, .scheduled])
        #expect(s.logText().contains("quick retry dropped (scheduled refresh took its place)"))
        #expect(!s.logText().contains("quick retry sent"))
    }

    /// A quick retry that requests no Claude account (only a Codex retry is
    /// due) neither logs a Claude request nor moves the refresh time as if
    /// the usage endpoint had been fetched (spec 010 FR-003, FR-009).
    @Test func quickRetryWithoutAClaudeRequestKeepsTheRefreshTime() async throws {
        // The kept Claude entry, as the subscription source returns it for an
        // account a quick retry does not request: no fetch outcome.
        let kept = SubscriptionEntry(status: Self.status, state: .ok)
        let s = try await Self.setup("qr-codex-only", json: CodexLimitsCoordinatorTests.json, output: Self.output(["acc-max": Self.ok()]))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        var codex = CodexLimitsCoordinatorTests.entry(.retrying(reason: "offline", retryAt: Self.start.addingTimeInterval(30)))
        codex.quickRetryAt = Self.start.addingTimeInterval(30)
        let codexSource = StaticSource(name: CodexLimitsSource.sourceName, output: .codexLimits(["acc-codex": codex]))
        await s.coordinator.register(codexSource)
        let first = await s.coordinator.refreshAndWait(trigger: .launch)
        #expect(first.lastSuccessfulRefreshAt == Self.start)
        #expect(await waitUntil { await s.quickGate.delays == [31] })
        await s.network.setOutput(Self.output(["acc-max": kept]))
        codexSource.output = .codexLimits(["acc-codex": CodexLimitsCoordinatorTests.entry(.live)])
        #expect(await s.fireQuickRetry(after: 31))
        #expect(codexSource.calls == 2)
        let snapshot = try #require(await s.coordinator.latestSnapshot)
        #expect(snapshot.lastSuccessfulRefreshAt == Self.start)
        #expect(!s.logText().contains("quick retry sent"))
        #expect(s.logText().contains("quick retry: no Claude account due"))
    }

    /// A due Codex retry while the Claude endpoint is rate limited still
    /// runs in the Codex source; no Claude retry was held back, so nothing
    /// is logged as suppressed (spec 010 FR-003, FR-007).
    @Test func codexRetryWhileClaudeIsRateLimitedIsNotLoggedAsSuppressed() async throws {
        let limited = SubscriptionEntry(status: nil, state: .stale(lastGoodAt: nil, error: "usage endpoint returned HTTP 429"),
                                        fetchOutcome: .rateLimited(retryAfter: 600))
        let s = try await Self.setup("qr-codex-blocked", json: CodexLimitsCoordinatorTests.json, output: Self.output(["acc-max": limited]))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        var codex = CodexLimitsCoordinatorTests.entry(.retrying(reason: "offline", retryAt: Self.start.addingTimeInterval(30)))
        codex.quickRetryAt = Self.start.addingTimeInterval(30)
        let codexSource = StaticSource(name: CodexLimitsSource.sourceName, output: .codexLimits(["acc-codex": codex]))
        await s.coordinator.register(codexSource)
        _ = await s.coordinator.refreshAndWait(trigger: .launch)
        #expect(await waitUntil { await s.quickGate.delays == [31] })
        codexSource.output = .codexLimits(["acc-codex": CodexLimitsCoordinatorTests.entry(.live)])
        #expect(await s.fireQuickRetry(after: 31))
        #expect(codexSource.calls == 2)
        #expect(await s.network.calls == 1)
        #expect(!s.logText().contains("quick retry suppressed"))
    }

    /// A stale entry with a quick retry (saved values only) whose retry is
    /// suppressed by a rate limit: the reused result must not set the timer
    /// again, so there is no retry loop (FR-007).
    @Test func suppressedRetryOfAStaleEntryDoesNotReArmTheTimer() async throws {
        let retryAt = Self.start.addingTimeInterval(30)
        let staleWithRetry = SubscriptionEntry(status: Self.status, state: .stale(lastGoodAt: Self.lastGood, error: "offline"),
                                               fetchOutcome: .otherError, quickRetryAt: retryAt)
        let limited = SubscriptionEntry(status: nil, state: .stale(lastGoodAt: nil, error: "usage endpoint returned HTTP 429"),
                                        fetchOutcome: .rateLimited(retryAfter: 600))
        let s = try await Self.setup("qr-blocked-stale", output: Self.output(["acc-max": staleWithRetry, "acc-b": limited]))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        _ = await s.coordinator.refreshAndWait(trigger: .launch)
        #expect(await waitUntil { await s.quickGate.delays == [31] })
        #expect(await s.fireQuickRetry(after: 31))
        #expect(await s.network.calls == 1)
        let snapshot = try #require(await s.coordinator.latestSnapshot)
        #expect(snapshot.subscriptions["acc-max"]?.quickRetryAt == nil)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await s.quickGate.delays == [31])
    }

    /// A reprice once the retry's due window (`retryAt + 30 s`) has passed
    /// without the retry being sent (for example while the Mac slept) shows
    /// the values stale (spec 010 FR-007, plan Design Note 10).
    @Test func repriceAfterTheRetryTimeShowsStale() async throws {
        let s = try await Self.setup("qr-reprice", output: Self.output(["acc-max": Self.retrying(at: Self.start.addingTimeInterval(30))]))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        _ = await s.coordinator.refreshAndWait(trigger: .launch)
        s.clock.advance(10)
        guard case .retrying? = await s.coordinator.repriceAndWait().subscriptions["acc-max"]?.state else {
            Issue.record("expected grace before the retry time")
            return
        }
        s.clock.advance(51)
        let late = await s.coordinator.repriceAndWait()
        #expect(late.subscriptions["acc-max"]?.state == .stale(lastGoodAt: Self.lastGood, error: "offline"))
        #expect(late.subscriptions["acc-max"]?.quickRetryAt == nil)
        #expect(late.sourceErrors.map(\.message) == ["acc-max: offline"])
    }

    /// Refreshes without a request that land between the retry time and
    /// the timer (`retryAt + 1 s`) keep the grace period and the pending
    /// timer, and the retry is still sent (spec 010 FR-005, FR-008, SC-001).
    @Test func refreshesWithoutARequestJustAfterTheRetryTimeKeepTheRetry() async throws {
        let retryAt = Self.start.addingTimeInterval(30)
        let s = try await Self.setup("qr-reprice-window", output: Self.output(["acc-max": Self.retrying(at: retryAt)]))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        _ = await s.coordinator.refreshAndWait(trigger: .launch)
        #expect(await waitUntil { await s.quickGate.delays == [31] })
        s.clock.advance(30.5)

        let repriced = await s.coordinator.repriceAndWait()
        #expect(repriced.subscriptions["acc-max"]?.state == .retrying(lastGoodAt: Self.lastGood, error: "offline", retryAt: retryAt))
        #expect(repriced.subscriptions["acc-max"]?.quickRetryAt == retryAt)
        #expect(repriced.sourceErrors.isEmpty)
        // Inside the 60 s spacing of the launch fetch: reused without a request.
        let manual = await s.coordinator.refreshAndWait(trigger: .manual)
        #expect(manual.subscriptions["acc-max"]?.state == .retrying(lastGoodAt: Self.lastGood, error: "offline", retryAt: retryAt))
        #expect(manual.subscriptions["acc-max"]?.quickRetryAt == retryAt)
        #expect(!s.logText().contains("quick retry dropped"))
        #expect(await s.quickGate.delays == [31])

        await s.network.setOutput(Self.output(["acc-max": Self.ok()]))
        #expect(await s.fireQuickRetry(after: 0.5))
        #expect(await s.network.triggers == [.launch, .quickRetry])
        #expect(await s.coordinator.latestSnapshot?.subscriptions["acc-max"]?.state == .ok)
    }

    /// A timer that fires while another refresh runs queues the quick retry;
    /// the running refresh neither ends the grace period nor sets a second
    /// timer for the same time (spec 010 FR-004, FR-008).
    @Test func timerFiringDuringARefreshQueuesTheRetryOnce() async throws {
        let retryAt = Self.start.addingTimeInterval(30)
        let s = try await Self.setup("qr-queued", output: Self.output(["acc-max": Self.retrying(at: retryAt)]))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        _ = await s.coordinator.refreshAndWait(trigger: .launch)
        #expect(await waitUntil { await s.quickGate.delays == [31] })
        let gated = GatedSource(name: "slow-log")
        await s.coordinator.register(gated)
        s.clock.advance(30.5)
        await s.coordinator.requestReprice()
        #expect(await waitUntil { await gated.calls == 1 })
        s.clock.advance(0.5)
        await s.quickGate.open()
        await s.network.setOutput(Self.output(["acc-max": Self.ok()]))
        // Let the fired timer queue its retry behind the running reprice.
        try? await Task.sleep(for: .milliseconds(30))
        await gated.release()
        #expect(await waitUntil {
            let count = await s.coordinator.refreshCount
            let running = await s.coordinator.isRunning
            return count == 3 && !running
        })
        #expect(await s.network.triggers == [.launch, .quickRetry])
        #expect(await s.coordinator.latestSnapshot?.subscriptions["acc-max"]?.state == .ok)
        #expect(s.logText().contains("reused for reprice, ok: 1 account(s) acc-max=retrying"))
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await s.quickGate.delays == [31])
    }

    @Test func rejectedSignInIsASourceError() async throws {
        let rejected = SubscriptionEntry(status: Self.status, state: .signInRejected(lastGoodAt: Self.lastGood),
                                         fetchOutcome: .otherError)
        let s = try await Self.setup("qr-rejected", output: Self.output(["acc-max": Self.ok()]))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        _ = await s.coordinator.refreshAndWait(trigger: .launch)
        s.clock.advance(300)
        await s.network.setOutput(Self.output(["acc-max": rejected]))
        let snapshot = await s.coordinator.refreshAndWait(trigger: .scheduled)
        #expect(snapshot.isStale)
        #expect(snapshot.sourceErrors.count == 1)
        #expect(snapshot.sourceErrors.first?.message.hasPrefix("acc-max: ") == true)
        #expect(snapshot.lastSuccessfulRefreshAt == Self.start)
    }

    @Test func quickRetryCountsForSpacingAndItsRateLimitBlocks() async throws {
        let s = try await Self.setup("qr-spacing", output: Self.output(["acc-max": Self.retrying(at: Self.start.addingTimeInterval(30))]))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        _ = await s.coordinator.refreshAndWait(trigger: .launch)
        await s.network.setOutput(Self.output(["acc-max": SubscriptionEntry(status: Self.status, state: .stale(lastGoodAt: Self.lastGood, error: "429"),
                                                                           fetchOutcome: .rateLimited(retryAfter: 300))]))
        #expect(await s.fireQuickRetry(after: 31))
        let limited = try #require(await s.coordinator.latestSnapshot)
        #expect(limited.endpointBlockedUntil == Self.start.addingTimeInterval(331))
        s.clock.advance(10)
        _ = await s.coordinator.refreshAndWait(trigger: .manual)
        #expect(await s.network.triggers == [.launch, .quickRetry])
    }

    @Test func quickRetrySetsTheLastAttemptForSpacing() async throws {
        let s = try await Self.setup("qr-last-attempt", output: Self.output(["acc-max": Self.retrying(at: Self.start.addingTimeInterval(30))]))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        _ = await s.coordinator.refreshAndWait(trigger: .launch)
        await s.network.setOutput(Self.output(["acc-max": Self.ok()]))
        // Past the launch fetch's 60 s spacing, so only the quick retry can space the manual refresh.
        #expect(await s.fireQuickRetry(after: 55))
        s.clock.advance(10)
        _ = await s.coordinator.refreshAndWait(trigger: .manual)
        #expect(await s.network.triggers == [.launch, .quickRetry])
    }

    @Test func successfulQuickRetryKeepsAPendingSettingsFollowUp() async throws {
        let s = try await Self.setup("qr-settings", output: Self.output(["acc-max": Self.retrying(at: Self.start.addingTimeInterval(30))]))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        _ = await s.coordinator.refreshAndWait(trigger: .launch)
        s.clock.advance(10)
        _ = await s.coordinator.refreshAndWait(trigger: .settings)
        #expect(await waitUntil { await s.retryGate.delays == [51] })
        await s.network.setOutput(Self.output(["acc-max": Self.ok()]))
        #expect(await s.fireQuickRetry(after: 21))
        #expect(await s.network.triggers == [.launch, .quickRetry])
        #expect(await s.coordinator.latestSnapshot?.nextRetryAt == Self.start.addingTimeInterval(60))
        // The follow-up still runs (spaced again by the quick retry, so it asks for another).
        s.clock.advance(30)
        await s.retryGate.open()
        #expect(await waitUntil { await s.retryGate.delays.count == 2 })
    }

    /// A rate-limit retry and a quick retry pending at the same time both
    /// run; a scheduled tick replaces both (spec 010 FR-007, FR-008).
    @Test func pendingRetryAndQuickRetryBothRun() async throws {
        let (coordinator, dir) = try makeCoordinator(name: "qr-pending-both")
        defer { try? FileManager.default.removeItem(at: dir) }
        let network = GatedNetworkSource(output: subscriptionOutput(), open: false)
        await coordinator.register(network)
        await coordinator.register(FakeLogSource())
        await coordinator.requestRefresh(trigger: .launch)
        #expect(await waitUntil { await network.calls == 1 })
        await coordinator.requestRefresh(trigger: .quickRetry)
        await coordinator.requestRefresh(trigger: .retry)
        await network.release()
        #expect(await waitUntil {
            let running = await coordinator.isRunning
            let count = await coordinator.refreshCount
            return !running && count == 3
        })

        let (other, otherDir) = try makeCoordinator(name: "qr-pending-scheduled")
        defer { try? FileManager.default.removeItem(at: otherDir) }
        let gated = GatedNetworkSource(output: subscriptionOutput(), open: false)
        await other.register(gated)
        await other.register(FakeLogSource())
        await other.requestRefresh(trigger: .launch)
        #expect(await waitUntil { await gated.calls == 1 })
        await other.requestRefresh(trigger: .retry)
        await other.requestRefresh(trigger: .quickRetry)
        await other.requestRefresh(trigger: .scheduled)
        await gated.release()
        #expect(await waitUntil {
            let running = await other.isRunning
            let count = await other.refreshCount
            return !running && count == 2
        })
    }
}

// MARK: - Spec 010: early result from saved values (FR-015, FR-020)

/// A network-bound source with saved values that can be told to fail.
actor SavedNetworkSource: NetworkBoundSource, SavedValuesSource {
    nonisolated let name = SubscriptionSource.sourceName
    private let saved: SourceOutput?
    private var fail: Bool
    struct Failure: Error, CustomStringConvertible { let description = "network down" }

    init(saved: SourceOutput?, fail: Bool = true) {
        self.saved = saved
        self.fail = fail
    }

    func savedOutput(configuration: Configuration, now: Date) async -> SourceOutput? { saved }

    func collect(context: RefreshContext) async throws -> SourceOutput {
        if fail { throw Failure() }
        return saved ?? .subscriptions([:])
    }
}

/// A network-bound source with saved values whose collect returns a fixed
/// output, like the subscription source, which never throws.
actor StaticSavedSource: NetworkBoundSource, SavedValuesSource {
    nonisolated let name = SubscriptionSource.sourceName
    private let saved: SourceOutput?
    private let output: SourceOutput

    init(saved: SourceOutput?, output: SourceOutput) {
        self.saved = saved
        self.output = output
    }

    func savedOutput(configuration: Configuration, now: Date) async -> SourceOutput? { saved }
    func collect(context: RefreshContext) async throws -> SourceOutput { output }
}

@Suite struct SavedValuesCoordinatorTests {
    static let now = isoDate("2026-10-13T08:00:00Z")

    static func saved(resetsAt: Date) -> SourceOutput {
        let status = SubscriptionStatus(fiveHour: nil, sevenDay: LimitWindow(utilizationPercent: 63, resetsAt: resetsAt),
                                        fetchedAt: now.addingTimeInterval(-3600))
        return .subscriptions(["acc-max": SubscriptionEntry(status: status, state: .ok)])
    }

    @Test func publishesAPreliminarySnapshotWithOnlySavedEntries() async throws {
        let (coordinator, dir) = try makeCoordinator(name: "saved-prelim", clock: { Self.now })
        defer { try? FileManager.default.removeItem(at: dir) }
        await coordinator.register(SavedNetworkSource(saved: Self.saved(resetsAt: Self.now.addingTimeInterval(86400))))
        await coordinator.register(FakeLogSource())
        let snapshot = try #require(await coordinator.publishSavedValues())
        #expect(snapshot.isPreliminary)
        #expect(snapshot.subscriptions["acc-max"]?.state == .ok)
        #expect(snapshot.subscriptions["acc-max"]?.status?.sevenDay?.utilizationPercent == 63)
        #expect(snapshot.groups.isEmpty)
        #expect(snapshot.accountBudgets.isEmpty)
        #expect(snapshot.tokenAccounts.isEmpty)
        #expect(snapshot.lastSuccessfulRefreshAt == nil)
        #expect(snapshot.sourceErrors.isEmpty)
        #expect(await coordinator.latestSnapshot == nil)
        var iterator = coordinator.snapshots.makeAsyncIterator()
        #expect(await iterator.next()?.isPreliminary == true)
    }

    @Test func publishesNothingWithoutSavedValuesOrAfterARefresh() async throws {
        let (empty, emptyDir) = try makeCoordinator(name: "saved-none", clock: { Self.now })
        defer { try? FileManager.default.removeItem(at: emptyDir) }
        await empty.register(SavedNetworkSource(saved: nil))
        #expect(await empty.publishSavedValues() == nil)

        let (coordinator, dir) = try makeCoordinator(name: "saved-late", clock: { Self.now })
        defer { try? FileManager.default.removeItem(at: dir) }
        await coordinator.register(SavedNetworkSource(saved: Self.saved(resetsAt: Self.now.addingTimeInterval(86400)), fail: false))
        _ = await coordinator.refreshAndWait(trigger: .launch)
        #expect(await coordinator.publishSavedValues() == nil)
    }

    @Test func savedFutureResetAlignsTheFirstWindow() async throws {
        let reset = isoDate("2026-10-15T07:00:00Z")
        let (coordinator, dir) = try makeCoordinator(name: "saved-align", clock: { Self.now })
        defer { try? FileManager.default.removeItem(at: dir) }
        let status = SubscriptionStatus(fiveHour: nil, sevenDay: LimitWindow(utilizationPercent: 63, resetsAt: reset),
                                        fetchedAt: Self.now.addingTimeInterval(-3600))
        // Like the real source: a failed first request returns the saved
        // values as a stale entry, it does not throw.
        let stale = SourceOutput.subscriptions(["acc-max": SubscriptionEntry(
            status: status, state: .stale(lastGoodAt: status.fetchedAt, error: "network down"), fetchOutcome: .otherError)])
        await coordinator.register(StaticSavedSource(saved: Self.saved(resetsAt: reset), output: stale))
        await coordinator.register(FakeLogSource())
        let preliminary = try #require(await coordinator.publishSavedValues())
        #expect(preliminary.windowSource == .aligned(accountId: "acc-max"))
        #expect(preliminary.window.end == reset)
        // The first refresh fails, yet its window is aligned by the saved reset.
        let first = await coordinator.refreshAndWait(trigger: .launch)
        #expect(first.windowSource == .aligned(accountId: "acc-max"))
        #expect(first.window.end == reset)
    }

    @Test func savedPastResetDoesNotAlign() async throws {
        let (coordinator, dir) = try makeCoordinator(name: "saved-align-past", clock: { Self.now })
        defer { try? FileManager.default.removeItem(at: dir) }
        await coordinator.register(SavedNetworkSource(saved: Self.saved(resetsAt: Self.now.addingTimeInterval(-60))))
        await coordinator.register(FakeLogSource())
        _ = await coordinator.publishSavedValues()
        let first = await coordinator.refreshAndWait(trigger: .launch)
        #expect(first.windowSource == .fallback)
    }

    /// The subscription source does not throw: a failed first request
    /// returns the saved values as a stale entry. A saved 7-day reset that
    /// has passed must not align the window through it (FR-020).
    @Test func staleSavedEntryWithPastResetDoesNotAlign() async throws {
        let (coordinator, dir) = try makeCoordinator(name: "saved-align-stale", clock: { Self.now })
        defer { try? FileManager.default.removeItem(at: dir) }
        let status = SubscriptionStatus(fiveHour: nil, sevenDay: LimitWindow(utilizationPercent: 63, resetsAt: Self.now.addingTimeInterval(-60)),
                                        fetchedAt: Self.now.addingTimeInterval(-3600))
        let stale = SourceOutput.subscriptions(["acc-max": SubscriptionEntry(
            status: status, state: .stale(lastGoodAt: status.fetchedAt, error: "network down"), fetchOutcome: .otherError)])
        await coordinator.register(StaticSavedSource(saved: Self.saved(resetsAt: Self.now.addingTimeInterval(-60)), output: stale))
        await coordinator.register(FakeLogSource())
        _ = await coordinator.publishSavedValues()
        let first = await coordinator.refreshAndWait(trigger: .launch)
        #expect(first.windowSource == .fallback)
    }

    /// A saved future reset aligns until it passes; once passed before any
    /// successful request, alignment falls back (FR-020).
    @Test func savedResetThatPassesBeforeASuccessStopsAligning() async throws {
        let reset = Self.now.addingTimeInterval(600)
        let clock = MutableClock(Self.now)
        let (coordinator, dir) = try makeCoordinator(name: "saved-align-passes", clock: { clock.now() })
        defer { try? FileManager.default.removeItem(at: dir) }
        let status = SubscriptionStatus(fiveHour: nil, sevenDay: LimitWindow(utilizationPercent: 63, resetsAt: reset),
                                        fetchedAt: Self.now.addingTimeInterval(-3600))
        let stale = SourceOutput.subscriptions(["acc-max": SubscriptionEntry(
            status: status, state: .stale(lastGoodAt: status.fetchedAt, error: "network down"), fetchOutcome: .otherError)])
        await coordinator.register(StaticSavedSource(saved: Self.saved(resetsAt: reset), output: stale))
        await coordinator.register(FakeLogSource())
        _ = await coordinator.publishSavedValues()
        let first = await coordinator.refreshAndWait(trigger: .launch)
        #expect(first.windowSource == .aligned(accountId: "acc-max"))
        clock.advance(600 + 3600)
        let later = await coordinator.refreshAndWait(trigger: .scheduled)
        #expect(later.windowSource == .fallback)
    }

    /// US3-1 end to end with the real subscription source, which never
    /// throws: saved values show early unmarked, then stale with their
    /// original fetch time after an offline first refresh, with a quick
    /// retry (FR-004, FR-015).
    @Test func realSourceShowsSavedValuesEarlyThenStaleAfterAnOfflineLaunch() async throws {
        let root = try makeTempDirectory("saved-e2e")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = Paths(home: root)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        let saved = SubscriptionSourceTests.saved(directory: Attributor.canonical(root.appendingPathComponent(".claude").path))
        let store = LastGoodStore(fileURL: paths.lastGoodFileURL, initial: LastGoodValues(claude: ["acc-max": saved]), log: nil)
        let token = "saved-e2e-\(UUID().uuidString)"
        StubURLProtocol.register(key: "Bearer \(token)") { _ in throw URLError(.notConnectedToInternet) }
        defer { StubURLProtocol.unregister(key: "Bearer \(token)") }
        let reader = FakeCredentialReader()
        reader.credentials["~/.claude"] = OAuthCredential(accessToken: token, expiresAt: Date(timeIntervalSince1970: 1_900_000_000))
        let clock = MutableClock(Date(timeIntervalSince1970: 1_800_000_000))
        let quickGate = SleepGate()
        let (coordinator, dir) = try makeCoordinator(name: "saved-e2e-coord", clock: { clock.now() },
                                                     quickRetrySleep: { await quickGate.sleep($0) })
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = SubscriptionSource(credentialReader: reader, client: UsageEndpointClient(session: StubURLProtocol.makeSession()),
                                        clock: { clock.now() }, store: store, paths: paths)
        await coordinator.register(source)

        let early = try #require(await coordinator.publishSavedValues())
        #expect(early.subscriptions["acc-max"]?.state == .ok)
        #expect(early.subscriptions["acc-max"]?.status?.sevenDay?.utilizationPercent == 63)

        let first = await coordinator.refreshAndWait(trigger: .launch)
        #expect(!first.isPreliminary)
        guard case .stale(let lastGoodAt, _)? = first.subscriptions["acc-max"]?.state else {
            Issue.record("expected stale, got \(String(describing: first.subscriptions["acc-max"]?.state))")
            return
        }
        #expect(lastGoodAt == saved.fetchedAt)
        #expect(first.subscriptions["acc-max"]?.status?.sevenDay?.utilizationPercent == 63)
        #expect(first.subscriptions["acc-max"]?.quickRetryAt == clock.now().addingTimeInterval(30))
        #expect(first.lastSuccessfulRefreshAt == nil)
        #expect(await waitUntil { await quickGate.delays == [31] })
    }

    /// A failed record source on the first refresh after the early result
    /// keeps the fresh aggregated entries, marked stale: the early result has
    /// no budgets to carry over (FR-015).
    @Test func failedRecordSourceAfterTheEarlyResultKeepsBudgetEntries() async throws {
        let (coordinator, dir) = try makeCoordinator(name: "saved-records-fail", clock: { Self.now })
        defer { try? FileManager.default.removeItem(at: dir) }
        let logs = FakeLogSource()
        logs.fail = true
        await coordinator.register(SavedNetworkSource(saved: Self.saved(resetsAt: Self.now.addingTimeInterval(86400)), fail: false))
        await coordinator.register(logs)
        _ = await coordinator.publishSavedValues()
        let first = await coordinator.refreshAndWait(trigger: .launch)
        #expect(first.groups["grp-vertex"]?.stale == true)
        #expect(first.unassigned.stale)
    }

    @Test func failedFirstRefreshShowsTheSavedValuesStale() async throws {
        let (coordinator, dir) = try makeCoordinator(name: "saved-carry", clock: { Self.now })
        defer { try? FileManager.default.removeItem(at: dir) }
        await coordinator.register(SavedNetworkSource(saved: Self.saved(resetsAt: Self.now.addingTimeInterval(86400))))
        await coordinator.register(FakeLogSource())
        _ = await coordinator.publishSavedValues()
        let first = await coordinator.refreshAndWait(trigger: .launch)
        #expect(!first.isPreliminary)
        #expect(first.subscriptions["acc-max"]?.state == .stale(lastGoodAt: Self.now.addingTimeInterval(-3600), error: "network down"))
        #expect(first.subscriptions["acc-max"]?.status?.sevenDay?.utilizationPercent == 63)
        #expect(first.lastSuccessfulRefreshAt == nil)
    }
}

