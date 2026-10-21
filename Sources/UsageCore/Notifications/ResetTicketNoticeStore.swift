import Foundation

/// One delivered expiry step of an account's tickets with one expiry time
/// (spec 033 FR-016, data-model "ResetTicketNoticeKey"). The account id is
/// the configuration's, stable across renames; the expiry time is kept in
/// whole seconds.
public struct ResetTicketNoticeKey: Hashable, Sendable {
    public let accountId: String
    public let expiresAt: Date
    public let step: ResetTicketExpiryStep

    public init(accountId: String, expiresAt: Date, step: ResetTicketExpiryStep) {
        self.accountId = accountId
        self.expiresAt = Date(timeIntervalSince1970: expiresAt.timeIntervalSince1970.rounded(.down))
        self.step = step
    }

    /// `"<accountId>|<expiry epoch seconds>|<step>"` (research R5).
    var stored: String {
        "\(accountId)|\(Int64(expiresAt.timeIntervalSince1970))|\(step.rawValue)"
    }

    /// The latest epoch a stored entry may hold: the end of year 9999, the
    /// limit of ISO 8601 internet time. A larger value would trap when it is
    /// written back (spec 033 FR-016).
    static let maximumEpoch: Int64 = 253_402_300_799

    /// Reads `stored`; nil for anything else, an epoch outside 0 to
    /// `maximumEpoch` included. The account id may itself contain "|", so
    /// the epoch and the step are taken from the end.
    init?(stored text: String) {
        let parts = text.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count >= 3, let step = ResetTicketExpiryStep(rawValue: String(parts[parts.count - 1])),
              let epoch = Int64(parts[parts.count - 2]), (0...Self.maximumEpoch).contains(epoch) else { return nil }
        let accountId = parts.dropLast(2).joined(separator: "|")
        guard !accountId.isEmpty else { return nil }
        self.init(accountId: accountId, expiresAt: Date(timeIntervalSince1970: TimeInterval(epoch)), step: step)
    }
}

/// Where the expiry tracker keeps the steps it delivered, so a relaunch
/// does not deliver them again (spec 033 FR-016, research R5).
public protocol ResetTicketNoticeStore: Sendable {
    func load() -> Set<ResetTicketNoticeKey>
    func save(_ keys: Set<ResetTicketNoticeKey>)
}

/// The record in AgentTacho's own macOS defaults, an array of strings under
/// `freeResetNotices`; unreadable entries are ignored (spec 033 FR-016,
/// research R5). It holds no ticket, grant or credit identifier (FR-006).
public struct UserDefaultsResetTicketNoticeStore: ResetTicketNoticeStore, @unchecked Sendable {
    public static let key = "freeResetNotices"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func load() -> Set<ResetTicketNoticeKey> {
        Set((defaults.stringArray(forKey: Self.key) ?? []).compactMap(ResetTicketNoticeKey.init(stored:)))
    }

    public func save(_ keys: Set<ResetTicketNoticeKey>) {
        defaults.set(keys.map(\.stored).sorted(), forKey: Self.key)
    }
}

/// An in-memory record, for tests; one instance stands for one defaults
/// domain across simulated relaunches.
public final class InMemoryResetTicketNoticeStore: ResetTicketNoticeStore, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: Set<ResetTicketNoticeKey> = []

    public init() {}

    public func load() -> Set<ResetTicketNoticeKey> {
        lock.lock(); defer { lock.unlock() }
        return keys
    }

    public func save(_ keys: Set<ResetTicketNoticeKey>) {
        lock.lock(); defer { lock.unlock() }
        self.keys = keys
    }
}
