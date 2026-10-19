import Foundation

/// The texts of the dropdown footer's status row (spec 025
/// FR-024, FR-025, research R6; spec 026 FR-012, FR-013).
public enum FooterText {
    /// "Last refreshed 16:54" for a refresh on the day of `now` in
    /// `calendar`'s time zone, "Last refreshed Oct 21, 16:54" for an earlier
    /// day. Without a refresh time: "Refreshing…" before the first result or
    /// while it is preliminary, "No successful refresh yet" otherwise. A
    /// known refresh time wins over "Refreshing…".
    public static func lastRefreshed(at: Date?, hasSnapshot: Bool, isPreliminary: Bool, now: Date, calendar: Calendar, locale: Locale) -> String {
        guard let at else {
            return !hasSnapshot || isPreliminary ? "Refreshing\u{2026}" : "No successful refresh yet"
        }
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        if calendar.isDate(at, inSameDayAs: now) {
            return "Last refreshed \(at.formatted(style.hour().minute()))"
        }
        return "Last refreshed \(at.formatted(style.month(.abbreviated).day().hour().minute()))"
    }

    /// The pace line text of spec 019 while a pace is slower than its base
    /// (spec 016 FR-016), nil otherwise: the accessibility value of the
    /// status text and one part of `statusTooltip` (spec 025 FR-025, spec
    /// 026 FR-013).
    public static func paceTooltip(_ status: RefreshPaceStatus?, now: Date, calendar: Calendar) -> String? {
        status?.text(now: now, calendar: calendar)
    }

    /// The tooltip of the status text in the footer's status row (spec 026
    /// FR-013): the full status text when the row truncates it, the pace
    /// line text while a pace is slowed (spec 025 FR-025), both joined by a
    /// line break when both apply, and nil otherwise. The view decides
    /// `isTruncated`; the accessibility value stays the pace text.
    public static func statusTooltip(statusText: String, isTruncated: Bool, paceText: String?) -> String? {
        let parts = [isTruncated ? statusText : nil, paceText].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}

/// One error line of the pinned footer, shown on one line and truncated,
/// with its full text as tooltip (spec 026 FR-011, research R6).
public struct FooterErrorLine: Equatable, Sendable {
    /// "Source: message", or "+N more" for the errors beyond the limit.
    public let text: String
    /// The full error, or every error on its own line for "+N more".
    public let tooltip: String

    public init(text: String, tooltip: String) {
        self.text = text
        self.tooltip = tooltip
    }
}

/// The source error lines of the pinned footer (spec 026 FR-011, research
/// R6), so many errors never crowd out the sections above it.
public enum FooterErrors {
    /// At most `limit` lines: every error when there are no more than
    /// `limit`, otherwise the first `limit - 1` errors and a last line "+N
    /// more" (N the hidden count) whose tooltip lists all errors.
    public static func visible(_ errors: [SourceError], limit: Int = 3) -> [FooterErrorLine] {
        let texts = errors.map { "\($0.sourceName): \($0.message)" }
        guard texts.count > limit else {
            return texts.map { FooterErrorLine(text: $0, tooltip: $0) }
        }
        let shown = max(limit - 1, 0)
        var lines = texts.prefix(shown).map { FooterErrorLine(text: $0, tooltip: $0) }
        lines.append(FooterErrorLine(text: "+\(texts.count - shown) more", tooltip: texts.joined(separator: "\n")))
        return lines
    }
}

/// The heights of the dropdown's scrolling sections and pinned footer
/// (spec 026 FR-010, FR-010a, FR-011).
public enum FooterLayout {
    /// The fixed height cap, used as is when the screen has room for it
    /// (spec 026 FR-010a).
    public static let maxCap: Double = 640
    /// The space kept free between the panel's bottom and the bottom of the
    /// screen's visible frame (spec 026 FR-010a).
    public static let screenMargin: Double = 8
    /// The sections' floor while the screen has room for it (spec 026 FR-011).
    public static let minimumSections: Double = 160

    /// The screen room: `available` (the panel's top edge to the bottom of
    /// its screen's visible frame) minus `margin`, never negative; unlimited
    /// when the screen is unknown (spec 026 FR-010a).
    public static func room(available: Double?, margin: Double = screenMargin) -> Double {
        guard let available else { return .infinity }
        return max(0, available - margin)
    }

    /// The height cap: the smaller of `maxCap` and the screen room, so 640 pt
    /// when the screen is unknown (spec 026 FR-010a).
    public static func cap(available: Double?, maxCap: Double = maxCap, margin: Double = screenMargin) -> Double {
        min(maxCap, room(available: available, margin: margin))
    }

    /// The sections area: all of the sections while they fit, otherwise what
    /// the height cap leaves above the footer, but never less than `minimum`
    /// (FR-011), unless the screen room is smaller than footer plus
    /// `minimum`: then the floor yields and the sections get the room minus
    /// the footer (FR-010a). min(content, room - footer, max(minimum,
    /// cap - footer)), never negative.
    public static func sectionsHeight(content: Double, footer: Double, cap: Double,
                                      room: Double = .infinity, minimum: Double = minimumSections) -> Double {
        max(0, min(content, room - footer, max(minimum, cap - footer)))
    }
}
