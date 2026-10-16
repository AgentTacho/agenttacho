import Foundation

/// Which credential notifications this run posted, for the presenter
/// (spec 014 FR-007, FR-010, FR-011, contracts/notification-texts.md).
/// Posting is asynchronous: a post can complete after its withdrawal or
/// after a newer post under the same identifier. Every post gets a
/// generation; only the latest post of an identifier that was not withdrawn
/// counts as posted, so `credential withdrawn` is logged only for a
/// notification that reached Notification Center and is still current.
public struct CredentialPostLedger: Sendable {
    /// What a completed post means.
    public enum Completion: Equatable, Sendable {
        /// The latest post of its identifier: now counts as posted.
        case current
        /// Withdrawn while it was being posted: the notification may have
        /// reached Notification Center after the removal and must be
        /// removed again.
        case withdrawn
        /// A newer post under the same identifier replaced it: nothing to do.
        case superseded
    }

    private var generations: [String: Int] = [:]
    private var posted: Set<String> = []
    private var next = 0

    public init() {}

    /// Starts a post and returns its generation.
    public mutating func begin(_ identifier: String) -> Int {
        next += 1
        generations[identifier] = next
        return next
    }

    /// A post that succeeded.
    public mutating func completed(_ identifier: String, generation: Int) -> Completion {
        guard let current = generations[identifier] else { return .withdrawn }
        guard current == generation else { return .superseded }
        posted.insert(identifier)
        return .current
    }

    /// Forgets the identifier; true when a post of it had completed, so the
    /// withdrawal is logged.
    public mutating func withdraw(_ identifier: String) -> Bool {
        generations[identifier] = nil
        return posted.remove(identifier) != nil
    }
}
