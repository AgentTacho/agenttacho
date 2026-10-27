import Foundation

/// A token-based account that neither the profile step nor its rule can
/// tell apart from others, for the warning in its "Session matching"
/// section (spec 037 FR-013, data-model "MatchOverlap").
public struct MatchOverlap: Equatable, Sendable {
    public let accountId: String
    /// The display names of the other accounts, in accounts order.
    public let otherNames: [String]

    public init(accountId: String, otherNames: [String]) {
        self.accountId = accountId
        self.otherNames = otherNames
    }

    /// The warning text (contracts/settings-ui.md).
    public var warning: String { MatchRuleText.overlapWarning(otherNames: otherNames) }
}

extension Configuration {
    /// Token-based accounts grouped by harness, rule and, for Claude Code,
    /// canonical main directory (an empty field is `~/.claude`); one entry
    /// per member of a group of two or more, in accounts order. Accounts
    /// that differ in directory or rule get none, and subscriptions never
    /// appear (spec 037 FR-013, research R7).
    public func matchOverlaps(paths: Paths = Paths()) -> [MatchOverlap] {
        struct Key: Hashable {
            let harness: Harness
            let rule: MatchRule
            /// The canonical main directory, Claude Code only.
            let directory: String?
        }
        var groups: [Key: [Account]] = [:]
        var keys: [(account: Account, key: Key)] = []
        for account in accounts {
            guard let settings = account.kind.tokenBased else { continue }
            let directory = settings.harness == .claudeCode
                ? settings.effectiveSessionDirectory.map { Attributor.canonical(paths.expand($0)) }
                : nil
            let key = Key(harness: settings.harness, rule: settings.matchRule, directory: directory)
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
