import Foundation

/// What the classifier index knows about one decision log, handed to the
/// probe so it reads only unread bytes (spec 045 data-model "KnownLogState",
/// FR-003).
public struct KnownLogState: Equatable, Sendable {
    public var size: Int
    public var modificationDate: Date
    public var parsedOffset: Int

    public init(size: Int, modificationDate: Date, parsedOffset: Int) {
        self.size = size
        self.modificationDate = modificationDate
        self.parsedOffset = parsedOffset
    }
}

/// Bytes the probe read from a decision log (spec 045 data-model
/// "ReadChunk").
public struct ReadChunk: Equatable, Sendable {
    /// The offset the bytes start at: the known parsed offset, or 0 for a
    /// new file or one shorter than its parsed offset.
    public var from: Int
    public var data: Data

    public init(from: Int, data: Data) {
        self.from = from
        self.data = data
    }
}

/// The outcome of checking one working directory (spec 045 data-model
/// "ProbeResult").
public enum ProbeResult: Equatable, Sendable {
    /// A regular decision log at its canonical `path`. `chunk` is nil when
    /// the file is unchanged or older than the window start (FR-002,
    /// FR-003).
    case found(path: String, size: Int, modificationDate: Date, chunk: ReadChunk?)
    /// No decision log, or no such directory.
    case absent
    /// A symbolic link, a FIFO, a folder or anything else that is not a
    /// regular file (FR-001).
    case notRegular
    /// Larger than `DecisionLogProbe.maximumSize` (FR-001).
    case tooLarge(path: String, size: Int)
    /// The check did not finish within the time limit (FR-012).
    case timedOut
    /// A check of this directory from an earlier refresh still runs
    /// (FR-012).
    case busy
}

/// The probe's result for one refresh (spec 045 data-model "ProbeReport").
public struct ProbeReport: Equatable, Sendable {
    /// Per raw working directory. A second spelling of a directory already
    /// checked in this refresh has no result of its own (FR-001).
    public var results: [String: ProbeResult] = [:]
    /// Per raw working directory, its canonical directory: from this
    /// refresh's check, or for a timed-out or busy one from the last check
    /// that finished (absent when none ever did).
    public var canonical: [String: String] = [:]
    /// Raw directories that timed out and were not reported since a check
    /// of them last finished (FR-012).
    public var newlyTimedOut: [String] = []

    public init(results: [String: ProbeResult] = [:], canonical: [String: String] = [:], newlyTimedOut: [String] = []) {
        self.results = results
        self.canonical = canonical
        self.newlyTimedOut = newlyTimedOut
    }
}

/// Checks working directories for Claude Code's Auto-mode decision log and
/// reads its unread bytes (spec 045 FR-001, FR-002, FR-003, FR-012,
/// research R4, R5). This is the only place that canonicalizes a working
/// directory or opens a decision log; it never writes anything (FR-014).
public final class DecisionLogProbe: @unchecked Sendable {
    /// The decision log's file name; no other location is searched (FR-001).
    public static let fileName = ".automode_decisions.jsonl"
    /// A larger file is skipped (FR-001): about 120,000 decisions.
    public static let maximumSize = 64 * 1024 * 1024

    /// Turns a raw working directory into its canonical spelling; touches
    /// the file system, so it runs inside the timed check (FR-012).
    public typealias Canonicalize = @Sendable (String) -> String
    /// Checks one canonical directory: `(directory, known, notBefore)`.
    public typealias Check = @Sendable (String, [String: KnownLogState], Date) -> ProbeResult

    /// The time limit of one directory's check (FR-012).
    public let timeout: TimeInterval
    private let canonicalize: Canonicalize
    private let checkDirectory: Check
    /// Guards the three sets below.
    private let lock = NSLock()
    /// Raw directories whose check still runs, at most one each (FR-012).
    private var inFlight = Set<String>()
    /// The canonical directory of the last finished check per raw
    /// directory.
    private var lastCanonical: [String: String] = [:]
    /// Raw directories whose time-out was reported and no check finished in
    /// time since (FR-012).
    private var reportedTimeOut = Set<String>()

    /// `timeout`, `canonicalize` and `check` are injectable for tests; the
    /// defaults are 2 seconds, `Attributor.canonical` and `inspect`.
    public init(timeout: TimeInterval = 2, canonicalize: Canonicalize? = nil, check: Check? = nil) {
        self.timeout = timeout
        self.canonicalize = canonicalize ?? { Attributor.canonical($0) }
        self.checkDirectory = check ?? { DecisionLogProbe.inspect(directory: $0, known: $1, notBefore: $2) }
    }

    /// The decision log path in a canonical directory.
    public static func logPath(inDirectory directory: String) -> String {
        directory == "/" ? "/" + fileName : directory + "/" + fileName
    }

    /// The results of one `check` call, written by its check threads.
    private final class Batch: @unchecked Sendable {
        let lock = NSLock()
        /// Canonical directories claimed by a spelling of this call.
        var claimed = Set<String>()
        /// Per raw directory: its canonical directory and, unless another
        /// spelling claimed it, its result.
        var finished: [String: (canonical: String, result: ProbeResult?)] = [:]
    }

