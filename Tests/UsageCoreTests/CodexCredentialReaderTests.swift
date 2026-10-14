import Foundation
import Testing
@testable import UsageCore

/// A synthetic JWT (header.payload.signature, base64url) for tests; never a
/// real token.
func syntheticJWT(exp: Date?, extra: [String: Any] = [:]) -> String {
    func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    var payload = extra
    if let exp { payload["exp"] = Int(exp.timeIntervalSince1970) }
    let header = try! JSONSerialization.data(withJSONObject: ["alg": "none", "typ": "JWT"])
    let body = try! JSONSerialization.data(withJSONObject: payload)
    return "\(base64url(header)).\(base64url(body)).c2lnbmF0dXJl"
}

/// Writes a Codex `auth.json` into `home`.
func writeCodexAuth(_ home: URL, mode: String? = "chatgpt", accessToken: String?, accountId: String? = "acct-test",
                    refreshToken: String = "REFRESH-SENTINEL", idToken: String = "ID-SENTINEL") throws {
    var tokens: [String: Any] = ["refresh_token": refreshToken, "id_token": idToken]
    if let accessToken { tokens["access_token"] = accessToken }
    if let accountId { tokens["account_id"] = accountId }
    var object: [String: Any] = ["OPENAI_API_KEY": NSNull(), "tokens": tokens, "last_refresh": "2026-10-14T08:00:00Z"]
    if let mode { object["auth_mode"] = mode }
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: object).write(to: home.appendingPathComponent("auth.json"))
}

/// spec 007 FR-002, FR-003, FR-018, research R3.
@Suite struct CodexCredentialReaderTests {
    let reader = FileCodexCredentialReader()

    @Test func chatgptSignInIsFoundWithExpiry() throws {
        let home = try makeTempDirectory("codex-cred-ok")
        defer { try? FileManager.default.removeItem(at: home) }
        let exp = isoDate("2026-10-20T10:00:00Z")
        let token = syntheticJWT(exp: exp)
        try writeCodexAuth(home, accessToken: token, accountId: "acct-1")
        let lookup = try reader.read(codexHome: home.path)
        #expect(lookup == .found(CodexCredential(accessToken: token, accountId: "acct-1", expiresAt: exp)))
    }

    @Test func nonJWTTokenHasNoExpiry() throws {
        let home = try makeTempDirectory("codex-cred-opaque")
        defer { try? FileManager.default.removeItem(at: home) }
        try writeCodexAuth(home, accessToken: "opaque-token", accountId: nil)
        let lookup = try reader.read(codexHome: home.path)
        #expect(lookup == .found(CodexCredential(accessToken: "opaque-token", accountId: nil, expiresAt: nil)))
        // A JWT without `exp` has no expiry either.
        try writeCodexAuth(home, accessToken: syntheticJWT(exp: nil, extra: ["sub": "x"]))
        guard case .found(let credential) = try reader.read(codexHome: home.path) else {
            Issue.record("expected a credential"); return
        }
        #expect(credential.expiresAt == nil)
    }

    @Test func apiKeyModeIsNoPlanSignIn() throws {
        let home = try makeTempDirectory("codex-cred-apikey")
        defer { try? FileManager.default.removeItem(at: home) }
        try writeCodexAuth(home, mode: "apikey", accessToken: nil, accountId: nil)
        #expect(try reader.read(codexHome: home.path) == .missing(reason: CodexCredentialLookup.noPlanSignIn))
        #expect(CodexCredentialLookup.noPlanSignIn == "no Codex plan sign-in found in this Codex home")
    }

    @Test func chatgptModeWithoutAccessTokenIsNoPlanSignIn() throws {
        let home = try makeTempDirectory("codex-cred-notoken")
        defer { try? FileManager.default.removeItem(at: home) }
        try writeCodexAuth(home, accessToken: nil)
        #expect(try reader.read(codexHome: home.path) == .missing(reason: CodexCredentialLookup.noPlanSignIn))
        try writeCodexAuth(home, accessToken: "")
        #expect(try reader.read(codexHome: home.path) == .missing(reason: CodexCredentialLookup.noPlanSignIn))
    }

