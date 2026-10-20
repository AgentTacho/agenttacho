import Foundation
import Testing
@testable import UsageCore

/// spec 030 FR-009, FR-010, FR-012, `contracts/direction-presentation.md`:
/// a level value in the chosen direction, with its text, accessibility
/// words, bar fill and tick.
@Suite struct DirectedPercentTests {
    struct Row: Sendable, CustomTestStringConvertible {
        let used: Int
        let direction: DisplayDirection
        let value: Int
        let text: String
        let budget: String
        let window: String
        var testDescription: String { "\(used) \(direction)" }
    }

    /// The contract table plus the window words.
    static let table: [Row] = [
        Row(used: 70, direction: .used, value: 70, text: "70%", budget: "70%", window: "70%"),
        Row(used: 70, direction: .remaining, value: 30, text: "30%", budget: "30% left", window: "30% left"),
        Row(used: 100, direction: .remaining, value: 0, text: "0%", budget: "0% left", window: "0% left"),
        Row(used: 115, direction: .used, value: 115, text: "115%", budget: "115%", window: "115%"),
        Row(used: 115, direction: .remaining, value: -15, text: "\u{2212}15%", budget: "15% over budget", window: "15% over the limit"),
        Row(used: 104, direction: .remaining, value: -4, text: "\u{2212}4%", budget: "4% over budget", window: "4% over the limit"),
        Row(used: 0, direction: .remaining, value: 100, text: "100%", budget: "100% left", window: "100% left"),
    ]

    @Test(arguments: table)
    func contractTable(row: Row) {
        let percent = DirectedPercent(usedPercent: row.used, direction: row.direction)
        #expect(percent.value == row.value)
        #expect(percent.text == row.text)
        #expect(percent.accessibilityText(.budget) == row.budget)
        #expect(percent.accessibilityText(.window) == row.window)
    }

    /// FR-012: the minus sign is U+2212, never a hyphen or a dash.
    @Test func negativeValueUsesTheTypographicMinus() {
        let text = DirectedPercent(usedPercent: 115, direction: .remaining).text
        #expect(text.unicodeScalars.first == "\u{2212}")
        #expect(!text.contains("-"))
    }

    /// FR-010: the fill is the used share, or the remaining share, clamped.
    @Test func fillInBothDirections() {
        #expect(abs(DirectedPercent.fill(usedPercent: 70.4, direction: .used) - 0.704) < 1e-12)
        #expect(abs(DirectedPercent.fill(usedPercent: 70.4, direction: .remaining) - 0.296) < 1e-12)
        #expect(DirectedPercent.fill(usedPercent: 100, direction: .remaining) == 0)
        #expect(DirectedPercent.fill(usedPercent: 115, direction: .used) == 1)
        #expect(DirectedPercent.fill(usedPercent: 115, direction: .remaining) == 0)
        #expect(DirectedPercent.fill(usedPercent: 0, direction: .remaining) == 1)
        #expect(DirectedPercent.fill(usedPercent: -4, direction: .remaining) == 1)
        #expect(DirectedPercent.fill(usedPercent: -4, direction: .used) == 0)
    }

    @Test func tickInBothDirections() {
        #expect(DirectedPercent.tick(expectedPercent: 40, direction: .used) == 0.4)
        #expect(abs(DirectedPercent.tick(expectedPercent: 40, direction: .remaining) - 0.6) < 1e-12)
        #expect(DirectedPercent.tick(expectedPercent: 130, direction: .used) == 1)
        #expect(DirectedPercent.tick(expectedPercent: 130, direction: .remaining) == 0)
        #expect(DirectedPercent.tick(expectedPercent: -20, direction: .remaining) == 1)
    }

    /// An absurd used percent (a tiny budget with a large spend) never
    /// traps the remaining value; it is clamped like `PercentFormatter`.
    @Test func extremeValuesNeverTrap() {
        for used in [Int.min, Int.min + 42, Int.max] {
            for direction in DisplayDirection.allCases {
                let directed = DirectedPercent(usedPercent: used, direction: direction)
                _ = directed.text
                _ = directed.accessibilityText(.budget)
            }
        }
        #expect(DirectedPercent(usedPercent: Int.max, direction: .remaining).value == 100 - 1_000_000_000)
        #expect(DirectedPercent(usedPercent: Int.min, direction: .remaining).value == 100 + 1_000_000_000)
        #expect(PercentFormatter.rounded(spent: Decimal(string: "92233720368547758.50")!, budget: 1) == 1_000_000_000)
        #expect(PercentFormatter.rounded(spent: Decimal(string: "92.2337203685477585")!, budget: Decimal(string: "0.000000000000001")!)
                == 1_000_000_000)
        #expect(PercentFormatter.rounded(spent: -Decimal(string: "92233720368547758.50")!, budget: 1) == -1_000_000_000)
        #expect(PercentFormatter.rounded(spent: 115, budget: 100) == 115)
    }

    /// A value that is not finite draws nothing in either direction.
    @Test func nonFiniteInputGivesZero() {
        for value in [Double.nan, .infinity, -.infinity] {
            for direction in DisplayDirection.allCases {
                #expect(DirectedPercent.fill(usedPercent: value, direction: direction) == 0)
                #expect(DirectedPercent.tick(expectedPercent: value, direction: direction) == 0)
            }
        }
    }
}
