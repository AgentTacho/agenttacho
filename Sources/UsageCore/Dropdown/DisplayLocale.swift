import Foundation

/// The locale for numbers and US dollar amounts. AgentTacho's UI is English
/// and every amount is in US dollars, so numbers read "48.2M", "48,213,507"
/// and "$108" whatever the region; dates, times and weekdays keep the
/// user's region (idea inbox english-number-format, amends spec 018 FR-003).
public enum DisplayLocale {
    public static let numbers = Locale(identifier: "en_US")
}

/// The format of the number fields in Settings (budget amounts, prices):
/// English numbers like everywhere else, while the parser also accepts a
/// decimal comma, so "99,50" and the decimal key of a German keyboard keep
/// working (idea inbox english-number-format).
public struct DecimalInputFormat: ParseableFormatStyle {
    public var maxFractionDigits: Int

    public init(maxFractionDigits: Int = 6) {
        self.maxFractionDigits = maxFractionDigits
    }

    public func format(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...maxFractionDigits)).locale(DisplayLocale.numbers))
    }

    public var parseStrategy: Strategy { Strategy() }

    public struct Strategy: ParseStrategy {
        public func parse(_ value: String) throws -> Decimal {
            try Decimal.FormatStyle(locale: DisplayLocale.numbers).parseStrategy.parse(Self.normalized(value))
        }

        /// The text with a decimal comma turned into a point: a German
        /// "1.234,50", or a single comma without a point that is not
        /// followed by exactly three digits (English grouping, "1,234")
        /// unless the integer part is 0 or empty ("0,375").
        static func normalized(_ value: String) -> String {
            let text = value.trimmingCharacters(in: .whitespaces)
            guard let comma = text.lastIndex(of: ",") else { return text }
            if let point = text.lastIndex(of: ".") {
                guard comma > point else { return text }
                return text.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            }
            guard text.filter({ $0 == "," }).count == 1 else { return text }
            let integer = text[..<comma]
            let fraction = text[text.index(after: comma)...]
            if fraction.count == 3 && !(integer.isEmpty || integer == "0") { return text }
            return text.replacingOccurrences(of: ",", with: ".")
        }
    }
}
