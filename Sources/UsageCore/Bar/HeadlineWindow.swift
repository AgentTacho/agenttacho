import Foundation

/// The window in effect for one subscription account at one snapshot (spec
/// 027 Key Entities "Resolved headline"): it decides the section header's
/// bold percent and the bar entry's value, level and markers (FR-007).
public struct ResolvedHeadline: Equatable, Sendable {
    /// The Claude window, set for a Claude subscription.
    public let claudeWindow: ClaudeWindow?
    /// The Codex window name, set for a Codex plan.
    public let codexName: String?
    /// True for the default window: the Claude default of spec 040 FR-009
    /// or the longest effective Codex window (FR-005).
    public let isDefault: Bool
    /// The rounded percent at the snapshot time; nil without values (no
    /// status, or no Claude plan window, spec 040 FR-009), which shows "--"
    /// (FR-007).
    public let percent: Int?
    /// The window's pace, for the `↗` marker (spec 011 FR-012); nil without
    /// a percent.
    public let pace: Pace?
    /// The window's burn key, for the `↑` marker (spec 017 FR-008).
    public let burnKey: BurnWindowKey
    /// The FR-008 tag before the value; nil for the default window.
    public let tag: String?
    /// The name of the window's row in the dropdown ("5-hour", "7-day",
    /// "Fable", "weekly"), where the `●` sits (FR-002).
    public let rowName: String
    /// The window named in full for VoiceOver ("5-hour window", "Fable
    /// weekly limit", "weekly window", FR-009).
    public let accessibilityName: String

    public init(claudeWindow: ClaudeWindow?, codexName: String?, isDefault: Bool, percent: Int?, pace: Pace?,
                burnKey: BurnWindowKey, tag: String?, rowName: String, accessibilityName: String) {
        self.claudeWindow = claudeWindow
        self.codexName = codexName
        self.isDefault = isDefault
        self.percent = percent
        self.pace = pace
        self.burnKey = burnKey
        self.tag = tag
        self.rowName = rowName
        self.accessibilityName = accessibilityName
    }
}

/// The section header's text right of the account name (spec 027 FR-008):
/// the tag in the secondary color and regular weight, then the bold value
/// in its level color (spec 030 FR-005).
public struct HeadlineHeader: Equatable, Sendable {
    /// Nil for the default window.
    public let tag: String?
    /// "58%", or "--" without values.
    public let value: String
    /// The same level as the account's bar entry, cross-window rules
    /// included (spec 030 FR-005).
    public let level: BarLevel
    /// The value in words for VoiceOver.
    public let accessibilityValue: String

    public init(tag: String?, value: String, level: BarLevel = .normal, accessibilityValue: String? = nil) {
        self.tag = tag
        self.value = value
        self.level = level
        self.accessibilityValue = accessibilityValue ?? value
    }

    /// The color of the bold value (spec 030 FR-005).
    public var percentTone: PercentTone {
        PercentTone(level)
    }
}

extension ResolvedHeadline {
    /// The header of a resolved headline: the tag with the percent or "--";
    /// the default window shows only a percent and nothing without one, as
    /// before spec 027 (FR-008, SC-003).
    public var header: HeadlineHeader? {
        if let tag { return HeadlineHeader(tag: tag, value: PercentFormatter.text(percent)) }
        return percent.map { HeadlineHeader(tag: nil, value: PercentFormatter.text($0)) }
    }
}

