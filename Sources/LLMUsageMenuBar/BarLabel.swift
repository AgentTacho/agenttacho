import SwiftUI
import UsageCore

/// One `<label> <percent>%` entry of the menu bar text (FR-002, FR-003).
struct BarSegment: Equatable, Identifiable {
    enum Level: Equatable {
        case normal
        case warning
        case critical
    }

    let id: String
    let label: String
    /// "42%", "--" (unavailable), or "…" (no data yet).
    let value: String
    let level: Level
    let stale: Bool

    var text: String {
        let prefix: String
        switch level {
        case .normal: prefix = ""
        case .warning: prefix = "⚠"
        case .critical: prefix = "‼"
        }
        return "\(label) \(prefix)\(stale ? "~" : "")\(value)"
    }
}

enum BarLabelBuilder {
    static let defaultWarningThreshold = 80

    /// Lowest configured threshold, or 80 when none is configured (FR-003).
    static func warningThreshold(_ thresholds: [Int]) -> Int {
        thresholds.filter { $0 > 0 }.min() ?? defaultWarningThreshold
    }

    static func level(percent: Int?, thresholds: [Int]) -> BarSegment.Level {
        guard let percent else { return .normal }
        if percent >= 100 { return .critical }
        if percent >= warningThreshold(thresholds) { return .warning }
        return .normal
    }

    /// Subscription accounts in configuration order, then groups in
    /// configuration order. Token-based accounts and Unassigned never appear.
    static func segments(snapshot: UsageSnapshot?, configuration: Configuration) -> [BarSegment] {
        var result: [BarSegment] = []
        for account in configuration.accounts {
            guard let settings = account.kind.subscription, settings.shownInBar else { continue }
            guard let snapshot else {
                result.append(BarSegment(id: account.id, label: account.label, value: "…", level: .normal, stale: false))
                continue
            }
            let entry = snapshot.subscriptions[account.id]
            let percent = entry?.status?.barPercent
            let stale: Bool
            let value: String
            switch entry?.state {
            case .ok?:
                stale = false
                value = PercentFormatter.text(percent)
            case .stale?:
                stale = percent != nil
                value = PercentFormatter.text(percent)
            case .notSignedIn?, .credentialsExpired?:
                stale = false
                value = "--"
            case nil:
                stale = false
                value = "…"
            }
            let level = entry?.state.isOk == true || entry?.state.isStale == true
                ? level(percent: percent, thresholds: settings.thresholds)
                : .normal
            result.append(BarSegment(id: account.id, label: account.label, value: value, level: level, stale: stale))
        }
        for group in configuration.groups where group.shownInBar {
            guard let snapshot else {
                result.append(BarSegment(id: group.id, label: group.label, value: "…", level: .normal, stale: false))
                continue
            }
            guard let entry = snapshot.groups[group.id] else {
                result.append(BarSegment(id: group.id, label: group.label, value: "…", level: .normal, stale: false))
                continue
            }
            result.append(BarSegment(id: group.id, label: group.label, value: "\(entry.percent)%",
                                     level: level(percent: entry.percent, thresholds: group.thresholds), stale: entry.stale))
        }
        return result
    }

    static func plainText(_ segments: [BarSegment]) -> String {
        segments.isEmpty ? "LLM" : segments.map(\.text).joined(separator: "  ")
    }

    /// Attributed form with color per level. `MenuBarExtra` may render the
    /// label as a template image and drop the color; the glyph prefix in
    /// `BarSegment.text` keeps FR-003 satisfied in that case.
    static func attributed(_ segments: [BarSegment]) -> AttributedString {
        guard !segments.isEmpty else { return AttributedString("LLM") }
        var result = AttributedString()
        for (index, segment) in segments.enumerated() {
            if index > 0 { result.append(AttributedString("  ")) }
            var part = AttributedString(segment.text)
            switch segment.level {
            case .normal: break
            case .warning: part.foregroundColor = .orange
            case .critical: part.foregroundColor = .red
            }
            result.append(part)
        }
        return result
    }
}

extension SubscriptionState {
    var isStale: Bool {
        if case .stale = self { return true }
        return false
    }
}

struct BarLabelView: View {
    let segments: [BarSegment]

    var body: some View {
        Text(BarLabelBuilder.attributed(segments))
            .monospacedDigit()
    }
}
