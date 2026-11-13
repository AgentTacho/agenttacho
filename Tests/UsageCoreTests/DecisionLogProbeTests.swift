import Foundation
import Testing
@testable import UsageCore

/// spec 045 FR-001, FR-003, FR-012: the probe finds and reads a working
/// directory's decision log.
@Suite struct DecisionLogProbeTests {
    static let fileName = ".automode_decisions.jsonl"

    func line(_ ts: Int, output: Int = 1) -> String {
        #"{"ts":\#(ts),"classifierModel":"m","outputTokens":\#(output)}"# + "\n"
    }

    func makeDirectory(_ name: String) throws -> URL {
        try makeTempDirectory(name).resolvingSymlinksInPath()
    }

    @Test func unknownFileIsReadFromTheStart() throws {
        let dir = try makeDirectory("probe-new")
        defer { try? FileManager.default.removeItem(at: dir) }
        let content = line(1) + line(2)
        try Data(content.utf8).write(to: dir.appendingPathComponent(Self.fileName))

        let report = DecisionLogProbe().check(directories: [dir.path], known: [:])
        let canonical = Attributor.canonical(dir.path)
        #expect(report.canonical[dir.path] == canonical)
        guard case .found(let path, let size, _, let chunk) = report.results[dir.path] else {
            Issue.record("expected .found, got \(String(describing: report.results[dir.path]))")
            return
        }
        #expect(path == canonical + "/" + Self.fileName)
        #expect(size == content.utf8.count)
        #expect(chunk?.from == 0 && chunk?.data == Data(content.utf8))
        #expect(chunk?.fileID != nil)
    }

    @Test func grownFileIsReadFromTheParsedOffset() throws {
        let dir = try makeDirectory("probe-grown")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(Self.fileName)
        let first = line(1)
        try Data((first + line(2)).utf8).write(to: url)
        let path = Attributor.canonical(dir.path) + "/" + Self.fileName
        let known = [path: KnownLogState(size: first.utf8.count, modificationDate: .distantPast, parsedOffset: first.utf8.count)]

        let report = DecisionLogProbe().check(directories: [dir.path], known: known)
        guard case .found(_, _, _, let chunk) = report.results[dir.path] else {
            Issue.record("expected .found")
            return
        }
        #expect(chunk?.from == first.utf8.count && chunk?.data == Data(line(2).utf8))
    }

    @Test func fileShorterThanTheParsedOffsetIsReadFromTheStart() throws {
        let dir = try makeDirectory("probe-shorter")
        defer { try? FileManager.default.removeItem(at: dir) }
        let content = line(9)
        try Data(content.utf8).write(to: dir.appendingPathComponent(Self.fileName))
        let path = Attributor.canonical(dir.path) + "/" + Self.fileName
        let known = [path: KnownLogState(size: 1000, modificationDate: .distantPast, parsedOffset: 1000)]

        let report = DecisionLogProbe().check(directories: [dir.path], known: known)
        guard case .found(_, _, _, let chunk) = report.results[dir.path] else {
            Issue.record("expected .found")
            return
        }
        #expect(chunk?.from == 0 && chunk?.data == Data(content.utf8))
    }

    @Test func unchangedFileIsNotRead() throws {
        let dir = try makeDirectory("probe-unchanged")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(Self.fileName)
        try Data(line(1).utf8).write(to: url)
        let first = DecisionLogProbe().check(directories: [dir.path], known: [:])
        guard case .found(let path, let size, let date, _) = first.results[dir.path] else {
            Issue.record("expected .found")
            return
        }
        let known = [path: KnownLogState(size: size, modificationDate: date, parsedOffset: size)]
        let second = DecisionLogProbe().check(directories: [dir.path], known: known)
        #expect(second.results[dir.path] == .found(path: path, size: size, modificationDate: date, chunk: nil))
    }

    @Test func missingLogOrDirectoryIsAbsent() throws {
        let dir = try makeDirectory("probe-absent")
        defer { try? FileManager.default.removeItem(at: dir) }
        let gone = dir.appendingPathComponent("removed-worktree").path
        let report = DecisionLogProbe().check(directories: [dir.path, gone], known: [:])
        #expect(report.results[dir.path] == .absent)
        #expect(report.results[gone] == .absent)
        #expect(report.canonical[dir.path] == Attributor.canonical(dir.path))
    }

