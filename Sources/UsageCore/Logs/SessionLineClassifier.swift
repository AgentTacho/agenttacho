import Foundation

/// The record type of one session line (spec 039 FR-013, FR-014, research
/// R4, data-model "SessionLineKind").
public enum SessionLineKind: Equatable, Hashable, Sendable {
    /// The line's own `type` is `assistant`: decoded for a usage record.
    case assistant
    /// The line's own `type` is `api-request-shape`: searched for
    /// configured directories (spec 037 FR-001).
    case shape
    /// The scans found no decidable top-level `type`, and the line holds a
    /// candidate marker: handled as every line was before, decoded, then
    /// searched for directories when it yields no record.
    case undecided
    /// Anything else: skipped.
    case other
}

/// Decides a line's record type from its top-level `type` member without
/// decoding the line (spec 039 FR-013, research R4).
///
/// 1. A forward scan of the first `headBudget` bytes and, when the line
///    ends in `}`, a backward scan of the last `tailBudget` bytes look for
///    the line's own `type` key: a string at nesting depth 1 followed by
///    `:`. Both track string state (escapes forward, backslash parity
///    backward) and the depth of `{` and `[` outside strings, so a `type`
///    key nested in the message content, such as a tool call's input,
///    never decides. Its value decides: `assistant`, `api-request-shape`,
///    or `.other` for any other string or a value that is not a string.
///    User, shape and system lines carry it in their first 130 bytes,
///    assistant lines in their last 1.2 KB.
/// 2. When neither scan decides, the whole line is searched with `memmem`
///    for the four markers the record parser and the shape detection
///    search: a hit is `.undecided`, no hit `.other`. So a line whose own
///    key sits elsewhere is handled exactly as before.
///
/// The scans compare one string with two constants; they extract no field
/// (spec 039 FR-020).
enum SessionLineClassifier {
    /// Bytes the forward scan reads at most.
    static let headBudget = 256
    /// Bytes the backward scan reads at most.
    static let tailBudget = 4096
    /// Raw bytes of a top-level `type` value read at most. Without an
    /// escape, a longer value decodes to more characters than either
    /// candidate has, so it is `.other`.
    static let valueCap = 128

    static func classify(_ line: UnsafeRawBufferPointer) -> SessionLineKind {
        switch scanHead(line) {
        case .decided(let kind): return kind
        case .fallback: return markerFallback(line)
        case .none: break
        }
        switch scanTail(line) {
        case .decided(let kind): return kind
        case .fallback, .none: return markerFallback(line)
        }
    }

    /// The forward scan's decision, nil when it decides nothing (for tests).
    static func headScan(_ line: UnsafeRawBufferPointer) -> SessionLineKind? {
        if case .decided(let kind) = scanHead(line) { return kind }
        return nil
    }

    /// The backward scan's decision, nil when it decides nothing (for tests).
    static func tailScan(_ line: UnsafeRawBufferPointer) -> SessionLineKind? {
        if case .decided(let kind) = scanTail(line) { return kind }
        return nil
    }

    /// Today's predicate: any of the four candidate markers anywhere in the
    /// line.
    static func markerFallback(_ line: UnsafeRawBufferPointer) -> SessionLineKind {
        guard let base = line.baseAddress else { return .other }
        for marker in markers {
            let hit = marker.withUnsafeBytes { memmem(base, line.count, $0.baseAddress, $0.count) }
            if hit != nil { return .undecided }
        }
        return .other
    }

    // MARK: - Scans

    private enum Scan {
        case decided(SessionLineKind)
        /// The line's own `type` was found but its value cannot be compared
        /// as bytes (an escape, or the line ends inside it).
        case fallback
        /// No top-level `type` within the budget.
        case none
    }

