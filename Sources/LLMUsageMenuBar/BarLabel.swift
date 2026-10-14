import AppKit
import SwiftUI
import UsageCore

extension BarItem {
    /// Plain-text form, for logs and accessibility: the entry's name, never
    /// its icon's name (spec 004 FR-004).
    var text: String {
        "\(name) \(valueText)"
    }

    /// The part after the icon: level glyph, stale marker and value.
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

/// Renders the bar items computed by `BarLayout` (spec 004 research R6).
/// Ordering, values and levels live in `UsageCore`.
enum BarLabelBuilder {
    static func plainText(_ items: [BarItem]) -> String {
        items.isEmpty ? "LLM" : items.map(\.text).joined(separator: "  ")
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
            text.append(NSAttributedString(string: "LLM", attributes: attributes))
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

    var body: some View {
        Image(nsImage: BarLabelBuilder.image(items))
            .accessibilityLabel(BarLabelBuilder.plainText(items))
    }
}
