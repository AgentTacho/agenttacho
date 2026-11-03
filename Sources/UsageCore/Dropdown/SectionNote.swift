import Foundation

/// How a section note is drawn (spec 025 FR-029): neutral in the secondary
/// color, warning in orange, alert in red.
public enum NoteStyle: Equatable, Sendable {
    case neutral
    case warning
    case alert
}

/// One note about the state of a section's values, with its text and
/// style decided here; the view only renders it (spec 025 FR-015, FR-029,
/// research R5, idea inbox dropdown-note-view-model). The texts are the
/// ones the dropdown showed before spec 025.
public struct SectionNote: Equatable, Sendable {
    public let text: String
    public let style: NoteStyle

    public init(text: String, style: NoteStyle) {
        self.text = text
        self.style = style
    }
}

/// The date formats of the section notes: abbreviated date with short
/// time ("Oct 21, 2026 at 9:30 AM") and short time alone, in the given
/// locale and time zone (spec 025 research R5).
public struct NoteDates: Sendable {
    private let dateTimeStyle: Date.FormatStyle
    private let timeStyle: Date.FormatStyle

    public init(locale: Locale, timeZone: TimeZone) {
        var calendar = locale.calendar
        calendar.timeZone = timeZone
        dateTimeStyle = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, calendar: calendar, timeZone: timeZone)
        timeStyle = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: timeZone)
    }

    public func dateTime(_ date: Date) -> String {
        date.formatted(dateTimeStyle)
    }

    public func time(_ date: Date) -> String {
        date.formatted(timeStyle)
    }
}

extension SectionNote {
    /// The notes of a Claude subscription section for its `state` (spec 010
    /// FR-005, FR-010, FR-015): none while values are current; for stale
    /// values the last good time, the error and the next retry or the rate
    /// limit (warning); a neutral note when not signed in, during a grace
    /// period and without any data; a warning for expired credentials; an
    /// alert for a rejected sign-in. Current values without any window
    /// (`windows` empty) get the neutral note "No limits reported" (spec 040
    /// edge case "no window at all").
    public static func claude(state: SubscriptionState?, windows: [ClaudeLimit]? = nil, credentialDirectory: String,
                              isPreliminary: Bool, nextRetryAt: Date?, endpointBlockedUntil: Date?, dates: NoteDates) -> [SectionNote] {
        switch state {
        case .ok?:
            return windows?.isEmpty == true ? [noLimitsReported] : []
        case .stale(let lastGoodAt, let error)?:
            var notes = [
                SectionNote(text: lastGoodAt.map { "Stale, last good value \(dates.dateTime($0))" } ?? "No data yet", style: .warning),
                SectionNote(text: error, style: .warning),
            ]
            if let nextRetryAt {
                notes.append(SectionNote(text: "Retrying at \(dates.time(nextRetryAt))", style: .warning))
            } else if let endpointBlockedUntil {
                notes.append(SectionNote(text: "Rate limited until \(dates.time(endpointBlockedUntil))", style: .warning))
            }
            return notes
        case .notSignedIn?:
            return [SectionNote(text: "Not signed in (no Claude Code credentials for \(credentialDirectory))", style: .neutral)]
        case .credentialsExpired?:
            return [SectionNote(text: "Credentials expired, run Claude Code to refresh them", style: .warning)]
        case .retrying(_, let error, let retryAt)?:
            return [SectionNote(text: "\(GraceNote.reason(claudeError: error)), retrying at \(dates.time(retryAt))", style: .neutral)]
        case .signInRejected(let lastGoodAt)?:
            var notes = [SectionNote(text: SignInRejectedNote.text(credentialDirectory: credentialDirectory), style: .alert)]
            if let lastGoodAt {
                notes.append(SectionNote(text: "Last good value \(dates.dateTime(lastGoodAt))", style: .alert))
            }
            return notes
        case nil:
            return [noData(isPreliminary: isPreliminary)]
        }
    }

    /// The note of a Codex section for where its values come from (spec 007
    /// FR-006, spec 010 FR-005, FR-012): none for live values; the
    /// observation time for a newer snapshot and local data (neutral); stale
    /// values with time and reason (warning); the reason when unavailable
    /// (neutral); a grace period (neutral). A rejected sign-in turns stale
    /// and unavailable into an alert.
    public static func codex(_ limits: CodexLimitsEntry, dates: NoteDates) -> SectionNote? {
        let observed = limits.observation.map { dates.dateTime($0.observedAt) } ?? "?"
        switch limits.state {
        case .live:
            return nil
        case .newerSnapshot:
            return SectionNote(text: "As of \(observed)", style: .neutral)
        case .stale(let reason):
            return SectionNote(text: "Stale, as of \(observed): \(reason)", style: limits.signInRejected ? .alert : .warning)
        case .localOnly:
            return SectionNote(text: "Local data, as of \(observed)", style: .neutral)
        case .unavailable(let reason):
            return SectionNote(text: reason, style: limits.signInRejected ? .alert : .neutral)
        case .retrying(let reason, let retryAt):
            return SectionNote(text: "\(GraceNote.reason(codexReason: reason)), retrying at \(dates.time(retryAt))", style: .neutral)
        }
    }

    /// A budget whose spend leaves out unpriced models (spec 001 FR-009).
    /// Model ids come from third-party records, so each is clipped to 32
    /// characters and at most three are named, the rest counted ("a, b, c
    /// and 2 more"), keeping the note and its VoiceOver text bounded (spec
    /// 043 FR-007).
    public static func budgetIncomplete(unpricedModels: [String]) -> SectionNote {
        let named = unpricedModels.prefix(maxNamedModels).map { Configuration.clipped($0) }.joined(separator: ", ")
        let more = unpricedModels.count - maxNamedModels
        return SectionNote(text: "incomplete, unpriced: \(named)\(more > 0 ? " and \(more) more" : "")", style: .warning)
    }

    /// How many unpriced models the "incomplete, unpriced" note names.
    static let maxNamedModels = 3

    /// A budget carried over a failed refresh: since the last successful
    /// refresh, or since launch without one.
    public static func budgetStale(since: Date?, dates: NoteDates) -> SectionNote {
        SectionNote(text: "stale since \(since.map(dates.dateTime) ?? "launch")", style: .warning)
    }

    /// An own budget without an amount whose Value as model is not in the
    /// effective price table: neutral, since the table changes through
    /// imports (spec 043 FR-007, spec 041 FR-013).
    public static func valueAsMissing(model: String) -> SectionNote {
        SectionNote(text: "\(OwnBudgetForm.valueAsLabel): \(model) has no price", style: .neutral)
    }

    /// A group without members (spec 009 FR-005).
    public static let emptyGroup = SectionNote(text: "No accounts in this group yet", style: .neutral)

    /// An ok Claude answer without any window (spec 040).
    public static let noLimitsReported = SectionNote(text: "No limits reported", style: .neutral)

    /// The plain marker of stale Codex and Unassigned values.
    public static let staleMarker = SectionNote(text: "stale", style: .warning)

    /// A section without values yet: "Refreshing…" while the first result
    /// is preliminary or missing, "No data" otherwise (spec 010 FR-015).
    public static func noData(isPreliminary: Bool) -> SectionNote {
        SectionNote(text: isPreliminary ? "Refreshing\u{2026}" : "No data", style: .neutral)
    }
}
