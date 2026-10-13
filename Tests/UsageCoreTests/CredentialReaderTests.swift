import Foundation
import Testing
@testable import UsageCore

@Suite struct CredentialReaderTests {
    @Test func defaultDirectoryUsesPlainServiceName() {
        let paths = Paths(home: URL(fileURLWithPath: "/Users/rhuss"))
        #expect(KeychainServiceName.for(configDirectory: "~/.claude", paths: paths) == "Claude Code-credentials")
        #expect(KeychainServiceName.for(configDirectory: "~/.claude/", paths: paths) == "Claude Code-credentials")
        #expect(KeychainServiceName.for(configDirectory: "/Users/rhuss/.claude", paths: paths) == "Claude Code-credentials")
    }

    @Test func otherDirectoriesUseHashSuffix() {
        let paths = Paths(home: URL(fileURLWithPath: "/Users/rhuss"))
        let expected = "Claude Code-credentials-bf7c1594"
        #expect(KeychainServiceName.for(configDirectory: "/Users/rhuss/.local/share/cc-deck/profiles/private/claude", paths: paths) == expected)
        #expect(KeychainServiceName.for(configDirectory: "~/.local/share/cc-deck/profiles/private/claude", paths: paths) == expected)
        #expect(KeychainServiceName.for(configDirectory: "~/.local/share/cc-deck/profiles/private/claude/", paths: paths) == expected)
        #expect(KeychainServiceName.for(configDirectory: "~/.local/share/cc-deck/profiles/work/claude", paths: paths) == "Claude Code-credentials-4381c536")
    }

    @Test func decodesClaudeAiOauth() throws {
        let json = """
        {
          "claudeAiOauth": {
            "accessToken": "SECRET-TOKEN-123",
            "refreshToken": "SECRET-REFRESH",
            "expiresAt": 1760000000000,
            "scopes": ["user:inference"],
            "subscriptionType": "max",
            "rateLimitTier": "default_claude_max_20x"
          },
          "mcpOAuth": { "x": { "accessToken": "other" } }
        }
        """
        let credential = try #require(try OAuthCredential.decode(keychainJSON: Data(json.utf8)))
        #expect(credential.accessToken == "SECRET-TOKEN-123")
        #expect(credential.expiresAt == Date(timeIntervalSince1970: 1_760_000_000))
        #expect(credential.subscriptionType == "max")
        #expect(credential.isExpired(now: Date(timeIntervalSince1970: 1_759_999_999)) == false)
        #expect(credential.isExpired(now: Date(timeIntervalSince1970: 1_760_000_000)) == true)
        #expect(credential.isExpired(now: Date(timeIntervalSince1970: 1_760_000_001)) == true)
        #expect(!String(describing: credential).contains("SECRET"))
        #expect(!"\(credential)".contains("SECRET"))
    }

    @Test func jsonWithoutClaudeAiOauthDecodesToNil() throws {
        let json = """
        { "mcpOAuth": { "x": { "accessToken": "other", "expiresAt": 1 } } }
        """
        #expect(try OAuthCredential.decode(keychainJSON: Data(json.utf8)) == nil)
    }

    @Test func malformedJSONThrows() {
        #expect(throws: (any Error).self) {
            try OAuthCredential.decode(keychainJSON: Data("not json".utf8))
        }
    }
}
