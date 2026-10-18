import Foundation
import UsageCore

/// What the demo app does at launch in place of the real setup (spec 024
/// FR-005, FR-006, FR-009, research R8).
public enum DemoSetup {
    /// Writes the scenario's configuration and imported prices into the
    /// demo's own folders, replacing what an earlier demo run left, and
    /// deletes the demo's saved last good values, so every launch starts
    /// from the scenario (FR-009). `paths` must be the demo's
    /// (`agenttacho-demo`); nothing else is touched (FR-005). The imports
    /// are dated one day before `launch`, so the Prices tab never shows a
    /// fixed past date (FR-011).
    public static func prepare(scenario: Scenario, paths: Paths, launch: Date = Date()) throws {
        try ConfigStore(fileURL: paths.configFileURL).save(scenario.configuration)
        let imported = scenario.importedPrices ?? .empty
        let importedAt = launch.addingTimeInterval(-86_400)
        let batches = imported.batches.map {
            PriceBatch(kind: $0.kind, origin: $0.origin, importedAt: importedAt, entries: $0.entries)
        }
        try ImportedPriceStore(fileURL: paths.importedPricesFileURL).save(ImportedPrices(version: imported.version, batches: batches))
        try removeLastGood(paths)
    }

    /// Leaves the demo empty when no scenario can be played: an empty
    /// configuration, no imported prices, no saved values, so nothing of an
    /// earlier run shows next to the error (FR-013).
    public static func clear(paths: Paths) throws {
        try ConfigStore(fileURL: paths.configFileURL).save(Configuration())
        try ImportedPriceStore(fileURL: paths.importedPricesFileURL).save(.empty)
        try removeLastGood(paths)
    }

    private static func removeLastGood(_ paths: Paths) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: paths.lastGoodFileURL.path) {
            try fm.removeItem(at: paths.lastGoodFileURL)
        }
    }

    /// The three demo sources the demo app registers instead of the five
    /// real ones (FR-006, SC-002). `importedPrices` is read on every refresh.
    public static func sources(player: ScenarioPlayer, builtInPrices: PriceTable,
                               importedPrices: @escaping @Sendable () -> ImportedPrices,
                               calendar: Calendar = .autoupdatingCurrent) -> [any UsageSource] {
        [
            DemoSubscriptionSource(player: player),
            DemoCodexLimitsSource(player: player),
            DemoRecordSource(player: player, builtInPrices: builtInPrices, importedPrices: importedPrices, calendar: calendar),
        ]
    }

    /// Seconds after launch at which a frame applies (FR-012).
    public static func frameOffsets(_ scenario: Scenario) -> [TimeInterval] {
        scenario.frames.map(\.at.seconds)
    }

    /// How long after a frame's offset its refresh runs, so the refresh
    /// sees the frame (FR-012: within 2 s).
    public static let frameRefreshDelay: TimeInterval = 0.5

    /// When the app refreshes for each frame: half a second after its
    /// offset. The app and the coverage check both use these times.
    public static func frameRefreshDates(_ scenario: Scenario, launch: Date) -> [Date] {
        frameOffsets(scenario).map { launch.addingTimeInterval($0 + frameRefreshDelay) }
    }

    /// The time of the last frame, or launch without frames: a snapshot
    /// generated at or after it shows the scenario's final state.
    public static func lastFrameDate(_ scenario: Scenario, launch: Date) -> Date {
        launch.addingTimeInterval(frameOffsets(scenario).last ?? 0)
    }
}

/// The demo build's credential reader: there is never a credential, and
/// nothing is read (spec 024 FR-006, research R8).
public struct NoCredentials: CredentialReader {
    public init() {}

    public func read(configDirectory: String) throws -> OAuthCredential? {
        nil
    }

    /// The first-launch default asks this; the demo writes its
    /// configuration before the store loads, so it never matters.
    public func hasDefaultCredential() -> Bool {
        false
    }
}
