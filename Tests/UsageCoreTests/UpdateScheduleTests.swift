import Foundation
import Testing
@testable import UsageCore

/// spec 013 FR-001, research R9: 5 minutes after launch, then every 24 hours
/// of wall-clock time.
@Suite struct UpdateScheduleTests {
    static let launch = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func constants() {
        #expect(UpdateSchedule.firstCheckDelay == 300)
        #expect(UpdateSchedule.interval == 86_400)
    }

    @Test func firstCheckIsDueFiveMinutesAfterLaunch() {
        #expect(!UpdateSchedule.isDue(now: Self.launch, launchedAt: Self.launch, lastCheck: nil))
        #expect(!UpdateSchedule.isDue(now: Self.launch.addingTimeInterval(299), launchedAt: Self.launch, lastCheck: nil))
        #expect(UpdateSchedule.isDue(now: Self.launch.addingTimeInterval(300), launchedAt: Self.launch, lastCheck: nil))
    }

    @Test func laterChecksAreDueEvery24Hours() {
        let last = Self.launch.addingTimeInterval(300)
        #expect(!UpdateSchedule.isDue(now: last.addingTimeInterval(86_399), launchedAt: Self.launch, lastCheck: last))
        #expect(UpdateSchedule.isDue(now: last.addingTimeInterval(86_400), launchedAt: Self.launch, lastCheck: last))
    }

    /// The loop sleeps until this time (the single source of the due rule).
    @Test func nextDueTime() {
        #expect(UpdateSchedule.nextDue(launchedAt: Self.launch, lastCheck: nil) == Self.launch.addingTimeInterval(300))
        let last = Self.launch.addingTimeInterval(1_000)
        #expect(UpdateSchedule.nextDue(launchedAt: Self.launch, lastCheck: last) == last.addingTimeInterval(86_400))
    }

    @Test func sleepAcrossDaysIsDue() {
        let last = Self.launch.addingTimeInterval(300)
        #expect(UpdateSchedule.isDue(now: last.addingTimeInterval(3 * 86_400 + 17), launchedAt: Self.launch, lastCheck: last))
    }

    @Test func clockMovedBackIsDue() {
        let last = Self.launch.addingTimeInterval(1_000)
        #expect(UpdateSchedule.isDue(now: last.addingTimeInterval(-60), launchedAt: Self.launch, lastCheck: last))
    }
}
