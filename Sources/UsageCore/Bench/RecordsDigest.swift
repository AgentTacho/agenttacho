import Foundation

/// The records of one bench run as text, for the comparison of the old
/// and the new code (spec 039 FR-004, FR-005, FR-008, research R9,
/// contracts/bench-cli.md "Digest file").
///
/// One line per `UsageRecord`, the record as the app keeps it: harness,
/// key, timestamp rounded to the nearest millisecond, model, canonical
/// model, the six token counts, project root, account id and cost, tab
/// separated, sorted by harness, key, timestamp and model. Never a session
/// line's content (FR-003).
public struct RecordsDigest: Equatable, Sendable {
    /// The first header line; a file without it is no digest.
    public static let versionLine = "digest 1"
    /// Differing lines shown per side by `compare` (FR-005).
    public static let shownDifferences = 20

    /// What the digest was taken over. Paths are written with `~`.
    public struct Header: Equatable, Sendable {
        public var configuration: String
        public var windowStart: String
        public var directory: String

        public init(configuration: String, windowStart: String, directory: String) {
            self.configuration = configuration
            self.windowStart = windowStart
            self.directory = directory
        }

        var lines: [String] {
            [RecordsDigest.versionLine, "config " + configuration, "window-start " + windowStart, "directory " + directory]
        }
    }

    /// The verdict of `compare`: record lines decide, header lines are
    /// notes only (research R9).
    public struct Comparison: Equatable, Sendable {
        public var identical = false
        /// The first `shownDifferences` lines found only in A, or only in B.
        public var onlyInA: [String] = []
        public var onlyInB: [String] = []
        /// All lines found only in A, or only in B.
        public var onlyInACount = 0
        public var onlyInBCount = 0
        /// Record lines in A and in B.
        public var countA = 0
        public var countB = 0
        /// Header lines that differ, informational.
        public var headerNotes: [String] = []

        public init() {}

        /// The output of `scan-bench compare` (contracts/bench-cli.md).
        public var text: String {
            var out: [String] = []
            if identical {
                out.append("identical: \(countA) records")
            } else {
                out.append("different: \(countA) records in A, \(countB) in B")
                out.append("only in A (\(onlyInA.count) shown of \(onlyInACount)):")
                out += onlyInA.map { "  " + $0 }
                out.append("only in B (\(onlyInB.count) shown of \(onlyInBCount)):")
                out += onlyInB.map { "  " + $0 }
            }
            out += headerNotes.map { "note: " + $0 }
            return out.joined(separator: "\n") + "\n"
        }
    }

    public var headerLines: [String]
    /// Sorted record lines.
    public var lines: [String]

    /// The digest of `records`; with `until`, records stamped at or after
    /// it are left out, so two runs a few minutes apart compare the same
    /// span of live session files (contracts/bench-cli.md).
    public init(records: [UsageRecord], header: Header, until: Date? = nil) {
        let kept = until.map { limit in records.filter { $0.timestamp < limit } } ?? records
        let entries = kept.map { record -> (sortKey: [String], line: String) in
            let columns = Self.columns(for: record)
            return ([columns[0], columns[1], columns[2], columns[3]], columns.joined(separator: "\t"))
        }
        self.headerLines = header.lines
        self.lines = entries.sorted { a, b in
            a.sortKey == b.sortKey ? a.line < b.line : a.sortKey.lexicographicallyPrecedes(b.sortKey)
        }.map(\.line)
    }

    init(headerLines: [String], lines: [String]) {
        self.headerLines = headerLines
        self.lines = lines
    }

    public var text: String {
        (headerLines + lines).joined(separator: "\n") + "\n"
    }

    public struct ParseError: Error, CustomStringConvertible {
        public let description: String
    }

    /// Reads a digest's text: the header lines up to the first record line,
    /// then the record lines. Text that does not start with
    /// `versionLine` is no digest.
    public static func parse(_ text: String) throws -> RecordsDigest {
        let all = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard all.first == versionLine else {
            throw ParseError(description: "not a records digest (first line is not \"\(versionLine)\")")
        }
        let headerCount = all.firstIndex { $0.contains("\t") } ?? all.count
        return RecordsDigest(headerLines: Array(all[..<headerCount]), lines: Array(all[headerCount...]))
    }

