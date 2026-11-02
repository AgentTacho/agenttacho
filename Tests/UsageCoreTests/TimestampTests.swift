import Foundation
import Testing
@testable import UsageCore

/// The shared timestamp parser equals today's two `ISO8601DateFormatter`
/// instances at millisecond precision, both rounded to the nearest
/// millisecond (spec 039 FR-015, research R5).
@Suite struct TimestampTests {
    static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Today's parse: fractional first, then plain.
    static func reference(_ text: String) -> Date? {
        fractional.date(from: text) ?? plain.date(from: text)
    }

    static func milliseconds(_ date: Date?) -> Int64? {
        date.map { Int64(($0.timeIntervalSinceReferenceDate * 1000).rounded()) }
    }

    /// The fast path alone, without the formatter fallback.
    static func fast(_ text: String) -> Date? {
        var copy = text
        return copy.withUTF8 { ISO8601Timestamp.parseFast(UnsafeRawBufferPointer($0)) }
    }

    static func expectSame(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(milliseconds(ISO8601Timestamp.parse(text)) == milliseconds(reference(text)), "\(text)", sourceLocation: sourceLocation)
    }

    /// The forms the agents write, and fractions whose fourth digit is 5 or
    /// more, so the formatter's truncation is pinned against rounding.
    @Test(arguments: [
        "2026-10-14T19:44:01Z",
        "2026-10-14T19:44:01.5Z",
        "2026-10-14T19:44:01.08Z",
        "2026-10-14T19:44:01.080Z",
        "2026-10-14T19:44:01.080123Z",
        "2026-10-14T19:44:01.080123456Z",
        "2026-10-14T19:44:01.0805Z",
        "2026-10-14T19:44:01.999999Z",
        "2026-10-14T19:44:01.123999999Z",
        "2025-12-31T23:59:59.999Z",
        "2026-01-01T00:00:00Z",
        "2028-02-29T12:00:00Z",
        "2026-02-28T23:59:59.9999Z",
        "1999-12-31T23:59:59Z",
        "2100-03-01T00:00:00.001Z",
    ])
    func fastPathFormsEqualTheFormatter(_ text: String) {
        #expect(Self.reference(text) != nil)
        // The agents' forms never reach the formatter.
        #expect(Self.milliseconds(Self.fast(text)) == Self.milliseconds(Self.reference(text)))
        Self.expectSame(text)
    }

    @Test func truncatesToTheMillisecondAsTheFormatterDoes() {
        #expect(Self.milliseconds(ISO8601Timestamp.parse("2026-10-14T19:44:01.0805Z"))
            == Self.milliseconds(Self.reference("2026-10-14T19:44:01.080Z")))
        #expect(Self.milliseconds(ISO8601Timestamp.parse("2026-10-14T19:44:01.999999Z"))
            == Self.milliseconds(Self.reference("2026-10-14T19:44:01.999Z")))
    }

    /// Forms the fast path does not take go to the formatter.
    @Test(arguments: [
        "2026-10-14T19:44:01+02:00",
        "2026-10-14T19:44:01.5-05:30",
        "2026-10-14T19:44:01z",
        "2026-10-14T19:44:01.123z",
        "2026-10-14T19:44:01.1234567890Z",
    ])
    func fallbackFormsEqualTheFormatter(_ text: String) {
        #expect(Self.reference(text) != nil)
        #expect(Self.fast(text) == nil)
        Self.expectSame(text)
    }

    /// Text that neither parses yields nil both ways.
    @Test(arguments: [
        "2026-13-14T19:44:01Z",
        "2026-10-32T19:44:01Z",
        "2026-10-14T19:60:00Z",
        "2026-10-14T19:44:60Z",
        "2026-1a-14T19:44:01Z",
        "2026-10-14T19:44:01.Z",
        "",
        "2026-10-14 19:44:01Z",
        "yesterday at noon",
    ])
    func invalidTextYieldsNilBothWays(_ text: String) {
        #expect(Self.reference(text) == nil)
        #expect(ISO8601Timestamp.parse(text) == nil)
    }

    /// The formatter rolls hour 24 over into the next day and February 30
    /// into March, so these are not invalid for it. The fast path leaves
    /// them to the formatter, and both agree (FR-015).
    @Test(arguments: ["2026-10-14T24:00:00Z", "2026-02-30T10:00:00Z", "2026-04-31T10:00:00.250Z"])
    func formsTheFormatterRollsOverEqualTheFormatter(_ text: String) {
        #expect(Self.fast(text) == nil)
        Self.expectSame(text)
    }

    /// Every timestamp in the fixtures, Claude Code and Codex alike.
    @Test func everyFixtureTimestampEqualsTheFormatter() throws {
        let root = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let pattern = try NSRegularExpression(pattern: #""timestamp":"([^"]*)""#)
        var seen = Set<String>()
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text) { seen.insert(String(text[range])) }
            }
        }
        #expect(seen.count > 50)
        #expect(seen.contains("2026-10-16T09:05:00.123999999Z"))
        #expect(seen.contains("2026-10-16T11:06:00.000+02:00"))
        for text in seen.sorted() {
            Self.expectSame(text)
        }
    }
}
