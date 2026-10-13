import AppKit
import CoreText
import SwiftUI
import UsageCore

/// Bundled Font Awesome Free fonts: registration and rendering helpers.
@MainActor
enum IconFont {
    private static var registered = false

    /// Registers the three fonts for this process. Safe to call more than once.
    static func register(log: DiagnosticLog? = nil) {
        guard !registered else { return }
        registered = true
        for (style, url) in IconCatalog.shared.fontURLs.sorted(by: { $0.key < $1.key }) {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                let message = error.map { "\($0.takeRetainedValue())" } ?? "unknown error"
                log?.append(source: "app", message: "icon font \(style.rawValue) not registered: \(message)")
            }
        }
    }

    static func nsFont(for style: IconStyle, size: CGFloat) -> NSFont {
        NSFont(name: style.postScriptName, size: size) ?? NSFont.systemFont(ofSize: size)
    }

    /// The label as an attributed-string fragment in the given base font: the
    /// icon character in its Font Awesome font, slightly smaller so it sits
    /// within the text's cap height, or the text itself.
    static func attributed(_ content: LabelContent, baseFont: NSFont, color: NSColor) -> NSAttributedString {
        switch content {
        case .text(let text):
            return NSAttributedString(string: text, attributes: [.font: baseFont, .foregroundColor: color])
        case .icon(let entry):
            let font = nsFont(for: entry.style, size: baseFont.pointSize * 0.92)
            return NSAttributedString(string: String(entry.character), attributes: [.font: font, .foregroundColor: color])
        }
    }
}

/// Text form of a label inside windows (dropdown, settings): the icon drawn
/// with its font, or the text. Concatenates with other `Text` values.
func labelText(_ content: LabelContent, size: CGFloat = NSFont.systemFontSize) -> Text {
    switch content {
    case .text(let text):
        return Text(text)
    case .icon(let entry):
        return Text(String(entry.character)).font(.custom(entry.style.postScriptName, fixedSize: size))
    }
}

/// Label for menu-style pickers, whose items are native menu items that
/// ignore custom fonts: the text label in front of the name, or the name
/// alone when an icon is set.
func pickerText(_ content: LabelContent, name: String) -> Text {
    switch content {
    case .text(let text): return Text("\(text)  \(name)")
    case .icon: return Text(name)
    }
}

/// A single icon drawn with its font, for larger sizes such as the picker grid.
struct IconGlyph: View {
    let entry: IconEntry
    var size: CGFloat = 20

    var body: some View {
        Text(String(entry.character))
            .font(.custom(entry.style.postScriptName, fixedSize: size))
    }
}
