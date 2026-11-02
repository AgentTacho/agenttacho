import Foundation

/// One window of a Claude subscription as AgentTacho shows it (spec 040 Key
/// Entities "Claude window"): a plan window (no scope) or a model limit
/// (scoped to a model), with its identity, group, length and display name.
public struct ClaudeLimit: Equatable, Sendable {
    /// Stable across refreshes; what the configuration and the threshold
    /// state store (spec 040 FR-004).
    public var identity: ClaudeWindow
    /// The entry's kind as reported (its group when it has none); `five_hour`
    /// and `seven_day` for the top-level fallback windows (FR-002).
    public var kind: String
    /// The window family as reported; `five_hour` and `weekly` for the
    /// fallback windows (FR-002, FR-003).
    public var group: String?
    /// The window length from the group (FR-003); nil for an unknown group,
    /// which has no pace (FR-007).
    public var length: TimeInterval?
    /// The display name (FR-003 to FR-005).
    public var name: String
    /// Set for a model limit: the model's display name (FR-001).
    public var modelName: String?
    /// The model limit's share of the weekly limit, when reported (spec 025 FR-001).
    public var allowancePercentOfWeekly: Int?
    public var utilizationPercent: Double
    /// Nil while the window has not started, and once its reset has passed
    /// in the effective status (spec 010 FR-016, spec 025 FR-008).
    public var resetsAt: Date?

    /// True for a limit scoped to a model.
    public var isModelLimit: Bool { modelName != nil }
    /// True for a window without a scope.
    public var isPlanWindow: Bool { modelName == nil }
    /// True for a model's first limit, the one with the identity
    /// `model:<model name>` (spec 040 FR-004). Compared with the model name
    /// rather than parsed from the identity, so a name with a colon counts.
    public var isPrimaryModelLimit: Bool {
        modelName.map { identity == .model($0) } ?? false
    }

    /// The tooltip of a model limit row's name (spec 025 FR-019a, spec 040
    /// FR-006): "<model> weekly limit" with its allowance of the 7-day
    /// limit for a model's first limit, "<name> limit" for a further one;
    /// nil for a plan window.
    public var nameHelp: String? {
        guard isModelLimit else { return nil }
        guard isPrimaryModelLimit else { return "\(name) limit" }
        return allowancePercentOfWeekly.map { "\(name) weekly limit, \($0)% of the 7-day limit" } ?? "\(name) weekly limit"
    }

    public init(identity: ClaudeWindow, kind: String, group: String?, length: TimeInterval?, name: String, modelName: String?,
                allowancePercentOfWeekly: Int?, utilizationPercent: Double, resetsAt: Date?) {
        self.identity = identity
        self.kind = kind
        self.group = group
        self.length = length
        self.name = name
        self.modelName = modelName
        self.allowancePercentOfWeekly = allowancePercentOfWeekly
        self.utilizationPercent = utilizationPercent
        self.resetsAt = resetsAt
    }

    /// A 5-hour window as the top-level fallback reads it (spec 040 FR-002).
    public static func fiveHour(_ percent: Double, resetsAt: Date?) -> ClaudeLimit {
        ClaudeLimit(identity: .fiveHour, kind: "five_hour", group: "five_hour", length: ClaudeLimits.fiveHourSeconds,
                    name: ClaudeLimits.fiveHourName, modelName: nil, allowancePercentOfWeekly: nil,
                    utilizationPercent: percent, resetsAt: resetsAt)
    }

    /// A 7-day window as the top-level fallback reads it (spec 040 FR-002).
    public static func sevenDay(_ percent: Double, resetsAt: Date?) -> ClaudeLimit {
        ClaudeLimit(identity: .sevenDay, kind: "seven_day", group: "weekly", length: ClaudeLimits.weekSeconds,
                    name: ClaudeLimits.sevenDayName, modelName: nil, allowancePercentOfWeekly: nil,
                    utilizationPercent: percent, resetsAt: resetsAt)
    }

    /// A model's weekly limit, as the endpoint reports it today (spec 025 FR-001).
    public static func model(_ name: String, _ percent: Double, resetsAt: Date?, allowance: Int? = nil) -> ClaudeLimit {
        ClaudeLimit(identity: .model(name), kind: "weekly_scoped", group: "weekly", length: ClaudeLimits.weekSeconds,
                    name: name, modelName: name, allowancePercentOfWeekly: allowance,
                    utilizationPercent: percent, resetsAt: resetsAt)
    }
}

