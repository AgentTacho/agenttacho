import Foundation

/// Text color on a level pill (spec 012 FR-008).
public enum PillTextColor: Equatable, Sendable {
    case black
    case white
}

/// WCAG 2 contrast math for the pill text color (spec 012 FR-008, SC-004,
/// research R3). The app resolves the pill fill for the current appearance
/// and asks which of black or white contrasts more with it.
public enum PillContrast {
    /// An sRGB color with components from 0 to 1.
    public struct RGB: Equatable, Sendable {
        public var red: Double
        public var green: Double
        public var blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    /// WCAG 2 relative luminance: 0 for black, 1 for white.
    public static func relativeLuminance(_ color: RGB) -> Double {
        func linear(_ c: Double) -> Double {
            let c = min(max(c, 0), 1)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    /// WCAG 2 contrast ratio, from 1 to 21; the order of the colors does not matter.
    public static func contrastRatio(_ a: RGB, _ b: RGB) -> Double {
        let la = relativeLuminance(a)
        let lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Black or white, whichever has the higher contrast ratio against the
    /// fill (black on a tie).
    public static func textColor(onFill fill: RGB) -> PillTextColor {
        let black = RGB(red: 0, green: 0, blue: 0)
        let white = RGB(red: 1, green: 1, blue: 1)
        return contrastRatio(black, fill) >= contrastRatio(white, fill) ? .black : .white
    }
}
