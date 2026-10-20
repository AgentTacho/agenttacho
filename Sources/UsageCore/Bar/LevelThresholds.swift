import Foundation

/// The warning and critical thresholds of one level owner (a Claude or
/// Codex subscription, a group budget or an own budget), derived from its
/// configured thresholds in used percent (spec 030 FR-002). Every level of
/// the menu bar and the dropdown goes through `decide(usedPercent:atRealLimit:)`
/// (FR-001), so the bar, the row percents, the section headers and the red
/// bar agree with the notifications.
public struct LevelThresholds: Equatable, Sendable {
    /// The lowest positive threshold, or 80 without one.
    public let warning: Int
    /// The second lowest positive threshold, or 100 with fewer than two.
    /// Duplicates count separately, so `[90, 90]` gives 90 (FR-002).
    public let critical: Int

    public init(_ thresholds: [Int]) {
        let positive = thresholds.filter { $0 > 0 }.sorted()
        warning = positive.first ?? BarLayout.defaultWarningThreshold
        critical = positive.count > 1 ? positive[1] : 100
    }

    /// The level of `usedPercent` and whether it comes from a real limit
    /// (FR-002, FR-003, FR-004), decided together so the accessibility
    /// words cannot drift from the level. A real limit is `atRealLimit` (a
    /// reached Codex limit, a full Claude 7-day window while another
    /// headline is chosen) or a used value at or above 100%; it is critical
    /// even without a value, since a reached limit is never hidden.
    /// Otherwise critical at or above the critical threshold (critical wins
    /// when both thresholds are equal), warning at or above the warning
    /// threshold, normal below it or without a value.
    public func decide(usedPercent: Int?, atRealLimit: Bool = false) -> LevelDecision {
        if atRealLimit || (usedPercent ?? 0) >= 100 { return LevelDecision(level: .critical, overLimit: true) }
        guard let used = usedPercent else { return LevelDecision(level: .normal, overLimit: false) }
        if used >= critical { return LevelDecision(level: .critical, overLimit: false) }
        return LevelDecision(level: used >= warning ? .warning : .normal, overLimit: false)
    }

    /// The level alone, from `decide(usedPercent:atRealLimit:)`.
    public func level(usedPercent: Int?, atRealLimit: Bool = false) -> BarLevel {
        decide(usedPercent: usedPercent, atRealLimit: atRealLimit).level
    }
}

/// One level with its cause (spec 030 FR-003, FR-004): `overLimit` is true
/// only for a critical level at a real limit, where the accessibility text
/// says "over limit" instead of "critical".
public struct LevelDecision: Equatable, Sendable {
    public let level: BarLevel
    public let overLimit: Bool

    public init(level: BarLevel, overLimit: Bool) {
        self.level = level
        self.overLimit = overLimit
    }
}

/// The color of a percent in the dropdown (spec 030 FR-005): a window row's
/// percent, a budget's percent and a section header's bold percent. Orange
/// at the warning level, red at the critical level, the primary color
/// otherwise; the app maps each tone to a color.
public enum PercentTone: Equatable, Sendable {
    case primary
    case warning
    case critical

    public init(_ level: BarLevel) {
        switch level {
        case .normal: self = .primary
        case .warning: self = .warning
        case .critical: self = .critical
        }
    }
}