/// One decoded entry of the usage endpoint's `limits` array (spec 040
/// FR-001, contracts/usage-endpoint-limits.md), before it becomes a window.
public struct ClaudeLimitEntry: Equatable, Sendable {
    public var kind: String?
    public var group: String?
    /// Nil when the entry has no readable percent; it is then skipped.
    public var percent: Double?
    /// The normalized reset time; nil for a null `resets_at`.
    public var resetsAt: Date?
    /// True when `resets_at` was present but not readable; the entry is skipped.
    public var resetUnreadable: Bool
    /// The model's display name of a model scope; nil without one, or when
    /// the model object has an empty or missing name.
    public var modelName: String?
    /// True when the entry's scope has a model object.
    public var hasModelScope: Bool
    /// True when the scope names a surface and no model (FR-001).
    public var isSurfaceOnly: Bool
    /// The index in the raw `limits` array, for `weekly_scoped_shares`.
    public var rawIndex: Int

    public init(kind: String?, group: String?, percent: Double?, resetsAt: Date?, resetUnreadable: Bool = false,
                modelName: String? = nil, hasModelScope: Bool = false, isSurfaceOnly: Bool = false, rawIndex: Int) {
        self.kind = kind
        self.group = group
        self.percent = percent
        self.resetsAt = resetsAt
        self.resetUnreadable = resetUnreadable
        self.modelName = modelName
        self.hasModelScope = hasModelScope
        self.isSurfaceOnly = isSurfaceOnly
        self.rawIndex = rawIndex
    }

    /// The scope as the diagnostic log writes it (FR-012).
    var scopeText: String {
        if hasModelScope { return "model:\(modelName ?? "")" }
        if isSurfaceOnly { return "surface" }
        return "none"
    }

    /// `<kind>/<group>/<scope>`, a missing kind or group as an empty field (FR-012).
    var reportText: String {
        "\(kind ?? "")/\(group ?? "")/\(scopeText)"
    }

    /// True for an entry that becomes a window by FR-001: a percent, a
    /// readable or null reset, and a kind or a group.
    var isReadable: Bool {
        percent != nil && !resetUnreadable && (kind != nil || group != nil)
    }

    /// A readable entry without a scope: a plan window (FR-001, FR-002).
    var isReadablePlanWindow: Bool {
        isReadable && !hasModelScope && !isSurfaceOnly
    }
}

/// What the endpoint client read, for the diagnostic log line (spec 040 FR-012).
public struct ClaudeWindowReport: Equatable, Sendable {
    /// True when the top-level `five_hour` / `seven_day` objects supplied
    /// the plan windows (FR-002).
    public var usedFallback: Bool
    /// `<kind>/<group>/<scope>` of every window read, in response order (the
    /// fallback windows first); a missing kind or group is an empty field
    /// (`daily_all//none`).
    public var read: [String]
    /// The entries that did not become a window, in the same format.
    public var skipped: [String]

    /// The set of windows compared between fetches; the log line is written
    /// when it changes (FR-012, clarification Q1).
    public var signature: Set<String> { Set(read + skipped.map { $0 + " skipped" }) }

    public init(usedFallback: Bool, read: [String], skipped: [String]) {
        self.usedFallback = usedFallback
        self.read = read
        self.skipped = skipped
    }

    /// The diagnostic log message (spec 040 FR-012): `<account id>: windows
    /// <kind>/<group>/<scope>, ... (limits|fallback)`, skipped entries
    /// marked ` skipped`; no percents, reset times or other account details.
    public func logMessage(accountId: String) -> String {
        let windows = read + skipped.map { $0 + " skipped" }
        return "\(accountId): windows \(windows.isEmpty ? "none" : windows.joined(separator: ", ")) (\(usedFallback ? "fallback" : "limits"))"
    }
}

extension SubscriptionStatus {
    /// The shown windows by display name with their rounded percent, for the
    /// "ok" summary lines (spec 040 FR-012): `7-day 11%, Fable 15%`, or
    /// `no limits`.
    public var windowSummary: String {
        guard !windows.isEmpty else { return "no limits" }
        return windows.map { "\($0.name) \(PercentFormatter.rounded($0.utilizationPercent))%" }.joined(separator: ", ")
    }
}

