import Foundation
import Testing
@testable import UsageCore

/// spec 030 FR-007, FR-015, SC-004: the thresholds editor in the chosen
/// direction, while thresholds stay stored in used percent.
@Suite struct ThresholdDisplayTests {
    @Test func conversionInBothDirections() {
        for (stored, shown) in [(80, 20), (100, 0), (120, -20), (70, 30), (1, 99)] {
            #expect(ThresholdDisplay.shown(stored: stored, direction: .remaining) == shown)
            #expect(ThresholdDisplay.stored(entered: shown, direction: .remaining) == stored)
            #expect(ThresholdDisplay.shown(stored: stored, direction: .used) == stored)
            #expect(ThresholdDisplay.stored(entered: stored, direction: .used) == stored)
        }
    }

    /// SC-004: switching the direction never changes what is stored.
    @Test func roundTripKeepsEveryStoredValue() {
        for stored in -50...250 {
            for direction in DisplayDirection.allCases {
                let shown = ThresholdDisplay.shown(stored: stored, direction: direction)
                #expect(ThresholdDisplay.stored(entered: shown, direction: direction) == stored)
            }
        }
    }

    /// A hand-edited configuration file or a mistyped field can hold any
    /// `Int`; the conversion clamps instead of trapping, so Settings never
    /// crashes (spec 030 FR-015).
    @Test func extremeValuesNeverTrap() {
        for value in [Int.min, Int.min + 99, -1_000_000_001, Int.max, Int.max - 99] {
            for direction in DisplayDirection.allCases {
                _ = ThresholdDisplay.shown(stored: value, direction: direction)
                _ = ThresholdDisplay.stored(entered: value, direction: direction)
            }
        }
        #expect(ThresholdDisplay.shown(stored: Int.min, direction: .remaining) == 100 + 1_000_000_000)
        #expect(ThresholdDisplay.stored(entered: Int.min, direction: .remaining) == 100 + 1_000_000_000)
        #expect(ThresholdDisplay.shown(stored: Int.max, direction: .remaining) == 100 - 1_000_000_000)
        #expect(ThresholdDisplay.furtherThresholds([80, 100, Int.min, Int.max], direction: .remaining) != nil)
        #expect(!ThresholdDisplay.hasInvalidStored([80, Int.max]))
        #expect(ThresholdDisplay.hasInvalidStored([80, Int.min]))
    }

    /// A stored value no entry can produce in either direction: 0 or below.
    @Test func invalidStoredValues() {
        #expect(!ThresholdDisplay.hasInvalidStored([]))
        #expect(!ThresholdDisplay.hasInvalidStored([80, 100, 120]))
        #expect(ThresholdDisplay.hasInvalidStored([0]))
        #expect(ThresholdDisplay.hasInvalidStored([80, -20]))
    }

    /// US4 scenario 2: an entry in a field converts back to used percent;
    /// an empty field removes its slot; further thresholds stay.
    @Test func replacingASlot() {
        #expect(ThresholdDisplay.replacing([80, 100, 90], slot: 0, entered: 30, direction: .remaining) == [70, 100, 90])
        #expect(ThresholdDisplay.replacing([80, 100, 90], slot: 1, entered: nil, direction: .remaining) == [80, 90])
        #expect(ThresholdDisplay.replacing([80, 100, 90], slot: 0, entered: nil, direction: .used) == [100, 90])
        #expect(ThresholdDisplay.replacing([80, 100], slot: 1, entered: 90, direction: .used) == [80, 90])
        #expect(ThresholdDisplay.replacing([], slot: 1, entered: 0, direction: .remaining) == [100])
        #expect(ThresholdDisplay.replacing([80], slot: 1, entered: -20, direction: .remaining) == [80, 120])
        #expect(ThresholdDisplay.replacing([], slot: 0, entered: nil, direction: .used) == [])
    }

    /// Used: greater than 0; remaining: below 100, negatives included, so
    /// every positive stored threshold can be entered.
    @Test func validity() {
        func valid(_ entered: Int, _ direction: DisplayDirection) -> Bool {
            !ThresholdDisplay.hasInvalidStored([ThresholdDisplay.stored(entered: entered, direction: direction)])
        }
        #expect(valid(1, .used))
        #expect(valid(150, .used))
        #expect(!valid(0, .used))
        #expect(!valid(-5, .used))
        #expect(valid(99, .remaining))
        #expect(valid(0, .remaining))
        #expect(valid(-20, .remaining))
        #expect(!valid(100, .remaining))
        #expect(!valid(130, .remaining))
        #expect(ThresholdDisplay.validationMessage(direction: .used) == "Use whole numbers greater than 0.")
        #expect(ThresholdDisplay.validationMessage(direction: .remaining) == "Use whole numbers below 100.")
    }

    @Test func captionOnlyAboveHundredInRemaining() {
        #expect(ThresholdDisplay.caption(stored: 120, direction: .remaining) == "(20% over)")
        #expect(ThresholdDisplay.caption(stored: 100, direction: .remaining) == nil)
        #expect(ThresholdDisplay.caption(stored: 80, direction: .remaining) == nil)
        #expect(ThresholdDisplay.caption(stored: 120, direction: .used) == nil)
    }

    @Test func placeholdersAndSuffix() {
        #expect(ThresholdDisplay.placeholders(direction: .used).first == "80")
        #expect(ThresholdDisplay.placeholders(direction: .used).second == "100")
        #expect(ThresholdDisplay.placeholders(direction: .remaining).first == "20")
        #expect(ThresholdDisplay.placeholders(direction: .remaining).second == "0")
        #expect(ThresholdDisplay.fieldSuffix(direction: .used) == "%")
        #expect(ThresholdDisplay.fieldSuffix(direction: .remaining) == "% left")
    }

    /// FR-007: both directions name both levels, the real limit and how
    /// empty fields behave.
    @Test func explanationNamesBothLevels() {
        let used = ThresholdDisplay.explanation(limitDescription: "the weekly budget", direction: .used)
        #expect(used.contains("the weekly budget"))
        #expect(used.contains("Leave a field empty to turn it off."))
        #expect(used.contains("warning"))
        #expect(used.contains("critical"))
        #expect(used.contains("80% and 100% when empty"))
        #expect(used.contains("A real limit at 100% is always critical."))
        let remaining = ThresholdDisplay.explanation(limitDescription: "the weekly budget", direction: .remaining)
        #expect(remaining.contains("the weekly budget"))
        #expect(remaining.contains("Leave a field empty to turn it off."))
        #expect(remaining.contains("warning"))
        #expect(remaining.contains("critical"))
        #expect(remaining.contains("20% and 0% left when empty"))
        #expect(remaining.contains("always critical"))
        #expect(remaining != used)
    }

    /// The note about further thresholds speaks the same direction.
    @Test func furtherThresholdsInTheDirection() {
        #expect(ThresholdDisplay.furtherThresholds([80, 100], direction: .used) == nil)
        #expect(ThresholdDisplay.furtherThresholds([80, 100, 90, 95], direction: .used)
                == "Also active from the configuration file: 90%, 95%.")
        #expect(ThresholdDisplay.furtherThresholds([80, 100, 90, 120], direction: .remaining)
                == "Also active from the configuration file: 10% left, 20% over.")
    }
}