/// Resolves the headline window of a Claude or Codex subscription from the
/// stored choice and the latest values, at drawing time (spec 027 FR-005,
/// FR-006, FR-008, research R3, R5). The bar entry and the section header
/// both use it, so they never disagree (FR-013).
public enum HeadlineWindow {
    /// A Claude subscription. `status` is the fetched status (the entry's,
    /// not yet effective); percents are taken at `now` (spec 010 FR-016),
    /// paces at the fetch time. A chosen window applies only while the
    /// status contains a window with that identity; otherwise the default
    /// window does and the stored choice stays as it is (spec 040 FR-009,
    /// FR-010). Without a status or without a plan window there is no
    /// headline: percent nil and no tag, under the `sevenDay` identity.
    public static func claude(accountId: String, status: SubscriptionStatus?, choice: HeadlineChoice?, now: Date) -> ResolvedHeadline {
        let effective = status?.effective(now: now)
        let fallback = status?.defaultWindow
        var chosen = fallback
        if let id = choice?.claudeWindow, let window = status?.window(id) { chosen = window }
        guard let status, let window = chosen else {
            return ResolvedHeadline(claudeWindow: .sevenDay, codexName: nil, isDefault: true, percent: nil, pace: nil,
                                    burnKey: .claude(accountId, .sevenDay), tag: nil, rowName: ClaudeLimits.sevenDayName,
                                    accessibilityName: "\(ClaudeLimits.sevenDayName) window")
        }
        let isDefault = window.identity == fallback?.identity
        let percent = effective?.window(window.identity).map { PercentFormatter.rounded($0.utilizationPercent) }
        return ResolvedHeadline(claudeWindow: window.identity, codexName: nil, isDefault: isDefault, percent: percent,
                                pace: percent != nil ? status.pace(of: window, now: now) : nil,
                                burnKey: .claude(accountId, window.identity), tag: isDefault ? nil : tag(claude: window),
                                rowName: window.name, accessibilityName: accessibilityName(window))
    }

    /// The window named in full for VoiceOver (spec 040 FR-011): "<name>
    /// window" for a plan window, "<model> weekly limit" for a model's first
    /// limit, "<name> limit" for a further one.
    static func accessibilityName(_ window: ClaudeLimit) -> String {
        if !window.isModelLimit { return "\(window.name) window" }
        if window.isPrimaryModelLimit, let model = window.modelName { return "\(model) weekly limit" }
        return "\(window.name) limit"
    }

    /// The Claude section header (FR-008): nothing before the first values
    /// (`state` nil) and for an account that is not signed in, like the bar
    /// entry; otherwise the headline's header.
    public static func header(_ headline: ResolvedHeadline, state: SubscriptionState?) -> HeadlineHeader? {
        switch state {
        case nil, .notSignedIn?: return nil
        default: return headline.header
        }
    }

    /// The Claude section header with its level (spec 030 FR-005):
    /// `header(_:state:)` with the level of the bar entry, decided
    /// by the same `BarLayout.subscriptionLevel`, so the header and the bar
    /// cannot disagree (the default window at or above 100% included, spec
    /// 040 FR-011), and its
    /// value in `direction` (FR-009). `now` is the snapshot time the
    /// headline was resolved at.
    public static func claudeHeader(_ headline: ResolvedHeadline, entry: SubscriptionEntry?, thresholds: [Int],
                                    direction: DisplayDirection, now: Date) -> HeadlineHeader? {
        guard let header = header(headline, state: entry?.state) else { return nil }
        let decision = BarLayout.subscriptionLevel(percent: headline.percent, status: entry?.status, thresholds: thresholds, now: now)
        return directed(header, percent: headline.percent, decision: decision, direction: direction)
    }

    /// The Codex section header with its level (spec 030 FR-005): the
    /// headline's header with the level of the bar entry, decided by the
    /// same `BarLayout.codexLevel` (any reached limit included). Nil
    /// without a headline or a percent.
    public static func codexHeader(_ headline: ResolvedHeadline?, entry: CodexLimitsEntry, thresholds: [Int],
                                   direction: DisplayDirection, now: Date) -> HeadlineHeader? {
        guard let headline, let header = headline.header, let percent = headline.percent else { return nil }
        let decision = BarLayout.codexLevel(percent: percent, entry: entry, thresholds: thresholds, now: now)
        return directed(header, percent: percent, decision: decision, direction: direction)
    }