/// Builds the Claude window list from the decoded answer (spec 040 FR-001
/// to FR-006, research R3 to R5). The endpoint client and the demo share it.
public enum ClaudeLimits {
    static let fiveHourSeconds = Pace.fiveHourSeconds
    static let weekSeconds = WindowResolver.weekSeconds
    static let fiveHourName = "5-hour"
    static let sevenDayName = "7-day"
    static let weeklyGroup = "weekly"
    static let weeklyAllKind = "weekly_all"
    static let fiveHourGroups: Set<String> = ["five_hour", "session", "5h"]

    /// The length of a known group (FR-003): `weekly` 7 days; `five_hour`,
    /// `session` and `5h` 5 hours; nil for any other group. Matched after
    /// lowercasing.
    public static func groupLength(_ group: String?) -> TimeInterval? {
        guard let group = group?.lowercased() else { return nil }
        if group == weeklyGroup { return weekSeconds }
        if fiveHourGroups.contains(group) { return fiveHourSeconds }
        return nil
    }

    /// A name from an answer string: lowercased, underscores as spaces (FR-005).
    static func words(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "_", with: " ")
    }

    static func isWeekly(_ group: String?) -> Bool { group?.lowercased() == weeklyGroup }
    static func isFiveHour(_ group: String?) -> Bool { group.map { fiveHourGroups.contains($0.lowercased()) } ?? false }

    /// The window list in FR-006 order and the report for the log line.
    ///
    /// Plan windows come from the unscoped `entries`; when there is none
    /// that is readable (or `entries` is nil), from the fallback values of
    /// the top-level objects (FR-002). Model limits always come from
    /// `entries`, with their allowance from `allowances` by raw index.
    /// Entries without a percent, with an unreadable reset, without kind and
    /// group, scoped only to a surface, scoped to a model without a name, or
    /// with an identity an earlier window already has are skipped and
    /// reported (FR-001, FR-005).
    public static func build(entries: [ClaudeLimitEntry]?, allowances: [Int: Int],
                             fallbackFiveHour: (percent: Double, resetsAt: Date?)?,
                             fallbackSevenDay: (percent: Double, resetsAt: Date?)?) -> (windows: [ClaudeLimit], report: ClaudeWindowReport) {
        let result = resolve(entries: entries, allowances: allowances, fallbackFiveHour: fallbackFiveHour,
                             fallbackSevenDay: fallbackSevenDay)
        return (result.windows, result.report)
    }

    /// The identity `build` gives each entry that becomes a window, by raw
    /// index (spec 040 FR-004); the demo keys its frame changes with it, so
    /// it needs no second parser (research R11).
    public static func identities(entries: [ClaudeLimitEntry]) -> [Int: ClaudeWindow] {
        resolve(entries: entries, allowances: [:], fallbackFiveHour: nil, fallbackSevenDay: nil).identities
    }

    private static func resolve(entries: [ClaudeLimitEntry]?, allowances: [Int: Int],
                                fallbackFiveHour: (percent: Double, resetsAt: Date?)?,
                                fallbackSevenDay: (percent: Double, resetsAt: Date?)?)
        -> (windows: [ClaudeLimit], report: ClaudeWindowReport, identities: [Int: ClaudeWindow]) {
        var identities: [Int: ClaudeWindow] = [:]
        // An empty kind or group counts as missing (spec 040 FR-004).
        let entries = (entries ?? []).map { entry in
            var copy = entry
            if copy.kind?.isEmpty == true { copy.kind = nil }
            if copy.group?.isEmpty == true { copy.group = nil }
            return copy
        }
        let usedFallback = !entries.contains { $0.isReadablePlanWindow }

        var planWindows: [ClaudeLimit] = []
        var modelLimits: [ClaudeLimit] = []
        var read: [String] = []
        var skipped: [String] = []
        var seen: Set<ClaudeWindow> = []

        if usedFallback {
            if let five = fallbackFiveHour {
                planWindows.append(.fiveHour(five.percent, resetsAt: five.resetsAt))
                read.append("five_hour/five_hour/none")
            }
            if let seven = fallbackSevenDay {
                planWindows.append(.sevenDay(seven.percent, resetsAt: seven.resetsAt))
                read.append("seven_day/weekly/none")
            }
            seen.formUnion(planWindows.map(\.identity))
        }

        // FR-004: `sevenDay` goes to the unscoped `weekly_all` entry when
        // there is one, otherwise to the first plan window of the weekly group.
        let planEntries = entries.filter { $0.isReadablePlanWindow }
        let sevenDayIndex = planEntries.firstIndex { $0.kind?.lowercased() == weeklyAllKind }
            ?? planEntries.firstIndex { isWeekly($0.group) }
        let sevenDayRaw = sevenDayIndex.map { planEntries[$0].rawIndex }
        let fiveHourRaw = planEntries.first { isFiveHour($0.group) }?.rawIndex

        // FR-004: per model, the first weekly limit (else the first limit)
        // has `model:<name>`.
        var primaryModelRaw: [String: Int] = [:]
        for entry in entries where entry.isReadable {
            guard let name = entry.modelName, !name.isEmpty, primaryModelRaw[name] == nil else { continue }
            let limits = entries.filter { $0.isReadable && $0.modelName == name }
            primaryModelRaw[name] = (limits.first { isWeekly($0.group) } ?? limits[0]).rawIndex
        }

        for entry in entries {
            guard entry.isReadable, let percent = entry.percent else {
                skipped.append(entry.reportText)
                continue
            }
            let kind = entry.kind ?? entry.group ?? ""
            let window: ClaudeLimit
            if entry.hasModelScope {
                guard let model = entry.modelName, !model.isEmpty else {
                    skipped.append(entry.reportText)
                    continue
                }
                let identity: ClaudeWindow
                let name: String
                if primaryModelRaw[model] == entry.rawIndex {
                    identity = .model(model)
                    name = model
                } else {
                    identity = ClaudeWindow(rawValue: "model:\(model):\(kind)")
                    // FR-004: named by its group, or by its kind when the
                    // group is weekly or missing.
                    let suffix = entry.group.flatMap { isWeekly($0) ? nil : $0 } ?? kind
                    name = "\(model) \(words(suffix))"
                }
                window = ClaudeLimit(identity: identity, kind: kind, group: entry.group, length: groupLength(entry.group),
                                     name: name, modelName: model, allowancePercentOfWeekly: allowances[entry.rawIndex],
                                     utilizationPercent: percent, resetsAt: entry.resetsAt)
            } else if entry.isSurfaceOnly {
                // A scope with only a surface is never shown (FR-001).
                skipped.append(entry.reportText)
                continue
            } else {
                let identity: ClaudeWindow
                let name: String
                if entry.rawIndex == sevenDayRaw {
                    identity = .sevenDay
                    name = sevenDayName
                } else if entry.rawIndex == fiveHourRaw {
                    identity = .fiveHour
                    name = fiveHourName
                } else {
                    identity = ClaudeWindow(rawValue: "limit:\(kind)")
                    // FR-005: an unknown group names the window (else its
                    // kind); a known group without its identity, the kind.
                    if groupLength(entry.group) == nil, let group = entry.group {
                        name = words(group)
                    } else {
                        name = words(kind)
                    }
                }
                window = ClaudeLimit(identity: identity, kind: kind, group: entry.group, length: groupLength(entry.group),
                                     name: name, modelName: nil, allowancePercentOfWeekly: nil,
                                     utilizationPercent: percent, resetsAt: entry.resetsAt)
            }
            guard seen.insert(window.identity).inserted else {
                skipped.append(entry.reportText)
                continue
            }
            read.append(entry.reportText)
            identities[entry.rawIndex] = window.identity
            if window.isModelLimit { modelLimits.append(window) } else { planWindows.append(window) }
        }

        let report = ClaudeWindowReport(usedFallback: usedFallback, read: read, skipped: skipped)
        return (ordered(planWindows) + modelLimits, report, identities)
    }

    /// FR-006: plan windows with a length from shortest to longest (equal
    /// lengths in response order), then plan windows without a length in
    /// response order. Model limits follow in response order.
    static func ordered(_ planWindows: [ClaudeLimit]) -> [ClaudeLimit] {
        let known = planWindows.enumerated().filter { $0.element.length != nil }
            .sorted { ($0.element.length!, $0.offset) < ($1.element.length!, $1.offset) }
            .map(\.element)
        return known + planWindows.filter { $0.length == nil }
    }
}
