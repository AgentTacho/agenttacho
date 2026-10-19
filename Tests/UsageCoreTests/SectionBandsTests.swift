import Foundation
import Testing
@testable import UsageCore

/// spec 028 FR-002, FR-003, FR-005, FR-006, SC-004: the stripe of each
/// dropdown section, the rule for showing Unassigned and the band strengths.
@Suite struct SectionBandsTests {
    // MARK: Stripes

    @Test func noSectionsHaveNoStripes() {
        #expect(SectionBands.stripes(arrangedCount: 0, unassignedShown: false).isEmpty)
    }

    /// Unassigned alone is the first section, so it is plain.
    @Test func unassignedAloneIsPlain() {
        #expect(SectionBands.stripes(arrangedCount: 0, unassignedShown: true) == [.plain])
    }

    @Test func singleSectionIsPlain() {
        #expect(SectionBands.stripes(arrangedCount: 1, unassignedShown: false) == [.plain])
    }

    @Test func sectionsAlternateStartingPlain() {
        #expect(SectionBands.stripes(arrangedCount: 4, unassignedShown: false) == [.plain, .tinted, .plain, .tinted])
    }

    /// Unassigned is the last section and takes the next stripe.
    @Test func unassignedContinuesTheAlternation() {
        #expect(SectionBands.stripes(arrangedCount: 4, unassignedShown: true) == [.plain, .tinted, .plain, .tinted, .plain])
        #expect(SectionBands.stripes(arrangedCount: 3, unassignedShown: true) == [.plain, .tinted, .plain, .tinted])
        #expect(SectionBands.stripes(arrangedCount: 1, unassignedShown: true) == [.plain, .tinted])
    }

    @Test func oddCountEndsPlain() {
        #expect(SectionBands.stripes(arrangedCount: 3, unassignedShown: false) == [.plain, .tinted, .plain])
    }

    /// For any count: the i-th section is plain for even i and tinted for
    /// odd i, and showing Unassigned only appends one stripe without
    /// changing the arranged entries' stripes.
    @Test(arguments: 0...7)
    func alternationHoldsForAnyCount(count: Int) {
        let hidden = SectionBands.stripes(arrangedCount: count, unassignedShown: false)
        let shown = SectionBands.stripes(arrangedCount: count, unassignedShown: true)
        #expect(hidden.count == count)
        #expect(shown.count == count + 1)
        for (index, stripe) in shown.enumerated() {
            #expect(stripe == (index.isMultiple(of: 2) ? .plain : .tinted), "index \(index) of \(count)")
        }
        #expect(Array(shown.prefix(count)) == hidden)
    }

    @Test func negativeCountActsAsZero() {
        #expect(SectionBands.stripes(arrangedCount: -2, unassignedShown: false).isEmpty)
        #expect(SectionBands.stripes(arrangedCount: -2, unassignedShown: true) == [.plain])
    }

    /// The footer band belongs to the footer only, never to a section.
    @Test func sectionsNeverGetTheFooterBand() {
        for count in 0...6 {
            for unassigned in [false, true] {
                #expect(!SectionBands.stripes(arrangedCount: count, unassignedShown: unassigned).contains(.footer))
            }
        }
    }

    // MARK: Strengths

    @Test(arguments: [false, true])
    func strengthsAreOrdered(increasedContrast: Bool) {
        let plain = BandStyle.plain.opacity(increasedContrast: increasedContrast)
        let tinted = BandStyle.tinted.opacity(increasedContrast: increasedContrast)
        let footer = BandStyle.footer.opacity(increasedContrast: increasedContrast)
        #expect(plain == 0)
        #expect(plain < tinted)
        #expect(tinted < footer)
    }

    @Test(arguments: [BandStyle.tinted, .footer])
    func increasedContrastIsStronger(style: BandStyle) {
        #expect(style.opacity(increasedContrast: true) > style.opacity(increasedContrast: false))
    }

    // MARK: Unassigned shown

    static let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))

    static func snapshot(unassigned: TokenAccountEntry) -> UsageSnapshot {
        UsageSnapshot(generatedAt: window.start, window: window, windowSource: .fallback, unassigned: unassigned)
    }

    @Test func noSnapshotShowsNoUnassigned() {
        #expect(!SectionBands.showsUnassigned(nil))
    }

    @Test func emptyUnassignedIsNotShown() {
        #expect(!SectionBands.showsUnassigned(Self.snapshot(unassigned: .empty)))
    }

    @Test func unassignedWithUsageIsShown() {
        let used = TokenAccountEntry(breakdown: UsageBreakdown(perModel: [ModelUsage(model: "claude-sonnet-4-5", inputTokens: 10)]))
        #expect(SectionBands.showsUnassigned(Self.snapshot(unassigned: used)))
    }
}
