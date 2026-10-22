import Testing
@testable import UsageCore

/// spec 034 FR-006, FR-007, FR-013, contracts/settings-layout.md: the
/// labels, prompts and captions of the account directory fields and the
/// Sources page.
@Suite struct AccountDirectoryTextTests {
    @Test func labelsAndSections() {
        #expect(AccountDirectoryText.claudeCodeDirectoryLabel == "Claude Code directory")
        #expect(AccountDirectoryText.codexHomeLabel == "Codex home")
        #expect(AccountDirectoryText.tokenBasedLabel(for: .vertex) == "Claude Code directory")
        #expect(AccountDirectoryText.tokenBasedLabel(for: .openai) == "Codex home")
        #expect(AccountDirectoryText.usageSourceSection == "Usage source")
        #expect(AccountDirectoryText.sourcesAccountsSection == "Claude Code and Codex")
    }

    @Test func subscriptionCaptions() {
        #expect(AccountDirectoryText.subscriptionCaption
                == "The Claude Code directory this account runs from: its sessions and its login come from here. Leave it empty for ~/.claude, or enter a profile directory such as ~/.claude-personal. Use the directory you run Claude Code with, so its login stays fresh.")
        #expect(AccountDirectoryText.codexSubscriptionCaption
                == "The Codex home this ChatGPT plan runs from: its sessions are read from here and, with live limits on, its sign-in. Leave it empty for ~/.codex, or enter another home such as ~/.codex-lab.")
        #expect(AccountDirectoryText.subscriptionCaption.contains("~/.claude-personal"))
        #expect(AccountDirectoryText.codexSubscriptionCaption.contains("~/.codex-lab"))
        #expect(!AccountDirectoryText.codexSubscriptionCaption.contains("It only matters"))
    }

    @Test func tokenBasedTexts() {
        #expect(AccountDirectoryText.tokenBasedCaption(for: .vertex)
                == "Sessions in this Claude Code directory are read for this account's usage. Leave it empty for ~/.claude. Only session files are read, never a login.")
        #expect(AccountDirectoryText.tokenBasedCaption(for: .openai)
                == "Sessions in this Codex home are read for this account's usage. Leave it empty for ~/.codex. Only session files are read, never auth.json.")
        #expect(AccountDirectoryText.tokenBasedPrompt(for: .vertex) == "~/profiles/acme/claude")
        #expect(AccountDirectoryText.tokenBasedPrompt(for: .openai) == "~/.codex-lab")
    }

    @Test func sourcesPageTexts() {
        #expect(AccountDirectoryText.sourcesAccountsCaption
                == "Claude Code directories and Codex homes are set per account in Accounts. An account without one uses ~/.claude or ~/.codex.")
        #expect(AccountDirectoryText.openCodePrompt == "~/.local/share/opencode-lab")
    }

    /// Each caption names the default an empty field uses; none claims a
    /// default is always read (spec 034 FR-008, walkthrough 2026-10-22).
    @Test func captionsNameTheirDefault() {
        #expect(AccountDirectoryText.subscriptionCaption.contains("~/.claude,"))
        #expect(AccountDirectoryText.codexSubscriptionCaption.contains("~/.codex,"))
        for provider in Provider.allCases {
            #expect(AccountDirectoryText.tokenBasedCaption(for: provider).contains("empty for " + provider.defaultSessionDirectory + "."))
            #expect(!AccountDirectoryText.tokenBasedCaption(for: provider).contains("always read"))
        }
        #expect(AccountDirectoryText.sourcesAccountsCaption.contains("uses ~/.claude or ~/.codex"))
        #expect(!AccountDirectoryText.sourcesAccountsCaption.contains("always read"))
    }

    /// Examples are invented, never a real local tool path (FR-013).
    @Test func noRealToolPaths() {
        let texts = [AccountDirectoryText.subscriptionCaption, AccountDirectoryText.codexSubscriptionCaption,
                     AccountDirectoryText.sourcesAccountsCaption, AccountDirectoryText.openCodePrompt]
            + Provider.allCases.flatMap { [AccountDirectoryText.tokenBasedCaption(for: $0), AccountDirectoryText.tokenBasedPrompt(for: $0)] }
        // Spelled in parts, so a search of the sources for the real tool's
        // name finds nothing (SC-005).
        let realTool = ["cc", "deck"].joined(separator: "-")
        for text in texts {
            #expect(!text.contains(realTool))
            #expect(!text.contains("/.local/share/") || text == AccountDirectoryText.openCodePrompt)
        }
    }
}
