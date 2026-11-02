import Foundation

/// The one timestamp parser of the Claude Code and Codex readers (spec 039
/// FR-015, research R5).
///
/// A fast path takes the forms the agents write, `YYYY-MM-DDTHH:MM:SSZ`
/// and `YYYY-MM-DDTHH:MM:SS.<1 to 9 digits>Z`, with ASCII digits and every
/// field in range, and computes the instant with integer arithmetic. It
/// keeps the first three fraction digits, as `ISO8601DateFormatter`
/// truncates to the millisecond, so both give the same instant at
/// millisecond precision. Every other form (an offset, a lowercase `z`, a
/// day the formatter rolls over such as hour 24 or February 30, a year
/// before the Gregorian switch) goes to the two cached formatters,
/// fractional first, as before. The system formatter costs about 25 µs a
/// call; the fast path allocates nothing.
public enum ISO8601Timestamp {
    public static func parse(_ text: String) -> Date? {
        let fast = text.utf8.withContiguousStorageIfAvailable { parseFast(UnsafeRawBufferPointer($0)) }
        if let fast { return fast ?? fallback(text) }
        var copy = text
        return copy.withUTF8 { parseFast(UnsafeRawBufferPointer($0)) } ?? fallback(text)
    }

    /// Today's formatters, for the forms the fast path does not take.
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func fallback(_ text: String) -> Date? {
        fractional.date(from: text) ?? plain.date(from: text)
    }

    /// The fast path; nil hands the text to the formatters.
    static func parseFast(_ bytes: UnsafeRawBufferPointer) -> Date? {
        let count = bytes.count
        // 20 bytes without a fraction, 21 + k with k fraction digits.
        guard count == 20 || (22...30).contains(count) else { return nil }
        guard bytes[4] == UInt8(ascii: "-"), bytes[7] == UInt8(ascii: "-"), bytes[10] == UInt8(ascii: "T"),
              bytes[13] == UInt8(ascii: ":"), bytes[16] == UInt8(ascii: ":"), bytes[count - 1] == UInt8(ascii: "Z") else {
            return nil
        }
        func number(_ start: Int, _ length: Int) -> Int? {
            var value = 0
            for index in start..<(start + length) {
                let digit = Int(bytes[index]) - 48
                guard digit >= 0, digit <= 9 else { return nil }
                value = value * 10 + digit
            }
            return value
        }
        guard let year = number(0, 4), let month = number(5, 2), let day = number(8, 2),
              let hour = number(11, 2), let minute = number(14, 2), let second = number(17, 2) else { return nil }
        // The formatter's Gregorian calendar is Julian before 1582, so the
        // fast path takes years it computes the same way only.
        guard (1900...9999).contains(year), (1...12).contains(month), day >= 1, day <= daysInMonth(year, month),
              hour <= 23, minute <= 59, second <= 59 else { return nil }
        var millisecond = 0
        if count > 20 {
            guard bytes[19] == UInt8(ascii: "."), let fraction = number(20, count - 21) else { return nil }
            let digits = count - 21
            millisecond = digits >= 3 ? fraction / pow10(digits - 3) : fraction * pow10(3 - digits)
        }
        let days = daysFromCivil(year, month, day)
        let milliseconds = ((days * 24 + hour) * 60 + minute) * 60_000 + second * 1000 + millisecond
        return Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    private static func pow10(_ exponent: Int) -> Int {
        var value = 1
        for _ in 0..<exponent { value *= 10 }
        return value
    }

    private static func daysInMonth(_ year: Int, _ month: Int) -> Int {
        switch month {
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// Days since 1970-01-01 of a proleptic Gregorian date (Howard
    /// Hinnant's `days_from_civil`).
    static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}
