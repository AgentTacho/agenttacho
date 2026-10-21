import Foundation
import Testing
@testable import UsageCore

/// spec 033 FR-016, research R5: the record of delivered expiry steps, in
/// memory for tests and in the macOS defaults for the app.
@Suite struct ResetTicketNoticeStoreTests {
    static let keys: Set<ResetTicketNoticeKey> = [
        ResetTicketNoticeKey(accountId: "acc-max", expiresAt: Date(timeIntervalSince1970: 1_800_000_000), step: .threeDays),
        ResetTicketNoticeKey(accountId: "acc-max", expiresAt: Date(timeIntervalSince1970: 1_800_000_000), step: .oneDay),
        ResetTicketNoticeKey(accountId: "acc|odd", expiresAt: Date(timeIntervalSince1970: 1_800_100_000), step: .threeDays),
    ]

    /// A defaults suite of its own, removed after the test.
    static func withDefaults(_ run: (UserDefaults, String) throws -> Void) rethrows {
        let suite = "agenttacho-tests-notices-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try run(defaults, suite)
    }

    @Test func inMemoryStoreRoundTrips() {
        let store = InMemoryResetTicketNoticeStore()
        #expect(store.load().isEmpty)
        store.save(Self.keys)
        #expect(store.load() == Self.keys)
        store.save([])
        #expect(store.load().isEmpty)
    }

    @Test func defaultsStoreRoundTripsAsStrings() {
        Self.withDefaults { defaults, _ in
            let store = UserDefaultsResetTicketNoticeStore(defaults: defaults)
            #expect(store.load().isEmpty)
            store.save(Self.keys)
            #expect(store.load() == Self.keys)
            let raw = defaults.stringArray(forKey: UserDefaultsResetTicketNoticeStore.key)
            #expect(UserDefaultsResetTicketNoticeStore.key == "freeResetNotices")
            #expect(Set(raw ?? []) == ["acc-max|1800000000|3d", "acc-max|1800000000|24h", "acc|odd|1800100000|3d"])
            // A new store over the same defaults reads them (relaunch).
            #expect(UserDefaultsResetTicketNoticeStore(defaults: defaults).load() == Self.keys)
        }
    }

    @Test func defaultsStoreIgnoresUnparsableEntries() {
        Self.withDefaults { defaults, _ in
            defaults.set(["acc-max|1800000000|3d", "garbage", "acc-max|soon|3d", "acc-max|1800000000|1w", "|1800000000|3d", 7 as Any]
                .compactMap { $0 as? String }, forKey: UserDefaultsResetTicketNoticeStore.key)
            let store = UserDefaultsResetTicketNoticeStore(defaults: defaults)
            #expect(store.load() == [ResetTicketNoticeKey(accountId: "acc-max", expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
                                                          step: .threeDays)])
            // An epoch out of range would trap when written back (spec 033
            // FR-016): ignored like any unreadable entry.
            defaults.set(["acc-max|9223372036854775807|3d", "acc-max|-1|24h", "acc-max|253402300800|3d"],
                         forKey: UserDefaultsResetTicketNoticeStore.key)
            #expect(store.load().isEmpty)
            defaults.set("not a list", forKey: UserDefaultsResetTicketNoticeStore.key)
            #expect(store.load().isEmpty)
        }
    }

    @Test func keysUseWholeSeconds() {
        let key = ResetTicketNoticeKey(accountId: "a", expiresAt: Date(timeIntervalSince1970: 1_800_000_000.75), step: .oneDay)
        #expect(key.expiresAt == Date(timeIntervalSince1970: 1_800_000_000))
    }
}
