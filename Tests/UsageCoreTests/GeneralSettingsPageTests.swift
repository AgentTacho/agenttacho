import Testing
@testable import UsageCore

/// spec 034 FR-001, FR-003, research R2: the pages of the General tab's
/// sidebar and the remembered selection.
@Suite struct GeneralSettingsPageTests {
    @Test func sidebarOrderAndTitles() {
        #expect(GeneralSettingsPage.allCases.map(\.title)
                == ["Refresh", "Appearance", "Weekly window", "Notifications", "Sources", "Startup"])
    }

    @Test func systemImages() {
        #expect(GeneralSettingsPage.allCases.map(\.systemImage)
                == ["arrow.clockwise", "paintbrush", "calendar", "bell", "folder", "power"])
    }

    @Test func rawValuesAndIds() {
        #expect(GeneralSettingsPage.allCases.map(\.rawValue)
                == ["refresh", "appearance", "weeklyWindow", "notifications", "sources", "startup"])
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

    /// The first time, and for anything unknown, Refresh is selected (FR-003).
    @Test(arguments: [nil, "", "display", "Refresh", "launch"] as [String?])
    func missingOrUnknownValueIsRefresh(stored: String?) {
        #expect(GeneralSettingsPage(stored: stored) == .refresh)
    }
}
