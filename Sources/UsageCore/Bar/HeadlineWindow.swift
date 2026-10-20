import Foundation

/// The window in effect for one subscription account at one snapshot (spec
/// 027 Key Entities "Resolved headline"): it decides the section header's
/// bold percent and the bar entry's value, level and markers (FR-007).
public struct ResolvedHeadline: Equatable, Sendable {
    /// The Claude window, set for a Claude subscription.
    public let claudeWindow: ClaudeWindow?
    /// The Codex window name, set for a Codex plan.
    public let codexName: String?
    /// True for the 7-day window or the longest effective Codex window
    /// (FR-005).
    public let isDefault: Bool
    /// The rounded percent at the snapshot time; nil for a fixed window
    /// without values, which shows "--" (FR-007).
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
    /// "58%", or "--" for a chosen fixed window without values.
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
    /// paces at the fetch time. A chosen fixed window always applies, also
    /// without values; a chosen model limit applies only while the status
    /// has a limit of exactly that name, otherwise the 7-day window does
    /// (FR-006). Without a status a fixed choice resolves with percent nil
    /// and its tag, anything else to the 7-day window with percent nil.
    public static func claude(accountId: String, status: SubscriptionStatus?, choice: HeadlineChoice?, now: Date) -> ResolvedHeadline {
        let effective = status?.effective(now: now)
        func make(_ window: ClaudeWindow, rowName: String, accessibilityName: String, used: Double?, pace: Pace?) -> ResolvedHeadline {
            let percent = used.map { PercentFormatter.rounded($0) }
            let isDefault = window == .sevenDay
            return ResolvedHeadline(claudeWindow: window, codexName: nil, isDefault: isDefault, percent: percent,
                                    pace: percent != nil ? pace : nil, burnKey: .claude(accountId, window),
                                    tag: isDefault ? nil : tag(claude: window), rowName: rowName, accessibilityName: accessibilityName)
        }
        let sevenDay = {
            make(.sevenDay, rowName: "7-day", accessibilityName: "7-day window",
                 used: effective?.sevenDay?.utilizationPercent, pace: status?.sevenDayPace(now: now))
        }
        switch choice {
        case .claudeFiveHour?:
            return make(.fiveHour, rowName: "5-hour", accessibilityName: "5-hour window",
                        used: effective?.fiveHour?.utilizationPercent, pace: status?.fiveHourPace(now: now))
        case .claudeModel(let name)?:
            // The first limit of the name, like the burn inputs.
            guard let status, let limit = status.modelLimits.first(where: { $0.modelName == name }),
                  let shown = effective?.modelLimits.first(where: { $0.modelName == name }) else { return sevenDay() }
            return make(.model(name), rowName: name, accessibilityName: "\(name) weekly limit",
                        used: shown.utilizationPercent, pace: status.pace(of: limit, now: now))
        case .claudeSevenDay?, .codexWindow?, nil:
            return sevenDay()
        }
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
    /// cannot disagree (the 7-day window at or above 100% included), and its
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

    /// The tag of a Claude window (FR-008): "5h", "7d" (never shown, it is
    /// the default), or the model name, cut to its first 7 characters plus
    /// "…" when longer than 8.
    public static func tag(claude window: ClaudeWindow) -> String {
        switch window {
        case .fiveHour: return "5h"
        case .sevenDay: return "7d"
        case .model(let name): return name.count > 8 ? String(name.prefix(7)) + "…" : name
        }
    }

    /// The tag of a Codex window name (FR-008): "Nh" for "N-hour", "Nd" for
    /// "N-day", "wk" for "weekly"; any other name as it is.
    public static func tag(codexName name: String) -> String {
        if name == "weekly" { return "wk" }
        if name.hasSuffix("-hour") { return String(name.dropLast("-hour".count)) + "h" }
        if name.hasSuffix("-day") { return String(name.dropLast("-day".count)) + "d" }
        return name
    }

    /// What a click on a Claude window row stores: nil for the 7-day row,
    /// which clears the choice (FR-001).
    public static func choice(forClaude window: ClaudeWindow) -> HeadlineChoice? {
        switch window {
        case .fiveHour: return .claudeFiveHour
        case .sevenDay: return nil
        case .model(let name): return .claudeModel(name)
        }
    }

    /// What a click on a Codex window row stores: nil for the longest
    /// effective window, which clears the choice (FR-001).
    public static func choice(forCodex name: String, entry: CodexLimitsEntry, now: Date) -> HeadlineChoice? {
        entry.barWindow(now: now)?.name == name ? nil : .codexWindow(name)
    }
}