    /// The header with its level, its value in `direction` and the value in
    /// words (spec 030 FR-009); "--" stays as it is.
    private static func directed(_ header: HeadlineHeader, percent: Int?, decision: LevelDecision,
                                 direction: DisplayDirection) -> HeadlineHeader {
        let directed = percent.map { DirectedPercent(usedPercent: $0, direction: direction) }
        return HeadlineHeader(tag: header.tag, value: directed?.text ?? header.value, level: decision.level,
                              accessibilityValue: directed?.accessibilityText(.window))
    }

    /// A Codex plan: the last effective window with the chosen name, else
    /// the longest effective window, which is also the default when the
    /// chosen name is its name (FR-005, FR-006). Two windows with one name
    /// resolve to the last, like `barWindow` and the burn inputs. Nil when
    /// the plan has no effective window.
    public static func codex(accountId: String, entry: CodexLimitsEntry, choice: HeadlineChoice?, now: Date) -> ResolvedHeadline? {
        // One definition of the default window, shared with `choice(forCodex:)`.
        guard let longest = entry.barWindow(now: now) else { return nil }
        let windows = entry.windows(now: now)
        var window = longest
        if case .codexWindow(let name)? = choice, let chosen = windows.last(where: { $0.name == name }) {
            window = chosen
        }
        let isDefault = window.name == longest.name
        return ResolvedHeadline(claudeWindow: nil, codexName: window.name, isDefault: isDefault,
                                percent: PercentFormatter.rounded(window.usedPercent), pace: entry.pace(of: window, now: now),
                                burnKey: .codex(accountId, window.name), tag: isDefault ? nil : tag(codexName: window.name),
                                rowName: window.name, accessibilityName: "\(window.name) window")
    }

    /// The index in `windows` of the row that carries the `●`: the last
    /// window with the headline's name (FR-002); nil for a Claude headline.
    public static func codexHeadlineIndex(_ headline: ResolvedHeadline, windows: [CodexLimitWindow]) -> Int? {
        guard let name = headline.codexName else { return nil }
        return windows.lastIndex { $0.name == name }
    }

    /// The tag of a Claude window (spec 027 FR-008, spec 040 FR-011): "5h"
    /// for `fiveHour`, "7d" for `sevenDay`, otherwise the display name, cut
    /// to its first 7 characters plus "…" when longer than 8.
    public static func tag(claude window: ClaudeLimit) -> String {
        if window.identity == .fiveHour { return "5h" }
        if window.identity == .sevenDay { return "7d" }
        let name = window.name
        return name.count > 8 ? String(name.prefix(7)) + "…" : name
    }

    /// The tag of a Codex window name (FR-008): "Nh" for "N-hour", "Nd" for
    /// "N-day", "wk" for "weekly"; any other name as it is.
    public static func tag(codexName name: String) -> String {
        if name == "weekly" { return "wk" }
        if name.hasSuffix("-hour") { return String(name.dropLast("-hour".count)) + "h" }
        if name.hasSuffix("-day") { return String(name.dropLast("-day".count)) + "d" }
        return name
    }

    /// What a click on a Claude window row stores: nil for the default
    /// window's row, which clears the choice (spec 027 FR-001, spec 040
    /// FR-009); the identity otherwise. Without a status the default is
    /// the `sevenDay` window.
    public static func choice(forClaude identity: ClaudeWindow, status: SubscriptionStatus?) -> HeadlineChoice? {
        let defaultIdentity = status.map { $0.defaultWindow?.identity } ?? .sevenDay
        return identity == defaultIdentity ? nil : .claude(identity)
    }

    /// What a click on a Codex window row stores: nil for the longest
    /// effective window, which clears the choice (FR-001).
    public static func choice(forCodex name: String, entry: CodexLimitsEntry, now: Date) -> HeadlineChoice? {
        entry.barWindow(now: now)?.name == name ? nil : .codexWindow(name)
    }
}
