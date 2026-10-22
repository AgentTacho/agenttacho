import Foundation

/// A top-level key of older configurations whose directories are no longer
/// read (spec 034 FR-011, FR-012). The configuration decodes the keys with
/// it; they are not among its `CodingKeys`, so they are never written.
public enum LegacyDirectoryKey: String, CodingKey, CaseIterable, Sendable {
    /// Extra Claude Code directories.
    case logDirectories
    /// Extra Codex homes.
    case codexHomes

    /// The agent whose directories the key listed.
    public var harness: Harness {
        switch self {
        case .logDirectories: return .claudeCode
        case .codexHomes: return .codex
        }
    }

    /// The account field that replaces the key.
    public var fieldLabel: String {
        switch self {
        case .logDirectories: return AccountDirectoryText.claudeCodeDirectoryLabel
        case .codexHomes: return AccountDirectoryText.codexHomeLabel
        }
    }
}

/// The load notes for the entries of a dropped global directory list (spec
/// 034 FR-011, research R6, contracts/configuration.md "Load notes"). Each
/// non-blank entry gets exactly one note: the directory is already covered
/// by an account, or where to set it instead. An entry equal to the default
/// is covered only by an account that resolves to it, for example through
/// an empty field (spec 034 FR-008).
public enum LegacyDirectoryNotes {
    /// The notes for `entries` of `key`, in entry order. Nil `entries` means
    /// the key holds something other than a list of strings, which gives one
    /// note for the key. Entries are compared with the accounts' directories
    /// by canonical path, as spec 015 FR-006 does.
    public static func notes(key: LegacyDirectoryKey, entries: [String]?, accounts: [Account], paths: Paths) -> [String] {
        guard let entries else { return ["\(key.rawValue) is not a list of directories, ignored"] }
        let nonBlank = entries.filter { !AccountDirectory.isBlank($0) }
        guard !nonBlank.isEmpty else { return [] }
        let covering = accounts.compactMap { account in
            account.agentDirectory(for: key.harness).map { (name: account.displayName, canonical: canonical($0, paths)) }
        }
        return nonBlank.map { entry in
            let prefix = "\(key.rawValue) entry \"\(Configuration.clipped(entry, limit: 160))\" is no longer read; "
            let path = canonical(entry, paths)
            if let account = covering.first(where: { $0.canonical == path }) {
                return prefix + "it is already covered by account \"\(Configuration.clipped(account.name))\""
            }
            return prefix + "set it as the \(key.fieldLabel) of an account in Settings > Accounts"
        }
    }

    private static func canonical(_ directory: String, _ paths: Paths) -> String {
        Attributor.canonical(paths.expand(AccountDirectory.trimmed(directory) ?? directory))
    }
}
