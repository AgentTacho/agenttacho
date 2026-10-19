import AppKit
import SwiftUI
import UsageCore

/// Renders the bar entries decided by `BarPresentation` (spec 004 research
/// R6, spec 012 FR-007 to FR-016). Ordering, values, levels and which part
/// gets which tone live in `UsageCore`; this only maps tones to colors and
/// draws.
enum BarLabelBuilder {
    /// Horizontal padding of a pill on each side of its entry (spec 012
    /// FR-008, contracts/bar-rendering.md).
    static let pillPadding: CGFloat = 3
    /// Vertical room above and below the text while a pill is drawn.
    static let pillVerticalPadding: CGFloat = 1
    /// Upper bound of the pill's corner radius.
    static let pillMaxCornerRadius: CGFloat = 4

    /// The bar drawn into one image: Font Awesome glyphs, then the values.
    /// `MenuBarExtra` labels drop images embedded in `Text`, but always show
    /// a plain image.
    ///
    /// When no part carries a level color, the image is a black template
    /// that macOS tints like the menu bar's other text, as before (spec 012
    /// FR-013, research R2). Otherwise it is a full-color image whose
    /// drawing handler resolves the dynamic system colors at draw time:
    /// under `appearance` when given (the Settings preview), else under the
    /// current drawing appearance (FR-011, FR-014, FR-015, research R1).
    /// `neutralOverride` replaces `labelColor` for neutral parts (research R5).
    @MainActor
    static func image(_ entries: [BarEntryPresentation], appearance: NSAppearance? = nil,
                      neutralOverride: NSColor? = nil) -> NSImage {
        let layout = Layout(entries)
        let bounds = layout.text.size()
        guard BarPresentation.usesColor(entries) else {
            let text = layout.text
            let size = NSSize(width: ceil(bounds.width), height: ceil(bounds.height))
            let image = NSImage(size: size, flipped: false) { rect in
                text.draw(at: NSPoint(x: 0, y: (rect.height - bounds.height) / 2))
                return true
            }
            image.isTemplate = true
            return image
        }
        // A pill at either end of the bar gets its padding inside the image;
        // between entries the padding is kern on the separator (FR-008).
        let leading = entries.first?.pill != nil ? pillPadding : 0
        let trailing = entries.last?.pill != nil ? pillPadding : 0
        let verticalPadding = layout.pills.isEmpty ? 0 : pillVerticalPadding
        let size = NSSize(width: ceil(leading + bounds.width + trailing),
                          height: ceil(bounds.height + 2 * verticalPadding))
        let image = NSImage(size: size, flipped: false) { rect in
            let draw = {
                for pill in layout.pills {
                    let pillRect = NSRect(x: leading + pill.minX - pillPadding, y: 0,
                                          width: pill.maxX - pill.minX + 2 * pillPadding, height: rect.height)
                    let radius = min(pillRect.height / 2, pillMaxCornerRadius)
                    pillFill(pill.level).setFill()
                    NSBezierPath(roundedRect: pillRect, xRadius: radius, yRadius: radius).fill()
                }
                let text = layout.colored(neutral: neutralOverride ?? .labelColor)
                text.draw(at: NSPoint(x: leading, y: (rect.height - bounds.height) / 2))
            }
            if let appearance {
                appearance.performAsCurrentDrawingAppearance(draw)
            } else {
                draw()
            }
            return true
        }
        // A cached bitmap from another appearance must never be reused (FR-014).
        image.cacheMode = .never
        return image
    }

    /// The attributed text of the bar in black, the ranges of each entry's
    /// parts so the colored path can recolor them by tone, and the
    /// horizontal extent of each pill.
    private struct Layout {
        struct Part {
            let range: NSRange
            let tone: BarTone
        }

        struct Pill {
            let level: BarLevel
            /// Start of the entry's icon and end of its value, in text coordinates.
            let minX: CGFloat
            let maxX: CGFloat
        }

        let text: NSAttributedString
        let parts: [Part]
        let pills: [Pill]

        @MainActor
        init(_ entries: [BarEntryPresentation]) {
            let size = NSFont.menuBarFont(ofSize: 0).pointSize
            let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            let text = NSMutableAttributedString()
            var parts: [Part] = []
            var pillRanges: [(BarLevel, NSRange)] = []
            if entries.isEmpty {
                text.append(NSAttributedString(string: BarPresentation.placeholder, attributes: attributes))
            }
            for (index, entry) in entries.enumerated() {
                if index > 0 {
                    // Two spaces as before; kern adds a pill's padding after
                    // the previous entry and before this one, so the full
                    // separator stays between adjacent pills (FR-008).
                    let separator = NSMutableAttributedString(string: "  ", attributes: attributes)
                    if entries[index - 1].pill != nil {
                        separator.addAttribute(.kern, value: BarLabelBuilder.pillPadding, range: NSRange(location: 0, length: 1))
                    }
                    if entry.pill != nil {
                        separator.addAttribute(.kern, value: BarLabelBuilder.pillPadding, range: NSRange(location: 1, length: 1))
                    }
                    text.append(separator)
                }
                let start = text.length
                let icon = IconFont.attributed(entry.icon, baseFont: font, color: .black)
                parts.append(Part(range: NSRange(location: text.length, length: icon.length), tone: entry.iconTone))
                text.append(icon)
                text.append(NSAttributedString(string: " ", attributes: attributes))
                // The headline window's tag in the icon's tone, inside the
                // pill, before glyph, stale marker and value (spec 027 FR-009).
                if let tag = entry.tag {
                    let tagText = NSAttributedString(string: tag, attributes: attributes)
                    parts.append(Part(range: NSRange(location: text.length, length: tagText.length), tone: entry.iconTone))
                    text.append(tagText)
                    text.append(NSAttributedString(string: " ", attributes: attributes))
                }
                // Glyph, then stale marker, then value (FR-010, FR-016).
                let value = NSAttributedString(string: (entry.glyph ?? "") + entry.valueText, attributes: attributes)
                parts.append(Part(range: NSRange(location: text.length, length: value.length), tone: entry.textTone))
                text.append(value)
                if let level = entry.pill {
                    pillRanges.append((level, NSRange(location: start, length: text.length - start)))
                }
                // The run-out marker follows the value in the neutral tone
                // (spec 011 FR-012); entries at a level never carry it.
                if let marker = entry.runOutMarker {
                    let markerText = NSAttributedString(string: marker, attributes: attributes)
                    parts.append(Part(range: NSRange(location: text.length, length: markerText.length), tone: .neutral))
                    text.append(markerText)
                }
            }
            self.text = text
            self.parts = parts
            self.pills = Self.measure(pillRanges, in: text)
        }

