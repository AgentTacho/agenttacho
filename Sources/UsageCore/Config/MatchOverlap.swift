import Foundation

/// A token-based account that neither its Claude Code directory nor kind
/// and condition can tell apart from others, for the warning in its "Which
/// sessions count" section (spec 038 FR-009, data-model "MatchOverlap").
public struct MatchOverlap: Equatable, Sendable {
    public let accountId: String
    /// The display names of the other accounts, in accounts order.
    public let otherNames: [String]

    public init(accountId: String, otherNames: [String]) {
        self.accountId = accountId
        self.otherNames = otherNames
    }
}

extension Configuration {
    /// Token-based accounts grouped by harness, kind, effective condition
    /// and, for Claude Code, canonical main directory (an empty field is
    /// `~/.claude`); one entry per member of a group of two or more, in
    /// accounts order. Directory only accounts are separated by their
    /// directory alone and never appear, nor do subscriptions (spec 038
    /// FR-009, research R12). Conditions compare as written, literal texts
    /// ignoring case.
    public func matchOverlaps(paths: Paths = Paths()) -> [MatchOverlap] {
        struct Key: Hashable {
            let harness: Harness
            let kind: SessionKind
            let condition: MatchConditionOverlapKey?
            /// The canonical main directory, Claude Code only.
            let directory: String?
        }
        var groups: [Key: [Account]] = [:]
        var keys: [(account: Account, key: Key)] = []
        for account in accounts {
            guard let settings = account.kind.tokenBased, settings.sessionKind != .claudeCodeDirectoryOnly else { continue }
            let directory = settings.harness == .claudeCode
                ? settings.effectiveSessionDirectory.map { Attributor.canonical(paths.expand($0)) }
                : nil
            let key = Key(harness: settings.harness, kind: settings.sessionKind,
                          condition: settings.effectiveCondition?.overlapKey, directory: directory)
            groups[key, default: []].append(account)
            keys.append((account, key))
        }
        return keys.compactMap { item in
            let members = groups[item.key] ?? []
            guard members.count > 1 else { return nil }
            return MatchOverlap(accountId: item.account.id,
                                otherNames: members.filter { $0.id != item.account.id }.map(\.displayName))
        }
    }

    /// The overlap of one account, nil when it has none.
    public func matchOverlap(forAccount id: String, paths: Paths = Paths()) -> MatchOverlap? {
        matchOverlaps(paths: paths).first { $0.accountId == id }
    }
}

/// A Directory only account whose main Claude Code directory another
/// account uses too, so its sessions count for that account (or tie) and
/// this one counts nothing, for the warning in its "Which sessions count"
/// section (spec 038 FR-013, research R12, data-model
/// "DirectoryOnlyConflict").
public struct DirectoryOnlyConflict: Equatable, Sendable {
    public let accountId: String
    /// The display names of the other accounts, in accounts order.
    public let otherNames: [String]

    public init(accountId: String, otherNames: [String]) {
        self.accountId = accountId
        self.otherNames = otherNames
    }
}

extension Configuration {
    /// The accounts, a Claude subscription or a token-based Claude Code
    /// account of any kind, whose canonical main Claude Code directory is
    /// that of the Directory only account `id` (an empty field is
    /// `~/.claude`); nil when `id` is no Directory only account or no other
    /// account shares its directory (spec 038 FR-013, research R12).
    public func directoryOnlyConflict(forAccount id: String, paths: Paths = Paths()) -> DirectoryOnlyConflict? {
        guard accounts.first(where: { $0.id == id })?.kind.tokenBased?.sessionKind == .claudeCodeDirectoryOnly else { return nil }
        let others = sharedClaudeCodeDirectory(forAccount: id, paths: paths)
        return others.isEmpty ? nil : DirectoryOnlyConflict(accountId: id, otherNames: others)
    }

    /// The display names of the other accounts, Claude subscriptions or
    /// token-based Claude Code accounts of any kind, whose canonical main
    /// Claude Code directory is that of account `id` (an empty field is
    /// `~/.claude`), in accounts order; empty when `id` has no Claude Code
    /// directory or nobody shares it. Sessions from a shared directory are
    /// decided by kind and condition, which the directory note says
    /// (spec 038 FR-013, walkthrough feedback).
    public func sharedClaudeCodeDirectory(forAccount id: String, paths: Paths = Paths()) -> [String] {
        func mainDirectory(_ account: Account) -> String? {
            account.agentDirectory(for: .claudeCode).map { Attributor.canonical(paths.expand($0)) }
        }
        guard let account = accounts.first(where: { $0.id == id }), let directory = mainDirectory(account) else { return [] }
        return accounts.filter { $0.id != id && mainDirectory($0) == directory }.map(\.displayName)
    }
}
