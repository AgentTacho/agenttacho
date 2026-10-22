import Foundation

/// A subscription account whose directory field is blank, so it reads the
/// default (`~/.claude` or `~/.codex`, spec 034 FR-006a), while another
/// subscription account of the same agent reads that default too. Both then
/// use the same login. A file saved before spec 034, when a blank field was
/// an empty path, can hold this; it still loads, with a load note, but a
/// Settings edit may not create it.
public struct SharedDefaultDirectory: Equatable, Sendable {
    public let accountId: String
    public let accountName: String
    /// The first other account in list order that reads the same default.
    public let otherName: String
    public let harness: Harness

    /// The field label: "Claude Code directory" or "Codex home".
    public var label: String {
        harness == .codex ? AccountDirectoryText.codexHomeLabel : AccountDirectoryText.claudeCodeDirectoryLabel
    }

    /// `~/.claude` or `~/.codex`.
    public var defaultDirectory: String {
        harness == .codex ? Paths.defaultCodexHome : Paths.defaultClaudeDirectory
    }

    /// The load note (contracts/configuration.md "Blank subscription
    /// directory on the default").
    public var note: String {
        "\(label) of account \"\(Configuration.clipped(accountName))\" is empty, so it reads \(defaultDirectory) like account \"\(Configuration.clipped(otherName))\""
    }
}

extension Configuration {
    /// Every blank subscription directory that shares its default with
    /// another subscription account of the same agent, in accounts order
    /// (spec 034 FR-006a).
    public func blankDirectoriesOnSharedDefault(paths: Paths = Paths()) -> [SharedDefaultDirectory] {
        var result: [SharedDefaultDirectory] = []
        for harness in [Harness.claudeCode, .codex] {
            let defaultDirectory = harness == .codex ? Paths.defaultCodexHome : Paths.defaultClaudeDirectory
            let defaultCanonical = Attributor.canonical(paths.expand(defaultDirectory))
            let onDefault = accounts.compactMap { account -> (account: Account, blank: Bool)? in
                guard let entered = account.enteredSubscriptionDirectory(for: harness),
                      let directory = account.agentDirectory(for: harness),
                      Attributor.canonical(paths.expand(directory)) == defaultCanonical else { return nil }
                return (account, AccountDirectory.isBlank(entered))
            }
            for item in onDefault where item.blank {
                guard let other = onDefault.first(where: { $0.account.id != item.account.id }) else { continue }
                result.append(SharedDefaultDirectory(accountId: item.account.id, accountName: item.account.displayName,
                                                     otherName: other.account.displayName, harness: harness))
            }
        }
        return result
    }

    /// Rejects a Settings edit that leaves a subscription directory blank
    /// where another account already reads the default, unless one of
    /// `previous` (the applied configuration, and an undo's target) had that
    /// account in the same state; a file that already holds one stays
    /// editable and undoable (spec 034 FR-006a).
    public func checkNoNewSharedDefault(comparedTo previous: [Configuration], paths: Paths = Paths()) throws {
        let before = Set(previous.flatMap { $0.blankDirectoriesOnSharedDefault(paths: paths) }.map { "\($0.harness.rawValue)|\($0.accountId)" })
        guard let added = blankDirectoriesOnSharedDefault(paths: paths)
            .first(where: { !before.contains("\($0.harness.rawValue)|\($0.accountId)") }) else { return }
        let agent = added.harness == .codex ? "Codex" : "Claude"
        throw ConfigurationError(kind: added.harness == .codex ? .duplicateCodexHome : .duplicateCredentialDirectory,
                                 message: "\(added.label) of account \"\(added.accountName)\" is empty, so it reads \(added.defaultDirectory) like \(agent) subscription account \"\(added.otherName)\". Enter the directory this account runs from.")
    }
}

extension Account {
    /// The directory field of a Claude subscription (`.claudeCode`) or a
    /// Codex subscription (`.codex`) as entered; nil for other accounts.
    func enteredSubscriptionDirectory(for harness: Harness) -> String? {
        switch (harness, kind) {
        case (.claudeCode, .subscription(let settings)): return settings.enteredCredentialDirectory
        case (.codex, .codexSubscription(let settings)): return settings.enteredCodexHome
        default: return nil
        }
    }
}
