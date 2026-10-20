import Foundation

/// The run-out and fast-burn markers in the chosen direction (spec 030
/// FR-011): "↗" and "↑" while values fill up, "↘" and "↓" while they count
/// down. When a marker shows stays as in spec 011 FR-012 and spec 017 FR-008.
public enum RunOutGlyph {
    public static func text(burnsFast: Bool, direction: DisplayDirection) -> String {
        switch (direction, burnsFast) {
        case (.used, false): return "↗"
        case (.used, true): return "↑"
        case (.remaining, false): return "↘"
        case (.remaining, true): return "↓"
        }
    }
}
