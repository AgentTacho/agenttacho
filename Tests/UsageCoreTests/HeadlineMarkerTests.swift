import Testing
@testable import UsageCore

/// spec 027 FR-002 (amendment 2026-10-19): the marker slot of a window row.
@Suite struct HeadlineMarkerTests {
    @Test func chosenHeadlineShowsAFullMarker() {
        let marker = HeadlineMarker.of(isHeadline: true, isDefault: false, isHovered: false)
        #expect(marker == .chosen)
        #expect(marker.symbol == "●")
        #expect(!marker.isDimmed)
    }

    @Test func defaultHeadlineShowsADimmedMarker() {
        let marker = HeadlineMarker.of(isHeadline: true, isDefault: true, isHovered: false)
        #expect(marker == .defaultWindow)
        #expect(marker.symbol == "●")
        #expect(marker.isDimmed)
    }

    @Test func headlineRowIgnoresHover() {
        #expect(HeadlineMarker.of(isHeadline: true, isDefault: true, isHovered: true) == .defaultWindow)
        #expect(HeadlineMarker.of(isHeadline: true, isDefault: false, isHovered: true) == .chosen)
    }

    @Test func otherRowShowsTheHoverHintOnlyWhileHovered() {
        let hovered = HeadlineMarker.of(isHeadline: false, isDefault: true, isHovered: true)
        #expect(hovered == .hoverHint)
        #expect(hovered.symbol == "○")
        #expect(hovered.isDimmed)
        let idle = HeadlineMarker.of(isHeadline: false, isDefault: false, isHovered: false)
        #expect(idle == .none)
        #expect(idle.symbol == "")
    }
}
