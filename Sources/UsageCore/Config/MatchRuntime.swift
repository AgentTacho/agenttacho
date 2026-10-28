import Foundation

/// A condition ready for matching: its matcher is compiled once, not per
/// record (spec 038 research R2, R4, data-model "CompiledCondition").
struct CompiledCondition: @unchecked Sendable {
    let condition: MatchCondition
    /// The compiled matcher, a literal one for starts with and contains
    /// (spec 038 SC-005); nil for an invalid pattern, which never matches
    /// (spec 038 FR-008), and for a blank text.
    let matcher: NSRegularExpression?

    init(_ condition: MatchCondition) {
        self.condition = condition
        matcher = condition.hasBlankText ? nil : MatchCondition.compile(condition.operator, condition.text)
    }

    /// True for a regex, the only operator that can time out.
    var isRegex: Bool { condition.operator == .regex }

    /// The value the condition compares: its field, or the raw line for
    /// Anywhere.
    func value(record: RawUsageRecord, rawLine: String) -> String {
        condition.field.value(of: record, rawLine: rawLine)
    }

    /// The outcome on `value`: the precompiled matcher, a regex within
    /// `limit` (spec 038 FR-007).
    func outcome(value: String, limit: Duration) -> MatchCondition.RegexOutcome {
        guard let matcher else { return .noMatch }
        return MatchCondition.find(matcher, condition.operator, in: value, limit: limit)
    }
}

/// What a source keeps of its match runtime from one refresh to the next,
/// so a slow regex costs a bounded amount of work over all refreshes (spec
/// 038 FR-007, SC-005). It belongs to one attributor fingerprint; a rule
/// change starts it empty.
public struct MatchMemory: Equatable, Sendable {
    /// The attributor fingerprint the memory belongs to.
    var fingerprint: String?
    /// Per rule, hashes of the field values it ran out of time on: they
    /// count as no match without running the regex again.
    var slowValues: [String: Set<Int>] = [:]
    /// Rules that ran out of time again while records were attributed once
    /// more: their sitting out no longer marks records for another
    /// attribution.
    var givenUp: Set<String> = []
    /// At most this many slow values are kept per rule.
    static let slowValueLimit = 1_000

    public init() {}

    init(fingerprint: String) {
        self.fingerprint = fingerprint
    }
}

/// The conditions of one attributor, that is of one source and refresh,
/// with the time limit per record and the rules that sit out (spec 038
/// FR-007, research R3 to R5). A rule whose regex runs longer than the
/// limit on one record counts as no match there and matches no further
/// record of this runtime; the next refresh builds a new runtime and tries
/// again. Shared by copies of the attributor, so it is a lock-protected
/// class.
public final class MatchRuntime: @unchecked Sendable {
    /// One candidate: its id, the account's display name for the log line,
    /// and its condition.
    public struct Entry: Sendable {
        public let id: String
        public let name: String
        public let condition: MatchCondition

        public init(id: String, name: String, condition: MatchCondition) {
            self.id = id
            self.name = name
            self.condition = condition
        }
    }

    private let rules: [String: CompiledCondition]
    private let names: [String: String]
    private let limit: Duration
    private let lock = NSLock()
    private var sittingOut: Set<String> = []
    private var timeOutCount = 0
    private var skippedCount = 0
    /// Skipped decisions per rule, so a retry tells which rule skipped
    /// where (spec 038 FR-007).
    private var skippedById: [String: Int] = [:]
    private var pendingSitOuts: [String] = []
    private var memoryState: MatchMemory

    /// `limit` is the time limit per record, 50 ms by default (spec 038
    /// FR-007); tests inject a shorter one. `memory` is what the source
    /// kept from its last refresh.
    public init(rules: [Entry], limit: Duration = MatchCondition.regexLimit, memory: MatchMemory = MatchMemory()) {
        self.memoryState = memory
        var compiled: [String: CompiledCondition] = [:]
        var names: [String: String] = [:]
        for entry in rules {
            compiled[entry.id] = CompiledCondition(entry.condition)
            names[entry.id] = entry.name
        }
        self.rules = compiled
        self.names = names
        self.limit = limit
    }

