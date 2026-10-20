import Foundation
import Testing
@testable import UsageCore

/// spec 030 FR-011: the run-out and fast-burn markers point down in
/// direction remaining.
@Suite struct RunOutGlyphTests {
    @Test func glyphsInBothDirections() {
        #expect(RunOutGlyph.text(burnsFast: false, direction: .used) == "↗")
        #expect(RunOutGlyph.text(burnsFast: true, direction: .used) == "↑")
        #expect(RunOutGlyph.text(burnsFast: false, direction: .remaining) == "↘")
        #expect(RunOutGlyph.text(burnsFast: true, direction: .remaining) == "↓")
    }
}
