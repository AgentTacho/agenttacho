import CryptoKit
import Foundation

/// Reads the OAuth credential Claude Code stores for a configuration directory.
/// Implementations never write; the app target provides the Keychain version.
public protocol CredentialReader: Sendable {
    /// Returns nil when no credential is stored for the directory.
    func read(configDirectory: String) throws -> OAuthCredential?
}

/// Keychain service name derivation (research R4).
public enum KeychainServiceName {
    public static let base = "Claude Code-credentials"

    public static func `for`(configDirectory: String, paths: Paths = Paths()) -> String {
        let expanded = paths.expand(configDirectory)
        if expanded == paths.defaultClaudeDirectoryPath {
            return base
        }
        let digest = SHA256.hash(data: Data(expanded.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(base)-\(hex.prefix(8))"
    }
}

/// The parts of the stored credential the app uses. Printing it never reveals
/// the token (FR-011a).
public struct OAuthCredential: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let accessToken: String
    public let expiresAt: Date
    public let subscriptionType: String?

    public init(accessToken: String, expiresAt: Date, subscriptionType: String? = nil) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.subscriptionType = subscriptionType
    }

    public func isExpired(now: Date) -> Bool {
        now >= expiresAt
    }

    public var description: String {
        "OAuthCredential(token: <redacted>, expiresAt: \(expiresAt), subscriptionType: \(subscriptionType ?? "nil"))"
    }

    public var debugDescription: String { description }

    /// Decodes the keychain item JSON. Returns nil when it has no `claudeAiOauth` object.
    public static func decode(keychainJSON data: Data) throws -> OAuthCredential? {
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard let oauth = envelope.claudeAiOauth else { return nil }
        return OAuthCredential(accessToken: oauth.accessToken,
                               expiresAt: Date(timeIntervalSince1970: oauth.expiresAt / 1000),
                               subscriptionType: oauth.subscriptionType)
    }

    private struct Envelope: Decodable {
        let claudeAiOauth: Inner?
    }

    private struct Inner: Decodable {
        let accessToken: String
        let expiresAt: Double
        let subscriptionType: String?
    }
}
