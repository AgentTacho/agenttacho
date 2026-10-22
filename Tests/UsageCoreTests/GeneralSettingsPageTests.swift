import Testing
@testable import UsageCore

/// spec 034 FR-001, FR-003, research R2: the pages of the General tab's
/// sidebar and the remembered selection.
@Suite struct GeneralSettingsPageTests {
    @Test func sidebarOrderAndTitles() {
        #expect(GeneralSettingsPage.allCases.map(\.title)
                == ["Appearance", "Weekly window", "Notifications", "Refresh", "Sources", "Startup"])
    }

    @Test func systemImages() {
        #expect(GeneralSettingsPage.allCases.map(\.systemImage)
                == ["paintbrush", "calendar", "bell", "arrow.clockwise", "folder", "power"])
    }

    @Test func rawValuesAndIds() {
        #expect(GeneralSettingsPage.allCases.map(\.rawValue)
                == ["appearance", "weeklyWindow", "notifications", "refresh", "sources", "startup"])
        for page in GeneralSettingsPage.allCases {
            #expect(page.id == page.rawValue)
        }
        #expect(GeneralSettingsPage.defaultsKey == "generalSettingsPage")
    }

    @Test func storedValueMapsToItsPage() {
        for page in GeneralSettingsPage.allCases {
            #expect(GeneralSettingsPage(stored: page.rawValue) == page)
        }
    }

    /// The first time, and for anything unknown, the first page is selected
    /// (FR-003): Appearance since Refresh moved down, so it reads as a
    /// setting, not an action (walkthrough 2026-10-22).
    @Test(arguments: [nil, "", "display", "Refresh", "launch"] as [String?])
    func missingOrUnknownValueIsTheFirstPage(stored: String?) {
        #expect(GeneralSettingsPage(stored: stored) == .appearance)
        #expect(GeneralSettingsPage.allCases.first == .appearance)
    }
}
