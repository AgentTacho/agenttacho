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
    /// default (spec 034 FR-008). The additional session directories are set
    /// there too (spec 035 FR-002).
    public static let sourcesAccountsCaption = "Claude Code directories and Codex homes are set per account in Accounts, together with any additional session directories. An account without one uses ~/.claude or ~/.codex."

    /// The section below an account's main directory that lists its
    /// additional session directories (spec 035 FR-002).
    public static let additionalDirectoriesSection = "Additional session directories"

    /// The caption of that section: read in addition to the main directory,
    /// `*` for one folder level, session files only (spec 035 FR-002,
    /// FR-014). `harness` is the account's `AccountKind.sessionHarness`,
    /// never `.openCode`, which no account has; it reads as Claude Code.
    public static func additionalDirectoriesCaption(for harness: Harness) -> String {
        let lead = "Sessions in these directories are read for this account's usage, in addition to the"
        switch harness {
        case .codex:
            return "\(lead) Codex home above. * stands for any folder name at one level, for example ~/agent-sessions/openshell/*/codex. Only session files are read, never a login or auth.json."
        case .claudeCode, .openCode:
            return "\(lead) Claude Code directory above. * stands for any folder name at one level, for example ~/agent-sessions/openshell/*/claude. Only session files are read, never a login."
        }
    }

    /// The invented example in the "Enter Path…" sheet's field (spec 035
    /// FR-014).
    public static func additionalDirectoriesPrompt(for harness: Harness) -> String {
        switch harness {
        case .codex: return "~/.codex-lab"
        case .claudeCode, .openCode: return "~/.claude-lab"
        }
    }

    /// The OpenCode list on the Sources page (spec 006 FR-003).
    public static let openCodeSection = "Additional OpenCode data directories"

    /// The caption of the OpenCode list: the default is always read, and
    /// `*` stands for one folder level (spec 035 FR-013, FR-014).
    public static let openCodeCaption = "\(Paths.defaultOpenCodeDirectory) is always read. Add other OpenCode data directories that hold an opencode.db. * stands for any folder name at one level, for example ~/agent-sessions/openshell/*/opencode."

    /// The invented example in the OpenCode "Enter Path…" field (spec 034
    /// FR-013).
    public static let openCodePrompt = "~/.local/share/opencode-lab"

    /// The items of a directory list's add menu (spec 035 FR-002, FR-013).
    public static let chooseFolderItem = "Choose Folder…"
    public static let enterPathItem = "Enter Path…"

    /// The sheet behind "Enter Path…", for entries a folder chooser cannot
    /// pick, such as `*` entries.
    public static let enterPathTitle = "Add Directory"
    public static let enterPathCaption = "Start with ~/ or /. * stands for any folder name at one level."

    /// Shown in a directory list without entries.
    public static let emptyList = "No directories"

    /// The context menu item that edits a row in place, like a double-click.
    public static let editItem = "Edit"

    /// The message of the "Choose Folder…" panel: an account list names its
    /// harness, `.openCode` stands for the OpenCode list of General > Sources.
    public static func chooseFolderMessage(for harness: Harness) -> String {
        switch harness {
        case .claudeCode: return "Choose Claude Code directories whose sessions count for this account."
        case .codex: return "Choose Codex homes whose sessions count for this account."
        case .openCode: return "Choose OpenCode data directories that hold an opencode.db."
        }
    }
}