    @Test func missingFileWithKeychainStorage() throws {
        let home = try makeTempDirectory("codex-cred-keyring")
        defer { try? FileManager.default.removeItem(at: home) }
        let config = home.appendingPathComponent("config.toml")
        #expect(try reader.read(codexHome: home.path) == .missing(reason: CodexCredentialLookup.noPlanSignIn))
        for value in ["\"keyring\"", "'auto'", "\"keyring\" # comment"] {
            try Data("model = \"gpt-5.5\"\ncli_auth_credentials_store = \(value)\n\n[tui]\nnotifications = true\n".utf8).write(to: config)
            #expect(try reader.read(codexHome: home.path) == .missing(reason: CodexCredentialLookup.keychain), "\(value)")
        }
        #expect(CodexCredentialLookup.keychain == "Codex keeps its sign-in in the keychain")
        try Data("cli_auth_credentials_store = \"file\"\n".utf8).write(to: config)
        #expect(try reader.read(codexHome: home.path) == .missing(reason: CodexCredentialLookup.noPlanSignIn))
        // A key inside a table is not the top-level setting.
        try Data("[profiles.x]\ncli_auth_credentials_store = \"keyring\"\n".utf8).write(to: config)
        #expect(try reader.read(codexHome: home.path) == .missing(reason: CodexCredentialLookup.noPlanSignIn))
    }

    @Test func malformedFileThrowsWithoutItsContent() throws {
        let home = try makeTempDirectory("codex-cred-malformed")
        defer { try? FileManager.default.removeItem(at: home) }
        try Data("{\"auth_mode\": \"chatgpt\", \"tokens\": {\"access_token\": \"SECRET-PARTIAL".utf8)
            .write(to: home.appendingPathComponent("auth.json"))
        do {
            _ = try reader.read(codexHome: home.path)
            Issue.record("expected an error")
        } catch {
            #expect(!String(describing: error).contains("SECRET"))
            #expect(!String(reflecting: error).contains("SECRET"))
            #expect(!error.localizedDescription.contains("SECRET"))
        }
    }

    @Test func credentialDescriptionsAreRedacted() throws {
        let credential = CodexCredential(accessToken: "SECRET-CODEX-TOKEN-123", accountId: "SECRET-ACCOUNT-456",
                                         expiresAt: isoDate("2026-10-20T10:00:00Z"))
        for text in [String(describing: credential), String(reflecting: credential),
                     String(describing: CodexCredentialLookup.found(credential)),
                     String(reflecting: CodexCredentialLookup.found(credential))] {
            #expect(!text.contains("SECRET"), "\(text)")
        }
    }

    /// FR-003, SC-004: reading never changes the Codex home.
    @Test func readingDoesNotModifyTheFile() throws {
        let home = try makeTempDirectory("codex-cred-immutable")
        defer { try? FileManager.default.removeItem(at: home) }
        try writeCodexAuth(home, accessToken: syntheticJWT(exp: isoDate("2026-10-20T10:00:00Z")))
        let file = home.appendingPathComponent("auth.json")
        let past = isoDate("2026-10-01T00:00:00Z")
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: file.path)
        let before = try Data(contentsOf: file)
        _ = try reader.read(codexHome: home.path)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect(attributes[.modificationDate] as? Date == past)
        #expect(try Data(contentsOf: file) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: home.path) == ["auth.json"])
    }

    @Test func tildeIsExpanded() throws {
        let fakeHome = try makeTempDirectory("codex-cred-tilde")
        defer { try? FileManager.default.removeItem(at: fakeHome) }
        try writeCodexAuth(fakeHome.appendingPathComponent(".codex-x"), accessToken: "opaque")
        let reader = FileCodexCredentialReader(paths: Paths(home: fakeHome))
        guard case .found = try reader.read(codexHome: "~/.codex-x") else {
            Issue.record("expected a credential"); return
        }
    }
}
