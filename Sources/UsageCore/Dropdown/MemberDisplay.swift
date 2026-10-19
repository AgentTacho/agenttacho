import Foundation

/// The member lines and member tables of one budget group (spec 026 FR-002,
/// FR-003, FR-007, research R1; idea inbox member-line-rule-in-core). Both
/// the dropdown's budget section and the demo coverage use it.
public struct MemberDisplay: Equatable, Sendable {
    /// Member ids with a summary line, in member order: every member with a
    /// usage entry, only when the group has two or more members; a single
    /// member's line would repeat the group's amount (spec 004 FR-018a,
    /// spec 025 FR-010).
    public let lines: [String]
    /// Member ids whose tables "Show account details" reveals, in member order
    /// (spec 008 FR-003): every member whose breakdown is not empty, only
    /// when there are two or more of them; one member's tables would repeat
    /// the group's (spec 026 FR-003, Edge Cases).
    public let tables: [String]

    /// The group's Details end with "Show account details" exactly when there are
    /// member tables to reveal (spec 026 FR-003).
    public var showsAccountsButton: Bool { !tables.isEmpty }

    public init(lines: [String], tables: [String]) {
        self.lines = lines
        self.tables = tables
    }

    /// The display for a group's `memberIds` in member order, with the
    /// members' usage entries for the group's period keyed by account id.
    public static func make(memberIds: [String], usage: [String: TokenAccountEntry]) -> MemberDisplay {
        guard memberIds.count >= 2 else { return MemberDisplay(lines: [], tables: []) }
        let lines = memberIds.filter { usage[$0] != nil }
        let withUsage = lines.filter { usage[$0]?.breakdown.isEmpty == false }
        return MemberDisplay(lines: lines, tables: withUsage.count >= 2 ? withUsage : [])
    }
}
