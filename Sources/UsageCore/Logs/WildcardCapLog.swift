import Foundation

/// When to log that a wildcard entry matched more folders than are read
/// (spec 035 FR-005, research R9): once after launch or after the
/// configuration changes, then again only when the number of matches
/// changes. Each session source keeps one.
public struct WildcardCapLog: Sendable {
    private var configuration: Configuration?
    /// Per entry text, the match count and truncation last logged.
    private var logged: [String: String] = [:]

    public init() {}

    /// The cap lines to log for the reports of one refresh. A level that
    /// kept only `WildcardExpander.levelBudget` candidates is logged the
    /// same way.
    public mutating func lines(for reports: [WildcardReport], configuration: Configuration) -> [String] {
        if self.configuration != configuration {
            self.configuration = configuration
            logged = [:]
        }
        var lines: [String] = []
        for report in reports {
            let capped = report.matched > report.read
            guard capped || report.isTruncated else {
                logged[report.entry] = nil
                continue
            }
            let state = "\(report.matched)|\(report.isTruncated)"
            guard logged[report.entry] != state else { continue }
            logged[report.entry] = state
            if report.isTruncated {
                lines.append("wildcard \"\(report.entry)\": more than \(WildcardExpander.levelBudget) folders at one level, only the first \(WildcardExpander.levelBudget) are looked at")
            }
            if capped {
                lines.append("wildcard \"\(report.entry)\": \(report.matched) folders matched, only the first \(WildcardExpander.cap) are read")
            }
        }
        return lines
    }
}
