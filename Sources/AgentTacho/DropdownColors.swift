import SwiftUI
import UsageCore

/// The dropdown's text colors as SwiftUI styles, built from the palette of
/// the current panel style and handed to the dropdown's views through the
/// environment (spec 032 FR-007 to FR-009). System roles map to the styles
/// the views used before, the hierarchical `.primary` and `.secondary` and
/// the system orange and red, so the dark panel draws as before (FR-008);
/// fixed roles map to their sRGB value.
struct DropdownColors {
    let primary: AnyShapeStyle
    let secondary: AnyShapeStyle
    let warning: AnyShapeStyle
    let critical: AnyShapeStyle
    /// The text of link-styled buttons (spec 032 FR-007).
    let link: AnyShapeStyle

    init(_ palette: DropdownPalette) {
        primary = Self.style(palette.text(.primary))
        secondary = Self.style(palette.text(.secondary))
        warning = Self.style(palette.text(.warning))
        critical = Self.style(palette.text(.critical))
        link = Self.style(palette.text(.link))
    }

    private init(primary: AnyShapeStyle, secondary: AnyShapeStyle, warning: AnyShapeStyle, critical: AnyShapeStyle,
                 link: AnyShapeStyle) {
        self.primary = primary
        self.secondary = secondary
        self.warning = warning
        self.critical = critical
        self.link = link
    }

    /// The colors of each panel, built once, so every body evaluation hands
    /// the dropdown's views the same values.
    private static let dark = DropdownColors(.forStyle(.dark))
    private static let light = DropdownColors(.forStyle(.light))

    /// The colors of a panel style (spec 032 FR-006, FR-007).
    static func forStyle(_ style: PanelStyle) -> DropdownColors {
        style.isDark ? dark : light
    }

    /// The system colors the views drew before spec 032, the default outside
    /// the dropdown's injected palette: a view reused elsewhere keeps the
    /// system colors of its window (FR-005).
    static let system = DropdownColors(primary: AnyShapeStyle(.primary), secondary: AnyShapeStyle(.secondary),
                                       warning: AnyShapeStyle(Color.orange), critical: AnyShapeStyle(Color.red),
                                       link: AnyShapeStyle(Color(nsColor: .linkColor)))

    private static func style(_ color: DropdownTextColor) -> AnyShapeStyle {
        switch color {
        case .system(.primary): AnyShapeStyle(.primary)
        case .system(.secondary): AnyShapeStyle(.secondary)
        case .system(.warning): AnyShapeStyle(Color.orange)
        case .system(.critical): AnyShapeStyle(Color.red)
        case .system(.link): AnyShapeStyle(Color(nsColor: .linkColor))
        case .fixed(let rgb): AnyShapeStyle(Color(rgb))
        }
    }
}

private struct DropdownColorsKey: EnvironmentKey {
    static let defaultValue = DropdownColors.system
}

extension EnvironmentValues {
    var dropdownColors: DropdownColors {
        get { self[DropdownColorsKey.self] }
        set { self[DropdownColorsKey.self] = newValue }
    }
}

/// A link-styled button in the dropdown's link color (spec 032 FR-007): the
/// system link and borderless styles draw in the system link or accent
/// color, which misses 4.5:1 on the footer band and on the light panel.
struct DropdownLinkButtonStyle: ButtonStyle {
    let color: AnyShapeStyle

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .foregroundStyle(color)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

extension View {
    /// The dropdown's link style when a color is given, the system link
    /// style otherwise (spec 032 FR-005, FR-007).
    @ViewBuilder
    func linkButtonStyle(_ color: AnyShapeStyle?) -> some View {
        if let color {
            buttonStyle(DropdownLinkButtonStyle(color: color))
        } else {
            buttonStyle(.link)
        }
    }
}

extension Color {
    /// An sRGB color from UsageCore, for the panel background and the fixed
    /// text colors (spec 032 FR-007, FR-009).
    init(_ rgb: PillContrast.RGB) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
