import Foundation
import Testing
@testable import UsageCore

/// spec 026 FR-002, FR-003, FR-007 and Edge Cases: which member lines a
/// budget group shows and which member tables "Show account details" reveals.
@Suite struct MemberDisplayTests {
    static let used = TokenAccountEntry(breakdown: UsageBreakdown(perModel: [ModelUsage(model: "claude-sonnet-4-5", inputTokens: 10)]))
    static let unused = TokenAccountEntry(breakdown: .empty)

    @Test func noMembersShowsNothing() {
        let display = MemberDisplay.make(memberIds: [], usage: [:])
        #expect(display.lines.isEmpty)
        #expect(display.tables.isEmpty)
        #expect(!display.showsAccountsButton)
    }

    /// A single member's line would repeat the group's amount (spec 025 FR-010).
    @Test func oneMemberShowsNothing() {
        let display = MemberDisplay.make(memberIds: ["a"], usage: ["a": Self.used])
        #expect(display.lines.isEmpty)
        #expect(display.tables.isEmpty)
        #expect(!display.showsAccountsButton)
    }

    @Test func twoMembersWithUsageShowLinesTablesAndButton() {
        let display = MemberDisplay.make(memberIds: ["a", "b"], usage: ["a": Self.used, "b": Self.used])
        #expect(display.lines == ["a", "b"])
        #expect(display.tables == ["a", "b"])
        #expect(display.showsAccountsButton)
    }

    /// The one member's tables would repeat the group's, so no button.
    @Test func twoMembersOneWithUsageShowLinesButNoTables() {
        let display = MemberDisplay.make(memberIds: ["a", "b"], usage: ["a": Self.used, "b": Self.unused])
        #expect(display.lines == ["a", "b"])
        #expect(display.tables.isEmpty)
        #expect(!display.showsAccountsButton)
    }

    @Test func threeMembersTwoWithUsageKeepMemberOrder() {
        let display = MemberDisplay.make(memberIds: ["c", "a", "b"],
                                         usage: ["a": Self.used, "b": Self.unused, "c": Self.used])
        #expect(display.lines == ["c", "a", "b"])
        #expect(display.tables == ["c", "a"])
        #expect(display.showsAccountsButton)
    }

    @Test func memberWithoutAUsageEntryHasNoLine() {
        let display = MemberDisplay.make(memberIds: ["a", "b", "c"], usage: ["a": Self.used, "c": Self.used])
        #expect(display.lines == ["a", "c"])
        #expect(display.tables == ["a", "c"])
        #expect(display.showsAccountsButton)
    }

    @Test func membersWithoutAnyUsageEntryShowNothing() {
        let display = MemberDisplay.make(memberIds: ["a", "b"], usage: [:])
        #expect(display.lines.isEmpty)
        #expect(display.tables.isEmpty)
        #expect(!display.showsAccountsButton)
    }
}
