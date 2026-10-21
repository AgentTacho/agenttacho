import Foundation

/// The two lead times before a ticket's expiry at which a notification
/// falls due (spec 033 FR-014). `rawValue` is the label in identifiers, the
/// notice record and the log.
public enum ResetTicketExpiryStep: String, Sendable, Hashable, CaseIterable {
    case threeDays = "3d"
    case oneDay = "24h"

    /// The lead time: a group of tickets is inside the step's range when
    /// its expiry is less than this far away (spec 033 FR-014).
    public var leadTime: TimeInterval {
        switch self {
        case .threeDays: return 3 * 86400
        case .oneDay: return 86400
        }
    }
}

/// One expiry notification: the tickets of one account with one expiry
/// time at one step (spec 033 FR-014, FR-015, contracts/texts.md). Holds
/// the display name, the count and the time only, never a token, a service
/// identifier or credential data (FR-015).
public struct ResetTicketExpiryAlert: Equatable, Sendable {
    public let accountId: String
    /// The account's display name at the time the step fell due.
    public let accountName: String
    public let step: ResetTicketExpiryStep
    public let expiresAt: Date
    /// How many free limit resets expire at `expiresAt`.
    public let count: Int

    public init(accountId: String, accountName: String, step: ResetTicketExpiryStep, expiresAt: Date, count: Int) {
        self.accountId = accountId
        self.accountName = accountName
        self.step = step
        self.expiresAt = expiresAt
        self.count = count
    }

    /// The prefix of every expiry notification identifier.
    public static let identifierPrefix = "free-reset-"

    /// `free-reset-<accountId>-<expiry epoch seconds>-<3d|24h>`.
    public var identifier: String {
        "\(Self.identifierPrefix)\(accountId)-\(Int64(expiresAt.timeIntervalSince1970))-\(step.rawValue)"
    }

    /// "<account>: free limit reset expires within 3 days", plural for more
    /// than one ticket.
    public var title: String {
        let within = step == .threeDays ? "within 3 days" : "within 24 hours"
        return count == 1
            ? "\(accountName): free limit reset expires \(within)"
            : "\(accountName): free limit resets expire \(within)"
    }

    /// "1 free limit reset expires Fri 14:00." with the absolute form of the
    /// window reset texts (spec 033 FR-015).
    public func body(times: TimeText) -> String {
        let at = times.absolute(expiresAt)
        return count == 1 ? "1 free limit reset expires \(at)." : "\(count) free limit resets expire \(at)."
    }

    /// The diagnostic log line of a delivered or suppressed notification:
    /// the account id, the step and the expiry time (spec 033 FR-019).
    public func logMessage(suppressed: Bool) -> String {
        let at = ISO8601DateFormatter().string(from: expiresAt)
        return suppressed
            ? "free reset expiry \(step.rawValue) for \(accountId) not sent (switch off), expires \(at)"
            : "free reset expiry \(step.rawValue) for \(accountId), expires \(at)"
    }
}

/// What the expiry tracker asks the presenter to do (spec 033 FR-014,
/// FR-017).
public enum ResetTicketExpiryEvent: Equatable, Sendable {
    /// Post the notification.
    case deliver(ResetTicketExpiryAlert)
    /// The step fell due while the switch was off: only logged, and it
    /// counts as delivered.
    case suppressed(ResetTicketExpiryAlert)
}