        /// The horizontal extent of each pill range, measured with a TextKit
        /// layout of the same attributed string; `draw(at:)` lays out a
        /// single line without a container width the same way.
        private static func measure(_ ranges: [(BarLevel, NSRange)], in text: NSAttributedString) -> [Pill] {
            guard !ranges.isEmpty else { return [] }
            let storage = NSTextStorage(attributedString: text)
            let manager = NSLayoutManager()
            let container = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                         height: CGFloat.greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            manager.addTextContainer(container)
            storage.addLayoutManager(manager)
            manager.ensureLayout(for: container)
            let usedWidth = manager.usedRect(for: container).width
            func x(_ characterIndex: Int) -> CGFloat {
                guard characterIndex < text.length else { return usedWidth }
                let glyph = manager.glyphIndexForCharacter(at: characterIndex)
                return manager.location(forGlyphAt: glyph).x
            }
            return ranges.map { level, range in
                Pill(level: level, minX: x(range.location), maxX: x(NSMaxRange(range)))
            }
        }

        /// The text with every part in the color of its tone, resolved under
        /// the current drawing appearance. Spaces and separators keep the
        /// neutral color; they draw nothing.
        func colored(neutral: NSColor) -> NSAttributedString {
            let result = NSMutableAttributedString(attributedString: text)
            result.addAttribute(.foregroundColor, value: neutral, range: NSRange(location: 0, length: result.length))
            for part in parts {
                result.addAttribute(.foregroundColor, value: BarLabelBuilder.color(part.tone, neutral: neutral), range: part.range)
            }
            return result
        }
    }

    /// The color of a tone (spec 012 FR-007, FR-011, contracts/bar-rendering.md).
    static func color(_ tone: BarTone, neutral: NSColor) -> NSColor {
        switch tone {
        case .neutral: return neutral
        case .warning: return .systemOrange
        case .overLimit: return .systemRed
        case .onPill(let level): return pillTextColor(level)
        }
    }

    /// Fill of the pill of a level: the level color (FR-008, FR-011).
    static func pillFill(_ level: BarLevel) -> NSColor {
        level == .critical ? .systemRed : .systemOrange
    }

    /// Black or white, whichever contrasts more with the pill fill as
    /// resolved for the current drawing appearance (FR-008, research R3).
    static func pillTextColor(_ level: BarLevel) -> NSColor {
        guard let fill = pillFill(level).usingColorSpace(.sRGB) else { return .black }
        let rgb = PillContrast.RGB(red: Double(fill.redComponent), green: Double(fill.greenComponent),
                                   blue: Double(fill.blueComponent))
        return PillContrast.textColor(onFill: rgb) == .black ? .black : .white
    }
}

/// The menu bar label, also used for the Settings preview (spec 008 FR-013).
struct BarLabelView: View {
    let items: [BarItem]
    let display: LevelDisplaySettings
    /// Renders for the preview's fixed dark capsule: dark-appearance level
    /// colors and white neutral parts (spec 012 FR-005, research R5).
    var preview: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        let entries = BarPresentation.entries(items, settings: display)
        image(entries)
            // Rebuilds the image when the appearance changes (FR-014).
            .id("\(colorScheme)-\(colorSchemeContrast)")
            .accessibilityLabel(BarPresentation.accessibilityText(entries))
    }

    @ViewBuilder
    private func image(_ entries: [BarEntryPresentation]) -> some View {
        if preview {
            let nsImage = BarLabelBuilder.image(entries, appearance: previewAppearance, neutralOverride: .white)
            // Follows the builder's own template decision (FR-013).
            if !nsImage.isTemplate {
                Image(nsImage: nsImage)
            } else {
                // The template drawn in white, as before (spec 008 FR-013).
                Image(nsImage: nsImage).renderingMode(.template).foregroundStyle(.white)
            }
        } else {
            // R1 primary path (T010 spike decision): no explicit appearance.
            Image(nsImage: BarLabelBuilder.image(entries))
        }
    }

    /// Dark appearance for the dark capsule (FR-005), the high-contrast
    /// variant when "Increase contrast" is on (FR-011). NSAppearance.h
    /// documents the accessibility names for `bestMatch(from:)` only and
    /// allows `NSAppearance(named:)` to return nil for them, so plain dark
    /// is the fallback; the preview never loses its dark rendering. The
    /// `.id` on `colorSchemeContrast` rebuilds the preview when it changes.
    private var previewAppearance: NSAppearance? {
        let highContrast = colorSchemeContrast == .increased
            ? NSAppearance(named: .accessibilityHighContrastDarkAqua) : nil
        return highContrast ?? NSAppearance(named: .darkAqua)
    }
}
