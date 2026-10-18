import Foundation
import Testing
@testable import DemoMode

/// Frames over time (spec 024 FR-011, FR-012).
@Suite struct ScenarioPlayerTests {
    static let launch = Date(timeIntervalSince1970: 1_791_000_000)

    static func scenario() throws -> Scenario {
        try ScenarioTests.decode(ScenarioTests.json(frames: """
            [ { "at": "12s",
                "claude": { "acc-max": { "sevenDay": { "used": 75 } } },
                "codex": { "acc-codex": { "windows": [ { "lengthMinutes": 300, "used": 45 } ] } },
                "usage": [ { "at": "-1m", "account": "acc-vertex", "harness": "openCode",
                             "model": "claude-sonnet-5-5", "project": "~/src/billing",
                             "input": 900000, "output": 120000, "cacheRead": 0, "cacheWrite": 0 } ] },
              { "at": "20s",
                "claude": { "acc-max": { "fiveHour": { "resetsIn": "4h" } } } } ]
            """))
    }

    @Test func launchStateHasTheBaseValues() async throws {
        let player = ScenarioPlayer(scenario: try Self.scenario(), launch: Self.launch)
        let state = await player.state(at: Self.launch)
        #expect(state.claude["acc-max"]?.sevenDay.used == 70)
        #expect(state.claude["acc-max"]?.fiveHour.used == 58)
        #expect(state.codex["acc-codex"]?.windows.map(\.used) == [40, 60])
        #expect(state.usage.count == 1)
    }

    @Test func frameAppliesAtItsOffsetNotBefore() async throws {
        let player = ScenarioPlayer(scenario: try Self.scenario(), launch: Self.launch)
        let before = await player.state(at: Self.launch.addingTimeInterval(11))
        #expect(before.claude["acc-max"]?.sevenDay.used == 70)
        #expect(before.usage.count == 1)
        let at = await player.state(at: Self.launch.addingTimeInterval(12))
        #expect(at.claude["acc-max"]?.sevenDay.used == 75)
        #expect(at.codex["acc-codex"]?.windows.map(\.used) == [45, 60])
        #expect(at.usage.count == 2)
    }

    @Test func framesChangeOnlyTheNamedFields() async throws {
        let player = ScenarioPlayer(scenario: try Self.scenario(), launch: Self.launch)
        let state = await player.state(at: Self.launch.addingTimeInterval(30))
        let max = try #require(state.claude["acc-max"])
        // Frame 1 changed the 7-day used percent, not its reset.
        #expect(max.sevenDay.used == 75)
        #expect(max.sevenDay.resetsIn.seconds == 3.5 * 86_400)
        // Frame 2 changed the 5-hour reset, not its used percent.
        #expect(max.fiveHour.used == 58)
        #expect(max.fiveHour.resetsIn.seconds == 4 * 3600)
        // The Codex weekly window was not named.
        let weekly = try #require(state.codex["acc-codex"]?.windows.last)
        #expect(weekly.used == 60)
        #expect(weekly.resetsIn.seconds == 3.5 * 86_400)
    }

    @Test func frameUsageStaysFromThatFrameOn() async throws {
        let player = ScenarioPlayer(scenario: try Self.scenario(), launch: Self.launch)
        let later = await player.state(at: Self.launch.addingTimeInterval(600))
        #expect(later.usage.count == 2)
        #expect(later.usage.last?.project == "~/src/billing")
    }

    /// Reset times are `launch + resetsIn` for the whole run: the
    /// durations do not count down as time passes.
    @Test func resetTimesStayFixedToLaunch() async throws {
        let player = ScenarioPlayer(scenario: try Self.scenario(), launch: Self.launch)
        let early = await player.state(at: Self.launch)
        let late = await player.state(at: Self.launch.addingTimeInterval(11))
        #expect(early.claude["acc-max"]?.sevenDay.resetsIn == late.claude["acc-max"]?.sevenDay.resetsIn)
        #expect(await player.launch == Self.launch)
        #expect(await player.resetDate(early.claude["acc-max"]!.sevenDay) == Self.launch.addingTimeInterval(3.5 * 86_400))
    }
}
