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
                == "Claude Code directories and Codex homes are set per account in Accounts, together with any additional session directories. An account without one uses ~/.claude or ~/.codex.")
        #expect(AccountDirectoryText.openCodePrompt == "~/.local/share/opencode-lab")
        // spec 035 FR-013: the OpenCode list explains `*`.
        #expect(AccountDirectoryText.openCodeSection == "Additional OpenCode data directories")
        #expect(AccountDirectoryText.openCodeCaption
                == "~/.local/share/opencode is always read. Add other OpenCode data directories that hold an opencode.db. * stands for any folder name at one level, for example ~/agent-sessions/openshell/*/opencode.")
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
                     AccountDirectoryText.sourcesAccountsCaption, AccountDirectoryText.openCodePrompt,
                     AccountDirectoryText.additionalDirectoriesSection, AccountDirectoryText.openCodeCaption]
            + Provider.allCases.flatMap { [AccountDirectoryText.tokenBasedCaption(for: $0), AccountDirectoryText.tokenBasedPrompt(for: $0)] }
            + [Harness.claudeCode, .codex].flatMap {
                [AccountDirectoryText.additionalDirectoriesCaption(for: $0), AccountDirectoryText.additionalDirectoriesPrompt(for: $0)]
            }
            + [AccountDirectoryText.chooseFolderItem, AccountDirectoryText.enterPathItem, AccountDirectoryText.enterPathTitle,
               AccountDirectoryText.enterPathCaption, AccountDirectoryText.emptyList]
            + Harness.allCases.map { AccountDirectoryText.chooseFolderMessage(for: $0) }
        // Spelled in parts, so a search of the sources for the real tool's
        // name finds nothing (SC-005).
        let realTool = ["cc", "deck"].joined(separator: "-")
        for text in texts {
            #expect(!text.contains(realTool))
            // The OpenCode prompt and caption name its default directory.
            #expect(!text.contains("/.local/share/") || text == AccountDirectoryText.openCodePrompt
                    || text == AccountDirectoryText.openCodeCaption)
        }
    }

    /// spec 035 FR-002, FR-014, contracts/settings-layout.md: the section of
    /// additional session directories on every account.
    @Test func additionalDirectoriesTexts() {
        #expect(AccountDirectoryText.additionalDirectoriesSection == "Additional session directories")
        #expect(AccountDirectoryText.additionalDirectoriesCaption(for: .claudeCode)
                == "Sessions in these directories are read for this account's usage, in addition to the Claude Code directory above. * stands for any folder name at one level, for example ~/agent-sessions/openshell/*/claude. Only session files are read, never a login.")
        #expect(AccountDirectoryText.additionalDirectoriesCaption(for: .codex)
                == "Sessions in these directories are read for this account's usage, in addition to the Codex home above. * stands for any folder name at one level, for example ~/agent-sessions/openshell/*/codex. Only session files are read, never a login or auth.json.")
        #expect(AccountDirectoryText.additionalDirectoriesPrompt(for: .claudeCode) == "~/.claude-lab")
        #expect(AccountDirectoryText.additionalDirectoriesPrompt(for: .codex) == "~/.codex-lab")
        for harness in [Harness.claudeCode, .codex] {
            let caption = AccountDirectoryText.additionalDirectoriesCaption(for: harness)
            #expect(caption.contains("* stands for any folder name at one level"))
            #expect(caption.contains("never a login"))
        }
        #expect(AccountDirectoryText.additionalDirectoriesCaption(for: .codex).contains("auth.json"))
        // The harness follows the account kind, so an OpenAI account shows
        // the Codex texts.
        let openai = AccountKind.tokenBased(TokenBasedSettings(groupId: "grp", provider: .openai))
        #expect(AccountDirectoryText.additionalDirectoriesPrompt(for: openai.sessionHarness) == "~/.codex-lab")
    }

    /// spec 035 FR-002, FR-013, contracts/settings-layout.md: the add menu,
    /// the Enter Path sheet and the folder chooser of the directory lists.
    @Test func directoryListControls() {
        #expect(AccountDirectoryText.chooseFolderItem == "Choose Folder…")
        #expect(AccountDirectoryText.enterPathItem == "Enter Path…")
        #expect(AccountDirectoryText.enterPathTitle == "Add Directory")
        #expect(AccountDirectoryText.enterPathCaption == "Start with ~/ or /. * stands for any folder name at one level.")
        #expect(AccountDirectoryText.emptyList == "No directories")
        #expect(AccountDirectoryText.editItem == "Edit")
        #expect(AccountDirectoryText.chooseFolderMessage(for: .claudeCode)
                == "Choose Claude Code directories whose sessions count for this account.")
        #expect(AccountDirectoryText.chooseFolderMessage(for: .codex)
                == "Choose Codex homes whose sessions count for this account.")
        #expect(AccountDirectoryText.chooseFolderMessage(for: .openCode)
                == "Choose OpenCode data directories that hold an opencode.db.")
    }
}
