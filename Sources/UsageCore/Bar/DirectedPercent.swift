import Foundation

/// A level value in the chosen direction (spec 030 FR-009, FR-010, FR-012,
/// `contracts/direction-presentation.md`): the shown number, its text, its
/// words for VoiceOver, and the bar's fill and tick. The level itself is
/// never decided here; it stays on the used value (FR-014).
public struct DirectedPercent: Equatable, Sendable {
    /// What the value is a share of, for the words past 100% (FR-012).
    public enum Kind: Sendable {
        case budget
        case window
    }

    /// The rounded used percent, the one direction used shows.
    public let usedPercent: Int
    public let direction: DisplayDirection

    public init(usedPercent: Int, direction: DisplayDirection) {
        self.usedPercent = usedPercent
        self.direction = direction
    }

    /// The used percent, or 100 minus it in direction remaining (FR-009);
    /// negative past 100% used. The used percent is clamped to the bounds
    /// of `PercentFormatter` first, so an absurd value never traps.
    public var value: Int {
        direction == .used ? usedPercent : 100 - PercentFormatter.clamped(usedPercent)
    }

    /// "70%" as today in direction used; "30%" or "−15%" (typographic minus
    /// U+2212) in direction remaining, without a "left" suffix, so the bar
    /// keeps its width (FR-009, FR-012).
    public var text: String {
        switch direction {
        case .used: return PercentFormatter.text(usedPercent)
        case .remaining: return value < 0 ? "\u{2212}\(-value)%" : "\(value)%"
        }
    }

    /// The value in words (FR-009, FR-012): the text as today in direction
    /// used; "30% left" in direction remaining, and past 100% used "15% over
    /// budget" for a budget or "15% over the limit" for a window instead of
    /// the sign.
    public func accessibilityText(_ kind: Kind) -> String {
        guard direction == .remaining else { return text }
        guard usedPercent > 100 else { return "\(value)% left" }
        return "\(usedPercent - 100)% " + (kind == .budget ? "over budget" : "over the limit")
    }

    /// The bar's fill from the unrounded `usedPercent` (FR-010): the used
    /// share, or the remaining share from the leading edge, clamped to
    /// 0...1; 0 when not finite, in both directions.
    public static func fill(usedPercent: Double, direction: DisplayDirection) -> Double {
        directed(share(usedPercent), direction: direction, finite: usedPercent.isFinite)
    }

    /// The pace tick at the expected used share, or at the expected
    /// remaining share in direction remaining (FR-010), clamped like the
    /// fill, so the bar and the tick keep their relation.
    public static func tick(expectedPercent: Double, direction: DisplayDirection) -> Double {
        directed(share(expectedPercent), direction: direction, finite: expectedPercent.isFinite)
    }

    /// `percent` as a share of the bar, clamped to 0...1; 0 when not finite.
    private static func share(_ percent: Double) -> Double {
        percent.isFinite ? min(max(percent / 100, 0), 1) : 0
    }

    private static func directed(_ share: Double, direction: DisplayDirection, finite: Bool) -> Double {
        guard finite else { return 0 }
        return direction == .used ? share : 1 - share
    }
}
