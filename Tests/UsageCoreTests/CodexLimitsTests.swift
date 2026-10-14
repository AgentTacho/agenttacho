import Foundation
import Testing
@testable import UsageCore

/// spec 007 FR-009, FR-010, FR-011, FR-012, research R2, R7.
@Suite struct CodexLimitsTests {
    static let now = isoDate("2026-10-14T15:00:00Z")

    static func window(_ minutes: Int, _ percent: Double, resetsIn: TimeInterval? = 3600, reached: Bool = false) -> CodexLimitWindow {
        CodexLimitWindow(lengthMinutes: minutes, usedPercent: percent,
                         resetsAt: resetsIn.map { now.addingTimeInterval($0) }, limitReached: reached)
    }

    static func observation(_ windows: [CodexLimitWindow], plan: String? = "plus") -> CodexLimitObservation {
        CodexLimitObservation(planType: plan, observedAt: now.addingTimeInterval(-60), origin: .live, windows: windows)
    }

    @Test func windowNames() {
        #expect(Self.window(300, 0).name == "5-hour")
        #expect(Self.window(60, 0).name == "1-hour")
        #expect(Self.window(10080, 0).name == "weekly")
        #expect(Self.window(10000, 0).name == "weekly")
        #expect(Self.window(43200, 0).name == "30-day")
        #expect(Self.window(2160, 0).name == "2-day")
    }

    /// FR-010: a window whose reset passed shows 0%, no reset, not reached.
    @Test func effectiveWindowsResetPassedWindows() {
        let observation = Self.observation([
            Self.window(10080, 40, resetsIn: 86400),
            Self.window(300, 100, resetsIn: -1, reached: true),
        ])
        let effective = observation.effectiveWindows(now: Self.now)
        #expect(effective.map(\.name) == ["5-hour", "weekly"])
        #expect(effective[0] == CodexLimitWindow(lengthMinutes: 300, usedPercent: 0, resetsAt: nil, limitReached: false))
        #expect(effective[1] == Self.window(10080, 40, resetsIn: 86400))
        // Exactly at the reset time the window has reset.
        let atReset = Self.observation([Self.window(300, 50, resetsIn: 0)]).effectiveWindows(now: Self.now)
        #expect(atReset[0].usedPercent == 0)
    }

    @Test func duplicateWindowNamesKeepTheFirst() {
        let observation = Self.observation([Self.window(10080, 10), Self.window(10000, 99)])
        #expect(observation.windows.count == 1)
        #expect(observation.windows[0].usedPercent == 10)
    }

    @Test func planDisplayName() {
        #expect(CodexLimitsEntry.planDisplayName("plus") == "Plus")
        #expect(CodexLimitsEntry.planDisplayName("free") == "Free")
        #expect(CodexLimitsEntry.planDisplayName(nil) == nil)
        #expect(CodexLimitsEntry.planDisplayName("") == nil)
    }

    /// FR-012: the bar shows the longest window, rounded and uncapped.
    @Test func barPercentIsTheLongestWindow() {
        let entry = CodexLimitsEntry(observation: Self.observation([Self.window(300, 77), Self.window(10080, 20.4)]), state: .live)
        #expect(entry.barPercent(now: Self.now) == 20)
        let over = CodexLimitsEntry(observation: Self.observation([Self.window(43200, 130.0)]), state: .live)
        #expect(over.barPercent(now: Self.now) == 130)
        let none = CodexLimitsEntry(observation: nil, state: .unavailable(reason: "offline"))
        #expect(none.barPercent(now: Self.now) == nil)
        #expect(none.windows(now: Self.now).isEmpty)
    }

    @Test func anyLimitReachedFollowsEffectiveWindows() {
        let entry = CodexLimitsEntry(observation: Self.observation([
            Self.window(300, 100, resetsIn: 600, reached: true), Self.window(10080, 40, resetsIn: 86400),
        ]), state: .live)
        #expect(entry.anyLimitReached(now: Self.now))
        #expect(!entry.anyLimitReached(now: Self.now.addingTimeInterval(601)))
        let calm = CodexLimitsEntry(observation: Self.observation([Self.window(300, 50)]), state: .live)
        #expect(!calm.anyLimitReached(now: Self.now))
    }

