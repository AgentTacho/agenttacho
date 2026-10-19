import Foundation

/// Styling of a bar entry (spec 001 FR-003).
public enum BarLevel: Hashable, Sendable {
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
    /// The entry's bar window or budget burns at least twice as fast as its
    /// remaining time allows, so the marker is "↑" instead of "↗" (spec 017
    /// FR-008). Only together with `runOutMarker`.
    public let burnsFast: Bool
    /// The headline window's tag ("5h", "wk", "Fable"), drawn after the
    /// icon; nil for the default window, a placeholder, budgets and member
    /// shares (spec 027 FR-008, FR-009).
    public let tag: String?
    /// The headline window named in full ("5-hour window"), for the
    /// accessibility text; set only together with `tag` (spec 027 FR-009).
    public let windowName: String?

    public init(id: String, icon: String, name: String, value: String, level: BarLevel, stale: Bool, runOutMarker: Bool = false,
                burnsFast: Bool = false, tag: String? = nil, windowName: String? = nil) {
        self.id = id
        self.icon = icon
        self.name = name
        self.value = value
        self.level = level
        self.stale = stale
        self.runOutMarker = runOutMarker
        self.burnsFast = burnsFast
        self.tag = tag
        self.windowName = windowName
    }

    /// Appended to the accessibility description of an entry with the
    /// marker (spec 011 FR-015); a fast entry names the fast burn instead
    /// (spec 017 FR-011).
    public var accessibilitySuffix: String {
        guard runOutMarker else { return "" }
        return burnsFast ? ", burning fast, projected to run out well before reset" : ", projected to run out before reset"
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

    /// The budget owner whose dropdown row the screenshot capture crops as
    /// the `budget` shot: the first owner (groups, then own budgets) at
    /// warning or critical level, otherwise the first owner; nil without a
    /// budget (spec 024 FR-019). Its row carries the accessibility
    /// identifiers the capture script looks for.
    public static func shotBudgetOwner(snapshot: UsageSnapshot?, configuration: Configuration) -> BudgetOwner? {
        let owners = configuration.budgetOwners
        let attention = owners.first { owner in
            let entry = owner.kind == .group ? snapshot?.groups[owner.id] : snapshot?.accountBudgets[owner.id]
            return level(percent: entry?.percent, thresholds: owner.budget.thresholds) != .normal
        }
        return attention ?? owners.first
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
                    result.append(budgetItem(id: account.id, key: .accountBudget(account.id), icon: account.icon,
                                             name: account.displayName, entry: snapshot?.accountBudgets[account.id],
                                             thresholds: budget.thresholds, snapshot: snapshot, showsMarker: showsMarker))
                case .codexSubscription(let settings):
                    guard settings.shownInBar else { continue }
                    result.append(codexItem(account, settings: settings, snapshot: snapshot, showsMarker: showsMarker))
                }
            case .group(let group, let members):
                let entry = snapshot?.groups[group.id]
                if group.shownInBar {
                    result.append(budgetItem(id: group.id, key: .group(group.id), icon: group.icon, name: group.name,
                                             entry: entry, thresholds: group.thresholds,
                                             snapshot: snapshot, showsMarker: showsMarker))
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

    /// Spec 001 rules with the headline window of spec 027 (FR-007,
    /// FR-008): the headline percent, "--" when not signed in or without
    /// values, "…" before the first data. Stale, rejected-sign-in and
    /// expired-credential values keep their percent with the stale marker;
    /// values in a grace period are unmarked (spec 010 FR-005, FR-010,
    /// FR-015). The level follows the headline percent, critical also when
    /// the 7-day window is at or above 100%; the run-out marker and the
    /// fast burn follow the headline window (spec 011 FR-012, spec 017
    /// FR-008). A non-default headline adds its tag, also to "--"; "…" and
    /// a not signed in "--" carry none.
    private static func subscriptionItem(_ account: Account, settings: SubscriptionSettings, snapshot: UsageSnapshot?,
                                         showsMarker: Bool) -> BarItem {
        guard let snapshot else {
            return BarItem(id: account.id, icon: account.icon, name: account.displayName, value: "…", level: .normal, stale: false)
        }
        let entry = snapshot.subscriptions[account.id]
        let now = snapshot.generatedAt
        // A window whose reset passed shows 0% (spec 010 FR-016).
        let headline = HeadlineWindow.claude(accountId: account.id, status: entry?.status, choice: settings.headlineWindow, now: now)
        let percent = headline.percent
        let stale: Bool
        let value: String
        let tag: String?
        switch entry?.state {
        case .notSignedIn?:
            stale = false
            value = "--"
            tag = nil
        case let state?:
            // `isStale` decides the marker: `.retrying` stays unmarked.
            stale = state.isStale && percent != nil
            value = PercentFormatter.text(percent)
            tag = headline.tag
        case nil:
            stale = false
            value = "…"
            tag = nil
        }
        // Without values (`percent` nil) the level is normal and there is no
        // pace; a full 7-day window is never hidden (spec 027 FR-007).
        let sevenDay = entry?.status?.effective(now: now).barPercent
        let level: BarLevel = (sevenDay ?? 0) >= 100 ? .critical : level(percent: percent, thresholds: settings.thresholds)
        let flags = markers(pace: headline.pace, key: headline.burnKey, snapshot: snapshot,
                            level: level, stale: stale, enabled: showsMarker)
        return BarItem(id: account.id, icon: account.icon, name: account.displayName, value: value, level: level, stale: stale,
                       runOutMarker: flags.runOut, burnsFast: flags.fast, tag: tag, windowName: tag != nil ? headline.accessibilityName : nil)
    }

    /// A Codex subscription account (spec 007 FR-012, spec 027 FR-007): the
    /// percent of the headline window, the longest plan window by default,
    /// "--" when no window is available, "…" before the first data. Any
    /// window whose limit is reached uses the at-or-above-100% style; only
    /// `.stale` values are styled stale, local-only values are not. Reset
    /// windows follow FR-010 at the snapshot's time. The run-out marker and
    /// the fast burn follow the headline window (spec 011 FR-012, spec 017
    /// FR-008); a non-default headline adds its tag (spec 027 FR-008).
    private static func codexItem(_ account: Account, settings: CodexSubscriptionSettings, snapshot: UsageSnapshot?,
                                  showsMarker: Bool) -> BarItem {
        guard let snapshot, let entry = snapshot.codexLimits[account.id] else {
            return BarItem(id: account.id, icon: account.icon, name: account.displayName, value: "…", level: .normal, stale: false)
        }
        let now = snapshot.generatedAt
        guard let headline = HeadlineWindow.codex(accountId: account.id, entry: entry, choice: settings.headlineWindow, now: now),
              let percent = headline.percent else {
            return BarItem(id: account.id, icon: account.icon, name: account.displayName, value: "--", level: .normal, stale: false)
        }
        let level: BarLevel = entry.anyLimitReached(now: now) ? .critical : level(percent: percent, thresholds: settings.thresholds)
        let stale = entry.state.isStale
        let flags = markers(pace: headline.pace, key: headline.burnKey, snapshot: snapshot, level: level, stale: stale, enabled: showsMarker)
        return BarItem(id: account.id, icon: account.icon, name: account.displayName, value: PercentFormatter.text(percent),
                       level: level, stale: stale, runOutMarker: flags.runOut, burnsFast: flags.fast,
                       tag: headline.tag, windowName: headline.tag != nil ? headline.accessibilityName : nil)
    }

    /// A budget owner's entry: its percent styled by its warning threshold,
    /// "…" until the first refresh produced its entry. The run-out marker
    /// and the fast burn follow the budget's pace at the snapshot time (spec
    /// 011 FR-012, spec 017 FR-008); `key` names the budget owner's kind,
    /// since a group and an account may share an id.
    private static func budgetItem(id: String, key: BurnWindowKey, icon: String, name: String, entry: GroupEntry?,
                                   thresholds: [Int], snapshot: UsageSnapshot?, showsMarker: Bool) -> BarItem {
        guard let entry else {
            return BarItem(id: id, icon: icon, name: name, value: "…", level: .normal, stale: false)
        }
        let level = level(percent: entry.percent, thresholds: thresholds)
        let pace = snapshot.flatMap { entry.pace(now: $0.generatedAt) }
        let flags = snapshot.map { markers(pace: pace, key: key, snapshot: $0, level: level, stale: entry.stale, enabled: showsMarker) }
        return BarItem(id: id, icon: icon, name: name, value: "\(entry.percent)%", level: level, stale: entry.stale,
                       runOutMarker: flags?.runOut ?? false, burnsFast: flags?.fast ?? false)
    }

    /// The marker rules of spec 011 FR-012 to FR-014 and spec 017 FR-008 to
    /// FR-010: enabled, a normal level, not stale; then "↑" when the bar
    /// window `key` burns fast, otherwise "↗" when spec 011 counts a
    /// run-out. The burn rate is looked up only when the item has a `pace`,
    /// so the item's pace guards (for example no bar percent) also hold for
    /// "↑" (research R8).
    private static func markers(pace: Pace?, key: BurnWindowKey?, snapshot: UsageSnapshot, level: BarLevel, stale: Bool,
                                enabled: Bool) -> (runOut: Bool, fast: Bool) {
        guard enabled, level == .normal, !stale, let pace else { return (false, false) }
        let fast = key.flatMap { snapshot.burnRate(for: $0) }?.burnsFast == true
        return (fast || pace.runOut != nil, fast)
    }
}
