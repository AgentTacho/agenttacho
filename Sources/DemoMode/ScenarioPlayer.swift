import Foundation
import UsageCore

/// The scenario's values at one moment: the base values with every frame
/// whose time has come applied (spec 024 FR-012).
public struct ScenarioState: Equatable, Sendable {
    public let claude: [String: ClaudeWindows]
    public let codex: [String: CodexWindows]
    /// The base records, then the records of each applied frame.
    public let usage: [UsageEntry]
}

/// Plays a scenario over time (spec 024 FR-011, FR-012, data-model
/// "ScenarioPlayer"). Pure apart from the clock the caller passes in; every
/// demo source asks it on `collect`, so all three see the same frames.
public actor ScenarioPlayer {
    public nonisolated let scenario: Scenario
    /// Every time in the scenario is relative to this date.
    public nonisolated let launch: Date

    public init(scenario: Scenario, launch: Date) {
        self.scenario = scenario
        self.launch = launch
    }

    /// The merged values of all frames with `launch + at <= now`. A frame
    /// changes only the fields it names; its records are added from then on.
    public func state(at now: Date) -> ScenarioState {
        var claude = scenario.claude
        var codex = scenario.codex
        var usage = scenario.usage
        for frame in scenario.frames where launch.addingTimeInterval(frame.at.seconds) <= now {
            for (id, change) in frame.claude ?? [:] {
                guard var windows = claude[id] else { continue }
                // Windows by identity (spec 040 FR-020).
                let indexByIdentity = windows.indexByIdentity
                for (identity, limitChange) in change.limits ?? [:] {
                    guard let index = indexByIdentity[ClaudeWindow(rawValue: identity)] else { continue }
                    windows.limits[index] = Self.applying(limitChange, to: windows.limits[index])
                }
                claude[id] = windows
            }
            for (id, change) in frame.codex ?? [:] {
                guard var windows = codex[id] else { continue }
                for windowChange in change.windows {
                    guard let index = windows.windows.firstIndex(where: { $0.lengthMinutes == windowChange.lengthMinutes }) else { continue }
                    if let used = windowChange.used { windows.windows[index].used = used }
                    if let resetsIn = windowChange.resetsIn { windows.windows[index].resetsIn = resetsIn }
                }
                codex[id] = windows
            }
            usage += frame.usage ?? []
        }
        return ScenarioState(claude: claude, codex: codex, usage: usage)
    }

    /// The reset time of a Claude window: fixed at `launch + resetsIn`;
    /// nil for a window that has not started.
    public func resetDate(_ window: ScenarioClaudeLimit) -> Date? {
        window.resetsIn.map { launch.addingTimeInterval($0.seconds) }
    }

    /// The reset time of a Codex plan window: fixed at `launch + resetsIn`.
    public func resetDate(_ window: CodexWindowValue) -> Date {
        launch.addingTimeInterval(window.resetsIn.seconds)
    }

    private static func applying(_ change: WindowChange, to value: ScenarioClaudeLimit) -> ScenarioClaudeLimit {
        var next = value
        if let used = change.used { next.used = used }
        if let resetsIn = change.resetsIn { next.resetsIn = resetsIn }
        return next
    }
}
