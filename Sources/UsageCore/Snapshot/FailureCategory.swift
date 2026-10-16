import Foundation

/// The kind of a failed request to a provider usage service (spec 010
/// FR-001, research R4). The same rules apply to the Claude usage service
/// and the Codex live limits service; the category decides the quick retry,
/// the stale marking and the wording.
public enum FailureCategory: String, Equatable, Sendable {
    /// No answer arrived (offline, name resolution, connection lost, timeout)
    /// or the service answered with HTTP 5xx.
    case transport
    /// HTTP 401 or 403.
    case signInRejected
    /// HTTP 429.
    case rateLimited
    /// An unreadable answer, a refused redirect, any other unexpected status
    /// or a Codex answer without main-bucket windows.
    case serviceChanged

    /// Classifies an error thrown by a usage client (spec 010 FR-001). Only
    /// our own error types are inspected; any other error type counts as a
    /// connection problem.
    public static func classify(_ error: Error) -> FailureCategory {
        if error as? CodexUsageError == .noLimits { return .serviceChanged }
        guard let endpoint = error as? UsageEndpointError else { return .transport }
        switch endpoint {
        case .network:
            return .transport
        case .rateLimited:
            return .rateLimited
        case .decoding:
            return .serviceChanged
        case .httpStatus(let code):
            switch code {
            case 401, 403: return .signInRejected
            case 500...599: return .transport
            default: return .serviceChanged
            }
        }
    }
}

/// The neutral note of a grace period (spec 010 FR-005): "Couldn't reach
/// the usage service" when no answer arrived, the failure text for an
/// HTTP 5xx answer. The view appends ", retrying at HH:MM".
public enum GraceNote {
    public static let unreachable = "Couldn't reach the usage service"

    /// For a Claude `.retrying` entry, from its error text.
    public static func reason(claudeError error: String) -> String {
        // Only a 5xx answer is a transport failure with an HTTP status
        // (`UsageEndpointError.httpStatus` text).
        error.hasPrefix("usage endpoint returned HTTP ") ? error : unreachable
    }

    /// For a Codex `.retrying` entry, from its stale reason.
    public static func reason(codexReason reason: String) -> String {
        reason == "offline" ? unreachable : reason
    }
}

/// The note of a rejected Claude sign-in (spec 010 FR-010): how to sign in
/// again, naming the credential directory when it is not the default one.
public enum SignInRejectedNote {
    /// "Sign-in rejected, run claude to sign in again", or with
    /// `CLAUDE_CONFIG_DIR=<directory as configured>` when the directory,
    /// expanded, differs from the expanded default `~/.claude`.
    public static func text(credentialDirectory: String, paths: Paths = Paths()) -> String {
        let isDefault = paths.expand(credentialDirectory) == paths.defaultClaudeDirectoryPath
        let command = isDefault ? "claude" : "CLAUDE_CONFIG_DIR=\(credentialDirectory) claude"
        return "Sign-in rejected, run \(command) to sign in again"
    }
}
