import Foundation
import Testing
@testable import UsageCore

@Suite struct SecurityToolCredentialReaderTests {
    let paths = Paths(home: URL(fileURLWithPath: "/Users/rhuss"))

    private static let credentialJSON = """
    {"claudeAiOauth":{"accessToken":"SECRET-TOKEN-123","refreshToken":"SECRET-REFRESH","expiresAt":1760000000000,"subscriptionType":"max"}}
    """

    /// Records the arguments of the last run.
    final class Recorder: @unchecked Sendable {
        var arguments: [String] = []
    }

    @Test func runsFindGenericPasswordForTheDirectorysService() throws {
        let recorder = Recorder()
        let reader = SecurityToolCredentialReader(paths: paths) { arguments in
            recorder.arguments = arguments
            return .init(status: 0, stdout: Data((Self.credentialJSON + "\n").utf8), stderr: Data())
        }
        let credential = try #require(try reader.read(configDirectory: "~/.local/share/cc-deck/profiles/private/claude"))
        #expect(recorder.arguments == ["find-generic-password", "-s", "Claude Code-credentials-bf7c1594", "-w"])
        #expect(credential.accessToken == "SECRET-TOKEN-123")
        #expect(credential.subscriptionType == "max")
    }

    @Test func missingItemMeansNotSignedIn() throws {
        let reader = SecurityToolCredentialReader(paths: paths) { _ in
            .init(status: 44, stdout: Data(), stderr: Data("security: SecKeychainSearchCopyNext: The specified item could not be found in the keychain.\n".utf8))
        }
        #expect(try reader.read(configDirectory: "~/.claude") == nil)
        #expect(reader.hasDefaultCredential() == false)
    }

    @Test func otherFailuresReportTheToolMessageWithoutTheSecret() {
        let reader = SecurityToolCredentialReader(paths: paths) { _ in
            .init(status: 51, stdout: Data(Self.credentialJSON.utf8), stderr: Data("security: user interaction is not allowed\n".utf8))
        }
        do {
            _ = try reader.read(configDirectory: "~/.claude")
            Issue.record("expected an error")
        } catch {
            let text = "\(error)"
            #expect(text.contains("51"))
            #expect(text.contains("user interaction is not allowed"))
            #expect(!text.contains("SECRET"))
        }
    }

    @Test func itemWithoutClaudeAiOauthIsNotSignedIn() throws {
        let reader = SecurityToolCredentialReader(paths: paths) { _ in
            .init(status: 0, stdout: Data("{\"mcpOAuth\":{}}\n".utf8), stderr: Data())
        }
        #expect(try reader.read(configDirectory: "~/.claude") == nil)
    }

    /// Pins the exit code the reader relies on, against the real tool, with
    /// a service name that cannot exist (no keychain dialog, nothing read).
    @Test func realToolReportsAMissingItemWithExitCode44() throws {
        let output = try SecurityToolCredentialReader.runSecurityTool(
            ["find-generic-password", "-s", "agenttacho-test-\(UUID().uuidString)", "-w"])
        #expect(output.status == SecurityToolCredentialReader.itemNotFoundStatus)
        #expect(output.stdout.isEmpty)
    }
}
