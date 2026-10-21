import Foundation
import Testing
@testable import UsageCore

/// spec 032 FR-001, FR-006: the dropdown theme and the panel style it
/// resolves to for a system appearance.
@Suite struct DropdownThemeTests {
    @Test func casesAndRawValues() {
        #expect(DropdownTheme.allCases == [.auto, .dark, .light])
        #expect(DropdownTheme.allCases.map(\.rawValue) == ["auto", "dark", "light"])
    }

    /// Auto follows the system appearance.
    @Test func autoFollowsTheSystem() {
        #expect(DropdownTheme.auto.panelStyle(systemIsDark: true) == .dark)
        #expect(DropdownTheme.auto.panelStyle(systemIsDark: false) == .light)
    }

    /// Dark and Light ignore the system appearance.
    @Test(arguments: [true, false])
    func fixedThemesIgnoreTheSystem(systemIsDark: Bool) {
        #expect(DropdownTheme.dark.panelStyle(systemIsDark: systemIsDark) == .dark)
        #expect(DropdownTheme.light.panelStyle(systemIsDark: systemIsDark) == .light)
    }

    @Test func panelStyleIsDark() {
        #expect(PanelStyle.dark.isDark)
        #expect(!PanelStyle.light.isDark)
    }
}
