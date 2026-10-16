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
    /// The entry's bar window or budget runs out before its reset at the
    /// current pace (spec 011 FR-012, FR-013). Only for a normal level and
    /// values that are not stale; never for a group member's share.
    public let runOutMarker: Bool

    public init(id: String, icon: String, name: String, value: String, level: BarLevel, stale: Bool, runOutMarker: Bool = false) {
        self.id = id
        self.icon = icon
        self.name = name
        self.value = value
        self.level = level
        self.stale = stale
        self.runOutMarker = runOutMarker
    }

    /// Appended to the accessibility description of an entry with the
    /// marker (spec 011 FR-015).
    public var accessibilitySuffix: String {
        runOutMarker ? ", projected to run out before reset" : ""
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

    /// The bar entries in arrangement order (spec 008 FR-002): every entry
    /// shown in bar, a Claude or Codex subscription account (spec 007
    /// FR-012), an account with its own budget, or a group; after a group's
    /// position its members shown in bar, in member order. A hidden group's
    /// shown members take its position (spec 004 FR-019). Unassigned never
    /// appears. With no stored arrangement this is the spec 004 FR-020 order.
    public static func segments(snapshot: UsageSnapshot?, configuration: Configuration) -> [BarItem] {
        var result: [BarItem] = []
        let showsMarker = configuration.showsRunOutMarker
        for arranged in configuration.arrangedEntries {
            switch arranged {
            case .account(let account):
                switch account.kind {
                case .subscription(let settings):
                    guard settings.shownInBar else { continue }
                    result.append(subscriptionItem(account, settings: settings, snapshot: snapshot, showsMarker: showsMarker))
                case .tokenBased(let settings):
                    guard let budget = settings.ownBudget, budget.shownInBar else { continue }
                    // An own budget is shown like a group (spec 004 FR-011).
                    result.append(budgetItem(id: account.id, icon: account.icon, name: account.displayName,
                                             entry: snapshot?.accountBudgets[account.id], thresholds: budget.thresholds,
                                             now: snapshot?.generatedAt, showsMarker: showsMarker))
                case .codexSubscription(let settings):
                    guard settings.shownInBar else { continue }
                    result.append(codexItem(account, settings: settings, snapshot: snapshot, showsMarker: showsMarker))
                }
            case .group(let group, let members):
                let entry = snapshot?.groups[group.id]
                if group.shownInBar {
                    result.append(budgetItem(id: group.id, icon: group.icon, name: group.name,
                                             entry: entry, thresholds: group.thresholds,
                                             now: snapshot?.generatedAt, showsMarker: showsMarker))
                }
                for member in members where member.kind.tokenBased?.memberShownInBar == true {
                    result.append(memberItem(member, group: group, entry: entry))
                }
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
    /// The run-out marker follows the 7-day window (spec 011 FR-012).
    private static func subscriptionItem(_ account: Account, settings: SubscriptionSettings, snapshot: UsageSnapshot?,
                                         showsMarker: Bool) -> BarItem {
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
        let pace = hasValues ? entry?.status?.sevenDayPace(now: snapshot.generatedAt) : nil
        return BarItem(id: account.id, icon: account.icon, name: account.displayName, value: value, level: level, stale: stale,
                       runOutMarker: marker(pace, level: level, stale: stale, enabled: showsMarker))
    }

    /// A Codex subscription account (spec 007 FR-012): the percent of the
    /// longest plan window, "--" when no window is available, "…" before the
    /// first data. Any window whose limit is reached uses the at-or-above-100%
    /// style; only `.stale` values are styled stale, local-only values are
    /// not. Reset windows follow FR-010 at the snapshot's time. The run-out
    /// marker follows the longest effective window (spec 011 FR-012).
    private static func codexItem(_ account: Account, settings: CodexSubscriptionSettings, snapshot: UsageSnapshot?,
                                  showsMarker: Bool) -> BarItem {
        guard let snapshot, let entry = snapshot.codexLimits[account.id] else {
            return BarItem(id: account.id, icon: account.icon, name: account.displayName, value: "…", level: .normal, stale: false)
        }
        let now = snapshot.generatedAt
        guard let percent = entry.barPercent(now: now) else {
            return BarItem(id: account.id, icon: account.icon, name: account.displayName, value: "--", level: .normal, stale: false)
        }
        let level: BarLevel = entry.anyLimitReached(now: now) ? .critical : level(percent: percent, thresholds: settings.thresholds)
        let pace = entry.barPace(now: now)
        let stale = entry.state.isStale
        return BarItem(id: account.id, icon: account.icon, name: account.displayName, value: PercentFormatter.text(percent),
                       level: level, stale: stale, runOutMarker: marker(pace, level: level, stale: stale, enabled: showsMarker))
    }

    /// A budget owner's entry: its percent styled by its warning threshold,
    /// "…" until the first refresh produced its entry. The run-out marker
    /// follows the budget's pace at the snapshot time `now` (spec 011 FR-012).
    private static func budgetItem(id: String, icon: String, name: String, entry: GroupEntry?, thresholds: [Int],
                                   now: Date?, showsMarker: Bool) -> BarItem {
        guard let entry else {
            return BarItem(id: id, icon: icon, name: name, value: "…", level: .normal, stale: false)
        }
        let level = level(percent: entry.percent, thresholds: thresholds)
        let pace = now.flatMap { entry.pace(now: $0) }
        return BarItem(id: id, icon: icon, name: name, value: "\(entry.percent)%", level: level, stale: entry.stale,
                       runOutMarker: marker(pace, level: level, stale: entry.stale, enabled: showsMarker))
    }

    /// The marker rule of spec 011 FR-012 to FR-014: enabled, a normal level,
    /// not stale, and a run-out that counts and is not withheld.
    private static func marker(_ pace: Pace?, level: BarLevel, stale: Bool, enabled: Bool) -> Bool {
        enabled && level == .normal && !stale && pace?.runOut != nil
    }
}
