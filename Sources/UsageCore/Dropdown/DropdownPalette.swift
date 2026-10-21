import Foundation

/// The text colors of the dropdown (spec 032 FR-007): the primary and the
/// secondary text, the orange warning text, the red critical text, and the
/// blue of link-styled buttons ("Install", "Release notes", "Show account
/// details").
public enum DropdownTextRole: CaseIterable, Sendable {
    case primary, secondary, warning, critical, link
}

/// How the dropdown draws one text role (spec 032 FR-008, FR-009).
public enum DropdownTextColor: Equatable, Sendable {
    /// The system color the dropdown drew before spec 032 (label, secondary
    /// label, orange, red, link), resolved under the panel's appearance, so it
    /// still adapts to Increase Contrast.
    case system(DropdownTextRole)
    /// A fixed sRGB value, the same with and without Increase Contrast.
    case fixed(PillContrast.RGB)
}

/// The colors of one panel style (spec 032 FR-007 to FR-011, research R3):
/// the opaque background, the foreground the bands and hover fills are drawn
/// from, and the text colors. Each fixed text color reaches 4.5:1
/// against every background it can sit on, also with Increase Contrast.
public struct DropdownPalette: Equatable, Sendable {
    public let style: PanelStyle
    /// The panel's fixed, opaque background (FR-007, FR-009).
    public let background: PillContrast.RGB
    /// The color of the bands and hover fills at the same factors on both
    /// panels (FR-011): white on the dark panel, black on the light one.
    /// The view draws them with `Color.primary`, the label color, whose RGB
    /// this is; the label color's own alpha (below 1) makes the drawn fills
    /// weaker than `backgrounds` models them, so the contrast tests err on
    /// the safe side (FR-007, FR-013).
    public let foreground: PillContrast.RGB
    private let primary: DropdownTextColor
    private let secondary: DropdownTextColor
    private let warning: DropdownTextColor
    private let critical: DropdownTextColor
    private let link: DropdownTextColor

    /// The strength of the hover fill on a headline switch row (spec 027
    /// FR-002), shared by the view and the contrast tests (spec 032 FR-011).
    public static let hoverOpacity = 0.06

    public func text(_ role: DropdownTextRole) -> DropdownTextColor {
        switch role {
        case .primary: return primary
        case .secondary: return secondary
        case .warning: return warning
        case .critical: return critical
        case .link: return link
        }
    }

    /// The palette of a panel style (spec 032 FR-008, FR-009).
    ///
    /// The dark panel keeps today's background and system colors, except the
    /// critical text: system red missed 4.5:1 on the footer band with
    /// Increase Contrast and on a hover over a tinted band, so it is a fixed
    /// lighter red (clarification Q3, FR-008). The light panel has a fixed
    /// light background; its secondary text is a fixed gray, and its warning
    /// and critical text keep their orange and red hues in darker shades,
    /// because the system colors miss 4.5:1 there (FR-009). The system link
    /// blue misses 4.5:1 on the footer band, where the update line sits, so
    /// the link is a fixed lighter blue on the dark panel and a fixed darker
    /// blue on the light one (FR-007).
    public static func forStyle(_ style: PanelStyle) -> DropdownPalette {
        switch style {
        case .dark:
            return DropdownPalette(style: .dark,
                                   background: PillContrast.RGB(red: 0.12, green: 0.12, blue: 0.13),
                                   foreground: PillContrast.RGB(red: 1, green: 1, blue: 1),
                                   primary: .system(.primary), secondary: .system(.secondary),
                                   warning: .system(.warning), critical: .fixed(rgb(0xFF8A84)),
                                   link: .fixed(rgb(0x6CB4FF)))
        case .light:
            return DropdownPalette(style: .light,
                                   background: rgb(0xD5D6D9),
                                   foreground: PillContrast.RGB(red: 0, green: 0, blue: 0),
                                   primary: .system(.primary), secondary: .fixed(rgb(0x48484A)),
                                   warning: .fixed(rgb(0x7A2E00)), critical: .fixed(rgb(0x8A000A)),
                                   link: .fixed(rgb(0x003E99)))
        }
    }

    /// One background a text can sit on, composited over the panel
    /// (spec 032 FR-007).
    public struct Background: Equatable, Sendable {
        public enum Kind: CaseIterable, Sendable {
            /// The plain panel.
            case plain
            /// A tinted section band (spec 028 FR-005).
            case tinted
            /// The pinned footer's band (spec 028 FR-007).
            case footer
            /// The hover fill over a tinted band, the strongest hover.
            case hoverOnTinted
        }

        public let kind: Kind
        public let rgb: PillContrast.RGB
    }

    /// The plain panel, the tinted and the footer band (the panel blended
    /// with `foreground` at `BandStyle.opacity`), and the hover over the
    /// tinted band (blended again at `hoverOpacity`), in `Kind` order
    /// (spec 032 FR-007, FR-011).
    public func backgrounds(increasedContrast: Bool) -> [Background] {
        let tinted = blend(background, BandStyle.tinted.opacity(increasedContrast: increasedContrast))
        let footer = blend(background, BandStyle.footer.opacity(increasedContrast: increasedContrast))
        return [Background(kind: .plain, rgb: background),
                Background(kind: .tinted, rgb: tinted),
                Background(kind: .footer, rgb: footer),
                Background(kind: .hoverOnTinted, rgb: blend(tinted, Self.hoverOpacity))]
    }

    /// `foreground` drawn at `opacity` over an opaque `base`, per sRGB
    /// component, as SwiftUI draws an opaque color at an opacity.
    private func blend(_ base: PillContrast.RGB, _ opacity: Double) -> PillContrast.RGB {
        func mix(_ b: Double, _ f: Double) -> Double { b * (1 - opacity) + f * opacity }
        return PillContrast.RGB(red: mix(base.red, foreground.red), green: mix(base.green, foreground.green),
                                blue: mix(base.blue, foreground.blue))
    }

    private static func rgb(_ hex: UInt32) -> PillContrast.RGB {
        PillContrast.RGB(red: Double((hex >> 16) & 0xFF) / 255,
                         green: Double((hex >> 8) & 0xFF) / 255,
                         blue: Double(hex & 0xFF) / 255)
    }
}
