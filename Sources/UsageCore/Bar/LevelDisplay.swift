import Foundation

/// How the bar colors an entry at a level (spec 012 FR-001).
public enum LevelColorStyle: String, CaseIterable, Codable, Sendable {
    /// Default: the value (and glyph) is drawn in the level color (FR-007).
    case text
    /// The entry is drawn on a rounded background in the level color (FR-008).
    case pill
    /// No color (FR-009).
    case off
}

/// The two level display settings of the configuration (spec 012 FR-001,
/// FR-002). They affect only how the bar presents levels, never the levels.
public struct LevelDisplaySettings: Equatable, Sendable {
    public var levelColor: LevelColorStyle
    /// Whether the bar shows the `⚠` and `‼` glyphs (FR-010).
    public var showSymbols: Bool

    public init(levelColor: LevelColorStyle = .text, showSymbols: Bool = false) {
        self.levelColor = levelColor
        self.showSymbols = showSymbols
    }

    /// Colored text without symbols (FR-001, FR-002).
    public static let `default` = LevelDisplaySettings()
}
