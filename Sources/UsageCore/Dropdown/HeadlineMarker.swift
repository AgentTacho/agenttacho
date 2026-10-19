import Foundation

/// What the marker slot of a window row in a Claude or Codex subscription
/// section shows (spec 027 FR-002, amendment 2026-10-19): `●` on the
/// headline row, dimmed while it is the default window, and the hollow `○`
/// on a hovered row a click would change. The view only maps `isDimmed` to
/// the secondary color (constitution II).
public enum HeadlineMarker: Equatable, Sendable {
    /// An empty slot: a row that is not the headline and not hovered.
    case none
    /// `○` on a hovered row that is not the headline.
    case hoverHint
    /// `●` on a headline row the user chose, in the primary color.
    case chosen
    /// `●` on the default window's headline row, in the secondary color.
    case defaultWindow

    /// The headline row never shows a hover state (FR-002).
    public static func of(isHeadline: Bool, isDefault: Bool, isHovered: Bool) -> HeadlineMarker {
        if isHeadline { return isDefault ? .defaultWindow : .chosen }
        return isHovered ? .hoverHint : .none
    }

    public var symbol: String {
        switch self {
        case .none: return ""
        case .hoverHint: return "○"
        case .chosen, .defaultWindow: return "●"
        }
    }

    /// Drawn in the secondary color instead of the primary one.
    public var isDimmed: Bool { self != .chosen }
}
