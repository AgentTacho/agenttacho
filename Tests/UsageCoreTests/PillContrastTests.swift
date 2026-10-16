import AppKit
import Foundation
import Testing
@testable import UsageCore

/// Spec 012 FR-008, SC-004, research R3: black or white text on a pill,
/// whichever contrasts more with the resolved fill, at least 4.5:1.
@Suite struct PillContrastTests {
    private static func rgb(_ hex: UInt32) -> PillContrast.RGB {
        PillContrast.RGB(red: Double((hex >> 16) & 0xFF) / 255,
                         green: Double((hex >> 8) & 0xFF) / 255,
                         blue: Double(hex & 0xFF) / 255)
    }

    private static let black = PillContrast.RGB(red: 0, green: 0, blue: 0)
    private static let white = PillContrast.RGB(red: 1, green: 1, blue: 1)

    @Test func relativeLuminanceOfReferenceColors() {
        #expect(PillContrast.relativeLuminance(Self.black) == 0)
        #expect(abs(PillContrast.relativeLuminance(Self.white) - 1) < 1e-9)
        // #808080: sRGB 0.502 linearizes to about 0.2159.
        #expect(abs(PillContrast.relativeLuminance(Self.rgb(0x808080)) - 0.2159) < 0.0005)
    }

    @Test func contrastRatioIsSymmetricAndBlackOnWhiteIs21() {
        #expect(abs(PillContrast.contrastRatio(Self.black, Self.white) - 21) < 1e-9)
        #expect(PillContrast.contrastRatio(Self.white, Self.black) == PillContrast.contrastRatio(Self.black, Self.white))
        let orange = Self.rgb(0xFF9500)
        #expect(PillContrast.contrastRatio(orange, Self.black) == PillContrast.contrastRatio(Self.black, orange))
        #expect(abs(PillContrast.contrastRatio(orange, orange) - 1) < 1e-9)
    }

    /// Reference fills: research R3's published orange and red in light,
    /// dark, light with increased contrast and dark with increased
    /// contrast, plus the values macOS 26 resolves for light and dark.
    /// The real colors are checked in `resolvedSystemFillsReachContrast`.
    @Test(arguments: [
        (UInt32(0xFF9500), PillTextColor.black), (0xFF3B30, .black), // light
        (0xFF9F0A, .black), (0xFF453A, .black), // dark
        (0xC93400, .white), (0xD70015, .white), // light, increased contrast
        (0xFFB340, .black), (0xFF6961, .black), // dark, increased contrast
        (0xFF8D28, .black), (0xFF383C, .black), // macOS 26 light
        (0xFF9230, .black), (0xFF4245, .black), // macOS 26 dark
    ])
    func textColorOnReferenceFills(fill hex: UInt32, expected: PillTextColor) {
        let fill = Self.rgb(hex)
        let chosen = PillContrast.textColor(onFill: fill)
        #expect(chosen == expected)
        let text = chosen == .black ? Self.black : Self.white
        #expect(PillContrast.contrastRatio(text, fill) >= 4.5)
    }

    /// SC-004 against the colors the app actually draws: `systemOrange` and
    /// `systemRed` resolved under the light and dark appearance of the
    /// running system, as `BarLabelBuilder.pillTextColor` resolves them.
    /// The increased-contrast variants follow the system setting and are
    /// covered by the walkthrough (the accessibility appearance names are
    /// not valid for `NSAppearance(named:)`).
    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func resolvedSystemFillsReachContrast(name: NSAppearance.Name) throws {
        let appearance = try #require(NSAppearance(named: name))
        var fills: [PillContrast.RGB] = []
        appearance.performAsCurrentDrawingAppearance {
            for color in [NSColor.systemOrange, NSColor.systemRed] {
                if let srgb = color.usingColorSpace(.sRGB) {
                    fills.append(PillContrast.RGB(red: Double(srgb.redComponent), green: Double(srgb.greenComponent),
                                                  blue: Double(srgb.blueComponent)))
                }
            }
        }
        #expect(fills.count == 2)
        for fill in fills {
            let text = PillContrast.textColor(onFill: fill) == .black ? Self.black : Self.white
            #expect(PillContrast.contrastRatio(text, fill) >= 4.5)
        }
    }

    /// The choice is the higher of the two ratios, also for other fills.
    @Test(arguments: [UInt32(0x000000), 0xFFFFFF, 0x808080, 0x0000FF, 0xFFFF00])
    func textColorPicksTheHigherRatio(fill hex: UInt32) {
        let fill = Self.rgb(hex)
        let blackRatio = PillContrast.contrastRatio(Self.black, fill)
        let whiteRatio = PillContrast.contrastRatio(Self.white, fill)
        let expected: PillTextColor = blackRatio >= whiteRatio ? .black : .white
        #expect(PillContrast.textColor(onFill: fill) == expected)
    }
}
