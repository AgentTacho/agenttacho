import Foundation

/// Collects notes about tolerated problems while a configuration file is
/// decoded, for example an unknown level color (spec 012 FR-003, research
/// R4). Passed through `JSONDecoder.userInfo` so `Configuration` stays free
/// of transient fields; the notes go to the diagnostic log, never to a
/// problem notice.
public final class ConfigurationLoadNotes: @unchecked Sendable {
    /// The `JSONDecoder.userInfo` key under which the collector is passed.
    public static let userInfoKey = CodingUserInfoKey(rawValue: "agenttacho.configurationLoadNotes")!

    private let lock = NSLock()
    private var collected: [String] = []

    public init() {}

    public func append(_ note: String) {
        lock.lock(); defer { lock.unlock() }
        collected.append(note)
    }

    public var notes: [String] {
        lock.lock(); defer { lock.unlock() }
        return collected
    }
}