    /// FR-001: two spellings of one directory (a trailing slash, a
    /// symlinked parent) are one directory, whose log is reported once.
    @Test func spellingsOfOneDirectoryAreReportedOnce() throws {
        let root = try makeDirectory("probe-spellings")
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("real/W")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"),
                                                   withDestinationURL: root.appendingPathComponent("real"))
        try Data(line(1).utf8).write(to: real.appendingPathComponent(Self.fileName))
        let spellings = [real.path, real.path + "/", root.appendingPathComponent("link/W").path]

        let report = DecisionLogProbe().check(directories: spellings, known: [:])
        let canonical = Attributor.canonical(real.path)
        #expect(spellings.allSatisfy { report.canonical[$0] == canonical })
        let found = report.results.values.filter { if case .found = $0 { return true } else { return false } }
        #expect(found.count == 1)
    }

    // MARK: Time limit and in-flight checks (FR-012, research R4)

    /// A check closure that blocks on `gate` for directories in `blocking`
    /// and counts its calls per directory.
    final class Gate: @unchecked Sendable {
        let gate = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var calls: [String: Int] = [:]
        var blocking: Set<String> = []

        func calls(_ directory: String) -> Int { lock.lock(); defer { lock.unlock() }; return calls[directory] ?? 0 }

        func check(_ directory: String) -> ProbeResult {
            lock.lock()
            calls[directory, default: 0] += 1
            let blocks = blocking.contains(directory)
            lock.unlock()
            if blocks { gate.wait() }
            return .absent
        }

        func setBlocking(_ directories: Set<String>) { lock.lock(); blocking = directories; lock.unlock() }
    }

    /// Canonical spelling `/canon<raw>` without touching the file system.
    func probe(_ gate: Gate, timeout: TimeInterval = 0.2) -> DecisionLogProbe {
        DecisionLogProbe(timeout: timeout, canonicalize: { "/canon" + $0 }, check: { directory, _, _, _ in gate.check(directory) })
    }

    /// Calls `check` until the directory is no longer busy.
    func waitUntilIdle(_ probe: DecisionLogProbe, _ directory: String) -> ProbeReport {
        for _ in 0..<200 {
            let report = probe.check(directories: [directory], known: [:])
            if report.results[directory] != .busy { return report }
            Thread.sleep(forTimeInterval: 0.01)
        }
        Issue.record("directory stayed busy")
        return ProbeReport()
    }

    @Test func blockedCheckTimesOutWhileOthersFinish() {
        let gate = Gate()
        gate.setBlocking(["/canon/blocked"])
        defer { gate.gate.signal() }
        let probe = probe(gate)

        let started = Date()
        let report = probe.check(directories: ["/blocked", "/free"], known: [:])
        let elapsed = Date().timeIntervalSince(started)
        #expect(elapsed >= 0.15 && elapsed < 1.5, "took \(elapsed) s")
        #expect(report.results["/blocked"] == .timedOut)
        #expect(report.results["/free"] == .absent)
        #expect(report.canonical["/free"] == "/canon/free")
        // No check of it ever finished: no canonical directory known.
        #expect(report.canonical["/blocked"] == nil)
        #expect(report.newlyTimedOut == ["/blocked"])
    }

    @Test func timedOutDirectoryKeepsItsLastCanonicalDirectory() {
        let gate = Gate()
        let probe = probe(gate)
        #expect(probe.check(directories: ["/b"], known: [:]).canonical["/b"] == "/canon/b")
        gate.setBlocking(["/canon/b"])
        defer { gate.gate.signal() }
        let report = probe.check(directories: ["/b"], known: [:])
        #expect(report.results["/b"] == .timedOut)
        #expect(report.canonical["/b"] == "/canon/b")
    }

    @Test func runningCheckMakesTheDirectoryBusyUntilItFinishes() {
        let gate = Gate()
        gate.setBlocking(["/canon/b"])
        let probe = probe(gate)
        let first = probe.check(directories: ["/b"], known: [:])
        #expect(first.results["/b"] == .timedOut)
        #expect(first.newlyTimedOut == ["/b"])

        let second = probe.check(directories: ["/b"], known: [:])
        #expect(second.results["/b"] == .busy)
        #expect(second.newlyTimedOut.isEmpty)
        #expect(gate.calls("/canon/b") == 1)

        gate.setBlocking([])
        gate.gate.signal()
        let later = waitUntilIdle(probe, "/b")
        #expect(later.results["/b"] == .absent)
        #expect(gate.calls("/canon/b") == 2)

        // Finished again: a new time-out is reported again.
        gate.setBlocking(["/canon/b"])
        defer { gate.gate.signal() }
        let again = probe.check(directories: ["/b"], known: [:])
        #expect(again.results["/b"] == .timedOut)
        #expect(again.newlyTimedOut == ["/b"])
    }

    /// FR-012: while the timed-out check stays stuck, later refreshes see
    /// the directory busy and do not report it again.
    @Test func timedOutDirectoryIsReportedOnceWhileItsCheckIsStuck() {
        let gate = Gate()
        gate.setBlocking(["/canon/b"])
        defer { gate.gate.signal() }
        let probe = probe(gate)
        #expect(probe.check(directories: ["/b"], known: [:]).newlyTimedOut == ["/b"])
        for _ in 0..<3 {
            let report = probe.check(directories: ["/b"], known: [:])
            #expect(report.results["/b"] == .busy)
            #expect(report.newlyTimedOut.isEmpty)
        }
    }

    /// FR-012: "logged once per directory until a check of it finishes
    /// again": a check that returns after its time-out also finishes, so the
    /// next time-out is reported again.
    @Test func lateFinishLetsTheNextTimeOutBeReported() {
        let gate = Gate()
        gate.setBlocking(["/canon/b"])
        let probe = probe(gate)
        #expect(probe.check(directories: ["/b"], known: [:]).newlyTimedOut == ["/b"])
        // The stuck check returns late, and the next one hangs again.
        gate.gate.signal()
        waitUntilReturned(probe, "/b")
        defer { gate.gate.signal() }
        let report = probe.check(directories: ["/b"], known: [:])
        #expect(report.results["/b"] == .timedOut)
        #expect(report.newlyTimedOut == ["/b"])
    }

    @Test func defaultTimeoutIsTwoSeconds() {
        #expect(DecisionLogProbe().timeout == 2)
    }

    /// FR-012: standardizing the path is part of the check and falls under
    /// the same limit.
    @Test func blockedCanonicalizationTimesOut() {
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let probe = DecisionLogProbe(timeout: 0.2, canonicalize: { raw in
            if raw == "/hung" { gate.wait() }
            return raw
        }, check: { _, _, _, _ in .absent })
        let started = Date()
        let report = probe.check(directories: ["/hung", "/free"], known: [:])
        #expect(Date().timeIntervalSince(started) < 1.5)
        #expect(report.results["/hung"] == .timedOut)
        #expect(report.canonical["/hung"] == nil)
        #expect(report.results["/free"] == .absent)
        #expect(probe.check(directories: ["/hung"], known: [:]).results["/hung"] == .busy)
    }

    /// FR-012: while `maximumStuckChecks` checks are stuck, a directory
    /// without a check that finished in time is deferred; one whose last
    /// check finished in time continues. Once the stuck checks return, all
    /// run again.
    @Test func stuckChecksAboveTheLimitDeferNewDirectories() {
        let gate = Gate()
        let probe = DecisionLogProbe(timeout: 0.2, maximumStuckChecks: 2, canonicalize: { "/canon" + $0 },
                                     check: { directory, _, _, _ in gate.check(directory) })
        #expect(probe.check(directories: ["/healthy"], known: [:]).results["/healthy"] == .absent)
        gate.setBlocking(["/canon/a", "/canon/b"])
        let first = probe.check(directories: ["/a", "/b"], known: [:])
        #expect(first.results["/a"] == .timedOut && first.results["/b"] == .timedOut)

        let deferred = probe.check(directories: ["/c", "/healthy"], known: [:])
        #expect(deferred.results["/c"] == .busy)
        #expect(gate.calls("/canon/c") == 0)
        #expect(deferred.results["/healthy"] == .absent)
        #expect(gate.calls("/canon/healthy") == 2)

        gate.setBlocking([])
        gate.gate.signal()
        gate.gate.signal()
        let later = waitUntilIdle(probe, "/c")
        #expect(later.results["/c"] == .absent)
        #expect(gate.calls("/canon/c") == 1)
    }

    /// Waits until no check of `raw` is in flight, without starting one.
    func waitUntilReturned(_ probe: DecisionLogProbe, _ raw: String) {
        for _ in 0..<200 {
            if !probe.isInFlight(raw) { return }
            Thread.sleep(forTimeInterval: 0.01)
        }
        Issue.record("check of \(raw) never returned")
    }

    /// FR-012: a directory that answered in time once stays proven when a
    /// later check of it timed out and returned late: under the stuck cap
    /// it is still checked.
    @Test func directoryThatOnceAnsweredInTimeIsCheckedUnderTheCap() {
        let gate = Gate()
        let probe = DecisionLogProbe(timeout: 0.2, maximumStuckChecks: 2, canonicalize: { "/canon" + $0 },
                                     check: { directory, _, _, _ in gate.check(directory) })
        #expect(probe.check(directories: ["/h"], known: [:]).results["/h"] == .absent)
        gate.setBlocking(["/canon/h"])
        #expect(probe.check(directories: ["/h"], known: [:]).results["/h"] == .timedOut)
        gate.setBlocking([])
        gate.gate.signal()
        waitUntilReturned(probe, "/h")

        gate.setBlocking(["/canon/a", "/canon/b"])
        defer { gate.gate.signal(); gate.gate.signal() }
        let first = probe.check(directories: ["/a", "/b"], known: [:])
        #expect(first.results["/a"] == .timedOut && first.results["/b"] == .timedOut)

        let report = probe.check(directories: ["/h", "/c"], known: [:])
        #expect(report.results["/h"] == .absent)
        #expect(gate.calls("/canon/h") == 3)
        #expect(report.results["/c"] == .busy)
    }

    /// FR-012: a directory whose checks only ever returned late has no
    /// check that finished in time: under the stuck cap it is deferred.
    @Test func directoryThatOnlyReturnedLateIsDeferredUnderTheCap() {
        let gate = Gate()
        let probe = DecisionLogProbe(timeout: 0.2, maximumStuckChecks: 2, canonicalize: { "/canon" + $0 },
                                     check: { directory, _, _, _ in gate.check(directory) })
        gate.setBlocking(["/canon/n"])
        #expect(probe.check(directories: ["/n"], known: [:]).results["/n"] == .timedOut)
        gate.setBlocking([])
        gate.gate.signal()
        waitUntilReturned(probe, "/n")

        gate.setBlocking(["/canon/a", "/canon/b"])
        defer { gate.gate.signal(); gate.gate.signal() }
        let first = probe.check(directories: ["/a", "/b"], known: [:])
        #expect(first.results["/a"] == .timedOut && first.results["/b"] == .timedOut)

        let report = probe.check(directories: ["/n"], known: [:])
        #expect(report.results["/n"] == .busy)
        #expect(gate.calls("/canon/n") == 1)
        // The late check's canonical directory is still reported.
        #expect(report.canonical["/n"] == "/canon/n")
    }

    // MARK: Hostile files (FR-001, FR-012)

    @Test func symbolicLinkIsNotFollowed() throws {
        let dir = try makeDirectory("probe-symlink")
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("elsewhere.jsonl")
        try Data(line(1).utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent(Self.fileName), withDestinationURL: target)
        #expect(DecisionLogProbe().check(directories: [dir.path], known: [:]).results[dir.path] == .notRegular)
    }

    @Test func fifoIsNotOpened() throws {
        let dir = try makeDirectory("probe-fifo")
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(mkfifo(dir.appendingPathComponent(Self.fileName).path, 0o600) == 0)
        let started = Date()
        let report = DecisionLogProbe().check(directories: [dir.path], known: [:])
        #expect(report.results[dir.path] == .notRegular)
        #expect(Date().timeIntervalSince(started) < 1.5)
    }

    @Test func fileAboveTheLimitIsNotRead() throws {
        let dir = try makeDirectory("probe-large")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(Self.fileName)
        try Data(line(1).utf8).write(to: url)
        // Sparse: no 64 MB written to disk.
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(DecisionLogProbe.maximumSize + 1))
        try handle.close()
        let path = Attributor.canonical(dir.path) + "/" + Self.fileName
        #expect(DecisionLogProbe().check(directories: [dir.path], known: [:]).results[dir.path]
                == .tooLarge(path: path, size: DecisionLogProbe.maximumSize + 1))
    }

    /// A read that hangs after the `lstat` times out like a hung `lstat`.
    @Test func blockedReadTimesOut() throws {
        let dir = try makeDirectory("probe-blocked-read")
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(line(1).utf8).write(to: dir.appendingPathComponent(Self.fileName))
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let probe = DecisionLogProbe(timeout: 0.2, check: { directory, known, notBefore, readLimit in
            var info = stat()
            _ = lstat(DecisionLogProbe.logPath(inDirectory: directory), &info)
            gate.wait()
            return DecisionLogProbe.inspect(directory: directory, known: known, notBefore: notBefore, readLimit: readLimit)
        })
        let started = Date()
        let report = probe.check(directories: [dir.path], known: [:])
        #expect(report.results[dir.path] == .timedOut)
        #expect(Date().timeIntervalSince(started) < 1.5)
    }

    // MARK: Review findings of 2026-11-13

    @Test func defaultLimitsAreSixteenStuckAndSixtyFourNewChecksAndAFullRead() {
        let probe = DecisionLogProbe()
        #expect(probe.maximumStuckChecks == 16)
        #expect(probe.maximumChecksPerCall == 64)
        #expect(probe.maximumReadSize == DecisionLogProbe.maximumSize)
        #expect(probe.minimumReadSize == 512 * 1024)
    }

    /// FR-003, FR-012: a time-out cuts the directory's read limit to a
    /// quarter, down to the minimum; each check that finishes in time
    /// doubles it back up to the maximum.
    @Test func timeOutShrinksTheReadLimitAndInTimeChecksRaiseIt() {
        let gate = Gate()
        let received = CheckedDirectories()
        let probe = DecisionLogProbe(timeout: 0.2, maximumReadSize: 4096, minimumReadSize: 512, canonicalize: { "/canon" + $0 },
                                     check: { directory, _, _, limit in
                                         received.append(String(limit))
                                         return gate.check(directory)
                                     })
        gate.setBlocking(["/canon/x"])
        #expect(probe.check(directories: ["/x"], known: [:]).results["/x"] == .timedOut)
        #expect(probe.readLimit(for: "/x") == 1024)
        gate.setBlocking([])
        gate.gate.signal()
        waitUntilReturned(probe, "/x")
        gate.setBlocking(["/canon/x"])
        _ = probe.check(directories: ["/x"], known: [:])
        gate.setBlocking([])
        gate.gate.signal()
        waitUntilReturned(probe, "/x")
        #expect(probe.readLimit(for: "/x") == 512)
        #expect(probe.check(directories: ["/x"], known: [:]).results["/x"] == .absent)
        #expect(probe.readLimit(for: "/x") == 1024)
        _ = probe.check(directories: ["/x"], known: [:])
        _ = probe.check(directories: ["/x"], known: [:])
        #expect(probe.readLimit(for: "/x") == 4096)
        // Each check received the limit in force when it started.
        #expect(received.all == ["4096", "1024", "512", "1024", "2048"])
    }

    /// A directory whose check is still in flight is not forgotten, and its
    /// time-out state goes once it returned and stayed unnamed.
    @Test func stateOfAStuckDirectoryIsKeptUntilItsCheckReturns() {
        let gate = Gate()
        let probe = DecisionLogProbe(timeout: 0.2, forgetAfterCalls: 2, canonicalize: { "/canon" + $0 },
                                     check: { directory, _, _, _ in gate.check(directory) })
        gate.setBlocking(["/canon/h"])
        #expect(probe.check(directories: ["/h"], known: [:]).results["/h"] == .timedOut)
        _ = probe.check(directories: ["/a"], known: [:])
        _ = probe.check(directories: ["/a"], known: [:])
        #expect(probe.rememberedDirectories.contains("/h"))
        gate.setBlocking([])
        gate.gate.signal()
        waitUntilReturned(probe, "/h")
        _ = probe.check(directories: ["/a"], known: [:])
        #expect(probe.rememberedDirectories == ["/a"])
    }

    /// FR-012: at most `maximumChecksPerCall` new checks start in one call;
    /// the others are busy and go first in the next call.
    @Test func directoriesAboveThePerCallLimitWaitAndGoFirstNextTime() {
        let probe = DecisionLogProbe(maximumChecksPerCall: 2, canonicalize: { $0 }, check: { _, _, _, _ in .absent })
        let first = probe.check(directories: ["/a", "/b", "/c"], known: [:])
        #expect(first.results == ["/a": .absent, "/b": .absent, "/c": .busy])
        let second = probe.check(directories: ["/a", "/b", "/c"], known: [:])
        #expect(second.results == ["/a": .absent, "/b": .busy, "/c": .absent])
        let third = probe.check(directories: ["/a", "/b", "/c"], known: [:])
        #expect(third.results["/b"] == .absent)
    }

    /// The state of a directory not named for `forgetAfterCalls` calls is
    /// dropped, so it does not grow with every short-lived directory.
    @Test func stateOfDirectoriesNoLongerNamedIsDropped() {
        #expect(DecisionLogProbe().forgetAfterCalls == 100)
        let probe = DecisionLogProbe(forgetAfterCalls: 2, canonicalize: { $0 }, check: { _, _, _, _ in .absent })
        _ = probe.check(directories: ["/a", "/b"], known: [:])
        #expect(probe.rememberedDirectories == ["/a", "/b"])
        _ = probe.check(directories: ["/b"], known: [:])
        #expect(probe.rememberedDirectories == ["/a", "/b"])
        _ = probe.check(directories: ["/b"], known: [:])
        #expect(probe.rememberedDirectories == ["/b"])
    }

    /// FR-003: an existing log that cannot be read is no missing one, so
    /// its counted rows are not dropped.
    @Test func logThatCannotBeOpenedIsUnreadableNotAbsent() throws {
        let dir = try makeDirectory("probe-unreadable")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: dir.appendingPathComponent(Self.fileName).path)
            try? FileManager.default.removeItem(at: dir)
        }
        let url = dir.appendingPathComponent(Self.fileName)
        try Data(line(1).utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        #expect(DecisionLogProbe().check(directories: [dir.path], known: [:]).results[dir.path] == .unreadable)
    }

    /// FR-003: the same file changed without growing (rewritten in place)
    /// is read from the start.
    @Test func fileRewrittenInPlaceAtTheSameSizeIsReadFromTheStart() throws {
        let dir = try makeDirectory("probe-rewritten")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(Self.fileName)
        try Data(line(1).utf8).write(to: url)
        let first = DecisionLogProbe().check(directories: [dir.path], known: [:])
        guard case .found(let path, let size, let date, let chunk) = first.results[dir.path] else {
            Issue.record("expected .found")
            return
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.write(contentsOf: Data(line(2).utf8))
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: date.addingTimeInterval(60)], ofItemAtPath: url.path)
        let known = [path: KnownLogState(size: size, modificationDate: date, parsedOffset: size, fileID: chunk?.fileID)]
        let second = DecisionLogProbe().check(directories: [dir.path], known: known)
        guard case .found(_, _, _, let again) = second.results[dir.path] else {
            Issue.record("expected .found")
            return
        }
        #expect(again?.from == 0 && again?.data == Data(line(2).utf8))
    }

    /// FR-003, FR-012: at most `readLimit` bytes are read per check; the
    /// chunk says it stopped before the end.
    @Test func readStopsAtTheReadLimit() throws {
        let dir = try makeDirectory("probe-read-limit")
        defer { try? FileManager.default.removeItem(at: dir) }
        let content = line(1) + line(2) + line(3)
        try Data(content.utf8).write(to: dir.appendingPathComponent(Self.fileName))
        let limit = line(1).utf8.count + 5
        let partial = DecisionLogProbe.inspect(directory: Attributor.canonical(dir.path), known: [:], notBefore: .distantPast,
                                               readLimit: limit)
        guard case .found(_, let size, _, let chunk) = partial else {
            Issue.record("expected .found")
            return
        }
        #expect(chunk?.data.count == limit && chunk?.isPartial == true && size == limit)
        let whole = DecisionLogProbe.inspect(directory: Attributor.canonical(dir.path), known: [:], notBefore: .distantPast)
        guard case .found(_, _, _, let full) = whole else {
            Issue.record("expected .found")
            return
        }
        #expect(full?.data == Data(content.utf8) && full?.isPartial == false)
    }
}