    private static let markers: [[UInt8]] = [
        Array(#""type":"assistant""#.utf8), Array(#""type": "assistant""#.utf8),
        Array(#""type":"api-request-shape""#.utf8), Array(#""type": "api-request-shape""#.utf8),
    ]
    private static let assistantValue = Array("assistant".utf8)
    private static let shapeValue = Array("api-request-shape".utf8)

    private static let quote = UInt8(ascii: "\"")
    private static let backslash = UInt8(ascii: "\\")

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }

    /// True when the string content `line[start..<end]` is `type`.
    private static func isType(_ line: UnsafeRawBufferPointer, _ start: Int, _ end: Int) -> Bool {
        end - start == 4 && line[start] == UInt8(ascii: "t") && line[start + 1] == UInt8(ascii: "y")
            && line[start + 2] == UInt8(ascii: "p") && line[start + 3] == UInt8(ascii: "e")
    }

    private enum Value {
        case decided(SessionLineKind)
        /// The string is not followed by `:`, so it is a value, not a key.
        case notKey
        case undecidable
    }

    /// The value after a `type` string at depth 1 whose closing quote is at
    /// `afterKey - 1`.
    private static func value(_ line: UnsafeRawBufferPointer, after afterKey: Int) -> Value {
        let count = line.count
        var i = afterKey
        while i < count, isWhitespace(line[i]) { i += 1 }
        guard i < count, line[i] == UInt8(ascii: ":") else { return .notKey }
        i += 1
        while i < count, isWhitespace(line[i]) { i += 1 }
        guard i < count else { return .undecidable }
        // A number, `null`, an object: the line's own member, which no
        // nested key may replace (FR-013).
        guard line[i] == quote else { return .decided(.other) }
        let start = i + 1
        var end = start
        while end < count, end - start <= valueCap {
            let byte = line[end]
            if byte == backslash { return .undecidable }
            if byte == quote {
                let length = end - start
                if equals(line, start, length, assistantValue) { return .decided(.assistant) }
                if equals(line, start, length, shapeValue) { return .decided(.shape) }
                return .decided(.other)
            }
            end += 1
        }
        return end >= count ? .undecidable : .decided(.other)
    }

    private static func equals(_ line: UnsafeRawBufferPointer, _ start: Int, _ length: Int, _ expected: [UInt8]) -> Bool {
        guard length == expected.count else { return false }
        for offset in 0..<length where line[start + offset] != expected[offset] { return false }
        return true
    }

    /// Forward from the first byte, at most `headBudget` bytes.
    private static func scanHead(_ line: UnsafeRawBufferPointer) -> Scan {
        let limit = min(line.count, headBudget)
        var depth = 0
        var i = 0
        while i < limit {
            switch line[i] {
            case quote:
                let start = i + 1
                var end = start
                while end < limit, line[end] != quote {
                    end += line[end] == backslash ? 2 : 1
                }
                guard end < limit else { return .none }
                if depth == 1, isType(line, start, end) {
                    switch value(line, after: end + 1) {
                    case .decided(let kind): return .decided(kind)
                    case .undecidable: return .fallback
                    case .notKey: break
                    }
                }
                i = end + 1
                continue
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth -= 1
                if depth <= 0 { return .none }
            default:
                break
            }
            i += 1
        }
        return .none
    }

    /// True when the quote at `index` is a string delimiter: an even number
    /// of backslashes precede it.
    private static func isDelimiter(_ line: UnsafeRawBufferPointer, _ index: Int) -> Bool {
        var backslashes = 0
        var p = index - 1
        while p >= 0, line[p] == backslash {
            backslashes += 1
            p -= 1
        }
        return backslashes % 2 == 0
    }

    /// Backward from the last byte, at most `tailBudget` bytes, and only
    /// when the last non-whitespace byte is `}`: the string state of a line
    /// cut off mid-write cannot be known from its end.
    private static func scanTail(_ line: UnsafeRawBufferPointer) -> Scan {
        var i = line.count - 1
        while i >= 0, isWhitespace(line[i]) { i -= 1 }
        guard i >= 0, line[i] == UInt8(ascii: "}") else { return .none }
        let limit = max(0, line.count - tailBudget)
        var depth = 0
        while i >= limit {
            switch line[i] {
            case quote:
                // Outside a string every quote closes one; an escaped one
                // means the line is not what it seems.
                guard isDelimiter(line, i) else { return .none }
                let end = i
                var start = i - 1
                while start >= limit, !(line[start] == quote && isDelimiter(line, start)) { start -= 1 }
                guard start >= limit else { return .none }
                if depth == 1, isType(line, start + 1, end) {
                    switch value(line, after: end + 1) {
                    case .decided(let kind): return .decided(kind)
                    case .undecidable: return .fallback
                    case .notKey: break
                    }
                }
                i = start - 1
                continue
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth += 1
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth -= 1
                if depth <= 0 { return .none }
            default:
                break
            }
            i -= 1
        }
        return .none
    }
}
