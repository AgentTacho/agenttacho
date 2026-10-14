import Foundation

/// Styling of a bar entry (spec 001 FR-003).
public enum BarLevel: Equatable, Sendable {
    case normal
    /// At or above the entry's warning threshold.
    case warning
    /// At or above 100%.
    case critical
}

/// One `<icon> <value>` entry of the menu bar (spec 001 FR-002, spec 004
/// FR-004). Rendering lives in the app; this is the pure layout.
public struct BarItem: Equatable, Sendable, Identifiable {
    /// Account or group id; `"<groupId>/<accountId>"` for a group member.
    public let id: String
    /// Catalog reference of the icon, for example `"brands:claude"`.
    public let icon: String
    /// The entry's name, for accessibility text and logs (FR-004).
    public let name: String
    /// `"42%"`, `"--"` (unavailable), or `"…"` (no data yet).
    public let value: String
    public let level: BarLevel
    public let stale: Bool

    public init(id: String, icon: String, name: String, value: String, level: BarLevel, stale: Bool) {
        self.id = id
        self.icon = icon
        self.name = name
        self.value = value
        self.level = level
        self.stale = stale
    }
}

/// Which entries the bar shows, in which order, with which values and
/// levels (spec 004 research R6).
public enum BarLayout {
    public static let defaultWarningThreshold = 80

    /// Lowest configured threshold, or 80 when none is configured (spec 001 FR-003).
    public static func warningThreshold(_ thresholds: [Int]) -> Int {
        thresholds.filter { $0 > 0 }.min() ?? defaultWarningThreshold
    }

    public static func level(percent: Int?, thresholds: [Int]) -> BarLevel {
        guard let percent else { return .normal }
        if percent >= 100 { return .critical }
        if percent >= warningThreshold(thresholds) { return .warning }
        return .normal
    }

    /// The bar entries in spec 004 FR-020 order: subscription accounts and
    /// accounts with their own budget that are shown in bar, in accounts-list
    /// order; then groups in groups-list order, each (when shown) followed by
    /// its members shown in bar, in accounts-list order. A hidden group's
    /// shown members take its position (FR-019). Unassigned never appears.
    public static func segments(snapshot: UsageSnapshot?, configuration: Configuration) -> [BarItem] {
        var result: [BarItem] = []
        for account in configuration.accounts {
            switch account.kind {
            case .subscription(let settings):
                guard settings.shownInBar else { continue }
                result.append(subscriptionItem(account, settings: settings, snapshot: snapshot))
            case .tokenBased(let settings):
                guard let budget = settings.ownBudget, budget.shownInBar else { continue }
                // An own budget is shown like a group (FR-011).
                result.append(budgetItem(id: account.id, icon: account.icon, name: account.displayName,
                                         entry: snapshot?.accountBudgets[account.id], thresholds: budget.thresholds))
            case .codexSubscription:
                // Token counts only until plan limits exist (spec 006 FR-017).
                continue
            }
        }
        for group in configuration.groups {
            let entry = snapshot?.groups[group.id]
            if group.shownInBar {
                result.append(budgetItem(id: group.id, icon: group.icon, name: group.name,
                                         entry: entry, thresholds: group.thresholds))
            }
            for member in configuration.members(of: group.id) where member.kind.tokenBased?.memberShownInBar == true {
                result.append(memberItem(member, group: group, entry: entry))
            }
        }
        return result
    }

    /// A group member's share: its spend in the group's window as a percent
    /// of the group budget, styled by the group's warning threshold, with the
    /// group's placeholder and stale state (FR-017, FR-018). Members have no
    /// thresholds of their own.
    private static func memberItem(_ member: Account, group: BudgetGroup, entry: GroupEntry?) -> BarItem {
        let id = "\(group.id)/\(member.id)"
        guard let entry else {
            return BarItem(id: id, icon: member.icon, name: member.displayName, value: "…", level: .normal, stale: false)
        }
        guard let percent = entry.memberPercent(member.id) else {
            // The group's values predate this member (FR-018 placeholder).
            return BarItem(id: id, icon: member.icon, name: member.displayName, value: "…", level: .normal, stale: entry.stale)
        }
        return BarItem(id: id, icon: member.icon, name: member.displayName, value: "\(percent)%",
                       level: level(percent: percent, thresholds: group.thresholds), stale: entry.stale)
    }

    /// Spec 001 rules: the 7-day percent (`barPercent`), "--" when
    /// not signed in or the credentials expired, "…" before the first data.
    private static func subscriptionItem(_ account: Account, settings: SubscriptionSettings, snapshot: UsageSnapshot?) -> BarItem {
        guard let snapshot else {
            return BarItem(id: account.id, icon: account.icon, name: account.displayName, value: "…", level: .normal, stale: false)
        }
        let entry = snapshot.subscriptions[account.id]
        let percent = entry?.status?.barPercent
        let stale: Bool
        let value: String
        var hasValues = false
        switch entry?.state {
        case .ok?:
            stale = false
            value = PercentFormatter.text(percent)
            hasValues = true
        case .stale?:
            stale = percent != nil
            value = PercentFormatter.text(percent)
            hasValues = true
        case .notSignedIn?, .credentialsExpired?:
            stale = false
            value = "--"
        case nil:
            stale = false
            value = "…"
        }
        let level = hasValues ? level(percent: percent, thresholds: settings.thresholds) : .normal
        return BarItem(id: account.id, icon: account.icon, name: account.displayName, value: value, level: level, stale: stale)
    }

    /// A budget owner's entry: its percent styled by its warning threshold,
    /// "…" until the first refresh produced its entry.
    private static func budgetItem(id: String, icon: String, name: String, entry: GroupEntry?, thresholds: [Int]) -> BarItem {
        guard let entry else {
            return BarItem(id: id, icon: icon, name: name, value: "…", level: .normal, stale: false)
        }
        return BarItem(id: id, icon: icon, name: name, value: "\(entry.percent)%",
                       level: level(percent: entry.percent, thresholds: thresholds), stale: entry.stale)
    }
}