    /// Compares the record lines as a multiset: a line twice in A and once
    /// in B is one difference (FR-005).
    public static func compare(_ a: RecordsDigest, _ b: RecordsDigest) -> Comparison {
        var comparison = Comparison()
        comparison.countA = a.lines.count
        comparison.countB = b.lines.count
        var remaining: [String: Int] = [:]
        for line in b.lines { remaining[line, default: 0] += 1 }
        var onlyInA: [String] = []
        for line in a.lines {
            if let count = remaining[line], count > 0 {
                remaining[line] = count - 1
            } else {
                onlyInA.append(line)
            }
        }
        var onlyInB: [String] = []
        for line in b.lines.reversed() where (remaining[line] ?? 0) > 0 {
            remaining[line]! -= 1
            onlyInB.append(line)
        }
        onlyInB.reverse()
        comparison.identical = onlyInA.isEmpty && onlyInB.isEmpty
        comparison.onlyInA = Array(onlyInA.prefix(shownDifferences))
        comparison.onlyInB = Array(onlyInB.prefix(shownDifferences))
        comparison.onlyInACount = onlyInA.count
        comparison.onlyInBCount = onlyInB.count
        for index in 0..<max(a.headerLines.count, b.headerLines.count) {
            let left = index < a.headerLines.count ? a.headerLines[index] : ""
            let right = index < b.headerLines.count ? b.headerLines[index] : ""
            if left != right {
                comparison.headerNotes.append("header differs: A \"\(left)\", B \"\(right)\"")
            }
        }
        return comparison
    }

    /// The digest line of one record.
    public static func line(for record: UsageRecord) -> String {
        columns(for: record).joined(separator: "\t")
    }

    static func columns(for record: UsageRecord) -> [String] {
        let key = record.messageId.isEmpty ? "req:" + record.requestId : "msg:" + record.messageId
        return [
            record.harness.rawValue,
            field(key),
            timestamp(record.timestamp),
            field(record.model),
            field(record.canonicalModel),
            String(record.inputTokens),
            String(record.outputTokens),
            String(record.cacheWrite5mTokens),
            String(record.cacheWrite1hTokens),
            String(record.cacheReadTokens),
            String(record.reasoningTokens),
            field(record.project?.rootPath ?? ""),
            field(record.accountId ?? ""),
            record.costUSD.map { "\($0)" } ?? "",
        ]
    }

    /// Escapes the characters that would split a line or a column.
    private static func field(_ text: String) -> String {
        guard text.contains(where: { $0 == "\t" || $0 == "\n" || $0 == "\r" || $0 == "\\" }) else { return text }
        return text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    /// `YYYY-MM-DDTHH:MM:SS.mmmZ`, rounded to the nearest millisecond: two
    /// parsers can reach the same millisecond through different
    /// floating-point paths, an ulp apart, and flooring would split them
    /// (research R5).
    public static func timestamp(_ date: Date) -> String {
        let referenceMilliseconds = (date.timeIntervalSinceReferenceDate * 1000).rounded()
        let milliseconds = Int64(referenceMilliseconds) + 978_307_200_000
        let (days, dayMilliseconds) = floorDivision(milliseconds, 86_400_000)
        let (year, month, day) = civil(fromDays: days)
        let hour = dayMilliseconds / 3_600_000
        let minute = dayMilliseconds / 60_000 % 60
        let second = dayMilliseconds / 1000 % 60
        let millisecond = dayMilliseconds % 1000
        return String(format: "%04lld-%02lld-%02lldT%02lld:%02lld:%02lld.%03lldZ", year, month, day, hour, minute, second, millisecond)
    }

    private static func floorDivision(_ value: Int64, _ divisor: Int64) -> (Int64, Int64) {
        let quotient = value >= 0 ? value / divisor : (value - divisor + 1) / divisor
        return (quotient, value - quotient * divisor)
    }

    /// The proleptic Gregorian date of a day count since 1970-01-01
    /// (Howard Hinnant's `civil_from_days`).
    static func civil(fromDays days: Int64) -> (year: Int64, month: Int64, day: Int64) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthPart = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthPart + 2) / 5 + 1
        let month = monthPart < 10 ? monthPart + 3 : monthPart - 9
        return (yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }
}
