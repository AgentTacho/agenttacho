import Foundation

/// The fill color of a row's bar (spec 025 FR-003, amended by spec 030
/// FR-006): neutral, the orange attention color, or red at the critical
/// level. The warning level never colors the bar.
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
    /// The used percent as a share of the bar, 0 to 1 (FR-002), or the
    /// remaining share in direction remaining (spec 030 FR-010).
    public let fill: Double
    /// The row's level from its owner's thresholds, its rounded percent and
    /// its own reached limit (spec 030 FR-005); the row percent and the bar
    /// color both follow it, so they never disagree.
    public let level: BarLevel
    /// The one pace source of the bar; nil without a pace (spec 011 FR-007).
    private let reading: PaceReading?
    /// For the tick's position (spec 030 FR-010).
    private let direction: DisplayDirection

    private init(fill: Double, level: BarLevel, direction: DisplayDirection, reading: PaceReading?) {
        self.fill = fill
        self.level = level
        self.direction = direction
        self.reading = reading
    }

    /// The bar of a window row with the unrounded `usedPercent`, whether a
    /// Codex limit is reached, the account's `thresholds` and its pace
    /// reading. The level uses the rounded percent, the one the row shows,
    /// and only the row's own reached limit (spec 030 FR-003, FR-005); the
    /// cross-window rules belong to the bar entry and the section header.
    /// Red when critical (FR-006), otherwise orange with a note when the
    /// reading calls for attention, otherwise neutral. The fill and the
    /// tick follow `direction` (FR-010); the level never does (FR-014). A
    /// used percent that is not finite draws an empty bar and is normal,
    /// unless the limit is reached (FR-003).
    public static func make(usedPercent: Double, limitReached: Bool, thresholds: [Int], direction: DisplayDirection,
                            reading: PaceReading?) -> RowBar {
        let rounded = usedPercent.isFinite ? PercentFormatter.rounded(usedPercent) : nil
        return RowBar(fill: DirectedPercent.fill(usedPercent: usedPercent, direction: direction),
                      level: LevelThresholds(thresholds).level(usedPercent: rounded, atRealLimit: limitReached),
                      direction: direction, reading: reading)
    }

    /// The bar of a budget (FR-009): the fill is the unrounded spend share,
    /// and the level comes from the header's rounded percent
    /// (`GroupEntry.percent`) and the budget's `thresholds` (spec 030
    /// FR-005, FR-006), so a header of 99% never sits next to a red bar
    /// without a threshold below it and 100% always does. The fill and the
    /// tick follow `direction`, so a budget over its limit has an empty bar
    /// in direction remaining (spec 030 FR-010, FR-012).
    public static func budget(_ entry: GroupEntry, thresholds: [Int], direction: DisplayDirection, reading: PaceReading?) -> RowBar {
        RowBar(fill: DirectedPercent.fill(usedPercent: entry.usedPercent, direction: direction),
               level: LevelThresholds(thresholds).level(usedPercent: entry.percent), direction: direction, reading: reading)
    }

    /// The color of the row's percent (spec 030 FR-005): orange at the
    /// warning level, red at the critical level, primary otherwise.
    public var percentTone: PercentTone {
        PercentTone(level)
    }

    /// The pace's expected percent as a share of the bar, 0 to 1, at the
    /// expected remaining share in direction remaining; nil without a pace
    /// (FR-002, spec 011 FR-007, spec 030 FR-010).
    public var tick: Double? {
        reading.map { DirectedPercent.tick(expectedPercent: $0.pace.expectedPercent, direction: direction) }
    }

    /// Red at the critical level, otherwise orange when the reading calls
    /// for attention, otherwise neutral (FR-003, spec 030 FR-006): the
    /// warning level never colors the bar.
    public var tone: RowBarTone {
        if level == .critical { return .overLimit }
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
