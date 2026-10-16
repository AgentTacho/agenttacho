import Foundation

/// One credential notification: which account, what failed and how to fix
/// it (spec 014 FR-009 to FR-011, contracts/notification-texts.md). Holds
/// no credential data, only the configured account and directory
/// (FR-010). It only formats: whether `directory` is the default one is the
/// tracker's decision.
public struct CredentialAlert: Equatable, Sendable {
    public enum Provider: String, Equatable, Sendable {
        case claude
        case codex
    }

    /// The failure kind; `rawValue` is the kind in the diagnostic log.
    public enum Kind: String, Equatable, Sendable {
        case rejected
        case notSignedIn
        /// Codex keeps its sign-in in the keychain (spec 014 clarification).
        case notReadable
        case expired
    }

    public let accountId: String
    /// The account's display name, as threshold notifications use it.
    public let accountName: String
    public let provider: Provider
    public let kind: Kind
    /// The credential directory (Claude) or Codex home as configured; nil
    /// when it is the default one.
    public let directory: String?

    public init(accountId: String, accountName: String, provider: Provider, kind: Kind, directory: String?) {
        self.accountId = accountId
        self.accountName = accountName
        self.provider = provider
        self.kind = kind
        self.directory = directory
    }

    /// The prefix of every credential notification identifier; the
    /// presenter removes leftovers from an earlier run by it (SC-005).
    public static let identifierPrefix = "credential-"

    /// Stable per account, so posting again replaces a delivered
    /// notification and a withdraw finds it (spec 014 FR-011).
    public static func identifier(accountId: String) -> String { identifierPrefix + accountId }

    public var identifier: String { Self.identifier(accountId: accountId) }

    public var title: String {
        switch kind {
        case .rejected: return "\(accountName): sign-in rejected"
        case .notSignedIn: return "\(accountName): no sign-in found"
        case .notReadable: return "\(accountName): sign-in not readable"
        case .expired: return "\(accountName): sign-in expired"
        }
    }

    public var body: String {
        switch kind {
        case .rejected: return "Run \(command) to sign in again."
        case .notSignedIn: return "Run \(command) to sign in."
        case .notReadable: return "Codex keeps its sign-in in the keychain, which AgentMeter cannot read."
        case .expired: return "Run \(command) to refresh it."
        }
    }

    /// The agent command, naming a non-default directory as spec 010
    /// FR-010 does (spec 014 FR-009).
    private var command: String {
        switch (provider, directory) {
        case (.claude, nil): return "claude"
        case (.claude, let directory?): return "CLAUDE_CONFIG_DIR=\(directory) claude"
        case (.codex, nil): return "codex"
        case (.codex, let directory?): return "CODEX_HOME=\(directory) codex"
        }
    }
}

/// What the credential tracker asks the presenter to do (spec 014 FR-003,
/// FR-007, FR-012).
public enum CredentialAlertEvent: Equatable, Sendable {
    /// Post the notification.
    case deliver(CredentialAlert)
    /// The notification fell due while the switch was off: only logged.
    case suppressed(CredentialAlert)
    /// Remove the account's delivered, pending or queued notification.
    case withdraw(accountId: String)

    /// The subject of the event's log line: `<accountId> <kind>` for deliver
    /// and suppressed, `<accountId>` for withdraw. The presenter adds the
    /// outcome prefix (spec 014 FR-010).
    public var logMessage: String {
        switch self {
        case .deliver(let alert), .suppressed(let alert): return "\(alert.accountId) \(alert.kind.rawValue)"
        case .withdraw(let accountId): return accountId
        }
    }
}
