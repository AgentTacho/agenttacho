import AppKit
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
    let label: LabelContent
    /// "42%", "--" (unavailable), or "…" (no data yet).
    let value: String
    let level: Level
    let stale: Bool

    /// Plain-text form, for logs and accessibility.
    var text: String {
        "\(label.plain) \(valueText)"
    }

    /// The part after the label: level glyph, stale marker and value.
    var valueText: String {
        let prefix: String
        switch level {
        case .normal: prefix = ""
        case .warning: prefix = "⚠"
        case .critical: prefix = "‼"
        }
        return "\(prefix)\(stale ? "~" : "")\(value)"
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
                result.append(BarSegment(id: account.id, label: account.shownLabel, value: "…", level: .normal, stale: false))
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
            result.append(BarSegment(id: account.id, label: account.shownLabel, value: value, level: level, stale: stale))
        }
        for group in configuration.groups where group.shownInBar {
            guard let snapshot else {
                result.append(BarSegment(id: group.id, label: group.shownLabel, value: "…", level: .normal, stale: false))
                continue
            }
            guard let entry = snapshot.groups[group.id] else {
                result.append(BarSegment(id: group.id, label: group.shownLabel, value: "…", level: .normal, stale: false))
                continue
            }
            result.append(BarSegment(id: group.id, label: group.shownLabel, value: "\(entry.percent)%",
                                     level: level(percent: entry.percent, thresholds: group.thresholds), stale: entry.stale))
        }
        return result
    }

    static func plainText(_ segments: [BarSegment]) -> String {
        segments.isEmpty ? "LLM" : segments.map(\.text).joined(separator: "  ")
    }

    /// The whole bar drawn into one template image: labels as text or Font
    /// Awesome glyphs, then the values. `MenuBarExtra` labels drop images
    /// embedded in `Text`, but always show a plain image. As a template it
    /// follows the light or dark menu bar; level colors are not available
    /// there, so the glyph prefix in `valueText` carries FR-003.
    @MainActor
    static func image(_ segments: [BarSegment]) -> NSImage {
        let size = NSFont.menuBarFont(ofSize: 0).pointSize
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
        let text = NSMutableAttributedString()
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        if segments.isEmpty {
            text.append(NSAttributedString(string: "LLM", attributes: attributes))
        }
        for (index, segment) in segments.enumerated() {
            if index > 0 { text.append(NSAttributedString(string: "  ", attributes: attributes)) }
            text.append(IconFont.attributed(segment.label, baseFont: font, color: .black))
            text.append(NSAttributedString(string: " " + segment.valueText, attributes: attributes))
        }
        let bounds = text.size()
        let image = NSImage(size: NSSize(width: ceil(bounds.width), height: ceil(bounds.height)), flipped: false) { rect in
            text.draw(at: NSPoint(x: 0, y: (rect.height - bounds.height) / 2))
            return true
        }
        image.isTemplate = true
        return image
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
        Image(nsImage: BarLabelBuilder.image(segments))
            .accessibilityLabel(BarLabelBuilder.plainText(segments))
    }
}
