import Foundation

/// The user's choice for the dropdown's look (spec 032 FR-001): follow the
/// system appearance (the default), or always the dark or the light panel.
/// The raw values are the configuration strings (FR-003). It applies to the
/// dropdown only (FR-005).
public enum DropdownTheme: String, Codable, CaseIterable, Sendable {
    case auto
    case dark
    case light

    /// The panel the dropdown shows for this theme while the system is in
    /// dark (`true`) or light appearance (spec 032 FR-006): Auto follows the
    /// system, Dark and Light ignore it.
    public func panelStyle(systemIsDark: Bool) -> PanelStyle {
        switch self {
        case .auto: return systemIsDark ? .dark : .light
        case .dark: return .dark
        case .light: return .light
        }
    }
}

/// What a dropdown theme resolves to at a given moment (spec 032 FR-006).
public enum PanelStyle: Equatable, Sendable {
    case light
    case dark

    public var isDark: Bool { self == .dark }
}