    /// research R2: at least 100% is reached; a reached flag from the source
    /// marks the window with the highest percent.
    @Test func limitReachedRule() {
        let windows = [Self.window(300, 60), Self.window(10080, 90)]
        let unflagged = CodexLimitWindow.applyingReachedRule(windows, sourceReportsReached: false)
        #expect(unflagged.map(\.limitReached) == [false, false])
        let flagged = CodexLimitWindow.applyingReachedRule(windows, sourceReportsReached: true)
        #expect(flagged.map(\.limitReached) == [false, true])
        let full = CodexLimitWindow.applyingReachedRule([Self.window(300, 100), Self.window(10080, 30)], sourceReportsReached: false)
        #expect(full.map(\.limitReached) == [true, false])
    }

    /// The shared window rules of the usage service and the session logs.
    @Test func windowFromSourceValues() {
        let window = CodexLimitWindow(minutes: 299.5, usedPercent: 20, resetEpoch: 1791999819)
        #expect(window == CodexLimitWindow(lengthMinutes: 300, usedPercent: 20, resetsAt: Date(timeIntervalSince1970: 1791999819)))
        #expect(CodexLimitWindow(minutes: 300, usedPercent: 20, resetEpoch: .infinity)?.resetsAt == nil)
        #expect(CodexLimitWindow(minutes: 300, usedPercent: 20, resetEpoch: nil)?.resetsAt == nil)
        #expect(CodexLimitWindow(minutes: 300, usedPercent: nil, resetEpoch: nil) == nil)
        #expect(CodexLimitWindow(minutes: 300, usedPercent: .nan, resetEpoch: nil) == nil)
        #expect(CodexLimitWindow(minutes: nil, usedPercent: 20, resetEpoch: nil) == nil)
        #expect(CodexLimitWindow(minutes: 0, usedPercent: 20, resetEpoch: nil) == nil)
        #expect(CodexLimitWindow(minutes: -5, usedPercent: 20, resetEpoch: nil) == nil)
        #expect(CodexLimitWindow(minutes: .infinity, usedPercent: 20, resetEpoch: nil) == nil)
        #expect(CodexLimitWindow(minutes: Double(Int32.max), usedPercent: 20, resetEpoch: nil) == nil)
    }

    /// FR-005, FR-021: what a failed refresh carries over, per state.
    @Test func markedStaleKeepsLocalAndFailedStates() {
        let observation = Self.observation([Self.window(300, 50)])
        let cases: [(CodexLimitsState, CodexLimitsState)] = [
            (.live, .stale(reason: "refresh failed")),
            (.newerSnapshot, .stale(reason: "refresh failed")),
            (.localOnly, .localOnly),
            (.stale(reason: "offline"), .stale(reason: "offline")),
            (.unavailable(reason: "no Codex plan limits recorded in this Codex home"),
             .unavailable(reason: "no Codex plan limits recorded in this Codex home")),
        ]
        for (state, expected) in cases {
            let entry = CodexLimitsEntry(observation: observation, state: state, sourceError: "usage service changed")
            let carried = entry.markedStale(reason: "refresh failed")
            #expect(carried.state == expected)
            #expect(carried.sourceError == nil)
            #expect(carried.observation == observation)
        }
    }

    /// Which live-limits setting can produce each state (FR-015).
    @Test func impliedLiveLimits() {
        #expect(CodexLimitsState.live.impliedLiveLimits == true)
        #expect(CodexLimitsState.newerSnapshot.impliedLiveLimits == true)
        #expect(CodexLimitsState.stale(reason: "offline").impliedLiveLimits == true)
        #expect(CodexLimitsState.localOnly.impliedLiveLimits == false)
        #expect(CodexLimitsState.unavailable(reason: "offline").impliedLiveLimits == nil)
    }
}
