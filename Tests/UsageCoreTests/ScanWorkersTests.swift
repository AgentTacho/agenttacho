import Foundation
import Testing
@testable import UsageCore

/// A thread-safe counter and log for the worker tests.
final class LockedLog<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Element] = []

    func append(_ item: Element) {
        lock.lock(); defer { lock.unlock() }
        items.append(item)
    }

    var values: [Element] {
        lock.lock(); defer { lock.unlock() }
        return items
    }
}

/// Counts jobs running at once and keeps the highest count seen.
final class ConcurrencyMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var running = 0
    private(set) var peak = 0

    func enter() {
        lock.lock(); defer { lock.unlock() }
        running += 1
        peak = max(peak, running)
    }

    func leave() {
        lock.lock(); defer { lock.unlock() }
        running -= 1
    }

    var highest: Int {
        lock.lock(); defer { lock.unlock() }
        return peak
    }
}

/// Bounded workers at utility priority, off the actors (spec 039 FR-017,
/// FR-018, research R7).
@Suite struct ScanWorkersTests {
    @Test func everyIndexRunsExactlyOnce() {
        let log = LockedLog<Int>()
        ScanWorkers(count: 3).forEach(jobs: 100, weight: { $0 % 7 }) { log.append($0) }
        #expect(log.values.sorted() == Array(0..<100))
    }

    @Test func zeroJobsReturnAtOnce() {
        let log = LockedLog<Int>()
        ScanWorkers(count: 3).forEach(jobs: 0, weight: { _ in 1 }) { log.append($0) }
        #expect(log.values.isEmpty)
    }

    @Test func neverMoreJobsAtOnceThanTheCount() {
        for count in [1, 2, 3] {
            let meter = ConcurrencyMeter()
            let log = LockedLog<Int>()
            ScanWorkers(count: count).forEach(jobs: 24, weight: { _ in 1 }) { index in
                meter.enter()
                usleep(3_000)
                log.append(index)
                meter.leave()
            }
            #expect(log.values.count == 24)
            #expect(meter.highest <= count, "count \(count), peak \(meter.highest)")
            #expect(meter.highest >= 1)
        }
    }

    /// The largest file starts first, ties in index order (FR-017).
    @Test func jobsStartInDescendingWeightOrder() {
        let weights = [5, 1, 9, 3, 9, 0]
        let log = LockedLog<Int>()
        ScanWorkers(count: 1).forEach(jobs: weights.count, weight: { weights[$0] }) { log.append($0) }
        #expect(log.values == [2, 4, 0, 3, 1, 5])
    }

    /// A higher-priority caller does not lift the scan: the jobs run at
    /// utility priority, on the helpers and on the lowered calling thread
    /// alike.
    @Test func jobsRunAtUtilityPriorityFromAUserInitiatedTask() async {
        let workers = ScanWorkers(count: 3)
        let classes = await Task(priority: .userInitiated) {
            await workers.offload {
                let log = LockedLog<UInt32>()
                workers.forEach(jobs: 12, weight: { $0 }) { _ in
                    usleep(1_000)
                    log.append(qos_class_self().rawValue)
                }
                return log.values
            }
        }.value
        #expect(classes.count == 12)
        #expect(classes.allSatisfy { $0 == QOS_CLASS_UTILITY.rawValue }, "\(classes)")
    }

    /// `offload` returns the work's result and does not hold a thread of
    /// the cooperative pool: an unrelated task completes meanwhile.
    @Test func offloadReturnsTheResultAndKeepsThePoolFree() async {
        let workers = ScanWorkers(count: 2)
        let gate = DispatchSemaphore(value: 0)
        async let held: DispatchTimeoutResult = workers.offload {
            gate.wait(timeout: .now() + 10)
        }
        let other = await Task.detached { 7 }.value
        #expect(other == 7)
        gate.signal()
        #expect(await held == .success)
    }

    /// More offloaded jobs blocked at once than the cooperative pool has
    /// threads: an unrelated task still completes before any is released,
    /// so none of them holds a pool thread (FR-018).
    @Test func offloadNeverHoldsACooperativeThread() async {
        let workers = ScanWorkers(count: 1)
        let gate = DispatchSemaphore(value: 0)
        let waits = LockedLog<DispatchTimeoutResult>()
        let blocked = ProcessInfo.processInfo.activeProcessorCount + 2
        let held = (0..<blocked).map { _ in
            Task.detached { await workers.offload { waits.append(gate.wait(timeout: .now() + 10)) } }
        }
        #expect(await Task.detached { 7 }.value == 7)
        for _ in 0..<blocked { gate.signal() }
        for task in held { await task.value }
        #expect(waits.values.count == blocked)
        #expect(waits.values.allSatisfy { $0 == .success })
    }

    /// The helpers run jobs at the same time as the calling thread: every
    /// job waits until `min(3, cores)` jobs have started (FR-017).
    @Test func jobsRunInParallelUpToTheCount() {
        let expected = min(3, ProcessInfo.processInfo.activeProcessorCount)
        let condition = NSCondition()
        var started = 0
        let seen = LockedLog<Int>()
        ScanWorkers(count: 3).forEach(jobs: expected, weight: { _ in 1 }) { _ in
            condition.lock()
            started += 1
            condition.broadcast()
            let deadline = Date().addingTimeInterval(10)
            while started < expected, condition.wait(until: deadline) {}
            seen.append(started)
            condition.unlock()
        }
        #expect(seen.values.count == expected)
        #expect(seen.values.allSatisfy { $0 == expected }, "\(seen.values)")
    }

    @Test func theDefaultCountAndTheClamp() {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        // At most 4: the worker-count step of BENCHMARK.md (step D) found
        // no count meeting SC-001 within SC-002, and 4 workers closest to
        // both (3.78 s at 171%; 3 workers 4.10 s at 157%).
        #expect(ScanWorkers.defaultCount == max(1, min(4, cores / 2)))
        #expect(ScanWorkers.default.count == ScanWorkers.defaultCount)
        #expect(ScanWorkers.default.qos == .utility)
        #expect(ScanWorkers(count: cores + 4).count == cores)
        #expect(ScanWorkers(count: 0).count == 1)
        #expect(ScanWorkers(count: -3).count == 1)
        #expect(ScanWorkers(count: 2).count == min(2, cores))
    }
}
