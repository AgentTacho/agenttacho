import AppKit
import SwiftUI
import UsageCore

extension BarItem {
    /// Plain-text form, for logs and accessibility: the entry's name, never
    /// its icon's name (spec 004 FR-004). The run-out marker is spelled out
    /// instead of its glyph (spec 011 FR-015).
    var text: String {
        "\(name) \(levelValueText)\(accessibilitySuffix)"
    }

    /// The part after the icon: level glyph, stale marker, value and the
    /// run-out marker (spec 011 FR-012).
    var valueText: String {
        levelValueText + (runOutMarker ? "↗" : "")
    }

    /// Level glyph, stale marker and value.
    private var levelValueText: String {
        let prefix: String
        switch level {
        case .normal: prefix = ""
        case .warning: prefix = "⚠"
        case .critical: prefix = "‼"
        }
        return "\(prefix)\(stale ? "~" : "")\(value)"
    }
}

/// Renders the bar items computed by `BarLayout` (spec 004 research R6).
/// Ordering, values and levels live in `UsageCore`.
enum BarLabelBuilder {
    /// Shown while no entry is configured for the bar, or before the first
    /// refresh has produced any entry.
    static let placeholder = "AgentMeter"

    static func plainText(_ items: [BarItem]) -> String {
        items.isEmpty ? placeholder : items.map(\.text).joined(separator: "  ")
    }

    /// The whole bar drawn into one template image: Font Awesome glyphs,
    /// then the values. `MenuBarExtra` labels drop images embedded in
    /// `Text`, but always show a plain image. As a template it follows the
    /// light or dark menu bar; level colors are not available there, so the
    /// glyph prefix in `valueText` carries FR-003.
    @MainActor
    static func image(_ items: [BarItem]) -> NSImage {
        let size = NSFont.menuBarFont(ofSize: 0).pointSize
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
        let text = NSMutableAttributedString()
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        if items.isEmpty {
            text.append(NSAttributedString(string: placeholder, attributes: attributes))
        }
        for (index, item) in items.enumerated() {
            if index > 0 { text.append(NSAttributedString(string: "  ", attributes: attributes)) }
            text.append(IconFont.attributed(item.icon, baseFont: font, color: .black))
            text.append(NSAttributedString(string: " " + item.valueText, attributes: attributes))
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

struct BarLabelView: View {
    let items: [BarItem]
    /// Draws the black template image in this color, for the Settings
    /// preview on a dark capsule (spec 008 FR-013, research R5). Nil keeps
    /// the plain image the menu bar tints itself.
    var tint: Color?

    var body: some View {
        if let tint {
            image.renderingMode(.template).foregroundStyle(tint)
                .accessibilityLabel(BarLabelBuilder.plainText(items))
        } else {
            image.accessibilityLabel(BarLabelBuilder.plainText(items))
        }
    }

    private var image: Image { Image(nsImage: BarLabelBuilder.image(items)) }
}
