import Foundation

/// The labels, prompts and captions of the account directory fields in
/// Settings > Accounts and of the Sources page in Settings > General
/// (spec 034 FR-006, FR-007, FR-013, contracts/settings-layout.md). Kept in
/// UsageCore so tests check the defaults they name and that every example
/// path is invented.
public enum AccountDirectoryText {
    /// The label of a Claude subscription's and a Vertex account's directory
    /// field; the configuration key stays `credentialDirectory` for a
    /// subscription (spec 034 FR-006).
    public static let claudeCodeDirectoryLabel = "Claude Code directory"

    /// The label of a Codex subscription's and an OpenAI account's directory
    /// field.
    public static let codexHomeLabel = "Codex home"

    /// The caption of a Claude subscription's directory field (spec 034
    /// FR-006, FR-006a).
    public static let subscriptionCaption = "The Claude Code directory this account runs from: its sessions and its login come from here. Leave it empty for ~/.claude, or enter a profile directory such as ~/.claude-personal. Use the directory you run Claude Code with, so its login stays fresh."

    /// The caption of a Codex subscription's Codex home (spec 034 FR-006).
    public static let codexSubscriptionCaption = "The Codex home this ChatGPT plan runs from: its sessions are read from here and, with live limits on, its sign-in. Leave it empty for ~/.codex, or enter another home such as ~/.codex-lab."

    /// The section of a token-based account that holds its directory, below
    /// the "Token-based" section (spec 034 FR-007).
    public static let usageSourceSection = "Usage source"

    /// The label of a token-based account's directory field, which follows
    /// the provider (spec 034 FR-007).
    public static func tokenBasedLabel(for provider: Provider) -> String {
        switch provider {
        case .vertex: return claudeCodeDirectoryLabel
        case .openai: return codexHomeLabel
        }
    }

    /// The caption of a token-based account's directory field: only session
    /// files are read from it, and an empty field means the default (spec 034
    /// FR-007, FR-008).
    public static func tokenBasedCaption(for provider: Provider) -> String {
        let empty = "Leave it empty for \(provider.defaultSessionDirectory)."
        switch provider {
        case .vertex:
            return "Sessions in this Claude Code directory are read for this account's usage. \(empty) Only session files are read, never a login."
        case .openai:
            return "Sessions in this Codex home are read for this account's usage. \(empty) Only session files are read, never auth.json."
        }
    }

    /// The invented example shown in an empty token-based directory field
    /// (spec 034 FR-013).
    public static func tokenBasedPrompt(for provider: Provider) -> String {
        switch provider {
        case .vertex: return "~/profiles/acme/claude"
        case .openai: return "~/.codex-lab"
        }
    }

    /// The Sources page section that points to the accounts (spec 034
    /// FR-002, FR-010).
    public static let sourcesAccountsSection = "Claude Code and Codex"

    /// Only the accounts' directories are read; an empty field means the
    /// default (spec 034 FR-008).
    public static let sourcesAccountsCaption = "Claude Code directories and Codex homes are set per account in Accounts. An account without one uses ~/.claude or ~/.codex."

    /// The invented example in the OpenCode "Add directory" field (spec 034
    /// FR-013).
    public static let openCodePrompt = "~/.local/share/opencode-lab"
}
