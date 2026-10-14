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

    /// The icon as an attributed-string fragment in the given base font: the
    /// icon character in its Font Awesome font, slightly smaller so it sits
    /// within the text's cap height. `icon` is a catalog reference such as
    /// `"brands:claude"`; an unknown reference (rejected by validation, spec
    /// 004 FR-005) draws a question mark.
    static func attributed(_ icon: String, baseFont: NSFont, color: NSColor) -> NSAttributedString {
        guard let entry = IconCatalog.shared.icon(for: icon) else {
            return NSAttributedString(string: "?", attributes: [.font: baseFont, .foregroundColor: color])
        }
        let font = nsFont(for: entry.style, size: baseFont.pointSize * 0.92)
        return NSAttributedString(string: String(entry.character), attributes: [.font: font, .foregroundColor: color])
    }

    /// The icon as a small template image, for native menu items (pickers)
    /// that ignore custom fonts in `Text`.
    static func image(_ icon: String, size: CGFloat = NSFont.systemFontSize) -> NSImage {
        let text = attributed(icon, baseFont: NSFont.systemFont(ofSize: size), color: .black)
        let bounds = text.size()
        let image = NSImage(size: NSSize(width: ceil(bounds.width), height: ceil(bounds.height)), flipped: false) { rect in
            text.draw(at: NSPoint(x: 0, y: (rect.height - bounds.height) / 2))
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Text form of an icon inside windows (dropdown, settings), drawn with its
/// font. Concatenates with other `Text` values (spec 004 FR-004).
func labelText(_ icon: String, size: CGFloat = NSFont.systemFontSize) -> Text {
    guard let entry = IconCatalog.shared.icon(for: icon) else { return Text("?") }
    return Text(String(entry.character)).font(.custom(entry.style.postScriptName, fixedSize: size))
}

/// Item of a menu-style picker: the icon followed by the entry's name
/// (spec 004 FR-004). Native menu items ignore custom fonts, so the icon is
/// passed as an image.
@MainActor
func pickerText(_ icon: String, name: String) -> some View {
    Label {
        Text(name)
    } icon: {
        Image(nsImage: IconFont.image(icon))
    }
    .labelStyle(.titleAndIcon)
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
