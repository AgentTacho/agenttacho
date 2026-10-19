import Foundation

/// The fill color of a row's bar (spec 025 FR-003): neutral, the orange
/// attention color, or red over the limit. The warning level colors of
/// spec 012 never color the bar.
public enum RowBarTone: Equatable, Sendable {
    case neutral
    case attention
    case overLimit
}

/// The orange note under a bar that calls for attention (spec 025 FR-004):
/// the pace summary of spec 011 and spec 017 with the run-out in the
/// section's time format. Only `RowBar` builds one, from its pace reading.
public struct PaceNote: Equatable, Sendable {
    /// For the status words and the spec 011 run-out.
    public let pace: Pace
    /// The spec 017 fast run-out; it replaces the spec 011 run-out in the text.
    public let fastRunOut: Date?

    init(_ reading: PaceReading) {
        pace = reading.pace
        fastRunOut = reading.burn?.fastRunOut
    }

    /// "15% ahead · runs out in 2d 13h", "15% ahead · burning fast · runs
    /// out in 3h 10m" (FR-004, FR-016).
    public func text(times: TimeText) -> String {
        pace.summary(runOutText: times.runOut, fastRunOut: fastRunOut)
    }

    /// Only the run-out time in the other form, the fast run-out when the
    /// row burns fast (spec 025 FR-019, amended by spec 026 FR-019b): the
    /// note already says the rest. Empty without a run-out, which a note
    /// never lacks, since it shows only on attention.
    public func tooltip(times: TimeText) -> String {
        (fastRunOut ?? pace.runOut).map(times.runOutTooltip) ?? ""
    }
}

/// What a window row or a budget draws below its first line (spec 025
/// FR-001 to FR-004, FR-009, FR-032, research R2): the fill share, the pace
/// tick, the fill tone and the note. The bar keeps its pace reading once
/// (FR-030) and derives the tick, the tone, the note and the accessibility
/// summary from it, so they cannot disagree. Only `make` and `budget` build
/// a bar.
public struct RowBar: Equatable, Sendable {
    /// The used percent as a share of the bar, 0 to 1 (FR-002).
    public let fill: Double
    /// Red over the limit (FR-003, FR-007), decided by the factory.
    private let overLimit: Bool
    /// The one pace source of the bar; nil without a pace (spec 011 FR-007).
    private let reading: PaceReading?

    private init(fill: Double, overLimit: Bool, reading: PaceReading?) {
        self.fill = fill
        self.overLimit = overLimit
        self.reading = reading
    }

    /// The bar of a window row with the unrounded `usedPercent`, whether a
    /// Codex limit is reached, and its pace reading. Red when the rounded
    /// percent, the one the row shows, is 100 or more or the limit is
    /// reached (FR-003, FR-007), otherwise orange with a note when the
    /// reading calls for attention, otherwise neutral. A used percent that
    /// is not finite draws an empty bar.
    public static func make(usedPercent: Double, limitReached: Bool, reading: PaceReading?) -> RowBar {
        let overLimit = limitReached || (usedPercent.isFinite && PercentFormatter.rounded(usedPercent) >= 100)
        return RowBar(fill: share(usedPercent), overLimit: overLimit, reading: reading)
    }

    /// The bar of a budget (FR-009): the fill is the unrounded spend share,
    /// and it is red exactly when the header's rounded percent
    /// (`GroupEntry.percent`) is 100 or more (FR-003), so a header of 99%
    /// never sits next to a red bar and 100% always does.
    public static func budget(_ entry: GroupEntry, reading: PaceReading?) -> RowBar {
        RowBar(fill: share(entry.usedPercent), overLimit: entry.percent >= 100, reading: reading)
    }

    /// `percent` as a share of the bar, clamped to 0...1; 0 when not finite.
    private static func share(_ percent: Double) -> Double {
        percent.isFinite ? min(max(percent / 100, 0), 1) : 0
    }

    /// The pace's expected percent as a share of the bar, 0 to 1; nil
    /// without a pace (FR-002, spec 011 FR-007).
    public var tick: Double? {
        reading.map { Self.share($0.pace.expectedPercent) }
    }

    /// Red over the limit, otherwise orange when the reading calls for
    /// attention, otherwise neutral (FR-003).
    public var tone: RowBarTone {
        if overLimit { return .overLimit }
        return reading?.callsForAttention == true ? .attention : .neutral
    }

    /// Set exactly when `tone` is `.attention` (FR-004).
    public var note: PaceNote? {
        tone == .attention ? reading.map(PaceNote.init) : nil
    }

    /// The pace summary for the row's accessibility label (FR-006): "on
    /// pace", "8% behind" or the note's text, also when no note shows; nil
    /// without a pace.
    public func accessibilitySummary(times: TimeText) -> String? {
        reading.map { PaceNote($0).text(times: times) }
    }
}