    /// True when the rule of `candidateId` claims `record`. A rule that sits
    /// out returns false without matching; a time-out returns false, makes
    /// the rule sit out and remembers the value, which then counts as no
    /// match without running again (spec 038 FR-007, SC-005). Callers check
    /// the harness first, so a rule only runs, and only times out, on
    /// records of its own harness.
    public func matches(candidateId: String, record: RawUsageRecord, rawLine: String) -> Bool {
        guard let compiled = rules[candidateId] else { return false }
        let known = lock.withLock { () -> Set<Int>? in
            guard !sittingOut.contains(candidateId) else {
                skippedCount += 1
                skippedById[candidateId, default: 0] += 1
                return nil
            }
            return memoryState.slowValues[candidateId] ?? []
        }
        guard let known else { return false }
        let value = compiled.value(record: record, rawLine: rawLine)
        if compiled.isRegex, !known.isEmpty, known.contains(value.hashValue) { return false }
        switch compiled.outcome(value: value, limit: limit) {
        case .match:
            return true
        case .noMatch:
            return false
        case .timedOut:
            lock.withLock {
                // Two concurrent time-outs of the same rule count once.
                if sittingOut.insert(candidateId).inserted {
                    timeOutCount += 1
                    pendingSitOuts.append(names[candidateId] ?? candidateId)
                }
                if memoryState.slowValues[candidateId, default: []].count < MatchMemory.slowValueLimit {
                    memoryState.slowValues[candidateId, default: []].insert(value.hashValue)
                }
                skippedCount += 1
                skippedById[candidateId, default: 0] += 1
            }
            return false
        }
    }

    /// How many rules timed out in this runtime; the sources attribute
    /// stored records again on the next refresh when it is not zero (spec
    /// 038 research R5).
    public var timeOuts: Int { lock.withLock { timeOutCount } }

    /// Grows on every time-out and on every record a sat-out rule was
    /// skipped for, so `LogIndex` can tell which files a skipped rule could
    /// have decided differently (spec 038 research R5).
    public var skippedDecisions: Int { lock.withLock { skippedCount } }

    /// The skipped decisions per rule and the rules that timed out so far,
    /// for `Attributor.tracking` (spec 038 FR-007).
    struct Snapshot: Equatable {
        let skipped: [String: Int]
        let timedOut: Set<String>
    }

    func snapshot() -> Snapshot {
        lock.withLock { Snapshot(skipped: skippedById, timedOut: sittingOut) }
    }

    /// True when, between `before` and `after`, a rule skipped a decision
    /// that must be made again on the next refresh. A rule that times out
    /// in a `retry` (the second attribution of the same records, which
    /// already skips the value it was slow on) is slow on more than one
    /// record: it is given up for this memory, and its skips mark nothing
    /// from then on (spec 038 FR-007, SC-005).
    func needsReattribution(from before: Snapshot, to after: Snapshot, retry: Bool) -> Bool {
        lock.withLock {
            var again = false
            for (id, count) in after.skipped where count != before.skipped[id, default: 0] {
                let timedOutHere = after.timedOut.contains(id) && !before.timedOut.contains(id)
                if retry && timedOutHere { memoryState.givenUp.insert(id) }
                if !memoryState.givenUp.contains(id) { again = true }
            }
            return again
        }
    }

    /// What the source keeps for its next refresh.
    public var memory: MatchMemory { lock.withLock { memoryState } }

    /// The display names of the accounts whose rule started sitting out
    /// since the last call, in order, for one log line each (spec 038
    /// FR-007).
    public func drainSitOutAccounts() -> [String] {
        lock.withLock {
            defer { pendingSitOuts = [] }
            return pendingSitOuts
        }
    }
}
