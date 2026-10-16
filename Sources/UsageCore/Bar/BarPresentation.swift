import Foundation

/// The color role of one drawn part of a bar entry (spec 012 FR-007 to
/// FR-009). The app maps each tone to a color; the decision which part gets
/// which tone is made here, without drawing (FR-020).
public enum BarTone: Equatable, Sendable {
    /// The menu bar's own text color (FR-013).
    case neutral
    /// The system orange (FR-011).
    case warning
    /// The system red (FR-011).
    case overLimit
    /// Black or white on the pill of this level, chosen by `PillContrast`
    /// for the resolved pill fill (FR-008).
    case onPill(BarLevel)
}

/// What the bar draws for one entry and how (spec 012 data-model
/// BarEntryPresentation). Derived from a `BarItem` and the level display
/// settings; no AppKit types.
public struct BarEntryPresentation: Equatable, Sendable, Identifiable {
    /// `BarItem.id`.
    public let id: String
    /// Catalog reference of the icon.
    public let icon: String
    /// `"⚠"` or `"‼"` when symbols are on and the entry is at a level (FR-010).
    public let glyph: String?
    /// The stale marker `~` (if stale) directly before the value (FR-016).
    public let valueText: String
    public let iconTone: BarTone
    /// Tone of the glyph, the stale marker and the value.
    public let textTone: BarTone
    /// The pill's level when the entry is drawn on a pill (FR-008).
    public let pill: BarLevel?
    /// The entry read with its level in words (FR-018).
    public let accessibilityText: String
    /// `"↗"` after the value when the entry runs out before its reset at the
    /// current pace (spec 011 FR-012), `"↑"` when it burns fast (spec 017
    /// FR-008). Only entries without a level carry it, so it is always drawn
    /// in the neutral tone.
    public let runOutMarker: String?

    public init(id: String, icon: String, glyph: String?, valueText: String, iconTone: BarTone,
                textTone: BarTone, pill: BarLevel?, accessibilityText: String, runOutMarker: String? = nil) {
        self.id = id
        self.icon = icon
        self.glyph = glyph
        self.valueText = valueText
        self.iconTone = iconTone
        self.textTone = textTone
        self.pill = pill
        self.accessibilityText = accessibilityText
        self.runOutMarker = runOutMarker
    }
}

/// The presentation decisions of the bar (spec 012 FR-007 to FR-018,
/// FR-020, `contracts/bar-rendering.md`). The level itself comes unchanged
/// from `BarLayout` (FR-017).
public enum BarPresentation {
    /// Shown, and read, while the bar has no entry (FR-013).
    public static let placeholder = "AgentMeter"

    /// One presentation per bar item, in bar order.
    public static func entries(_ items: [BarItem], settings: LevelDisplaySettings) -> [BarEntryPresentation] {
        items.map { entry($0, settings: settings) }
    }

    private static func entry(_ item: BarItem, settings: LevelDisplaySettings) -> BarEntryPresentation {
        let valueText = (item.stale ? "~" : "") + item.value
        let atLevel = item.level != .normal
        let glyph: String?
        switch item.level {
        case .normal: glyph = nil
        case .warning: glyph = settings.showSymbols ? "⚠" : nil
        case .critical: glyph = settings.showSymbols ? "‼" : nil
        }
        let iconTone: BarTone
        let textTone: BarTone
        let pill: BarLevel?
        switch settings.levelColor {
        case .text where atLevel:
            // FR-007: the value (and glyph) carries the level color, the icon stays neutral.
            iconTone = .neutral
            textTone = item.level == .critical ? .overLimit : .warning
            pill = nil
        case .pill where atLevel:
            // FR-008: the whole entry sits on the pill.
            iconTone = .onPill(item.level)
            textTone = .onPill(item.level)
            pill = item.level
        default:
            // FR-009 (Off) and every entry without a level.
            iconTone = .neutral
            textTone = .neutral
            pill = nil
        }
        return BarEntryPresentation(id: item.id, icon: item.icon, glyph: glyph, valueText: valueText,
                                    iconTone: iconTone, textTone: textTone, pill: pill,
                                    accessibilityText: accessibilityText(item, valueText: valueText),
                                    runOutMarker: item.runOutMarker ? (item.burnsFast ? "↑" : "↗") : nil)
    }

    /// `"<name> <valueText>"`, with "warning" or "over limit" before the
    /// value at a level, whatever the settings (FR-018). Never a glyph; the
    /// run-out marker is spelled out (spec 011 FR-015, spec 017 FR-011).
    private static func accessibilityText(_ item: BarItem, valueText: String) -> String {
        let text: String
        switch item.level {
        case .normal: text = "\(item.name) \(valueText)"
        case .warning: text = "\(item.name) warning \(valueText)"
        case .critical: text = "\(item.name) over limit \(valueText)"
        }
        return text + item.accessibilitySuffix
    }

    /// True when any part of the bar carries a level color, so the bar is
    /// drawn as a full-color image; otherwise it stays a template image
    /// tinted by the system (FR-013, research R2).
    public static func usesColor(_ entries: [BarEntryPresentation]) -> Bool {
        entries.contains { $0.iconTone != .neutral || $0.textTone != .neutral || $0.pill != nil }
    }

    /// The bar's accessibility text and plain-text form for log lines:
    /// entries joined by two spaces, the placeholder when empty (FR-018).
    public static func accessibilityText(_ entries: [BarEntryPresentation]) -> String {
        entries.isEmpty ? placeholder : entries.map(\.accessibilityText).joined(separator: "  ")
    }
}
