import AppKit
import Foundation
import Testing
@testable import UsageCore

/// spec 032 FR-007 to FR-011, FR-013, SC-003: the colors of the light and
/// the dark panel, and every text color at 4.5:1 against every background
/// it can sit on, with the real system colors resolved as spec 012 does
/// for the menu bar pills.
@Suite struct DropdownPaletteTests {
    private typealias RGB = PillContrast.RGB

    private static func rgb(_ hex: UInt32) -> RGB {
        RGB(red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }

    private static let black = RGB(red: 0, green: 0, blue: 0)
    private static let white = RGB(red: 1, green: 1, blue: 1)
    private static let styles: [PanelStyle] = [.dark, .light]

    private static func close(_ a: RGB, _ b: RGB) -> Bool {
        abs(a.red - b.red) < 1e-9 && abs(a.green - b.green) < 1e-9 && abs(a.blue - b.blue) < 1e-9
    }

    private static func background(_ kind: DropdownPalette.Background.Kind, _ palette: DropdownPalette,
                                   increasedContrast: Bool) throws -> RGB {
        try #require(palette.backgrounds(increasedContrast: increasedContrast).first { $0.kind == kind }).rgb
    }

    // MARK: Table (data-model.md)

    /// FR-008: the dark panel keeps today's background and system colors;
    /// only the critical text is a fixed lighter red (clarification Q3).
    @Test func darkPaletteMatchesTheTable() {
        let dark = DropdownPalette.forStyle(.dark)
        #expect(dark.style == .dark)
        #expect(dark.background == RGB(red: 0.12, green: 0.12, blue: 0.13))
        #expect(dark.foreground == Self.white)
        #expect(dark.text(.primary) == .system(.primary))
        #expect(dark.text(.secondary) == .system(.secondary))
        #expect(dark.text(.warning) == .system(.warning))
        #expect(dark.text(.critical) == .fixed(Self.rgb(0xFF8A84)))
        #expect(dark.text(.link) == .fixed(Self.rgb(0x6CB4FF)))
    }

    /// FR-009: a fixed light background, darker fixed secondary, orange and
    /// red text.
    @Test func lightPaletteMatchesTheTable() {
        let light = DropdownPalette.forStyle(.light)
        #expect(light.style == .light)
        #expect(light.background == Self.rgb(0xD5D6D9))
        #expect(light.foreground == Self.black)
        #expect(light.text(.primary) == .system(.primary))
        #expect(light.text(.secondary) == .fixed(Self.rgb(0x48484A)))
        #expect(light.text(.warning) == .fixed(Self.rgb(0x7A2E00)))
        #expect(light.text(.critical) == .fixed(Self.rgb(0x8A000A)))
        #expect(light.text(.link) == .fixed(Self.rgb(0x003E99)))
    }

    @Test func hoverOpacityIsTheDropdownsHoverFill() {
        #expect(DropdownPalette.hoverOpacity == 0.06)
    }

    // MARK: Backgrounds

    @Test(arguments: [false, true])
    func backgroundsComeInKindOrder(increasedContrast: Bool) {
        for style in Self.styles {
            let kinds = DropdownPalette.forStyle(style).backgrounds(increasedContrast: increasedContrast).map(\.kind)
            #expect(kinds == [.plain, .tinted, .footer, .hoverOnTinted])
            #expect(kinds == DropdownPalette.Background.Kind.allCases)
        }
    }

    /// The panel blended with the foreground at the band factor, then the
    /// hover over the tinted band, checked against hand-computed values.
    @Test func backgroundsAreComposited() throws {
        let dark = DropdownPalette.forStyle(.dark)
        #expect(try Self.background(.plain, dark, increasedContrast: false) == dark.background)
        // 0.12 * 0.96 + 0.04 = 0.1552, 0.13 * 0.96 + 0.04 = 0.1648.
        let tinted = try Self.background(.tinted, dark, increasedContrast: false)
        #expect(Self.close(tinted, RGB(red: 0.1552, green: 0.1552, blue: 0.1648)))
        // 0.1552 * 0.94 + 0.06 = 0.205888, 0.1648 * 0.94 + 0.06 = 0.214912.
        let hover = try Self.background(.hoverOnTinted, dark, increasedContrast: false)
        #expect(Self.close(hover, RGB(red: 0.205888, green: 0.205888, blue: 0.214912)))

        let light = DropdownPalette.forStyle(.light)
        // Black at 0.12 over #D5D6D9: each component times 0.88.
        let footer = try Self.background(.footer, light, increasedContrast: true)
        #expect(Self.close(footer, RGB(red: 213.0 / 255 * 0.88, green: 214.0 / 255 * 0.88, blue: 217.0 / 255 * 0.88)))
        let lightTinted = try Self.background(.tinted, light, increasedContrast: true)
        #expect(Self.close(lightTinted, RGB(red: 213.0 / 255 * 0.92, green: 214.0 / 255 * 0.92, blue: 217.0 / 255 * 0.92)))
    }

    // MARK: Contrast (FR-007, FR-013)

    /// Every fixed text color reaches 4.5:1 against every background of its
    /// palette, with and without Increase Contrast.
    @Test(arguments: [false, true])
    func fixedTextColorsReachContrast(increasedContrast: Bool) {
        for style in Self.styles {
            let palette = DropdownPalette.forStyle(style)
            for role in DropdownTextRole.allCases {
                guard case .fixed(let text) = palette.text(role) else { continue }
                for background in palette.backgrounds(increasedContrast: increasedContrast) {
                    let ratio = PillContrast.contrastRatio(text, background.rgb)
                    #expect(ratio >= 4.5, "\(style) \(role) on \(background.kind): \(ratio)")
                }
            }
        }
    }

    private static func systemColor(_ role: DropdownTextRole) -> NSColor {
        switch role {
        case .primary: return .labelColor
        case .secondary: return .secondaryLabelColor
        case .warning: return .systemOrange
        case .critical: return .systemRed
        case .link: return .linkColor
        }
    }

    /// Every system text color, resolved under the panel's appearance and
    /// alpha-blended onto each background with the normal contrast setting,
    /// reaches 4.5:1. The increased-contrast system variants follow the
    /// system setting and cannot be resolved here (the accessibility
    /// appearance names are not valid for `NSAppearance(named:)`); the
    /// walkthrough covers them, as in spec 012.
    @Test func resolvedSystemTextColorsReachContrast() throws {
        for style in Self.styles {
            let palette = DropdownPalette.forStyle(style)
            let appearance = try #require(NSAppearance(named: style.isDark ? .darkAqua : .aqua))
            for role in DropdownTextRole.allCases {
                guard case .system(let systemRole) = palette.text(role) else { continue }
                #expect(systemRole == role)
                var resolved: NSColor?
                appearance.performAsCurrentDrawingAppearance {
                    resolved = Self.systemColor(systemRole).usingColorSpace(.sRGB)
                }
                let color = try #require(resolved, "\(style) \(role)")
                let alpha = Double(color.alphaComponent)
                for background in palette.backgrounds(increasedContrast: false) {
                    let bg = background.rgb
                    let text = RGB(red: Double(color.redComponent) * alpha + bg.red * (1 - alpha),
                                   green: Double(color.greenComponent) * alpha + bg.green * (1 - alpha),
                                   blue: Double(color.blueComponent) * alpha + bg.blue * (1 - alpha))
                    let ratio = PillContrast.contrastRatio(text, bg)
                    #expect(ratio >= 4.5, "\(style) \(role) on \(background.kind): \(ratio)")
                }
            }
        }
    }

    // MARK: Bands (FR-011)

    /// A band differs from the plain panel in both palettes, and the light
    /// band is no stronger than the dark one. `BandStyle` is not
    /// `CaseIterable`, so the bands are listed explicitly, as in
    /// `SectionBandsTests`, plus the hover over a tinted band.
    @Test(arguments: [false, true])
    func bandsAreVisibleAndNoStrongerOnTheLightPanel(increasedContrast: Bool) throws {
        let kinds: [DropdownPalette.Background.Kind] = [.tinted, .footer, .hoverOnTinted]
        let dark = DropdownPalette.forStyle(.dark)
        let light = DropdownPalette.forStyle(.light)
        for kind in kinds {
            let darkRatio = PillContrast.contrastRatio(try Self.background(kind, dark, increasedContrast: increasedContrast), dark.background)
            let lightRatio = PillContrast.contrastRatio(try Self.background(kind, light, increasedContrast: increasedContrast), light.background)
            #expect(darkRatio > 1.0, "dark \(kind): \(darkRatio)")
            #expect(lightRatio > 1.0, "light \(kind): \(lightRatio)")
            #expect(lightRatio <= darkRatio, "\(kind): light \(lightRatio), dark \(darkRatio)")
        }
    }

    /// `color` resolved under the panel's appearance, in sRGB, with its alpha.
    private static func resolve(_ color: NSColor, _ style: PanelStyle) throws -> (rgb: RGB, alpha: Double) {
        let appearance = try #require(NSAppearance(named: style.isDark ? .darkAqua : .aqua))
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance { resolved = color.usingColorSpace(.sRGB) }
        let c = try #require(resolved, "\(style)")
        return (RGB(red: Double(c.redComponent), green: Double(c.greenComponent), blue: Double(c.blueComponent)),
                Double(c.alphaComponent))
    }

    /// `color` at `opacity` over an opaque `base`, per sRGB component.
    private static func over(_ color: RGB, _ opacity: Double, _ base: RGB) -> RGB {
        func mix(_ b: Double, _ f: Double) -> Double { b * (1 - opacity) + f * opacity }
        return RGB(red: mix(base.red, color.red), green: mix(base.green, color.green), blue: mix(base.blue, color.blue))
    }

    /// The views draw bands and hover fills with `Color.primary`, the label
    /// color. Its RGB is the palette's `foreground` and its alpha is at most
    /// 1, so the modeled fills are an upper bound of the drawn ones (FR-007);
    /// the drawn bands, at the label color's alpha, still differ from the
    /// panel and are no stronger on the light panel (FR-011).
    @Test(arguments: [false, true])
    func drawnBandsMatchTheModel(increasedContrast: Bool) throws {
        var ratios: [PanelStyle: Double] = [:]
        for style in Self.styles {
            let palette = DropdownPalette.forStyle(style)
            let label = try Self.resolve(.labelColor, style)
            #expect(abs(label.rgb.red - palette.foreground.red) < 0.01, "\(style) label \(label.rgb)")
            #expect(abs(label.rgb.green - palette.foreground.green) < 0.01, "\(style) label \(label.rgb)")
            #expect(abs(label.rgb.blue - palette.foreground.blue) < 0.01, "\(style) label \(label.rgb)")
            #expect(label.alpha <= 1)
            let factor = BandStyle.tinted.opacity(increasedContrast: increasedContrast) * label.alpha
            let ratio = PillContrast.contrastRatio(Self.over(label.rgb, factor, palette.background), palette.background)
            #expect(ratio > 1.0, "\(style) drawn band: \(ratio)")
            ratios[style] = ratio
        }
        let light = try #require(ratios[.light]), dark = try #require(ratios[.dark])
        #expect(light <= dark, "drawn band: light \(light), dark \(dark)")
    }

    /// The bar track (`RowBarView`, the secondary color at 0.25) stays
    /// visible on the plain panel and on a tinted band in both panels
    /// (FR-010, FR-011).
    @Test(arguments: [false, true])
    func barTrackIsVisible(increasedContrast: Bool) throws {
        for style in Self.styles {
            let palette = DropdownPalette.forStyle(style)
            let secondary = try Self.resolve(.secondaryLabelColor, style)
            for background in palette.backgrounds(increasedContrast: increasedContrast)
            where background.kind == .plain || background.kind == .tinted {
                let track = Self.over(secondary.rgb, 0.25 * secondary.alpha, background.rgb)
                let ratio = PillContrast.contrastRatio(track, background.rgb)
                #expect(ratio > 1.0, "\(style) track on \(background.kind): \(ratio)")
            }
        }
    }
}
