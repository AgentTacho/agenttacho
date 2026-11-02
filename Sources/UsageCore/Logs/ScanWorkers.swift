import Foundation

/// A bounded number of threads at a priority below user interaction that
/// read and parse session files, off the sources' actors and off the
/// cooperative pool (spec 039 FR-017, FR-018, research R7).
///
/// `offload` runs the work on a global dispatch queue at the caller's
/// priority and suspends the caller, so neither its actor nor a thread of
/// the cooperative pool is held while files are parsed. `forEach` runs jobs
/// on at most `count` helper threads at `qos`, the largest first. The same
/// bound and priority serve every refresh, the first scan and the
/// incremental ones alike (FR-017).
public struct ScanWorkers: Sendable {
    /// Threads that run jobs at once; never more than the machine's cores.
    public let count: Int
    /// The priority of the jobs: utility, below user interaction.
    public let qos: DispatchQoS.QoSClass
    /// Test hook, called on the worker before each job.
    let beforeJob: (@Sendable (Int) -> Void)?

    /// Half the active cores, at least one and at most four. The
    /// worker-count step measured 2, 3 and 4 workers (BENCHMARK.md, step D):
    /// none met SC-001's 3 s within SC-002's 200%, and 4 came closest to
    /// both (3.78 s at 171%), so it is the default (research R7, T040).
    public static var defaultCount: Int {
        max(1, min(4, ProcessInfo.processInfo.activeProcessorCount / 2))
    }

    public static let `default` = ScanWorkers()

    /// `count` is clamped to `1...activeProcessorCount` (FR-017).
    public init(count: Int = ScanWorkers.defaultCount, qos: DispatchQoS.QoSClass = .utility,
                beforeJob: (@Sendable (Int) -> Void)? = nil) {
        self.count = min(max(1, count), max(1, ProcessInfo.processInfo.activeProcessorCount))
        self.qos = qos
        self.beforeJob = beforeJob
    }

    /// Runs `work` on the global queue of the calling task's priority and
    /// resumes the caller with its result. What `work` does itself, such as
    /// the index's merge and attribution with its wall-clock time limit for
    /// conditions (spec 038 FR-007), keeps the refresh's priority; the
    /// parse jobs it hands to `forEach` run at `qos`. `work` may block its
    /// dispatch thread, never the caller's.
    public func offload<T>(_ work: @escaping () -> T) async -> T {
        let job = UncheckedSendableBox(work)
        let callerQoS = DispatchQoS.QoSClass(rawValue: qos_class_t(rawValue: UInt32(Task.currentPriority.rawValue))) ?? .default
        return await withCheckedContinuation { (continuation: CheckedContinuation<UncheckedSendableBox<T>, Never>) in
            DispatchQueue.global(qos: callerQoS).async {
                continuation.resume(returning: UncheckedSendableBox(job.value()))
            }
        }.value
    }

    /// Runs `body` for every index in `0..<jobs`, largest `weight` first
    /// (ties in index order), on at most `count` threads at `qos`: `min(count,
    /// jobs) - 1` helper threads, where `.enforceQoS` keeps them at `qos`
    /// when a caller of higher priority submits them, plus the calling
    /// thread, lowered to `qos` while it runs jobs and set back to its own
    /// priority before it returns. So a user-initiated refresh does not lift
    /// the parsing, and the caller's own work after `forEach` keeps its
    /// priority. The calling thread runs jobs too, so the jobs finish even
    /// when no helper thread is given out, as for a caller on a blocked
    /// cooperative pool. Each thread takes the next index from a
    /// lock-protected cursor until none is left. Returns when every job is
    /// done, at once for zero jobs. Each job runs in its own autorelease
    /// pool: a dispatch thread drains its pool only when its work item ends,
    /// so the file buffers Foundation autoreleases would otherwise pile up
    /// over a whole scan (spec 039 SC-003).
    public func forEach(jobs: Int, weight: (Int) -> Int, body: (Int) -> Void) {
        guard jobs > 0 else { return }
        let weights = (0..<jobs).map(weight)
        let order = (0..<jobs).sorted { weights[$0] != weights[$1] ? weights[$0] > weights[$1] : $0 < $1 }
        let cursor = JobCursor(order)
        let beforeJob = beforeJob
        withoutActuallyEscaping(body) { body in
            // The helpers finish before `forEach` returns (the group wait),
            // so `body` does not outlive this call.
            let shared = UncheckedSendableBox(body)
            let run: @Sendable () -> Void = {
                while let index = cursor.next() {
                    beforeJob?(index)
                    autoreleasepool { shared.value(index) }
                }
            }
            let group = DispatchGroup()
            for _ in 0..<(min(count, jobs) - 1) {
                DispatchQueue.global(qos: qos).async(group: group, qos: DispatchQoS(qosClass: qos, relativePriority: 0),
                                                     flags: .enforceQoS, execute: run)
            }
            let own = qos_class_self()
            let lowered = own.rawValue > qos.rawValue.rawValue && pthread_set_qos_class_self_np(qos.rawValue, 0) == 0
            run()
            if lowered { pthread_set_qos_class_self_np(own, 0) }
            group.wait()
        }
    }
}

/// Hands out job indices in order, one at a time, to any thread.
private final class JobCursor: @unchecked Sendable {
    private let lock = NSLock()
    private let order: [Int]
    private var position = 0

    init(_ order: [Int]) {
        self.order = order
    }

    func next() -> Int? {
        lock.lock(); defer { lock.unlock() }
        guard position < order.count else { return nil }
        defer { position += 1 }
        return order[position]
    }
}

/// Carries a value that is not `Sendable` to a dispatch thread; the compiler
/// checks nothing, the user guarantees one of two contracts:
/// - Exclusive hand-off: the owner does not touch the value until the
///   offloaded work has returned. `offload` carries its work and result so,
///   and `SessionLogSource` its `LogIndex`: its `scanning` flag makes every
///   other `collect` wait and defers `resetForEarlierWindow()`, so nothing
///   else reaches the index while the update runs (spec 039 research R7).
/// - Concurrent calls: `forEach` calls its `body` on several threads at
///   once, each with its own index, so `body` must be safe for that.
final class UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
