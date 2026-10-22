import Foundation

/// One page of the General tab's sidebar in Settings, in sidebar order
/// (spec 034 FR-001, FR-002). The selected page is stored in the defaults
/// under `defaultsKey`, never in `config.json` (FR-003, research R2).
public enum GeneralSettingsPage: String, CaseIterable, Identifiable, Sendable {
    case refresh
    case appearance
    case weeklyWindow
    case notifications
    case sources
    case startup

    /// The defaults key of the selected page, next to the selected tab.
    public static let defaultsKey = "generalSettingsPage"

    /// The stored page, or Refresh for nil or an unknown value (FR-003).
    public init(stored: String?) {
        self = stored.flatMap(GeneralSettingsPage.init(rawValue:)) ?? .refresh
    }

    public var id: String { rawValue }

    /// The sidebar entry's name.
    public var title: String {
        switch self {
        case .refresh: return "Refresh"
        case .appearance: return "Appearance"
        case .weeklyWindow: return "Weekly window"
        case .notifications: return "Notifications"
        case .sources: return "Sources"
        case .startup: return "Startup"
        }
    }

    /// The system symbol of the sidebar entry (spec 034 clarification 3).
    public var systemImage: String {
        switch self {
        case .refresh: return "arrow.clockwise"
        case .appearance: return "paintbrush"
        case .weeklyWindow: return "calendar"
        case .notifications: return "bell"
        case .sources: return "folder"
        case .startup: return "power"
        }
    }
}