    /// Checks each raw directory on its own thread: canonicalizes it, then
    /// inspects its decision log unless another spelling of the same
    /// directory was claimed in this call (FR-001). Waits at most `timeout`
    /// for all of them, started together, so each gets that long; an
    /// unfinished one is `.timedOut` and stays in flight until its thread
    /// returns, and a directory still in flight is `.busy` without a new
    /// check (FR-012). `known` is the index's state by canonical log path;
    /// `notBefore` is the window start: an older log is not read (FR-002).
    public func check(directories: [String], known: [String: KnownLogState], notBefore: Date = .distantPast) -> ProbeReport {
        var unique: [String] = []
        var seen = Set<String>()
        for raw in directories where seen.insert(raw).inserted { unique.append(raw) }

        var report = ProbeReport()
        var started: [String] = []
        lock.lock()
        for raw in unique {
            if inFlight.contains(raw) {
                report.results[raw] = .busy
                report.canonical[raw] = lastCanonical[raw]
            } else {
                inFlight.insert(raw)
                started.append(raw)
            }
        }
        lock.unlock()

        let batch = Batch()
        let group = DispatchGroup()
        let canonicalize = canonicalize
        let checkDirectory = checkDirectory
        // One thread per check rather than a dispatch queue: a hung `lstat`
        // or read keeps its thread, and blocked threads must not use up a
        // shared pool's width, which would make every other check time out
        // too (research R4). The in-flight set bounds them to one per
        // directory.
        for raw in started {
            group.enter()
            let thread = Thread {
                let directory = canonicalize(raw)
                batch.lock.lock()
                let claims = batch.claimed.insert(directory).inserted
                batch.lock.unlock()
                let result = claims ? checkDirectory(directory, known, notBefore) : nil
                batch.lock.lock()
                batch.finished[raw] = (directory, result)
                batch.lock.unlock()
                self.finish(raw, canonical: directory)
                group.leave()
            }
            thread.qualityOfService = .utility
            thread.name = "agenttacho.decision-log-probe"
            thread.start()
        }
        _ = group.wait(timeout: .now() + timeout)

        batch.lock.lock()
        let finished = batch.finished
        batch.lock.unlock()
        lock.lock()
        for raw in started {
            if let done = finished[raw] {
                report.canonical[raw] = done.canonical
                if let result = done.result { report.results[raw] = result }
                reportedTimeOut.remove(raw)
            } else {
                report.results[raw] = .timedOut
                report.canonical[raw] = lastCanonical[raw]
                if reportedTimeOut.insert(raw).inserted { report.newlyTimedOut.append(raw) }
            }
        }
        lock.unlock()
        return report
    }

    /// Called on a check's thread when it returns, also after its time-out.
    private func finish(_ raw: String, canonical: String) {
        lock.lock()
        inFlight.remove(raw)
        lastCanonical[raw] = canonical
        lock.unlock()
    }

    /// The file system part of a check (research R5): `lstat` of the log,
    /// then for a new or changed regular file an open that follows no
    /// symbolic link and does not block, `fstat` on the same descriptor,
    /// and a read of the unread bytes. Nothing is created or changed.
    public static func inspect(directory: String, known: [String: KnownLogState], notBefore: Date) -> ProbeResult {
        let path = logPath(inDirectory: directory)
        var info = stat()
        guard lstat(path, &info) == 0 else { return .absent }
        guard info.st_mode & S_IFMT == S_IFREG else { return .notRegular }
        let size = Int(info.st_size)
        guard size <= maximumSize else { return .tooLarge(path: path, size: size) }
        let date = modificationDate(info)
        let state = known[path]
        // Unchanged (FR-003) or older than the window (FR-002): not read.
        if date < notBefore || (state?.size == size && state?.modificationDate == date) {
            return .found(path: path, size: size, modificationDate: date, chunk: nil)
        }

        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else {
            switch errno {
            case ENOENT, ENOTDIR: return .absent
            case ELOOP: return .notRegular
            default: return .absent
            }
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        // The file may have been swapped since the lstat: decide again from
        // the open descriptor.
        guard fstat(fd, &info) == 0 else { return .absent }
        guard info.st_mode & S_IFMT == S_IFREG else { return .notRegular }
        let openedSize = Int(info.st_size)
        guard openedSize <= maximumSize else { return .tooLarge(path: path, size: openedSize) }
        let openedDate = modificationDate(info)
        if openedDate < notBefore || (state?.size == openedSize && state?.modificationDate == openedDate) {
            return .found(path: path, size: openedSize, modificationDate: openedDate, chunk: nil)
        }
        // A grown file is read from its parsed offset, a new one or one
        // shorter than its parsed offset from the start (FR-003).
        let from = state.map { openedSize >= $0.parsedOffset ? $0.parsedOffset : 0 } ?? 0
        let data: Data
        do {
            try handle.seek(toOffset: UInt64(from))
            // At most up to the limit, also when the file grew meanwhile.
            data = try handle.read(upToCount: maximumSize - from + 1) ?? Data()
        } catch {
            return .absent
        }
        guard from + data.count <= maximumSize else { return .tooLarge(path: path, size: from + data.count) }
        return .found(path: path, size: from + data.count, modificationDate: openedDate,
                      chunk: ReadChunk(from: from, data: data))
    }

    private static func modificationDate(_ info: stat) -> Date {
        Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
    }
}
