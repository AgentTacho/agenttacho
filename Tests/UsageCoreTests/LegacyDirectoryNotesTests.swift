import Foundation
import Testing
@testable import UsageCore

/// Spec 034 FR-011, research R6, contracts/configuration.md "Load notes":
/// the load notes for entries of the dropped `logDirectories` and
/// `codexHomes` lists.
@Suite struct LegacyDirectoryNotesTests {
    static func claude(_ name: String, _ dir: String) -> Account {
        Account(id: name, displayName: name, kind: .subscription(SubscriptionSettings(credentialDirectory: dir)))
    }

    static func codex(_ name: String, _ home: String) -> Account {
        Account(id: name, displayName: name, harness: .codex, kind: .codexSubscription(CodexSubscriptionSettings(codexHome: home)))
    }

    static func token(_ name: String, _ provider: Provider, _ dir: String) -> Account {
        Account(id: name, displayName: name, harness: provider.sessionHarness,
                kind: .tokenBased(TokenBasedSettings(membership: .group(id: "grp", shownInBar: false), provider: provider,
                                                     sessionDirectory: dir)))
    }

    private func withHome(_ name: String, _ body: (URL, Paths) throws -> Void) throws {
        let root = try makeTempDirectory(name)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root, Paths(home: root))
    }

    @Test func genericNotePerKey() throws {
        try withHome("legacy-generic") { _, paths in
            #expect(LegacyDirectoryNotes.notes(key: .logDirectories, entries: ["~/profiles/acme/claude"],
                                               accounts: [], paths: paths)
                    == [#"logDirectories entry "~/profiles/acme/claude" is no longer read; set it as the Claude Code directory of an account in Settings > Accounts"#])
            #expect(LegacyDirectoryNotes.notes(key: .codexHomes, entries: ["~/.codex-lab"],
                                               accounts: [], paths: paths)
                    == [#"codexHomes entry "~/.codex-lab" is no longer read; set it as the Codex home of an account in Settings > Accounts"#])
        }
    }

    /// The first covering account in list order, compared by canonical path
    /// (tilde, absolute spelling, trailing slash).
    @Test func coveredNoteNamesTheFirstMatchingAccount() throws {
        try withHome("legacy-covered") { root, paths in
            let accounts = [Self.codex("Plus", "~/profiles/acme/claude"),
                            Self.token("Acme Vertex", .vertex, "~/profiles/acme/claude"),
                            Self.claude("Max", "~/profiles/acme/claude")]
            let absolute = root.appendingPathComponent("profiles/acme/claude").path
            for entry in ["~/profiles/acme/claude", absolute, absolute + "/"] {
                #expect(LegacyDirectoryNotes.notes(key: .logDirectories, entries: [entry], accounts: accounts, paths: paths)
                        == [#"logDirectories entry "\#(entry)" is no longer read; it is already covered by account "Acme Vertex""#])
            }
            let codexAccounts = [Self.token("Acme Vertex", .vertex, "~/.codex-lab"),
                                 Self.token("OpenAI Lab", .openai, "~/.codex-lab"),
                                 Self.codex("Plus", "~/.codex-lab")]
            #expect(LegacyDirectoryNotes.notes(key: .codexHomes, entries: ["~/.codex-lab/"],
                                               accounts: codexAccounts, paths: paths)
                    == [#"codexHomes entry "~/.codex-lab/" is no longer read; it is already covered by account "OpenAI Lab""#])
        }
    }

    /// US3 scenario 3: a Claude subscription's own directory, listed in the
    /// old global list as well, is covered by that account.
    @Test func coveredBySubscriptionAccount() throws {
        try withHome("legacy-covered-subscription") { root, paths in
            let accounts = [Self.codex("Plus", "~/.claude-personal"), Self.claude("Max", "~/.claude-personal")]
            for entry in ["~/.claude-personal", root.path + "/.claude-personal/"] {
                #expect(LegacyDirectoryNotes.notes(key: .logDirectories, entries: [entry], accounts: accounts, paths: paths)
                        == [#"logDirectories entry "\#(entry)" is no longer read; it is already covered by account "Max""#])
            }
        }
    }

    /// Entries are compared by canonical path: a symlink to an account's
    /// directory and a `..` spelling of it are covered too, and surrounding
    /// whitespace is ignored.
    @Test func coveredThroughSymlinkAndDotDot() throws {
        try withHome("legacy-covered-symlink") { root, paths in
            let target = root.appendingPathComponent("profiles/acme/claude")
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("acme-link"), withDestinationURL: target)
            let accounts = [Self.token("Acme Vertex", .vertex, "~/profiles/acme/claude")]
            for entry in ["~/acme-link", "~/profiles/acme/../acme/claude", " ~/profiles/acme/claude "] {
                #expect(LegacyDirectoryNotes.notes(key: .logDirectories, entries: [entry], accounts: accounts, paths: paths)
                        == [#"logDirectories entry "\#(entry)" is no longer read; it is already covered by account "Acme Vertex""#])
            }
        }
    }

    /// Spec 034 FR-006a: a blank subscription directory that reads the
    /// default another account already reads gets a note; one account on
    /// the default alone, or a blank token-based directory, gets none.
    @Test func blankSubscriptionSharingTheDefaultIsNoted() throws {
        try withHome("legacy-shared-default") { _, paths in
            let accounts = [Self.claude("Blank", ""), Self.claude("Max", "~/.claude"),
                            Self.codex("Plus", "~/.codex"), Self.codex("Spare", "  "),
                            Self.token("Acme Vertex", .vertex, "")]
            #expect(Configuration(accounts: accounts).blankDirectoriesOnSharedDefault(paths: paths).map(\.note) == [
                #"Claude Code directory of account "Blank" is empty, so it reads ~/.claude like account "Max""#,
                #"Codex home of account "Spare" is empty, so it reads ~/.codex like account "Plus""#,
            ])
            let alone = Configuration(accounts: [Self.claude("Blank", ""), Self.claude("Work", "~/.claude-personal")])
            #expect(alone.blankDirectoriesOnSharedDefault(paths: paths).isEmpty)
        }
    }

    /// A Settings edit may not clear a subscription directory next to an
    /// account on the default, while a configuration that already holds
    /// such an account stays editable.
    @Test func settingsEditMayNotCreateASharedDefault() throws {
        try withHome("legacy-shared-default-edit") { _, paths in
            let before = Configuration(accounts: [Self.claude("Max", "~/.claude"), Self.claude("Work", "~/.claude-personal")])
            let cleared = Configuration(accounts: [Self.claude("Max", "~/.claude"), Self.claude("Work", "")])
            do {
                try cleared.checkNoNewSharedDefault(comparedTo: [before], paths: paths)
                Issue.record("expected the edit to be rejected")
            } catch let error as ConfigurationError {
                #expect(error.kind == .duplicateCredentialDirectory)
                #expect(error.message == #"Claude Code directory of account "Work" is empty, so it reads ~/.claude like Claude subscription account "Max". Enter the directory this account runs from."#)
            }
            // Loaded that way, other edits still apply.
            var renamed = cleared
            renamed.accounts[0].displayName = "Max 20x"
            try renamed.checkNoNewSharedDefault(comparedTo: [cleared], paths: paths)
            // An undo back to the loaded state restores it, after an edit
            // that removed the sharing was applied.
            try cleared.checkNoNewSharedDefault(comparedTo: [before, cleared], paths: paths)
            // A Codex home cleared next to ~/.codex is rejected too.
            let codexBefore = Configuration(accounts: [Self.codex("Plus", "~/.codex"), Self.codex("Pro", "~/.codex-lab")])
            let codexCleared = Configuration(accounts: [Self.codex("Plus", "~/.codex"), Self.codex("Pro", " ")])
            #expect(throws: ConfigurationError.self) { try codexCleared.checkNoNewSharedDefault(comparedTo: [codexBefore], paths: paths) }
            // A blank field with no other account on the default is fine.
            try Configuration(accounts: [Self.claude("Work", "")]).checkNoNewSharedDefault(comparedTo: [before], paths: paths)
        }
    }

    /// A Codex account never covers a Claude Code entry, and the other way
    /// round.
    @Test func otherAgentsAccountsDoNotCover() throws {
        try withHome("legacy-other-agent") { _, paths in
            let accounts = [Self.codex("Plus", "~/shared"), Self.token("OpenAI Lab", .openai, "~/shared")]
            #expect(LegacyDirectoryNotes.notes(key: .logDirectories, entries: ["~/shared"], accounts: accounts, paths: paths)
                    .allSatisfy { $0.hasSuffix("in Settings > Accounts") })
            let claudeAccounts = [Self.claude("Max", "~/shared"), Self.token("Acme Vertex", .vertex, "~/shared")]
            #expect(LegacyDirectoryNotes.notes(key: .codexHomes, entries: ["~/shared"], accounts: claudeAccounts, paths: paths)
                    .allSatisfy { $0.hasSuffix("in Settings > Accounts") })
        }
    }

    /// An entry equal to the default is covered by the first account that
    /// resolves to it, also through an empty field; without such an account
    /// it gets the note on where to set it (spec 034 FR-008, FR-011,
    /// walkthrough 2026-10-22).
    @Test func defaultEntryIsCoveredOnlyByAnAccountOnTheDefault() throws {
        try withHome("legacy-default") { root, paths in
            let accounts = [Self.claude("Max", "~/.claude"), Self.codex("Plus", "")]
            #expect(LegacyDirectoryNotes.notes(key: .logDirectories, entries: ["~/.claude", root.path + "/.claude/"],
                                               accounts: accounts, paths: paths)
                    == [#"logDirectories entry "~/.claude" is no longer read; it is already covered by account "Max""#,
                        #"logDirectories entry "\#(root.path)/.claude/" is no longer read; it is already covered by account "Max""#])
            #expect(LegacyDirectoryNotes.notes(key: .codexHomes, entries: ["~/.codex"], accounts: accounts, paths: paths)
                    == [#"codexHomes entry "~/.codex" is no longer read; it is already covered by account "Plus""#])
            // Empty token-based fields resolve to the default too.
            let tokens = [Self.token("Acme Vertex", .vertex, ""), Self.token("OpenAI Lab", .openai, " ")]
            #expect(LegacyDirectoryNotes.notes(key: .logDirectories, entries: ["~/.claude"], accounts: tokens, paths: paths)
                    == [#"logDirectories entry "~/.claude" is no longer read; it is already covered by account "Acme Vertex""#])
            #expect(LegacyDirectoryNotes.notes(key: .codexHomes, entries: ["~/.codex"], accounts: tokens, paths: paths)
                    == [#"codexHomes entry "~/.codex" is no longer read; it is already covered by account "OpenAI Lab""#])
            // No account on the default: the entry is set on an account.
            let elsewhere = [Self.claude("Work", "~/.claude-personal"), Self.token("OpenAI Lab", .openai, "~/.codex-lab")]
            #expect(LegacyDirectoryNotes.notes(key: .logDirectories, entries: ["~/.claude"], accounts: elsewhere, paths: paths)
                    == [#"logDirectories entry "~/.claude" is no longer read; set it as the Claude Code directory of an account in Settings > Accounts"#])
            #expect(LegacyDirectoryNotes.notes(key: .codexHomes, entries: ["~/.codex"], accounts: [], paths: paths)
                    == [#"codexHomes entry "~/.codex" is no longer read; set it as the Codex home of an account in Settings > Accounts"#])
        }
    }

    @Test func blankEntriesGiveNoNote() throws {
        try withHome("legacy-blank") { _, paths in
            #expect(LegacyDirectoryNotes.notes(key: .logDirectories, entries: ["", "  ", "\n"], accounts: [], paths: paths).isEmpty)
            #expect(LegacyDirectoryNotes.notes(key: .codexHomes, entries: [], accounts: [], paths: paths).isEmpty)
        }
    }

    @Test func unreadableValueGivesOneNoteForTheKey() throws {
        try withHome("legacy-unreadable") { _, paths in
            #expect(LegacyDirectoryNotes.notes(key: .logDirectories, entries: nil, accounts: [], paths: paths)
                    == ["logDirectories is not a list of directories, ignored"])
            #expect(LegacyDirectoryNotes.notes(key: .codexHomes, entries: nil, accounts: [], paths: paths)
                    == ["codexHomes is not a list of directories, ignored"])
        }
    }

    @Test func entriesAndNamesAreClipped() throws {
        try withHome("legacy-clipped") { _, paths in
            let entry = "~/" + String(repeating: "d", count: 200)
            let generic = LegacyDirectoryNotes.notes(key: .logDirectories, entries: [entry], accounts: [], paths: paths)
            #expect(generic == ["logDirectories entry \"\(String(entry.prefix(160)))...\" is no longer read; set it as the Claude Code directory of an account in Settings > Accounts"])
            let name = String(repeating: "n", count: 40)
            let covered = LegacyDirectoryNotes.notes(key: .logDirectories, entries: ["~/profiles/acme/claude"],
                                                     accounts: [Self.token(name, .vertex, "~/profiles/acme/claude")], paths: paths)
            #expect(covered == ["logDirectories entry \"~/profiles/acme/claude\" is no longer read; it is already covered by account \"\(String(name.prefix(32)))...\""])
        }
    }
}
