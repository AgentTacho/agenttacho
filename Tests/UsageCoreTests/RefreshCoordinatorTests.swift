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

    /// Lets the waiting calls return, but keeps the gate closed for later ones.
    func releaseWaiting() {
        let w = waiters
        waiters = []
        w.forEach { $0.resume() }
    }

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

    /// Spec 015 FR-004, FR-005, US1 scenarios 6 and 7: a period switch while
    /// the record source fails drops the carried-over weekly entry instead
    /// of showing it under monthly wording; no notification is sent, and
    /// the monthly value appears when the source recovers.
    @Test func periodSwitchWhileTheSourceFailsDropsTheOldPeriodsEntry() async throws {
        let now = self.now
        let (coordinator, dir) = try makeCoordinator(name: "switch-failing", clock: { now })
        defer { try? FileManager.default.removeItem(at: dir) }
        let configURL = dir.appendingPathComponent("config.json")
        let logs = FakeLogSource()
        logs.records = [
            makeRecord(id: "early", accountId: "acc-vertex", timestamp: isoDate("2026-10-05T10:00:00Z"), cost: 300),
            makeRecord(id: "week", accountId: "acc-vertex", timestamp: isoDate("2026-10-12T10:00:00Z"), cost: 57),
        ]
        await coordinator.register(logs)
        var tracker = ThresholdTracker()
        let weeklyConfig = ConfigStore(fileURL: configURL).load().0
        let first = await coordinator.refreshAndWait()
        #expect(first.groups["grp-vertex"]?.period == .weekly)
        #expect(first.groups["grp-vertex"]?.percent == 95)
        _ = tracker.observe(snapshot: first, configuration: weeklyConfig)

        logs.fail = true
        let stale = await coordinator.refreshAndWait()
        #expect(stale.groups["grp-vertex"]?.stale == true)
        #expect(stale.groups["grp-vertex"]?.period == .weekly)

        try Data(Self.monthlyJSON.utf8).write(to: configURL)
        let mtime = try FileManager.default.attributesOfItem(atPath: configURL.path)[.modificationDate] as! Date
        try FileManager.default.setAttributes([.modificationDate: mtime.addingTimeInterval(5)], ofItemAtPath: configURL.path)
        let monthlyConfig = ConfigStore(fileURL: configURL).load().0
        #expect(monthlyConfig.groups.first?.budget.period == .monthly)

        let switched = await coordinator.refreshAndWait()
        #expect(switched.configError == nil)
        #expect(switched.sourceErrors.map(\.sourceName) == ["sessionLogs"])
        #expect(switched.groups["grp-vertex"] == nil)
        #expect(tracker.observe(snapshot: switched, configuration: monthlyConfig).isEmpty)

        logs.fail = false
        let recovered = await coordinator.refreshAndWait()
        let group = recovered.groups["grp-vertex"]
        #expect(group?.period == .monthly)
        #expect(group?.stale == false)
        #expect(group?.spentUSD == 357)
        // The first monthly value is a baseline, even above the thresholds.
        #expect(tracker.observe(snapshot: recovered, configuration: monthlyConfig).isEmpty)
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
    /// The accounts reported as "last request got no answer" (spec 021).
    private var noAnswer: Set<String> = []
    /// When set, every collect leaves this no-answer set behind.
    private var noAnswerAfterCollect: Set<String>?
    private(set) var contexts: [RefreshContext] = []

    init(_ output: SourceOutput) { self.output = output }

    func setOutput(_ output: SourceOutput) { self.output = output }

    func setSlow(_ clock: MutableClock, seconds: TimeInterval) { slow = (clock, seconds) }

    func setNoAnswer(_ ids: Set<String>, afterCollect: Set<String>? = nil) {
        noAnswer = ids
        noAnswerAfterCollect = afterCollect
    }

    var calls: Int { triggers.count }

    func collect(context: RefreshContext) async throws -> SourceOutput {
        triggers.append(context.trigger)
        contexts.append(context)
        if let slow { slow.clock.advance(slow.seconds) }
        if let after = noAnswerAfterCollect { noAnswer = after }
        return output
    }

    func noAnswerAccounts() async -> Set<String> {
        noAnswer
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


// MARK: - Adaptive pace (spec 016)

/// Shared order of events across the probe sources of one test.
actor OrderProbe {
    private(set) var events: [String] = []
    func note(_ event: String) { events.append(event) }
}

/// A record source (neither network-bound nor endpoint-gated) with
/// settable records that notes when it starts and ends.
final class ProbeRecordSource: UsageSource, @unchecked Sendable {
    let name = "probeRecords"
    private let lock = NSLock()
    private var stored: [UsageRecord] = []
    private var count = 0
    let probe: OrderProbe

    init(probe: OrderProbe) { self.probe = probe }

    var records: [UsageRecord] {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }

    func collect(context: RefreshContext) async throws -> SourceOutput {
        await probe.note("records-start")
        try? await Task.sleep(for: .milliseconds(5))
        lock.lock(); count += 1; let output = stored; lock.unlock()
        await probe.note("records-end")
        return .records(output)
    }
}

/// Stands in for `SubscriptionSource`: one Claude account, a settable
/// answer, and the trigger of every call.
actor ProbeClaudeSource: NetworkBoundSource {
    nonisolated let name = SubscriptionSource.sourceName
    let probe: OrderProbe
    private(set) var triggers: [RefreshTrigger] = []
    private var entry: SubscriptionEntry

    init(probe: OrderProbe) {
        self.probe = probe
        entry = ProbeClaudeSource.ok()
    }

    static func ok() -> SubscriptionEntry {
        let status = SubscriptionStatus(fiveHour: LimitWindow(utilizationPercent: 12, resetsAt: isoDate("2026-10-20T00:00:00Z")),
                                        sevenDay: nil, fetchedAt: isoDate("2026-10-14T08:00:00Z"))
        return SubscriptionEntry(status: status, state: .ok, fetchOutcome: .success, reachedService: true)
    }

    /// A transport failure: no answer reached the service.
    static func offline() -> SubscriptionEntry {
        SubscriptionEntry(status: nil, state: .stale(lastGoodAt: nil, error: "offline"), fetchOutcome: .otherError, reachedService: false)
    }

    static func rateLimited(_ wait: TimeInterval) -> SubscriptionEntry {
        SubscriptionEntry(status: nil, state: .stale(lastGoodAt: nil, error: "usage endpoint returned HTTP 429"),
                          fetchOutcome: .rateLimited(retryAfter: wait), reachedService: true)
    }

    var calls: Int { triggers.count }
    func answer(_ entry: SubscriptionEntry) { self.entry = entry }

    func collect(context: RefreshContext) async throws -> SourceOutput {
        await probe.note("claude-start")
        triggers.append(context.trigger)
        return .subscriptions(Dictionary(uniqueKeysWithValues: context.configuration.subscriptionAccounts.map { ($0.id, entry) }))
    }
}

/// Stands in for `CodexLimitsSource`: an endpoint-gated source that
/// records every context and "fetches" unless the pace held a scheduled
/// request back.
actor ProbeCodexSource: EndpointGatedSource {
    nonisolated let name = CodexLimitsSource.sourceName
    let probe: OrderProbe
    private(set) var contexts: [RefreshContext] = []
    private(set) var fetches = 0
    private var reached = true

    init(probe: OrderProbe) { self.probe = probe }

    func reachService(_ value: Bool) { reached = value }

    func collect(context: RefreshContext) async throws -> SourceOutput {
        await probe.note("codex-start")
        contexts.append(context)
        let fetched = context.trigger != .scheduled || context.codexPaceDue
        if fetched { fetches += 1 }
        let window = CodexLimitWindow(lengthMinutes: 10080, usedPercent: 42, resetsAt: isoDate("2026-10-20T00:00:00Z"))
        let entry = CodexLimitsEntry(observation: CodexLimitObservation(planType: "plus", observedAt: isoDate("2026-10-14T08:00:00Z"),
                                                                        origin: .live, windows: [window]),
                                     state: .live, reachedService: fetched && reached)
        return .codexLimits(["acc-codex": entry])
    }
}

/// spec 016 FR-004 to FR-007, FR-013, FR-014, SC-001, SC-002, SC-004:
/// scheduled refreshes scan at the base pace and call each usage endpoint
/// only when its pace says so. Times are minutes after `start`.
@Suite struct AdaptivePaceCoordinatorTests {
    static let start = isoDate("2026-10-14T15:00:00Z")

    static func json(adaptive: Bool = true, codex: Bool = false, secondClaude: Bool = false) -> String {
        var accounts = [#"{ "id": "acc-max", "type": "subscription", "displayName": "Claude Max", "credentialDirectory": "~/.claude" }"#]
        if secondClaude {
            accounts.append(#"{ "id": "acc-two", "type": "subscription", "displayName": "Claude Two", "credentialDirectory": "~/.claude-two" }"#)
        }
        if codex {
            accounts.append(#"{ "id": "acc-codex", "type": "codexSubscription", "displayName": "ChatGPT Plus", "harness": "codex", "codexHome": "~/.codex" }"#)
        }
        return """
        { "refreshIntervalSeconds": 300, "adaptiveRefresh": \(adaptive), "accounts": [\(accounts.joined(separator: ", "))] }
        """
    }

    struct Setup {
        let coordinator: RefreshCoordinator
        let dir: URL
        let clock: MutableClock
        let probe: OrderProbe
        let records: ProbeRecordSource
        let claude: ProbeClaudeSource
        let codex: ProbeCodexSource?

        func t(_ minutes: Double) -> Date { AdaptivePaceCoordinatorTests.start.addingTimeInterval(minutes * 60) }

        /// Moves the clock to minute `minutes` and runs one refresh.
        @discardableResult
        func refresh(at minutes: Double, _ trigger: RefreshTrigger = .scheduled) async -> UsageSnapshot {
            clock.advance(t(minutes).timeIntervalSince(clock.now()))
            return await coordinator.refreshAndWait(trigger: trigger)
        }

        /// Scheduled refreshes at every `step` minutes in `range`; returns
        /// the minutes at which the Claude stub was called.
        func ticks(_ range: StrideThrough<Double>) async -> [Double] {
            var called: [Double] = []
            for minute in range {
                let before = await claude.calls
                await refresh(at: minute)
                if await claude.calls > before { called.append(minute) }
            }
            return called
        }

        func logText() -> String {
            (try? String(contentsOf: dir.appendingPathComponent("usage.log"), encoding: .utf8)) ?? ""
        }

        func writeConfig(_ json: String) throws {
            try Data(json.utf8).write(to: dir.appendingPathComponent("config.json"))
        }
    }

    static func setup(_ name: String, json: String = AdaptivePaceCoordinatorTests.json(), codex: Bool = false) async throws -> Setup {
        let clock = MutableClock(start)
        let (coordinator, dir) = try makeCoordinator(configJSON: json, name: name, clock: { clock.now() })
        let probe = OrderProbe()
        let records = ProbeRecordSource(probe: probe)
        let claude = ProbeClaudeSource(probe: probe)
        let codexSource = codex ? ProbeCodexSource(probe: probe) : nil
        await coordinator.register(records)
        await coordinator.register(claude)
        if let codexSource { await coordinator.register(codexSource) }
        return Setup(coordinator: coordinator, dir: dir, clock: clock, probe: probe, records: records, claude: claude, codex: codexSource)
    }

    private func occurrences(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    /// research R3: the record sources finish before the endpoint sources start.
    @Test func recordSourcesFinishBeforeTheEndpointSources() async throws {
        let s = try await Self.setup("pace-order", json: Self.json(codex: true), codex: true)
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        let events = await s.probe.events
        let end = try #require(events.firstIndex(of: "records-end"))
        let claude = try #require(events.firstIndex(of: "claude-start"))
        let codex = try #require(events.firstIndex(of: "codex-start"))
        #expect(end < claude)
        #expect(end < codex)
    }

    /// P1, SC-001: no agent activity, Claude called at 0, 5, 15, 35, 65, 95.
    @Test func p1QuietClaudeEndpointSlowsDown() async throws {
        let s = try await Self.setup("pace-p1")
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        let called = await s.ticks(stride(from: 5, through: 120, by: 5))
        #expect(called == [5, 15, 35, 65, 95])
        #expect(s.records.calls == 25)
        #expect(await s.claude.calls <= 7)
        let log = s.logText()
        #expect(occurrences("pace: claude interval 600 s (no agent activity)", in: log) == 1)
        #expect(log.contains("pace: claude interval 1200 s (no agent activity)"))
        #expect(log.contains("pace: claude interval 1800 s (no agent activity)"))
    }

    /// P2, SC-002: a Claude Code record after the last call brings the call back.
    @Test func p2ActivityCallsAgain() async throws {
        let s = try await Self.setup("pace-p2")
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        _ = await s.ticks(stride(from: 5, through: 65, by: 5))
        s.records.records = [paceRecord(.claudeCode, at: s.t(69))]
        let called = await s.ticks(stride(from: 70, through: 75, by: 5))
        #expect(called == [70, 75])
        #expect(s.logText().contains("pace: claude interval back to base (activity)"))
    }

    /// FR-007: a paced reuse shows the values unmarked and keeps the refresh time.
    @Test func pacedReuseIsNotStale() async throws {
        let s = try await Self.setup("pace-reuse")
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        await s.refresh(at: 5)
        let paced = await s.refresh(at: 10)
        #expect(await s.claude.calls == 2)
        #expect(paced.subscriptions["acc-max"]?.state == .ok)
        #expect(!paced.isStale)
        #expect(paced.lastSuccessfulRefreshAt == s.t(5))
        #expect(paced.endpointBlockedUntil == nil)
        #expect(s.logText().contains("endpoint reused (adaptive pace, next call 2026-10-14T15:15:00Z)"))
        // EndpointPolicy saw no call at 10: a manual refresh 30 s later is
        // not held back by the 60 s spacing.
        await s.refresh(at: 10.5, .manual)
        #expect(await s.claude.calls == 3)
    }

    /// P3: Codex records keep Codex at the base while Claude is paced.
    @Test func codexRecordsKeepCodexAtTheBase() async throws {
        let s = try await Self.setup("pace-codex", json: Self.json(codex: true), codex: true)
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        var called: [Double] = []
        for minute in stride(from: 5.0, through: 40, by: 5) {
            s.records.records = [paceRecord(.codex, at: s.t(minute - 1))]
            let before = await s.claude.calls
            await s.refresh(at: minute)
            if await s.claude.calls > before { called.append(minute) }
        }
        #expect(called == [5, 15, 35])
        let scheduled = await s.codex!.contexts.filter { $0.trigger == .scheduled }
        #expect(scheduled.count == 8)
        #expect(scheduled.allSatisfy { $0.codexPaceDue })
    }

    @Test func quietCodexIsPacedToo() async throws {
        let s = try await Self.setup("pace-codex-quiet", json: Self.json(codex: true), codex: true)
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        _ = await s.ticks(stride(from: 5, through: 40, by: 5))
        let due = await s.codex!.contexts.filter { $0.trigger == .scheduled }.map(\.codexPaceDue)
        // Ticks 5 to 40: due at 5, 15, 35.
        #expect(due == [true, false, true, false, false, false, true, false])
        #expect(s.logText().contains("pace: codex interval 600 s (no agent activity)"))
        // FR-017: each paced Codex reuse names the next call.
        #expect(s.logText().contains("pace: codex reused (adaptive pace, next call 2026-10-14T15:15:00Z)"))
    }

    /// P6: a transport failure leaves the pace unchanged.
    @Test func p6TransportFailureLeavesThePace() async throws {
        let s = try await Self.setup("pace-p6")
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        await s.claude.answer(ProbeClaudeSource.offline())
        let called = await s.ticks(stride(from: 5, through: 15, by: 5))
        #expect(called == [5, 10, 15])
        #expect(!s.logText().contains("pace: claude interval"))
    }

    /// P8, P9: a dropdown-open call counts as last call without doubling,
    /// and returns to the base when it saw activity.
    @Test func p8p9DropdownOpenCallCountsAsLastCall() async throws {
        let s = try await Self.setup("pace-p8")
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        _ = await s.ticks(stride(from: 5, through: 15, by: 5))
        await s.refresh(at: 20, .dropdownOpen)
        #expect(await s.claude.calls == 4)
        // Interval stays 20 minutes, counted from 20.
        let called = await s.ticks(stride(from: 25, through: 40, by: 5))
        #expect(called == [40])
        #expect(!s.logText().contains("pace: claude interval back to base"))
        s.records.records = [paceRecord(.openCode, at: s.t(41))]
        await s.refresh(at: 42, .dropdownOpen)
        #expect(s.logText().contains("pace: claude interval back to base (activity)"))
    }

    /// U2: during a rate-limit block the pace never causes a call and the
    /// scheduled retry stays at the end of the block.
    @Test func u2RateLimitBlockWins() async throws {
        let s = try await Self.setup("pace-u2")
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.claude.answer(ProbeClaudeSource.rateLimited(2400))
        let first = await s.refresh(at: 0, .launch)
        #expect(first.nextRetryAt == s.t(40))
        for minute in stride(from: 5.0, through: 35, by: 5) {
            let snapshot = await s.refresh(at: minute)
            #expect(snapshot.nextRetryAt == s.t(40))
        }
        #expect(await s.claude.calls == 1)
    }

    /// U4: a scheduled tick during a Claude block still passes the Codex pace.
    @Test func u4CodexPaceDuringAClaudeBlock() async throws {
        let s = try await Self.setup("pace-u4", json: Self.json(codex: true), codex: true)
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.claude.answer(ProbeClaudeSource.rateLimited(2400))
        await s.refresh(at: 0, .launch)
        await s.refresh(at: 5)
        await s.refresh(at: 10)
        let scheduled = await s.codex!.contexts.filter { $0.trigger == .scheduled }.map(\.codexPaceDue)
        #expect(scheduled == [true, false])
        #expect(await s.claude.calls == 1)
    }

    /// U5: reusing a stored result whose entries reached the service records
    /// no call.
    @Test func u5ReuseRecordsNoCall() async throws {
        let s = try await Self.setup("pace-u5")
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        await s.refresh(at: 1, .local)
        let called = await s.ticks(stride(from: 5, through: 5, by: 5))
        #expect(called == [5], "a recorded reprice at 1 would have moved the due time to 6")
    }

    /// U6: an account added by hand while Claude is paced is fetched at once.
    @Test func u6ChangedAccountsAreFetched() async throws {
        let s = try await Self.setup("pace-u6")
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        _ = await s.ticks(stride(from: 5, through: 10, by: 5))
        #expect(await s.claude.calls == 2)
        try s.writeConfig(Self.json(secondClaude: true))
        let snapshot = await s.refresh(at: 11)
        #expect(await s.claude.calls == 3)
        #expect(snapshot.subscriptions["acc-two"]?.state == .ok)
    }

    /// U3, SC-004, P13: with the toggle off every tick calls, as before.
    @Test func u3ToggleOffCallsEveryTick() async throws {
        let s = try await Self.setup("pace-u3", json: Self.json(adaptive: false, codex: true), codex: true)
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        let called = await s.ticks(stride(from: 5, through: 120, by: 5))
        #expect(called == Array(stride(from: 5.0, through: 120, by: 5)))
        #expect(await s.codex!.contexts.allSatisfy { $0.codexPaceDue })
        #expect(!s.logText().contains("pace:"))
    }

    // MARK: Public pace API (T017a)

    @Test func nextScheduledRefreshFollowsThePace() async throws {
        let s = try await Self.setup("pace-api-next")
        defer { try? FileManager.default.removeItem(at: s.dir) }
        #expect(await s.coordinator.nextScheduledRefresh() == s.t(5), "before the first refresh: one interval from now")
        await s.refresh(at: 0, .launch)
        #expect(await s.coordinator.nextScheduledRefresh() == s.t(5))
        await s.refresh(at: 5)
        // Claude due at 15; the local scan keeps the base pace.
        #expect(await s.coordinator.nextScheduledRefresh() == s.t(10))
        let off = try await Self.setup("pace-api-next-off", json: Self.json(adaptive: false))
        defer { try? FileManager.default.removeItem(at: off.dir) }
        await off.refresh(at: 0, .launch)
        #expect(await off.coordinator.nextScheduledRefresh() == nil)
    }

    /// A re-arm while a refresh runs (its calls not recorded yet) never
    /// asks for a second scheduled refresh at once (FR-014, research R7).
    @Test func nextScheduledRefreshWhileARefreshRunsIsOneIntervalAway() async throws {
        let s = try await Self.setup("pace-api-running")
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        let gated = GatedSource(name: "slow-scan")
        await s.coordinator.register(gated)
        s.clock.advance(400)
        await s.coordinator.requestRefresh(trigger: .local)
        #expect(await waitUntil { await gated.calls == 1 })
        #expect(await s.coordinator.nextScheduledRefresh() == s.t(400.0 / 60 + 5))
        await gated.release()
        #expect(await waitUntil { await !s.coordinator.isRunning })
        // Claude was due at 5 and is still due: the next tick is now.
        #expect(await s.coordinator.nextScheduledRefresh() == s.clock.now())
    }

    @Test func setConditionsLogsTimerChanges() async throws {
        let s = try await Self.setup("pace-api-conditions")
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        #expect(await s.coordinator.setConditions(SystemConditions(lowPowerMode: true)))
        #expect(s.logText().contains("pace: timer 600 s (Low Power Mode)"))
        #expect(await s.coordinator.setConditions(SystemConditions(lowPowerMode: true)) == false)
        #expect(await s.coordinator.setConditions(SystemConditions()))
        #expect(s.logText().contains("pace: timer back to base 300 s"))
    }

    @Test func configurationChangedAppliesAtOnce() async throws {
        let s = try await Self.setup("pace-api-config")
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        _ = await s.ticks(stride(from: 5, through: 15, by: 5))
        #expect(await s.coordinator.paceStatus()?.reason == .noAgentActivity)
        var config = try decodeConfig(Self.json(adaptive: false))
        await s.coordinator.configurationChanged(config)
        #expect(s.logText().contains("pace: adaptive refresh off"))
        #expect(await s.coordinator.paceStatus() == nil)
        #expect(await s.coordinator.nextScheduledRefresh() == nil)
        #expect(await s.coordinator.setConditions(SystemConditions(idle: true)) == false)
        config.adaptiveRefresh = true
        await s.coordinator.configurationChanged(config)
        #expect(s.logText().contains("pace: adaptive refresh on"))
        // Switching on starts every pace at the base; the stored idle
        // condition now applies to the timer.
        #expect(await s.coordinator.paceStatus()?.reason == .idle)
    }

    @Test func baseChangeLogsIntervalsBackToBase() async throws {
        let s = try await Self.setup("pace-api-base")
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        _ = await s.ticks(stride(from: 5, through: 15, by: 5))
        var config = try decodeConfig(Self.json())
        config.refreshIntervalSeconds = 600
        await s.coordinator.configurationChanged(config)
        // A changed base resets every endpoint interval (spec 016 FR-017).
        #expect(s.logText().contains("pace: base 600 s, intervals back to base (configuration)"))
        #expect(await s.coordinator.paceStatus() == nil)
    }

    /// FR-017: switching on while idle logs the stretched timer too.
    @Test func toggleOnWhileIdleLogsTheTimer() async throws {
        let s = try await Self.setup("pace-toggle-idle", json: Self.json(adaptive: false))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        #expect(await s.coordinator.setConditions(SystemConditions(idle: true)) == false)
        await s.coordinator.configurationChanged(try decodeConfig(Self.json()))
        #expect(s.logText().contains("pace: adaptive refresh on"))
        #expect(s.logText().contains("pace: timer 1800 s (idle)"))
        // Switching off while idle returns the timer to the base, logged too.
        await s.coordinator.configurationChanged(try decodeConfig(Self.json(adaptive: false)))
        #expect(s.logText().contains("pace: adaptive refresh off"))
        #expect(s.logText().contains("pace: timer back to base 300 s"))
    }

    /// FR-014, spec 010 FR-008: a wake call that failed by transport is not
    /// followed by a scheduled call at once; the timer runs from the wake.
    @Test func failedWakeCallKeepsTheTimerAtTheBase() async throws {
        let s = try await Self.setup("pace-wake-fail")
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        await s.refresh(at: 5)
        await s.claude.answer(ProbeClaudeSource.offline())
        await s.refresh(at: 60, .wake)
        #expect(await s.claude.calls == 3)
        #expect(await s.coordinator.nextScheduledRefresh() == s.t(65))
    }

    /// FR-014: a manual refresh merged into a pending scheduled run keeps
    /// its endpoint call; the pace does not hold the merged run back.
    @Test func scheduledRunMergedWithAManualRefreshIgnoresThePace() async throws {
        let s = try await Self.setup("pace-merge")
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        #expect(await s.ticks(stride(from: 5, through: 15, by: 5)) == [5, 15])
        let gated = GatedSource(name: "slow-scan")
        await s.coordinator.register(gated)
        s.clock.advance(s.t(20).timeIntervalSince(s.clock.now()))
        await s.coordinator.requestRefresh(trigger: .scheduled)
        #expect(await waitUntil { await gated.calls == 1 })
        await s.coordinator.requestRefresh(trigger: .manual)
        await s.coordinator.requestRefresh(trigger: .scheduled)
        await gated.release()
        #expect(await waitUntil { await !s.coordinator.isRunning })
        // The run at 20 was paced (Claude due at 35); the merged run calls.
        #expect(await s.coordinator.refreshCount == 6)
        #expect(await s.claude.calls == 4)
        #expect(s.logText().contains("pace: scheduled run merged with an earlier request, pace not applied"))
    }

    /// FR-011, FR-012: the merged run keeps the 60 s spacing; right after a
    /// call it makes none, as neither merged request would have.
    @Test func mergedRunKeepsTheSpacing() async throws {
        let s = try await Self.setup("pace-merge-spaced")
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        let gated = GatedSource(name: "slow-scan")
        await s.coordinator.register(gated)
        s.clock.advance(s.t(5).timeIntervalSince(s.clock.now()))
        await s.coordinator.requestRefresh(trigger: .manual)
        #expect(await waitUntil { await gated.calls == 1 })
        await s.coordinator.requestRefresh(trigger: .idleReturn)
        await s.coordinator.requestRefresh(trigger: .scheduled)
        await gated.release()
        #expect(await waitUntil { await !s.coordinator.isRunning })
        // The manual run at 5 called; the merged run at 5 does not.
        #expect(await s.coordinator.refreshCount == 3)
        #expect(await s.claude.calls == 2)
        #expect(!s.logText().contains("pace: scheduled run merged"))
    }

    /// FR-014: a rate-limit retry after a short Retry-After, merged into a
    /// scheduled run, still calls although the 429 was under 60 s ago.
    @Test func mergedRateLimitRetryIsNeverPaced() async throws {
        let s = try await Self.setup("pace-merge-retry")
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        await s.claude.answer(ProbeClaudeSource.rateLimited(20))
        await s.refresh(at: 5)
        #expect(await s.claude.calls == 2)
        await s.claude.answer(ProbeClaudeSource.ok())
        let gated = GatedSource(name: "slow-scan")
        await s.coordinator.register(gated)
        s.clock.advance(21)
        await s.coordinator.requestRefresh(trigger: .local)
        #expect(await waitUntil { await gated.calls == 1 })
        await s.coordinator.requestRefresh(trigger: .retry)
        await s.coordinator.requestRefresh(trigger: .scheduled)
        await gated.release()
        #expect(await waitUntil { await !s.coordinator.isRunning })
        #expect(await s.claude.calls == 3)
        #expect(s.logText().contains("pace: scheduled run merged with an earlier request, pace not applied"))
    }

    /// Edge case "Clock moved backwards": the coordinator normalizes before
    /// scheduling, so the timer is never pushed into the future.
    @Test func clockMovedBackwardsNeverBlocksTheTimer() async throws {
        let s = try await Self.setup("pace-clock-back")
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        _ = await s.ticks(stride(from: 5, through: 15, by: 5))
        s.clock.advance(-3600)
        // Last refresh normalized to -45, plus the 5-minute timer.
        #expect(await s.coordinator.nextScheduledRefresh() == s.t(-40))
    }

    @Test func paceStatusNamesTheNextPlanLimitCheck() async throws {
        let s = try await Self.setup("pace-api-status")
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        #expect(await s.coordinator.paceStatus() == nil)
        _ = await s.ticks(stride(from: 5, through: 10, by: 5))
        #expect(await s.coordinator.paceStatus() == RefreshPaceStatus(reason: .noAgentActivity, nextAt: s.t(15), kind: .planLimits, plans: [.claude]))
    }
}


/// spec 016 FR-012, SC-003, contracts/refresh-pace.md rows D1 to D7: the
/// refresh when the dropdown opens.
@Suite struct DropdownOpenCoordinatorTests {
    typealias Pace = AdaptivePaceCoordinatorTests

    /// D1, D2: the last Claude call's age decides.
    @Test func d1d2OpenRefreshesWhenTheLastCallIsAMinuteOld() async throws {
        let s = try await Pace.setup("open-d1")
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        s.clock.advance(30)
        #expect(await s.coordinator.shouldRefreshOnOpen() == false)
        s.clock.advance(210)
        #expect(await s.coordinator.shouldRefreshOnOpen())
        await s.refresh(at: 4, .dropdownOpen)
        #expect(await s.claude.calls == 2)
        #expect(s.logText().contains("trigger dropdownOpen, endpoint fetched"))
    }

    /// D3: only the endpoint called a minute or more ago is called.
    @Test func d3OnlyTheOldEndpointIsCalled() async throws {
        let s = try await Pace.setup("open-d3", json: Pace.json(codex: true), codex: true)
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        // Codex calls stop reaching the service, so its last call stays at 0.
        await s.codex!.reachService(false)
        await s.refresh(at: 5)
        #expect(await s.claude.calls == 2)
        s.clock.advance(30)
        #expect(await s.coordinator.shouldRefreshOnOpen())
        let before = await s.codex!.fetches
        await s.refresh(at: 5.5, .dropdownOpen)
        #expect(await s.claude.calls == 2, "Claude was called 30 s ago")
        #expect(await s.codex!.fetches == before + 1)
    }

    /// D4: a rate-limit block allows the refresh but no endpoint call.
    @Test func d4BlockedOpenCallsNoEndpoint() async throws {
        let s = try await Pace.setup("open-d4")
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.claude.answer(ProbeClaudeSource.rateLimited(2400))
        await s.refresh(at: 0, .launch)
        s.clock.advance(240)
        #expect(await s.coordinator.shouldRefreshOnOpen())
        let snapshot = await s.refresh(at: 4, .dropdownOpen)
        #expect(await s.claude.calls == 1)
        #expect(snapshot.endpointBlockedUntil == s.t(40))
    }

    /// D6, FR-002: with the toggle off opening never refreshes.
    @Test func d6ToggleOffNeverRefreshesOnOpen() async throws {
        let s = try await Pace.setup("open-d6", json: Pace.json(adaptive: false))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        s.clock.advance(600)
        #expect(await s.coordinator.shouldRefreshOnOpen() == false)
    }

    /// D7: while a refresh runs, opening neither starts nor queues another.
    @Test func d7NoOpenRefreshWhileOneRuns() async throws {
        let s = try await Pace.setup("open-d7")
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        let gated = GatedSource(name: "slow-scan")
        await s.coordinator.register(gated)
        s.clock.advance(240)
        await s.coordinator.requestRefresh(trigger: .scheduled)
        #expect(await waitUntil { await gated.calls == 1 })
        #expect(await s.coordinator.shouldRefreshOnOpen() == false)
        #expect(await s.coordinator.refreshOnOpenIfDue() == false)
        await gated.release()
        #expect(await waitUntil { await !s.coordinator.isRunning })
        #expect(await s.coordinator.refreshCount == 2)
    }

    /// The app's hook: one call that checks and starts the refresh.
    @Test func refreshOnOpenIfDueStartsTheRefresh() async throws {
        let s = try await Pace.setup("open-if-due")
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        s.clock.advance(30)
        #expect(await s.coordinator.refreshOnOpenIfDue() == false)
        s.clock.advance(60)
        #expect(await s.coordinator.refreshOnOpenIfDue())
        #expect(await waitUntil {
            let count = await s.coordinator.refreshCount
            let running = await s.coordinator.isRunning
            return count == 2 && !running
        })
        #expect(await s.claude.triggers == [.launch, .dropdownOpen])
    }

    /// FR-012, FR-020: an expired sign-in never reaches the service, yet
    /// opening refreshes at most once a minute (no repeated credential
    /// reads).
    @Test func openWaitsAMinuteAfterATryWithoutAnswer() async throws {
        let s = try await Pace.setup("open-expired")
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.claude.answer(SubscriptionEntry(status: nil, state: .credentialsExpired))
        await s.refresh(at: 0, .launch)
        s.clock.advance(30)
        #expect(await s.coordinator.shouldRefreshOnOpen() == false)
        await s.refresh(at: 1, .dropdownOpen)
        s.clock.advance(10)
        #expect(await s.coordinator.shouldRefreshOnOpen() == false)
        s.clock.advance(50)
        #expect(await s.coordinator.shouldRefreshOnOpen())
    }
}

/// spec 016 FR-008 to FR-011, contracts/refresh-pace.md rows T1, T5 and
/// T7: system conditions stretch the timer; returning from idle refreshes.
@Suite struct SystemConditionsCoordinatorTests {
    typealias Pace = AdaptivePaceCoordinatorTests

    @Test func idleStretchesTheTimerAndLogsOnce() async throws {
        let s = try await Pace.setup("cond-idle")
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        _ = await s.ticks(stride(from: 5, through: 10, by: 5))
        // Claude: last call 5, interval 10, due 15 at the base timer.
        #expect(await s.coordinator.setConditions(SystemConditions(idle: true)))
        #expect(s.logText().contains("pace: timer 1800 s (idle)"))
        // Due = last call 5 + max(10, 30) = 35, before last refresh 10 + 30.
        #expect(await s.coordinator.nextScheduledRefresh() == s.t(35))
        #expect(await s.coordinator.paceStatus()?.reason == .idle)
        let lines = s.logText().components(separatedBy: "pace: timer").count
        #expect(await s.coordinator.setConditions(SystemConditions(idle: true)) == false)
        #expect(s.logText().components(separatedBy: "pace: timer").count == lines)
        #expect(await s.coordinator.setConditions(SystemConditions()))
        #expect(s.logText().contains("pace: timer back to base 300 s"))
        #expect(await s.coordinator.nextScheduledRefresh() == s.t(15))
    }

    @Test func withoutAnEndpointTheTimerFollowsTheLastRefresh() async throws {
        let s = try await Pace.setup("cond-no-endpoint", json: #"{ "refreshIntervalSeconds": 300 }"#)
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        #expect(await s.coordinator.setConditions(SystemConditions(lowPowerMode: true, thermalPressure: true)))
        #expect(s.logText().contains("pace: timer 600 s (Low Power Mode)"))
        #expect(await s.coordinator.nextScheduledRefresh() == s.t(10))
        #expect(await s.coordinator.paceStatus() == RefreshPaceStatus(reason: .lowPowerMode, nextAt: s.t(10), kind: .refresh))
    }

    /// FR-011: the return-from-idle refresh ignores the endpoint pace but
    /// keeps the 60 s spacing.
    @Test func idleReturnCallsRegardlessOfThePaceButIsSpaced() async throws {
        let s = try await Pace.setup("cond-return")
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        _ = await s.ticks(stride(from: 5, through: 15, by: 5))
        #expect(await s.claude.calls == 3)
        await s.refresh(at: 15.5, .idleReturn)
        #expect(await s.claude.calls == 3, "spaced: last call 30 s ago")
        await s.refresh(at: 17, .idleReturn)
        #expect(await s.claude.calls == 4, "Claude due only at 35, called anyway")
        #expect(s.logText().contains("trigger idleReturn, endpoint fetched"))
    }

    /// P13: with the toggle off the conditions do nothing and log nothing.
    @Test func toggleOffIgnoresConditions() async throws {
        let s = try await Pace.setup("cond-off", json: Pace.json(adaptive: false))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        #expect(await s.coordinator.setConditions(SystemConditions(idle: true, lowPowerMode: true)) == false)
        #expect(!s.logText().contains("pace:"))
        #expect(await s.coordinator.nextScheduledRefresh() == nil)
        // FR-002: a return from idle starts no refresh either.
        await s.coordinator.setConditions(SystemConditions())
        #expect(await s.coordinator.isRunning == false)
        #expect(await s.coordinator.refreshCount == 1)
    }

    /// FR-011: the coordinator starts the return-from-idle refresh, except
    /// within 60 s after a wake refresh.
    @Test func returnFromIdleRefreshesUnlessRightAfterWake() async throws {
        let s = try await Pace.setup("cond-return-wake")
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.refresh(at: 0, .launch)
        await s.coordinator.setConditions(SystemConditions(idle: true))
        s.clock.advance(600)
        await s.coordinator.setConditions(SystemConditions())
        #expect(await waitUntil {
            let count = await s.coordinator.refreshCount
            let running = await s.coordinator.isRunning
            return count == 2 && !running
        })
        #expect(await s.claude.triggers.last == .idleReturn)
        await s.coordinator.setConditions(SystemConditions(idle: true))
        await s.refresh(at: 30, .wake)
        s.clock.advance(30)
        await s.coordinator.setConditions(SystemConditions())
        #expect(s.logText().contains("pace: return from idle right after wake, no extra refresh"))
        #expect(await s.coordinator.isRunning == false)
        #expect(await s.coordinator.refreshCount == 3)
    }
}

// MARK: - Spec 017: observations kept across refreshes (FR-003, FR-004, SC-005)

@Suite struct BurnRateCoordinatorTests {
    static let start = isoDate("2026-10-14T13:10:00Z")
    /// 66 hours after 14:00 (US1).
    static let reset = isoDate("2026-10-17T08:00:00Z")
    static let seven = BurnWindowKey.claude("acc-max", .sevenDay)
    static let group = BurnWindowKey.group("grp-vertex")

    static func claude(_ percent: Double, fetched: Date) -> SourceOutput {
        let status = SubscriptionStatus(fiveHour: nil, sevenDay: LimitWindow(utilizationPercent: percent, resetsAt: reset), fetchedAt: fetched)
        return .subscriptions(["acc-max": SubscriptionEntry(status: status, state: .ok)])
    }

    /// 12 of the group's 60 dollars: 20%.
    static let records: SourceOutput = .records([makeRecord(id: "a", accountId: "acc-vertex", timestamp: isoDate("2026-10-12T10:00:00Z"), cost: 12)])

    static func count(_ snapshot: UsageSnapshot?, _ key: BurnWindowKey) -> Int {
        snapshot?.observations.entries[key]?.count ?? 0
    }

    /// US1 AS1 through the coordinator: 30% at 13:10, 36% at 14:00 give a
    /// recent rate of 7.2 points per hour and "↑" in the bar.
    @Test func burstShowsUpArrowOnTheSecondRefresh() async throws {
        let clock = MutableClock(Self.start)
        let (coordinator, dir) = try makeCoordinator(name: "burn-burst", clock: { clock.now() })
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = StaticSource(name: "subscription", output: Self.claude(30, fetched: Self.start))
        await coordinator.register(source)
        let first = await coordinator.refreshAndWait()
        #expect(Self.count(first, Self.seven) == 1)
        #expect(first.observations.recentRate(for: Self.seven, now: first.generatedAt) == nil)

        clock.advance(50 * 60)
        source.output = Self.claude(36, fetched: clock.now())
        let second = await coordinator.refreshAndWait()
        let recent = try #require(second.observations.recentRate(for: Self.seven, now: second.generatedAt))
        #expect(abs(recent.perHour - 7.2) < 1e-9)
        let configuration = try decodeConfig(contractExampleJSON)
        let item = BarLayout.segments(snapshot: second, configuration: configuration).first { $0.id == "acc-max" }
        #expect(item?.value == "36%")
        #expect(item?.runOutMarker == true)
        #expect(item?.burnsFast == true)
        #expect(await coordinator.latestSnapshot?.observations == second.observations)
    }

    /// The early result from saved values records them, so a refresh 20
    /// minutes later already has a recent rate (FR-003).
    @Test func savedValuesCountAsTheFirstObservation() async throws {
        let clock = MutableClock(Self.start.addingTimeInterval(5 * 60))
        let (coordinator, dir) = try makeCoordinator(name: "burn-saved", clock: { clock.now() })
        defer { try? FileManager.default.removeItem(at: dir) }
        let fetchedLater = Self.start.addingTimeInterval(25 * 60)
        await coordinator.register(StaticSavedSource(saved: Self.claude(30, fetched: Self.start), output: Self.claude(36, fetched: fetchedLater)))
        let early = try #require(await coordinator.publishSavedValues())
        #expect(Self.count(early, Self.seven) == 1)
        clock.advance(20 * 60)
        let refreshed = await coordinator.refreshAndWait(trigger: .launch)
        let recent = try #require(refreshed.observations.recentRate(for: Self.seven, now: refreshed.generatedAt))
        #expect(abs(recent.perHour - 6 / (25.0 / 60)) < 1e-9)
    }

    /// A price import or removal (`requestReprice`) discards the budget
    /// observations and keeps the Claude ones; the next scheduled refresh
    /// counts as no price change.
    @Test func repriceDiscardsBudgetObservationsOnly() async throws {
        let clock = MutableClock(Self.start)
        let (coordinator, dir) = try makeCoordinator(name: "burn-reprice", clock: { clock.now() })
        defer { try? FileManager.default.removeItem(at: dir) }
        let claude = StaticSource(name: "subscription", output: Self.claude(30, fetched: Self.start))
        await coordinator.register(claude)
        await coordinator.register(StaticSource(name: "sessionLogs", output: Self.records))
        let first = await coordinator.refreshAndWait()
        #expect(Self.count(first, Self.group) == 1)
        #expect(Self.count(first, Self.seven) == 1)

        clock.advance(10 * 60)
        claude.output = Self.claude(31, fetched: clock.now())
        let repriced = await coordinator.repriceAndWait()
        #expect(Self.count(repriced, Self.group) == 1)
        #expect(repriced.observations.entries[Self.group]?.first?.observedAt == clock.now())
        #expect(Self.count(repriced, Self.seven) == 2)

        clock.advance(10 * 60)
        let scheduled = await coordinator.refreshAndWait()
        #expect(Self.count(scheduled, Self.group) == 2)
    }

    /// A changed manual price override discards the budget observations.
    @Test func changedPriceOverridesDiscardBudgetObservations() async throws {
        let clock = MutableClock(Self.start)
        let (coordinator, dir) = try makeCoordinator(name: "burn-overrides", clock: { clock.now() })
        defer { try? FileManager.default.removeItem(at: dir) }
        let claude = StaticSource(name: "subscription", output: Self.claude(30, fetched: Self.start))
        await coordinator.register(claude)
        await coordinator.register(StaticSource(name: "sessionLogs", output: Self.records))
        _ = await coordinator.refreshAndWait()
        clock.advance(10 * 60)
        claude.output = Self.claude(31, fetched: clock.now())
        let unchanged = await coordinator.refreshAndWait()
        #expect(Self.count(unchanged, Self.group) == 2)

        var config = try decodeConfig(contractExampleJSON)
        config.priceOverrides[0].inputPerMTok = 9
        let configURL = dir.appendingPathComponent("config.json")
        let mtime = try FileManager.default.attributesOfItem(atPath: configURL.path)[.modificationDate] as! Date
        try JSONEncoder().encode(config).write(to: configURL, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: mtime.addingTimeInterval(5)], ofItemAtPath: configURL.path)
        clock.advance(10 * 60)
        claude.output = Self.claude(32, fetched: clock.now())
        let edited = await coordinator.refreshAndWait()
        #expect(Self.count(edited, Self.group) == 1)
        // The Claude observations are kept and keep growing.
        #expect(Self.count(edited, Self.seven) == 3)
    }

    /// A reprice requested while a refresh is in flight still discards the
    /// budget observations in the follow-up refresh that reprices.
    @Test func repriceDuringARefreshDiscardsInTheFollowUp() async throws {
        let clock = MutableClock(Self.start)
        let (coordinator, dir) = try makeCoordinator(name: "burn-inflight", clock: { clock.now() })
        defer { try? FileManager.default.removeItem(at: dir) }
        let logs = GatedSource(name: "sessionLogs", output: Self.records)
        await logs.release()
        await coordinator.register(logs)
        let first = await coordinator.refreshAndWait()
        #expect(Self.count(first, Self.group) == 1)

        await logs.close()
        clock.advance(10 * 60)
        await coordinator.requestRefresh()
        #expect(await waitUntil { await logs.calls == 2 })
        await coordinator.requestReprice()
        clock.advance(10 * 60)
        await logs.release()
        let done = await waitUntil {
            let count = await coordinator.refreshCount
            let running = await coordinator.isRunning
            return count == 3 && !running
        }
        #expect(done)
        let latest = await coordinator.latestSnapshot
        #expect(Self.count(latest, Self.group) == 1)
        #expect(latest?.observations.entries[Self.group]?.first?.observedAt == clock.now())
    }

    /// A reprice requested while a refresh is in flight may already reach
    /// the prices that refresh reads, so the in-flight refresh discards the
    /// budget observations too, and no transient "↑" can come from the
    /// repriced spend (FR-003).
    @Test func repriceDuringARefreshDiscardsInThatRefresh() async throws {
        let clock = MutableClock(Self.start)
        let (coordinator, dir) = try makeCoordinator(name: "burn-inflight-same", clock: { clock.now() })
        defer { try? FileManager.default.removeItem(at: dir) }
        let logs = GatedSource(name: "sessionLogs", output: Self.records)
        await logs.release()
        await coordinator.register(logs)
        _ = await coordinator.refreshAndWait()

        await logs.close()
        clock.advance(10 * 60)
        let inFlightAt = clock.now()
        await coordinator.requestRefresh()
        #expect(await waitUntil { await logs.calls == 2 })
        await coordinator.requestReprice()
        clock.advance(10 * 60)
        // Lets the in-flight refresh finish; the follow-up blocks at its collect.
        await logs.releaseWaiting()
        #expect(await waitUntil { await logs.calls == 3 })
        let inFlight = await coordinator.latestSnapshot
        #expect(await coordinator.refreshCount == 2)
        #expect(Self.count(inFlight, Self.group) == 1)
        #expect(inFlight?.observations.entries[Self.group]?.first?.observedAt == inFlightAt)

        await logs.release()
        #expect(await waitUntil { await !coordinator.isRunning })
        let followUp = await coordinator.latestSnapshot
        #expect(Self.count(followUp, Self.group) == 1)
        #expect(followUp?.observations.entries[Self.group]?.first?.observedAt == clock.now())
    }

    /// SC-005: observations write no file and add no log lines.
    @Test func observationsWriteNothing() async throws {
        let clock = MutableClock(Self.start)
        let (coordinator, dir) = try makeCoordinator(name: "burn-files", clock: { clock.now() })
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = StaticSource(name: "subscription", output: Self.claude(30, fetched: Self.start))
        await coordinator.register(source)
        await coordinator.register(StaticSource(name: "sessionLogs", output: Self.records))
        _ = await coordinator.refreshAndWait()
        clock.advance(50 * 60)
        source.output = Self.claude(36, fetched: clock.now())
        let second = await coordinator.refreshAndWait()
        #expect(second.burnRate(for: Self.seven)?.burnsFast == true)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(files == ["config.json", "usage.log"])
        let logText = try String(contentsOf: dir.appendingPathComponent("usage.log"), encoding: .utf8).lowercased()
        #expect(!logText.contains("observation"))
        #expect(!logText.contains("burn"))
    }
}

// MARK: - Spec 021: "Refresh now" after a no-answer failure

/// spec 021 FR-003 to FR-006, FR-003a to FR-003c, SC-002: a manual refresh
/// inside the 60 s spacing asks again the accounts and Codex homes whose
/// last request got no answer, once per refresh; everything else keeps
/// today's spacing.
@Suite struct NoAnswerRetryCoordinatorTests {
    static let start = QuickRetryCoordinatorTests.start
    static let far = Date(timeIntervalSince1970: 4_000_000_000)

    /// The real Claude and Codex sources on the stub session, so request
    /// counts are real.
    struct Live {
        let coordinator: RefreshCoordinator
        let dir: URL
        let clock: MutableClock
        let claudeReader = FakeCredentialReader()
        let codexReader = FakeCodexCredentialReader()

        func logText() -> String {
            (try? String(contentsOf: dir.appendingPathComponent("usage.log"), encoding: .utf8)) ?? ""
        }

        /// The log of the two sources, kept apart from the coordinator's.
        func sourceLogText() -> String {
            (try? String(contentsOf: dir.appendingPathComponent("sources.log"), encoding: .utf8)) ?? ""
        }

        func signInClaude(_ directory: String = "~/.claude", token: String) {
            claudeReader.credentials[directory] = OAuthCredential(accessToken: token, expiresAt: NoAnswerRetryCoordinatorTests.far)
        }

        func signInCodex(token: String) {
            codexReader.set("~/.codex", .success(.found(CodexCredential(accessToken: token, accountId: "acct", expiresAt: nil))))
        }
    }

    static func live(_ name: String, json: String) async throws -> Live {
        let clock = MutableClock(start)
        let (coordinator, dir) = try makeCoordinator(configJSON: json, name: name, clock: { clock.now() },
                                                     retrySleep: { _ in try? await Task.sleep(for: .seconds(3600)) },
                                                     quickRetrySleep: { _ in try? await Task.sleep(for: .seconds(3600)) })
        let setup = Live(coordinator: coordinator, dir: dir, clock: clock)
        let sourceLog = DiagnosticLog(fileURL: dir.appendingPathComponent("sources.log"))
        await coordinator.register(SubscriptionSource(credentialReader: setup.claudeReader,
                                                      client: UsageEndpointClient(session: StubURLProtocol.makeSession()),
                                                      log: sourceLog, clock: { clock.now() }))
        await coordinator.register(CodexLimitsSource(credentialReader: setup.codexReader,
                                                     client: CodexUsageClient(session: StubURLProtocol.makeSession(), userAgent: "AgentMeter/test"),
                                                     log: sourceLog, paths: Paths(home: dir), clock: { clock.now() }))
        await coordinator.register(FakeLogSource())
        return setup
    }

    static func token(_ label: String) -> String { "na-coord-\(label)-\(UUID().uuidString)" }
    static func offline(_ token: String) {
        StubURLProtocol.register(key: "Bearer \(token)") { _ in throw offlineErrorWithDetail(secret: token) }
    }
    /// Registering an answer resets the token's recorded requests.
    static func answer(_ token: String, status: Int = 200, body: String) {
        StubURLProtocol.register(key: "Bearer \(token)") { _ in (status, Data(body.utf8)) }
    }
    static func requests(_ token: String) -> Int { StubURLProtocol.recordedRequests(key: "Bearer \(token)").count }

    static func okEntry() -> SubscriptionEntry {
        var entry = QuickRetryCoordinatorTests.ok()
        entry.reachedService = true
        return entry
    }

    static func output(_ entry: SubscriptionEntry) -> SourceOutput { .subscriptions(["acc-max": entry]) }

    static func retrying(_ seconds: TimeInterval = 30) -> SubscriptionEntry {
        QuickRetryCoordinatorTests.retrying(at: start.addingTimeInterval(seconds))
    }

    /// Runs `requests` while a reprice is held by a slow record source, then
    /// lets everything finish; `expectedCount` is the refresh count after.
    static func whileARepriceRuns(_ s: QuickRetryCoordinatorTests.Setup, expectedCount: Int,
                                  _ requests: () async -> Void) async -> Bool {
        let gated = GatedSource(name: "slow-log")
        await s.coordinator.register(gated)
        await s.coordinator.requestReprice()
        guard await waitUntil({ await gated.calls == 1 }) else { return false }
        await requests()
        await gated.release()
        return await waitUntil {
            let running = await s.coordinator.isRunning
            let count = await s.coordinator.refreshCount
            return !running && count == expectedCount
        }
    }

    // MARK: Real sources

    /// SC-002: one Claude and one Codex request within 60 s; after their
    /// answers, the next click is spaced again.
    @Test func manualAfterNoAnswerSendsOneRequestPerService() async throws {
        let s = try await Self.live("na-each", json: CodexLimitsCoordinatorTests.json)
        defer { try? FileManager.default.removeItem(at: s.dir) }
        let claude = Self.token("claude"), codex = Self.token("codex")
        defer { [claude, codex].forEach { StubURLProtocol.unregister(key: "Bearer \($0)") } }
        Self.offline(claude)
        Self.offline(codex)
        s.signInClaude(token: claude)
        s.signInCodex(token: codex)
        _ = await s.coordinator.refreshAndWait(trigger: .launch)
        #expect(Self.requests(claude) == 1)
        #expect(Self.requests(codex) == 1)
        // SC-003: both sources log the detail, never the token.
        let sourceLog = s.sourceLogText()
        #expect(sourceLog.contains("acc-max: fetch failed (transport): usage endpoint unreachable: \(offlineDescription) [NSURLErrorDomain -1009"))
        #expect(sourceLog.contains("acc-codex: unavailable, reason: offline, request failed: usage endpoint unreachable: \(offlineDescription) [NSURLErrorDomain -1009"))
        #expect(!sourceLog.contains(claude) && !sourceLog.contains(codex))

        s.clock.advance(10)
        Self.answer(claude, body: usageResponseJSON)
        Self.answer(codex, body: codexUsageSampleJSON)
        let fresh = await s.coordinator.refreshAndWait(trigger: .manual)
        #expect(Self.requests(claude) == 1)
        #expect(Self.requests(codex) == 1)
        #expect(fresh.subscriptions["acc-max"]?.state == .ok)
        #expect(fresh.codexLimits["acc-codex"]?.state == .live)
        #expect(s.logText().contains("trigger manual, endpoint fetched for no-answer accounts (Refresh now)"))

        s.clock.advance(10)
        _ = await s.coordinator.refreshAndWait(trigger: .manual)
        #expect(Self.requests(claude) == 1)
        #expect(Self.requests(codex) == 1)
        #expect(s.logText().contains("trigger manual, endpoint reused (last fetch 10 s ago)"))
    }

    /// FR-004, SC-002: after an HTTP 5xx answer no request is sent within
    /// the spacing, for either service.
    @Test func manualAfter5xxReusesWithinSpacing() async throws {
        let s = try await Self.live("na-5xx", json: CodexLimitsCoordinatorTests.json)
        defer { try? FileManager.default.removeItem(at: s.dir) }
        let claude = Self.token("claude5xx"), codex = Self.token("codex5xx")
        defer { [claude, codex].forEach { StubURLProtocol.unregister(key: "Bearer \($0)") } }
        Self.answer(claude, status: 503, body: "{}")
        Self.answer(codex, status: 503, body: "{}")
        s.signInClaude(token: claude)
        s.signInCodex(token: codex)
        _ = await s.coordinator.refreshAndWait(trigger: .launch)
        s.clock.advance(10)
        _ = await s.coordinator.refreshAndWait(trigger: .manual)
        #expect(Self.requests(claude) == 1)
        #expect(Self.requests(codex) == 1)
        #expect(s.logText().contains("trigger manual, endpoint reused (last fetch 10 s ago)"))
    }

    /// Edge case "Both services fail", SC-002: only Codex got no answer, so
    /// the click asks the Codex home again while Claude, which answered,
    /// keeps its spacing (the run reprices Claude).
    @Test func manualAsksOnlyCodexWhenOnlyCodexGotNoAnswer() async throws {
        let s = try await Self.live("na-mixed-codex", json: CodexLimitsCoordinatorTests.json)
        defer { try? FileManager.default.removeItem(at: s.dir) }
        let claude = Self.token("mixclaude"), codex = Self.token("mixcodex")
        defer { [claude, codex].forEach { StubURLProtocol.unregister(key: "Bearer \($0)") } }
        Self.answer(claude, body: usageResponseJSON)
        Self.offline(codex)
        s.signInClaude(token: claude)
        s.signInCodex(token: codex)
        _ = await s.coordinator.refreshAndWait(trigger: .launch)
        #expect(Self.requests(claude) == 1)
        #expect(Self.requests(codex) == 1)

        s.clock.advance(10)
        Self.answer(codex, body: codexUsageSampleJSON)
        let fresh = await s.coordinator.refreshAndWait(trigger: .manual)
        #expect(Self.requests(claude) == 1)
        #expect(Self.requests(codex) == 1)
        #expect(fresh.codexLimits["acc-codex"]?.state == .live)
        #expect(s.logText().contains("trigger manual, endpoint reused (last fetch 10 s ago)"))
    }

    /// Edge case "Both services fail", SC-002: only Claude got no answer, so
    /// the click asks Claude again while the Codex home, which answered,
    /// keeps its spacing.
    @Test func manualAsksOnlyClaudeWhenOnlyClaudeGotNoAnswer() async throws {
        let s = try await Self.live("na-mixed-claude", json: CodexLimitsCoordinatorTests.json)
        defer { try? FileManager.default.removeItem(at: s.dir) }
        let claude = Self.token("mixclaude2"), codex = Self.token("mixcodex2")
        defer { [claude, codex].forEach { StubURLProtocol.unregister(key: "Bearer \($0)") } }
        Self.offline(claude)
        Self.answer(codex, body: codexUsageSampleJSON)
        s.signInClaude(token: claude)
        s.signInCodex(token: codex)
        _ = await s.coordinator.refreshAndWait(trigger: .launch)
        #expect(Self.requests(claude) == 1)
        #expect(Self.requests(codex) == 1)

        s.clock.advance(10)
        Self.answer(claude, body: usageResponseJSON)
        let fresh = await s.coordinator.refreshAndWait(trigger: .manual)
        #expect(Self.requests(claude) == 1)
        #expect(Self.requests(codex) == 1)
        #expect(fresh.subscriptions["acc-max"]?.state == .ok)
        #expect(s.logText().contains("trigger manual, endpoint fetched for no-answer accounts (Refresh now)"))
    }

    /// FR-003c: with two Claude accounts, only the one without an answer is
    /// asked; the other keeps its last result.
    @Test func answeredAccountKeepsItsLastResult() async throws {
        let s = try await Self.live("na-two", json: AdaptivePaceCoordinatorTests.json(secondClaude: true))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        let answered = Self.token("answered"), silent = Self.token("silent")
        defer { [answered, silent].forEach { StubURLProtocol.unregister(key: "Bearer \($0)") } }
        Self.answer(answered, body: usageResponseJSON)
        Self.offline(silent)
        s.signInClaude("~/.claude", token: answered)
        s.signInClaude("~/.claude-two", token: silent)
        _ = await s.coordinator.refreshAndWait(trigger: .launch)

        s.clock.advance(10)
        Self.answer(silent, body: usageResponseJSON)
        let snapshot = await s.coordinator.refreshAndWait(trigger: .manual)
        #expect(Self.requests(answered) == 1)
        #expect(Self.requests(silent) == 1)
        #expect(snapshot.subscriptions["acc-max"]?.state == .ok)
        #expect(snapshot.subscriptions["acc-max"]?.status?.fetchedAt == Self.start)
        #expect(snapshot.subscriptions["acc-two"]?.state == .ok)
        #expect(snapshot.subscriptions["acc-two"]?.status?.fetchedAt == Self.start.addingTimeInterval(10))
    }

    // MARK: Scripted Claude source

    /// FR-005: wake, dropdown open, settings and the return from idle stay
    /// spaced after a no-answer failure; only the click asks again.
    @Test func nonManualTriggersStaySpacedAfterNoAnswer() async throws {
        let s = try await QuickRetryCoordinatorTests.setup("na-others", output: Self.output(Self.retrying()))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.network.setNoAnswer(["acc-max"])
        _ = await s.coordinator.refreshAndWait(trigger: .launch)
        for trigger in [RefreshTrigger.wake, .dropdownOpen, .settings, .idleReturn] {
            s.clock.advance(5)
            _ = await s.coordinator.refreshAndWait(trigger: trigger)
        }
        #expect(await s.network.calls == 1)
        s.clock.advance(5)
        _ = await s.coordinator.refreshAndWait(trigger: .manual)
        #expect(await s.network.triggers == [.launch, .manual])
    }

    /// FR-003b: the bypass counts as the last attempt for the spacing and
    /// the dropdown-open spacing, and is not a scheduled call for the pace.
    @Test func bypassCountsForSpacingPaceAndDropdownOpen() async throws {
        let s = try await QuickRetryCoordinatorTests.setup("na-counts", output: Self.output(Self.retrying()))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.network.setNoAnswer(["acc-max"])
        _ = await s.coordinator.refreshAndWait(trigger: .launch)
        s.clock.advance(10)
        await s.network.setOutput(Self.output(Self.okEntry()))
        await s.network.setNoAnswer(["acc-max"], afterCollect: [])
        _ = await s.coordinator.refreshAndWait(trigger: .manual)
        #expect(await s.network.calls == 2)

        // 65 s after the launch request, 55 s after the bypass.
        s.clock.advance(55)
        #expect(await s.coordinator.shouldRefreshOnOpen() == false)
        _ = await s.coordinator.refreshAndWait(trigger: .wake)
        #expect(await s.network.calls == 2)
        #expect(s.logText().contains("trigger wake, endpoint reused (last fetch 55 s ago)"))
        #expect(!s.logText().contains("pace: claude interval"))
    }

    /// FR-003b: a rate limit on the bypass request sets the block as usual,
    /// and the block then wins over a later click.
    @Test func bypassRateLimitSetsTheBlock() async throws {
        let s = try await QuickRetryCoordinatorTests.setup("na-429", output: Self.output(Self.retrying()))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.network.setNoAnswer(["acc-max"])
        _ = await s.coordinator.refreshAndWait(trigger: .launch)
        s.clock.advance(10)
        let limited = SubscriptionEntry(status: QuickRetryCoordinatorTests.status,
                                        state: .stale(lastGoodAt: QuickRetryCoordinatorTests.lastGood, error: "usage endpoint returned HTTP 429"),
                                        fetchOutcome: .rateLimited(retryAfter: 300))
        await s.network.setOutput(Self.output(limited))
        let blocked = await s.coordinator.refreshAndWait(trigger: .manual)
        #expect(blocked.endpointBlockedUntil == Self.start.addingTimeInterval(310))
        #expect(await waitUntil { await s.retryGate.delays == [301] })
        s.clock.advance(10)
        _ = await s.coordinator.refreshAndWait(trigger: .manual)
        #expect(await s.network.triggers == [.launch, .manual])
        #expect(s.logText().contains("trigger manual, endpoint reused (rate limited until"))
    }

    /// FR-003a, R7: a settings edit and a click merged into one run keep the
    /// settings follow-up, scheduled from `.fetchNoAnswer(retryAt:)`, and a
    /// successful no-answer run does not cancel it.
    @Test func noAnswerRunKeepsThePendingSettingsFollowUp() async throws {
        let s = try await QuickRetryCoordinatorTests.setup("na-settings", output: Self.output(Self.retrying()))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.network.setNoAnswer(["acc-max"])
        _ = await s.coordinator.refreshAndWait(trigger: .launch)
        s.clock.advance(10)
        await s.network.setOutput(Self.output(Self.okEntry()))
        await s.network.setNoAnswer(["acc-max"], afterCollect: [])
        #expect(await Self.whileARepriceRuns(s, expectedCount: 3) {
            await s.coordinator.requestRefresh(trigger: .settings)
            await s.coordinator.requestRefresh(trigger: .manual)
        })
        #expect(await s.network.triggers == [.launch, .settings])
        #expect(await s.network.contexts.last?.claudeNoAnswerOnly == true)
        #expect(await s.coordinator.latestSnapshot?.nextRetryAt == Self.start.addingTimeInterval(60))
        #expect(s.logText().contains("endpoint settings follow-up scheduled at"))
        #expect(await waitUntil { await s.retryGate.delays == [51] })
    }

    /// Edge case "A no-answer failure inside the spec 010 grace period": a
    /// click 10 s after the failure sends one request, which takes the quick
    /// retry's place; the timer then sends nothing.
    @Test func manualBeforeQuickRetryTakesItsPlace() async throws {
        let s = try await QuickRetryCoordinatorTests.setup("na-before-qr", output: Self.output(Self.retrying()))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.network.setNoAnswer(["acc-max"])
        _ = await s.coordinator.refreshAndWait(trigger: .launch)
        #expect(await waitUntil { await s.quickGate.delays == [31] })
        s.clock.advance(10)
        await s.network.setOutput(Self.output(Self.okEntry()))
        await s.network.setNoAnswer(["acc-max"], afterCollect: [])
        _ = await s.coordinator.refreshAndWait(trigger: .manual)
        #expect(s.logText().contains("quick retry dropped (manual refresh took its place)"))
        s.clock.advance(21)
        await s.quickGate.open()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await s.network.triggers == [.launch, .manual])
    }

    // MARK: Merged triggers (FR-003a, FR-006)

    /// A click merged into a pending scheduled run that the adaptive pace
    /// would hold back still asks the no-answer accounts, and the pace does
    /// not count that request as a scheduled call.
    @Test func manualMergedIntoPendingScheduledKeepsTheBypass() async throws {
        let s = try await QuickRetryCoordinatorTests.setup("na-merged-scheduled", output: Self.output(Self.okEntry()))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        _ = await s.coordinator.refreshAndWait(trigger: .launch)
        s.clock.advance(70)
        await s.network.setOutput(Self.output(Self.retrying(100)))
        await s.network.setNoAnswer([], afterCollect: ["acc-max"])
        _ = await s.coordinator.refreshAndWait(trigger: .wake)
        #expect(await s.network.calls == 2)

        s.clock.advance(10)
        await s.network.setOutput(Self.output(Self.okEntry()))
        await s.network.setNoAnswer(["acc-max"], afterCollect: [])
        #expect(await Self.whileARepriceRuns(s, expectedCount: 4) {
            await s.coordinator.requestRefresh(trigger: .manual)
            await s.coordinator.requestRefresh(trigger: .scheduled)
        })
        #expect(await s.network.triggers == [.launch, .wake, .scheduled])
        let context = await s.network.contexts.last
        #expect(context?.claudeNoAnswerOnly == true)
        #expect(context?.manualRequested == true)
        #expect(s.logText().contains("trigger scheduled, endpoint fetched for no-answer accounts (Refresh now)"))
        #expect(!s.logText().contains("pace: claude interval"))
    }

    /// A click merged into a pending quick retry adds no request of its
    /// own: the quick retry asks the no-answer accounts too.
    @Test func manualMergedIntoPendingQuickRetrySendsOneRequest() async throws {
        let s = try await QuickRetryCoordinatorTests.setup("na-merged-qr", output: Self.output(Self.retrying()))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.network.setNoAnswer(["acc-max"])
        _ = await s.coordinator.refreshAndWait(trigger: .launch)
        #expect(await waitUntil { await s.quickGate.delays == [31] })
        await s.network.setOutput(Self.output(Self.okEntry()))
        await s.network.setNoAnswer(["acc-max"], afterCollect: [])
        s.clock.advance(31)
        #expect(await Self.whileARepriceRuns(s, expectedCount: 3) {
            await s.quickGate.open()
            try? await Task.sleep(for: .milliseconds(30))
            await s.coordinator.requestRefresh(trigger: .manual)
        })
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await s.coordinator.refreshCount == 3)
        #expect(await s.network.triggers == [.launch, .quickRetry])
        #expect(await s.network.contexts.last?.manualRequested == true)
    }

    /// A click merged into a pending wake keeps the bypass.
    @Test func manualMergedIntoPendingWakeKeepsTheBypass() async throws {
        let s = try await QuickRetryCoordinatorTests.setup("na-merged-wake", output: Self.output(Self.retrying()))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.network.setNoAnswer(["acc-max"])
        _ = await s.coordinator.refreshAndWait(trigger: .launch)
        s.clock.advance(10)
        await s.network.setOutput(Self.output(Self.okEntry()))
        await s.network.setNoAnswer(["acc-max"], afterCollect: [])
        #expect(await Self.whileARepriceRuns(s, expectedCount: 3) {
            await s.coordinator.requestRefresh(trigger: .wake)
            await s.coordinator.requestRefresh(trigger: .manual)
        })
        #expect(await s.network.triggers == [.launch, .wake])
        #expect(await s.network.contexts.last?.claudeNoAnswerOnly == true)
    }

    /// FR-006: three clicks during a running bypass collapse into one
    /// follow-up, which bypasses again because the running one got no
    /// answer either.
    @Test func clicksDuringARunningRefreshCollapseIntoOneFollowUp() async throws {
        let s = try await QuickRetryCoordinatorTests.setup("na-clicks", output: Self.output(Self.retrying()))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.network.setNoAnswer(["acc-max"])
        _ = await s.coordinator.refreshAndWait(trigger: .launch)
        s.clock.advance(10)
        let gated = GatedSource(name: "slow-log")
        await s.coordinator.register(gated)
        await s.coordinator.requestRefresh(trigger: .manual)
        #expect(await waitUntil { await gated.calls == 1 })
        for _ in 0..<3 { await s.coordinator.requestRefresh(trigger: .manual) }
        await gated.release()
        #expect(await waitUntil {
            let running = await s.coordinator.isRunning
            let count = await s.coordinator.refreshCount
            return !running && count == 3
        })
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await s.coordinator.refreshCount == 3)
        #expect(await s.network.triggers == [.launch, .manual, .manual])
    }

    /// FR-003a, FR-006: a click merged into a queued quick retry survives
    /// when the running refresh drops that quick retry (the running click
    /// got no answer again and ended the grace period): the follow-up still
    /// runs as a click and asks the no-answer account.
    @Test func clickMergedIntoADroppedQuickRetryStillRuns() async throws {
        let s = try await QuickRetryCoordinatorTests.setup("na-dropped-qr", output: Self.output(Self.retrying()))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.network.setNoAnswer(["acc-max"])
        _ = await s.coordinator.refreshAndWait(trigger: .launch)
        #expect(await waitUntil { await s.quickGate.delays == [31] })
        s.clock.advance(10)
        let stale = SubscriptionEntry(status: QuickRetryCoordinatorTests.status,
                                      state: .stale(lastGoodAt: QuickRetryCoordinatorTests.lastGood, error: "offline"),
                                      fetchOutcome: .otherError)
        await s.network.setOutput(Self.output(stale))
        let gated = GatedSource(name: "slow-log")
        await s.coordinator.register(gated)
        await s.coordinator.requestRefresh(trigger: .manual)
        #expect(await waitUntil { await gated.calls == 1 })
        await s.quickGate.open()
        try? await Task.sleep(for: .milliseconds(30))
        await s.coordinator.requestRefresh(trigger: .manual)
        await gated.release()
        #expect(await waitUntil {
            let running = await s.coordinator.isRunning
            let count = await s.coordinator.refreshCount
            return !running && count == 3
        })
        #expect(s.logText().contains("quick retry dropped (manual refresh took its place)"))
        #expect(await s.network.triggers == [.launch, .manual, .manual])
    }

    /// FR-006: when the running bypass got an answer, the follow-up of the
    /// clicks during it is spaced as today.
    @Test func followUpAfterAnAnsweredRunStaysSpaced() async throws {
        let s = try await QuickRetryCoordinatorTests.setup("na-clicks-answered", output: Self.output(Self.retrying()))
        defer { try? FileManager.default.removeItem(at: s.dir) }
        await s.network.setNoAnswer(["acc-max"])
        _ = await s.coordinator.refreshAndWait(trigger: .launch)
        s.clock.advance(10)
        await s.network.setOutput(Self.output(Self.okEntry()))
        await s.network.setNoAnswer(["acc-max"], afterCollect: [])
        let gated = GatedSource(name: "slow-log")
        await s.coordinator.register(gated)
        await s.coordinator.requestRefresh(trigger: .manual)
        #expect(await waitUntil { await gated.calls == 1 })
        for _ in 0..<3 { await s.coordinator.requestRefresh(trigger: .manual) }
        await gated.release()
        #expect(await waitUntil {
            let running = await s.coordinator.isRunning
            let count = await s.coordinator.refreshCount
            return !running && count == 3
        })
        #expect(await s.network.triggers == [.launch, .manual])
        #expect(s.logText().contains("trigger manual, endpoint reused (last fetch 0 s ago)"))
    }
}
