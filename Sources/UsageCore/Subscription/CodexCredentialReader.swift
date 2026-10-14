import Foundation

/// The parts of the Codex sign-in the app uses (spec 007 Key Entities,
/// research R3). Printing it never reveals the token or the account id
/// (FR-018).
public struct CodexCredential: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let accessToken: String
    /// Sent as `ChatGPT-Account-ID`; nil when the file has none.
    public let accountId: String?
    /// The access token's JWT `exp` claim; nil when unknown.
    public let expiresAt: Date?

    public init(accessToken: String, accountId: String?, expiresAt: Date?) {
        self.accessToken = accessToken
        self.accountId = accountId
        self.expiresAt = expiresAt
    }

    /// True when the token's expiry is known and at or before `now`. Only
    /// Codex renews it (FR-003).
    public func isExpired(now: Date) -> Bool {
        expiresAt.map { $0 <= now } ?? false
    }

    public var description: String {
        "CodexCredential(token: <redacted>, accountId: \(accountId == nil ? "nil" : "<redacted>"), expiresAt: \(expiresAt.map { "\($0)" } ?? "unknown"))"
    }

    public var debugDescription: String { description }
}

/// Result of reading a Codex home's sign-in (research R3).
public enum CodexCredentialLookup: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case found(CodexCredential)
    /// No usable plan sign-in; `reason` is shown as the stale reason.
    case missing(reason: String)

    public static let noPlanSignIn = "no Codex plan sign-in found in this Codex home"
    public static let keychain = "Codex keeps its sign-in in the keychain"

    public var description: String {
        switch self {
        case .found(let credential): return "found(\(credential))"
        case .missing(let reason): return "missing(\(reason))"
        }
    }

    public var debugDescription: String { description }
}

/// Reads the Codex sign-in of a Codex home at refresh time. Implementations
/// never write to the Codex home and never renew the sign-in (FR-002, FR-003).
public protocol CodexCredentialReader: Sendable {
    func read(codexHome: String) throws -> CodexCredentialLookup
}

/// A Codex sign-in file that could not be read. The message never contains
/// file content (FR-018).
public struct CodexCredentialError: Error, Equatable, Sendable, CustomStringConvertible, LocalizedError {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
    public var errorDescription: String? { message }
}

/// Reads `<codexHome>/auth.json` (contracts/codex-usage-endpoint.md section 2).
/// Only `auth_mode`, `tokens.access_token` and `tokens.account_id` are
/// decoded; the refresh token and id token are never decoded. When the file
/// is missing, `<codexHome>/config.toml` is checked for keychain storage.
public struct FileCodexCredentialReader: CodexCredentialReader {
    private let paths: Paths

    public init(paths: Paths = Paths()) {
        self.paths = paths
    }

    public func read(codexHome: String) throws -> CodexCredentialLookup {
        let home = URL(fileURLWithPath: paths.expand(codexHome), isDirectory: true)
        let file = home.appendingPathComponent("auth.json")
        guard FileManager.default.fileExists(atPath: file.path) else {
            return .missing(reason: Self.keychainStorage(configFile: home.appendingPathComponent("config.toml"))
                ? CodexCredentialLookup.keychain : CodexCredentialLookup.noPlanSignIn)
        }
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            throw CodexCredentialError("Codex sign-in file could not be read")
        }
        let auth: AuthFile
        do {
            auth = try JSONDecoder().decode(AuthFile.self, from: data)
        } catch {
            throw CodexCredentialError("Codex sign-in file is not in the expected format")
        }
        guard auth.auth_mode == "chatgpt", let token = auth.tokens?.access_token, !token.isEmpty else {
            return .missing(reason: CodexCredentialLookup.noPlanSignIn)
        }
        let accountId = auth.tokens?.account_id.flatMap { $0.isEmpty ? nil : $0 }
        return .found(CodexCredential(accessToken: token, accountId: accountId, expiresAt: Self.jwtExpiry(token)))
    }

    /// The minimal shape of `auth.json`; every other key is ignored.
    private struct AuthFile: Decodable {
        let auth_mode: String?
        let tokens: Tokens?

        struct Tokens: Decodable {
            let access_token: String?
            let account_id: String?
        }
    }

    /// True when the top-level `cli_auth_credentials_store` key of
    /// `config.toml` is `keyring` or `auto`. Read line by line; nothing else
    /// of the file is interpreted.
    static func keychainStorage(configFile: URL) -> Bool {
        guard let data = try? Data(contentsOf: configFile) else { return false }
        for rawLine in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // Keys after the first table header belong to that table.
            if line.hasPrefix("[") { return false }
            guard line.hasPrefix("cli_auth_credentials_store"), let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            guard key == "cli_auth_credentials_store" else { continue }
            var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if let hash = value.firstIndex(of: "#") { value = value[..<hash].trimmingCharacters(in: .whitespaces) }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return value == "keyring" || value == "auto"
        }
        return false
    }

    /// The `exp` claim of a JWT's payload, read locally (no signature check);
    /// nil for a token that is not a JWT or has no `exp`.
    static func jwtExpiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = payload["exp"] as? NSNumber, exp.doubleValue.isFinite else { return nil }
        return Date(timeIntervalSince1970: exp.doubleValue)
    }
}
