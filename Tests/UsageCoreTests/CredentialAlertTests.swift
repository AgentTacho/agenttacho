import Foundation
import Testing
@testable import UsageCore

/// spec 014 FR-009 to FR-011, contracts/notification-texts.md.
@Suite struct CredentialAlertTests {
    private func alert(_ provider: CredentialAlert.Provider, _ kind: CredentialAlert.Kind, directory: String? = nil,
                       name: String = "Claude (Work)") -> CredentialAlert {
        CredentialAlert(accountId: "acc-1", accountName: name, provider: provider, kind: kind, directory: directory)
    }

    @Test func claudeTextsWithTheDefaultDirectory() {
        let rejected = alert(.claude, .rejected)
        #expect(rejected.title == "Claude (Work): sign-in rejected")
        #expect(rejected.body == "Run claude to sign in again.")
        let missing = alert(.claude, .notSignedIn)
        #expect(missing.title == "Claude (Work): no sign-in found")
        #expect(missing.body == "Run claude to sign in.")
        let expired = alert(.claude, .expired)
        #expect(expired.title == "Claude (Work): sign-in expired")
        #expect(expired.body == "Run claude to refresh it.")
    }

    @Test func claudeTextsWithAnotherDirectory() {
        #expect(alert(.claude, .rejected, directory: "~/.claude-work").body
            == "Run CLAUDE_CONFIG_DIR=~/.claude-work claude to sign in again.")
        #expect(alert(.claude, .notSignedIn, directory: "~/.claude-work").body
            == "Run CLAUDE_CONFIG_DIR=~/.claude-work claude to sign in.")
        #expect(alert(.claude, .expired, directory: "/Users/me/.claude-b").body
            == "Run CLAUDE_CONFIG_DIR=/Users/me/.claude-b claude to refresh it.")
    }

    @Test func codexTextsWithTheDefaultHome() {
        let rejected = alert(.codex, .rejected, name: "Codex")
        #expect(rejected.title == "Codex: sign-in rejected")
        #expect(rejected.body == "Run codex to sign in again.")
        let missing = alert(.codex, .notSignedIn, name: "Codex")
        #expect(missing.title == "Codex: no sign-in found")
        #expect(missing.body == "Run codex to sign in.")
        let expired = alert(.codex, .expired, name: "Codex")
        #expect(expired.title == "Codex: sign-in expired")
        #expect(expired.body == "Run codex to refresh it.")
        let keychain = alert(.codex, .notReadable, name: "Codex")
        #expect(keychain.title == "Codex: sign-in not readable")
        #expect(keychain.body == "Codex keeps its sign-in in the keychain, which AgentTacho cannot read.")
    }

    @Test func codexTextsWithAnotherHome() {
        #expect(alert(.codex, .rejected, directory: "~/.codex-work").body == "Run CODEX_HOME=~/.codex-work codex to sign in again.")
        #expect(alert(.codex, .notSignedIn, directory: "~/.codex-work").body == "Run CODEX_HOME=~/.codex-work codex to sign in.")
        #expect(alert(.codex, .expired, directory: "~/.codex-work").body == "Run CODEX_HOME=~/.codex-work codex to refresh it.")
        // The keychain text names no command, so the home does not change it.
        #expect(alert(.codex, .notReadable, directory: "~/.codex-work").body
            == "Codex keeps its sign-in in the keychain, which AgentTacho cannot read.")
    }

    @Test func identifierIsPerAccount() {
        #expect(alert(.claude, .rejected).identifier == "credential-acc-1")
        #expect(alert(.codex, .expired, directory: "~/x").identifier == "credential-acc-1")
        #expect(CredentialAlert.identifier(accountId: "acc-1") == "credential-acc-1")
        #expect(alert(.claude, .rejected).identifier.hasPrefix(CredentialAlert.identifierPrefix))
    }

    @Test func logMessages() {
        let rejected = alert(.claude, .rejected)
        #expect(CredentialAlertEvent.deliver(rejected).logMessage == "acc-1 rejected")
        #expect(CredentialAlertEvent.suppressed(alert(.codex, .notSignedIn)).logMessage == "acc-1 notSignedIn")
        #expect(CredentialAlertEvent.deliver(alert(.codex, .notReadable)).logMessage == "acc-1 notReadable")
        #expect(CredentialAlertEvent.deliver(alert(.claude, .expired)).logMessage == "acc-1 expired")
        #expect(CredentialAlertEvent.withdraw(accountId: "acc-1").logMessage == "acc-1")
    }

    /// The log line names the account id and kind only, never the display
    /// name or directory (FR-010).
    @Test func logMessageCarriesNothingElse() {
        let event = CredentialAlertEvent.deliver(alert(.claude, .rejected, directory: "~/.claude-secret", name: "Private name"))
        #expect(!event.logMessage.contains("secret"))
        #expect(!event.logMessage.contains("Private"))
    }
}
