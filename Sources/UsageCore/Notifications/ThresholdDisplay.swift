import Foundation

/// The thresholds editor in the chosen direction (spec 030 FR-007, FR-015):
/// thresholds stay stored in used percent; in direction remaining each
/// field shows 100 minus its stored value and converts an entry back, so
/// switching the direction never changes what is stored (SC-004).
public enum ThresholdDisplay {
    /// A stored threshold T as the field shows it: T, or 100 − T. A
    /// hand-edited value is clamped first (`PercentFormatter.clamped`), so
    /// the editor never traps.
    public static func shown(stored: Int, direction: DisplayDirection) -> Int {
        direction == .used ? stored : 100 - PercentFormatter.clamped(stored)
    }

    /// An entered value L as it is stored: L, or 100 − L, clamped like
    /// `shown(stored:direction:)`.
    public static func stored(entered: Int, direction: DisplayDirection) -> Int {
        direction == .used ? entered : 100 - PercentFormatter.clamped(entered)
    }

    /// Whether any stored threshold is one no entry produces in either
    /// direction: 0 or below. The editor then shows
    /// `validationMessage(direction:)`.
    public static func hasInvalidStored(_ stored: [Int]) -> Bool {
        stored.contains { $0 <= 0 }
    }

    /// `stored` after an entry in field `slot` (0 or 1): the entry converted
    /// back to used percent, or the slot removed when the field is empty;
    /// thresholds beyond the two fields stay as they are (FR-015).
    public static func replacing(_ stored: [Int], slot: Int, entered: Int?, direction: DisplayDirection) -> [Int] {
        var first: Int? = stored.count > 0 ? stored[0] : nil
        var second: Int? = stored.count > 1 ? stored[1] : nil
        let value = entered.map { self.stored(entered: $0, direction: direction) }
        if slot == 0 { first = value } else { second = value }
        return [first, second].compactMap { $0 } + stored.dropFirst(2)
    }

    /// The message under the fields for an invalid entry.
    public static func validationMessage(direction: DisplayDirection) -> String {
        direction == .used ? "Use whole numbers greater than 0." : "Use whole numbers below 100."
    }

    /// "(20% over)" next to a stored threshold above 100 in direction
    /// remaining, whose field shows a negative number; nil otherwise.
    public static func caption(stored: Int, direction: DisplayDirection) -> String? {
        guard direction == .remaining, stored > 100 else { return nil }
        return "(\(stored - 100)% over)"
    }

    /// The prompts of the empty fields: the default thresholds 80 and 100,
    /// in the direction.
    public static func placeholders(direction: DisplayDirection) -> (first: String, second: String) {
        direction == .used ? ("80", "100") : ("20", "0")
    }

    /// The text after each field: "%" or "% left".
    public static func fieldSuffix(direction: DisplayDirection) -> String {
        direction == .used ? "%" : "% left"
    }

    /// The explanation under the fields (FR-007): when macOS notifies, how
    /// empty fields behave, and both levels, with the real limit always
    /// critical. `limitDescription` says what 100% means for the entry.
    public static func explanation(limitDescription: String, direction: DisplayDirection) -> String {
        switch direction {
        case .used:
            return "macOS notifies you once each time usage rises past one of these percentages of \(limitDescription). "
                + "Leave a field empty to turn it off. "
                + "The first value marks the entry as a warning, the second as critical (80% and 100% when empty). "
                + "A real limit at 100% is always critical. The Menu Bar tab sets how levels look."
        case .remaining:
            return "macOS notifies you once each time what is left of \(limitDescription) falls to one of these percentages. "
                + "Leave a field empty to turn it off. "
                + "The first value marks the entry as a warning, the second as critical (20% and 0% left when empty). "
                + "Running out at 0% left is always critical. The Menu Bar tab sets how levels look."
        }
    }

    /// The note about thresholds beyond the two fields, which only the
    /// configuration file sets, in the direction; nil without any.
    public static func furtherThresholds(_ stored: [Int], direction: DisplayDirection) -> String? {
        guard stored.count > 2 else { return nil }
        let texts = stored.dropFirst(2).map { value -> String in
            guard direction == .remaining else { return "\(value)%" }
            return value > 100 ? "\(value - 100)% over" : "\(shown(stored: value, direction: direction))% left"
        }
        return "Also active from the configuration file: \(texts.joined(separator: ", "))."
    }
}
