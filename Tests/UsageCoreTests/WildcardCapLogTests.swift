import Foundation
import Testing
@testable import UsageCore

/// spec 035 FR-005, research R9: the cap line is logged once after launch
/// or a configuration change, and again only when the match count changes.
@Suite struct WildcardCapLogTests {
    static let entry = "~/agent-sessions/openshell/*/claude"

    static func report(_ matched: Int, entry: String = entry) -> WildcardReport {
        WildcardReport(entry: entry, matched: matched, read: min(matched, WildcardExpander.cap), listingErrors: [])
    }

    static let config = AdditionalSessionDirectoryTests.config([AdditionalSessionDirectoryTests.claude("max", extra: [entry])])

    @Test func capLineOncePerCountAndConfiguration() {
        var log = WildcardCapLog()
        let line = #"wildcard "~/agent-sessions/openshell/*/claude": 120 folders matched, only the first 100 are read"#
        #expect(log.lines(for: [Self.report(120)], configuration: Self.config) == [line])
        #expect(log.lines(for: [Self.report(120)], configuration: Self.config).isEmpty)
        #expect(log.lines(for: [Self.report(121)], configuration: Self.config)
                == [#"wildcard "~/agent-sessions/openshell/*/claude": 121 folders matched, only the first 100 are read"#])
        var changed = Self.config
        changed.refreshIntervalSeconds = 600
        #expect(log.lines(for: [Self.report(121)], configuration: changed).count == 1)
        #expect(log.lines(for: [Self.report(121)], configuration: changed).isEmpty)
    }

    @Test func uncappedReportsGiveNothing() {
        var log = WildcardCapLog()
        #expect(log.lines(for: [Self.report(100), Self.report(0, entry: "~/.claude-*")], configuration: Self.config).isEmpty)
        // Dropping below the cap and rising again logs again.
        _ = log.lines(for: [Self.report(101)], configuration: Self.config)
        _ = log.lines(for: [Self.report(99)], configuration: Self.config)
        #expect(log.lines(for: [Self.report(101)], configuration: Self.config).count == 1)
    }

    /// A truncated level is logged once, like the cap line.
    @Test func truncatedLevelIsLoggedOnce() {
        var log = WildcardCapLog()
        let report = WildcardReport(entry: "~/many/*/*", matched: 40, read: 40, listingErrors: [], isTruncated: true)
        let line = #"wildcard "~/many/*/*": more than 1000 folders at one level, only the first 1000 are looked at"#
        #expect(log.lines(for: [report], configuration: Self.config) == [line])
        #expect(log.lines(for: [report], configuration: Self.config).isEmpty)
    }

    /// The listing lines name the folder and the reason.
    @Test func listingLinesNameTheReason() {
        let report = WildcardReport(entry: "~/x/*", matched: 0, read: 0,
                                    listingErrors: [WildcardListingError(path: "/Users/tester/x", reason: "Permission denied")])
        #expect(report.listingLines == [#"wildcard "~/x/*": cannot list /Users/tester/x: Permission denied"#])
    }
}
