import AppKit
import ServiceManagement
import SwiftUI
import UsageCore

@main
struct AgentMeterApp: App {
    @State private var model: AppModel

    init() {
        // AgentMeter runs only once; the check must come before the model,
        // which starts refreshing as soon as it exists.
        SingleInstance.ensure()
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        MenuBarExtra {
            DropdownView(model: model)
        } label: {
            BarLabelView(items: model.barItems, display: model.configuration.levelDisplay)
        }
        .menuBarExtraStyle(.window)

        // The standard settings window: toolbar panes, title per pane, no
        // minimize or zoom (Apple HIG, Settings).
        Settings {
            SettingsView(model: model)
        }
    }
}

/// Owns the configuration store, the refresh coordinator, the refresh timer
/// and the wake observer. Everything the views need comes from here.
@MainActor
@Observable
final class AppModel {

    let paths: Paths
    let configStore: ConfigStore
    let log: DiagnosticLog
    let coordinator: RefreshCoordinator
    let credentialReader: SecurityToolCredentialReader
    let builtInPrices: PriceTable
    /// Owns `imported-prices.json` (FR-025 to FR-027).
    let importedPriceStore: ImportedPriceStore

    private(set) var snapshot: UsageSnapshot?
    private(set) var configuration: Configuration
    /// The stored imports, updated after every apply or removal.
    private(set) var importedPrices: ImportedPrices
    /// Set when the stored imports could not be read at launch (FR-027);
    /// cleared by the next successful apply or removal.
    private(set) var importedPricesNotice: String?

    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var consumerTask: Task<Void, Never>?
    @ObservationIgnored private var currentInterval: Int = Configuration.defaultRefreshIntervalSeconds
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var thresholdTracker = ThresholdTracker()
    /// Credential notifications (spec 014): baseline per account, one
    /// notification per failure episode.
    @ObservationIgnored private var credentialTracker: CredentialAlertTracker
    /// True once a snapshot from a refresh (not the early result from saved
    /// values) arrived (spec 010 FR-015).
    @ObservationIgnored private var sawRefreshResult = false
    /// Created in `init`, not on first use, so the notification click
    /// handler exists before any click (spec 014 FR-013).
    @ObservationIgnored private let notifications: NotificationPresenter

    init(paths: Paths = Paths()) {
        self.paths = paths
        let log = DiagnosticLog(fileURL: paths.logFileURL)
        // Icon labels need the bundled Font Awesome fonts before the first draw.
        IconFont.register(log: log)
        // Reads through /usr/bin/security, which Claude Code's keychain items
        // trust, so no keychain dialog appears after a rebuild.
        let reader = SecurityToolCredentialReader(paths: paths)
        let store = ConfigStore(fileURL: paths.configFileURL, makeDefault: {
            // FR-034: first launch without a file gets a subscription account
            // when the default keychain item exists.
            let hasCredentials = reader.hasDefaultCredential()
            log.append(source: "config", message: "no configuration file, creating default (credentials found: \(hasCredentials))")
            return ConfigStore.makeDefault(hasDefaultCredentials: hasCredentials)
        })
        self.log = log
        self.configStore = store
        self.credentialReader = reader
        self.builtInPrices = (try? PriceTable.builtIn()) ?? PriceTable(entries: [])
        let priceStore = ImportedPriceStore(fileURL: paths.importedPricesFileURL)
        self.importedPrices = priceStore.load()
        self.importedPricesNotice = priceStore.loadError
        if let reason = priceStore.loadError {
            log.append(source: "prices", message: "imported prices ignored, using manual and built-in prices: \(reason)")
        }
        self.importedPriceStore = priceStore
        self.coordinator = RefreshCoordinator(configStore: store, log: log, resolver: WindowResolver(), aggregator: Aggregator())
        self.configuration = store.current
        self.credentialTracker = CredentialAlertTracker(paths: paths)
        log.append(source: "app", message: "launch, \(AppVersionInfo(infoDictionary: Bundle.main.infoDictionary ?? [:]).label)")
        self.notifications = NotificationPresenter(log: log)

        startConsumingSnapshots()
        observeWake()
        restartTimer(interval: configStore.current.refreshIntervalSeconds)

        // The last good values of the previous launch, AgentMeter's own file
        // (spec 010 FR-013 to FR-018). Logged without any values.
        let (savedValues, savedProblem) = LastGoodStore.load(from: paths.lastGoodFileURL)
        if let savedProblem {
            log.append(source: "lastGood", message: savedProblem)
        } else if let savedValues {
            log.append(source: "lastGood", message: "loaded saved last good values: \(savedValues.claude.count) Claude, \(savedValues.codex.count) Codex account(s)")
        }
        let lastGoodStore = LastGoodStore(fileURL: paths.lastGoodFileURL, initial: savedValues, log: log)

        // Register sources, then run the first refresh immediately (FR-024).
        let subscriptionSource = SubscriptionSource(credentialReader: reader, client: UsageEndpointClient(), log: log,
                                                    store: lastGoodStore, paths: paths)
        let sessionLogSource: SessionLogSource?
        do {
            sessionLogSource = try SessionLogSource(paths: paths, log: log, builtInPrices: builtInPrices, importedPrices: priceStore)
        } catch {
            sessionLogSource = nil
            log.append(source: SessionLogSource.sourceName, message: "disabled: \(error)")
        }
        // OpenCode's database, read-only (spec 006 FR-001).
        let openCodeSource: OpenCodeSource?
        do {
            openCodeSource = try OpenCodeSource(paths: paths, log: log, builtInPrices: builtInPrices, importedPrices: priceStore)
        } catch {
            openCodeSource = nil
            log.append(source: OpenCodeSource.sourceName, message: "disabled: \(error)")
        }
        // Codex rollout files, read-only; the auth mode comes from the logs
        // only, never from credential files (spec 006 FR-001, FR-014).
        let codexSource: CodexSessionSource?
        do {
            codexSource = try CodexSessionSource(paths: paths, log: log, builtInPrices: builtInPrices, importedPrices: priceStore)
        } catch {
            codexSource = nil
            log.append(source: CodexSessionSource.sourceName, message: "disabled: \(error)")
        }
        // Codex plan limits: live from the ChatGPT usage service with the
        // sign-in in each account's Codex home (read, never renewed), local
        // snapshots as the fallback (spec 007 FR-002 to FR-005).
        let codexLimitsSource = CodexLimitsSource(credentialReader: FileCodexCredentialReader(paths: paths),
                                                  client: CodexUsageClient(), log: log, paths: paths, store: lastGoodStore)
        let coordinator = self.coordinator
        Task {
            await coordinator.register(subscriptionSource)
            if let sessionLogSource {
                await coordinator.register(sessionLogSource)
            }
            if let openCodeSource {
                await coordinator.register(openCodeSource)
            }
            if let codexSource {
                await coordinator.register(codexSource)
            }
            await coordinator.register(codexLimitsSource)
            // Saved values right away, before the first refresh (spec 010 FR-015).
            await coordinator.publishSavedValues()
            await coordinator.requestRefresh(trigger: .launch)
        }
    }

    var barItems: [BarItem] {
        BarLayout.segments(snapshot: snapshot, configuration: configuration)
    }

    // MARK: Actions

    /// "Refresh now": calls the usage endpoint unless the last fetch is
    /// under 60 s old or a rate-limit block is active.
    func refreshNow() {
        let coordinator = self.coordinator
        Task { await coordinator.requestRefresh(trigger: .manual) }
    }

    func openLog() {
        if !FileManager.default.fileExists(atPath: paths.logFileURL.path) {
            log.append(source: "app", message: "log opened")
        }
        NSWorkspace.shared.open(paths.logFileURL)
    }

    /// Validates and writes a configuration from the settings window, which
    /// applies changes as they are made. Only changes that affect what a
    /// refresh computes trigger one; icon, name, visibility and
    /// threshold edits just redraw from the existing snapshot. Only
    /// subscription changes may call the usage endpoint; all other
    /// data-relevant edits re-price locally.
    func saveConfiguration(_ config: Configuration) throws {
        let previous = configuration
        try configStore.save(config)
        configuration = config
        let refresh = config.needsRefresh(comparedTo: previous)
        let trigger: RefreshTrigger = config.needsNetworkRefresh(comparedTo: previous) ? .settings : .local
        log.append(source: "config", message: "saved from settings: \(config.accounts.count) account(s), \(config.groups.count) group(s), interval \(config.refreshIntervalSeconds) s"
                   + (refresh ? ", refresh \(trigger.rawValue)" : ", display only"))
        if config.refreshIntervalSeconds != currentInterval {
            restartTimer(interval: config.refreshIntervalSeconds)
        }
        applyStartAtLogin(config.startAtLogin)
        // The credential notification switch takes effect without a refresh
        // (spec 014 FR-012, research R5).
        let credentialEvents = credentialTracker.configurationChanged(config)
        if !credentialEvents.isEmpty {
            notifications.handle(credentialEvents)
        }
        if refresh {
            let coordinator = self.coordinator
            Task { await coordinator.requestRefresh(trigger: trigger) }
        }
    }

    // MARK: Prices

    /// The layered price table with the given manual overrides (FR-001).
    func effectivePrices(overrides: [PriceEntry]) -> PriceTable {
        PriceTable.effective(builtIn: builtInPrices, imported: importedPrices, overrides: overrides)
    }

    /// Canonical ids of the models in every breakdown of the current
    /// snapshot (`UsageSnapshot.usedModels`); nil before the first snapshot
    /// (FR-020c, FR-030, research R9).
    var usedModels: Set<String>? {
        snapshot?.usedModels
    }

    /// Fetches the LiteLLM price list and builds the preview of a provider
    /// import. Runs only from the Import menu, never from a timer or at
    /// launch (FR-034). `overrides` are the manual overrides shown on the
    /// Prices tab, which may not be saved yet. A failure is logged with its
    /// reason (no prices) unless the sheet was closed.
    func previewProviderImport(_ kind: ImportKind, overrides: [PriceEntry]) async throws -> (ProposedImport, PriceDiff) {
        do {
            let importer = LiteLLMImporter()
            let data = try await importer.fetch()
            let origin = importer.url.absoluteString
            let batch = try await Task.detached(priority: .userInitiated) {
                try LiteLLMImporter.batch(from: data, kind: kind, origin: origin, importedAt: Date())
            }.value
            let proposal = ProposedImport(batch: batch)
            return (proposal, diff(for: proposal, overrides: overrides))
        } catch {
            if !Task.isCancelled {
                log.append(source: "prices", message: "\(kind.displayName) import failed: \(error)")
            }
            throw error
        }
    }

    /// Largest CSV file the import reads; a price table is a few kilobytes.
    static let maxCSVBytes = 5 * 1024 * 1024

    /// Reads a CSV file and builds the preview of a CSV import (FR-014 to
    /// FR-017b). The origin is the file name. Files over `maxCSVBytes` are
    /// rejected without reading the rest. A failure is logged with its reason.
    func previewCSVImport(url: URL, overrides: [PriceEntry]) throws -> (ProposedImport, PriceDiff) {
        do {
            // Read at most one byte more than the limit, so that the limit
            // holds even when the file size is not known up front.
            let data: Data
            do {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                data = try handle.read(upToCount: AppModel.maxCSVBytes + 1) ?? Data()
            } catch {
                throw PriceImportError.unreadableFile(error.localizedDescription)
            }
            guard data.count <= AppModel.maxCSVBytes else {
                throw PriceImportError.unreadableFile("the file is larger than 5 MB")
            }
            guard let text = String(data: data, encoding: .utf8) else {
                throw PriceImportError.unreadableFile("the file is not UTF-8 text")
            }
            let proposal = try PriceCSV.parse(text, origin: url.lastPathComponent, importedAt: Date())
            return (proposal, diff(for: proposal, overrides: overrides))
        } catch {
            log.append(source: "prices", message: "CSV import of \(url.lastPathComponent) failed: \(error)")
            throw error
        }
    }

    /// The preview diff of a proposed import against the stored imports,
    /// with the given manual overrides.
    func diff(for proposal: ProposedImport, overrides: [PriceEntry]) -> PriceDiff {
        PriceDiff.compute(current: importedPrices, proposed: proposal.batch, kind: proposal.batch.kind, builtIn: builtInPrices,
                          overrides: overrides, usedModels: usedModels)
    }

    /// Stores the proposed import, replacing an earlier import of the same
    /// kind only, then re-prices the session logs without calling the usage
    /// endpoint (FR-021, FR-023a, FR-033). `overrides` are the manual
    /// overrides the preview used, so the logged counts match it. A failed
    /// save throws `PriceImportError.saveFailed` and changes nothing (FR-026).
    func applyImport(_ proposal: ProposedImport, overrides: [PriceEntry]) throws {
        let current = importedPriceStore.current
        // The import time is the time the import is applied.
        let batch = PriceBatch(kind: proposal.batch.kind, origin: proposal.batch.origin, importedAt: Date(),
                               entries: proposal.batch.entries)
        let diff = PriceDiff.compute(current: current, proposed: batch, kind: batch.kind, builtIn: builtInPrices,
                                     overrides: overrides, usedModels: nil)
        do {
            try importedPriceStore.save(current.replacing(batch))
        } catch {
            log.append(source: "prices", message: "import of \(batch.kind.displayName) prices not saved: \(error.localizedDescription)")
            throw PriceImportError.saveFailed(error.localizedDescription)
        }
        importedPrices = importedPriceStore.current
        importedPricesNotice = nil
        log.append(source: "prices", message: "imported \(batch.entries.count) \(batch.kind.displayName) prices from \(batch.origin) "
                   + "(\(diff.newModels.count) new, \(diff.changed.count) changed, \(diff.removed.count) removed)")
        requestReprice()
    }

    /// What removing the stored import of `kind` would do: the removed
    /// models fall back to another price or become unpriced (FR-023, R8).
    func removalImpact(_ kind: ImportKind, overrides: [PriceEntry]) -> PriceDiff {
        PriceDiff.compute(current: importedPrices, proposed: nil, kind: kind, builtIn: builtInPrices,
                          overrides: overrides, usedModels: nil)
    }

    /// Removes the stored import of `kind` and re-prices without calling the
    /// usage endpoint (FR-023, FR-023a, FR-033). `overrides` are the manual
    /// overrides the confirmation used, so the logged count matches it. A
    /// failed save throws `PriceImportError.saveFailed` and changes nothing.
    func removeImport(_ kind: ImportKind, overrides: [PriceEntry]) throws {
        let impact = removalImpact(kind, overrides: overrides)
        do {
            try importedPriceStore.save(importedPriceStore.current.removing(kind))
        } catch {
            log.append(source: "prices", message: "removal of \(kind.displayName) prices not saved: \(error.localizedDescription)")
            throw PriceImportError.saveFailed(error.localizedDescription)
        }
        importedPrices = importedPriceStore.current
        importedPricesNotice = nil
        log.append(source: "prices", message: "removed \(kind.displayName) prices (\(impact.removed.count) models affected)")
        requestReprice()
    }

    /// Writes the effective price table with the given manual overrides (the
    /// table shown on the Prices tab) as CSV (FR-019). A write failure is
    /// logged and rethrown; the caller shows its reason (FR-024).
    func exportPrices(to url: URL, overrides: [PriceEntry]) throws {
        let table = effectivePrices(overrides: overrides)
        do {
            try Data(PriceCSV.export(table).utf8).write(to: url, options: .atomic)
        } catch {
            log.append(source: "prices", message: "CSV export failed: \(error.localizedDescription)")
            throw error
        }
        log.append(source: "prices", message: "exported \(table.entries.count) prices as CSV")
    }

    private func requestReprice() {
        let coordinator = self.coordinator
        Task { await coordinator.requestReprice() }
    }

    // MARK: Start at login (FR-035)

    var startAtLoginStatus: SMAppService.Status {
        SMAppService.mainApp.status
    }

    private func applyStartAtLogin(_ wanted: Bool) {
        let service = SMAppService.mainApp
        let enabled = service.status == .enabled
        guard wanted != enabled else { return }
        do {
            if wanted {
                try service.register()
            } else {
                try service.unregister()
            }
            log.append(source: "app", message: "start at login \(wanted ? "enabled" : "disabled")")
        } catch {
            log.append(source: "app", message: "start at login could not be \(wanted ? "enabled" : "disabled"): \(error.localizedDescription)")
        }
    }

    // MARK: Refresh plumbing

    private func startConsumingSnapshots() {
        let coordinator = self.coordinator
        consumerTask = Task { [weak self] in
            for await snapshot in coordinator.snapshots {
                guard let self else { return }
                self.apply(snapshot)
            }
        }
    }

    private func apply(_ snapshot: UsageSnapshot) {
        // The early result from saved values is not the first snapshot:
        // launch-time work waits for the first refresh (spec 010 FR-015).
        let firstSnapshot = !snapshot.isPreliminary && !sawRefreshResult
        if !snapshot.isPreliminary { sawRefreshResult = true }
        self.snapshot = snapshot
        let config = configStore.current
        self.configuration = config
        if config.refreshIntervalSeconds != currentInterval {
            restartTimer(interval: config.refreshIntervalSeconds)
        }
        if firstSnapshot {
            // Reconcile the system state with the saved preference once per launch.
            log.append(source: "app", message: "start at login: configured \(config.startAtLogin), system status \(startAtLoginStatus.rawValue)")
            applyStartAtLogin(config.startAtLogin)
            // Ask for notification permission now, not on the first crossing.
            notifications.prepare()
        }

        // Threshold notifications (FR-028): the first observation is the
        // baseline. The tracker skips saved Claude values (spec 010 FR-019).
        let crossings = thresholdTracker.observe(snapshot: snapshot, configuration: config)
        if !crossings.isEmpty {
            for crossing in crossings {
                log.append(source: "notifications", message: "crossing: \(crossing.entityName) \(crossing.windowKind.displayName) \(crossing.threshold)% (now \(crossing.percent)%)")
            }
            notifications.send(crossings)
        }

        // Credential notifications (spec 014 FR-003 to FR-008): the tracker
        // skips the early result from saved values.
        let credentialEvents = credentialTracker.observe(snapshot: snapshot, configuration: config)
        if !credentialEvents.isEmpty {
            notifications.handle(credentialEvents)
        }
    }

    /// Restarts the repeating refresh timer with a new interval (FR-024).
    func restartTimer(interval: Int) {
        currentInterval = max(interval, Configuration.minimumRefreshIntervalSeconds)
        timerTask?.cancel()
        let seconds = currentInterval
        let coordinator = self.coordinator
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                if Task.isCancelled { break }
                await coordinator.requestRefresh(trigger: .scheduled)
            }
        }
    }

    private func observeWake() {
        let coordinator = self.coordinator
        let log = self.log
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            log.append(source: "app", message: "wake from sleep, refreshing")
            // The timer's sleep counts on during system sleep, so a tick due
            // then would follow the wake refresh at once and take a pending
            // quick retry's place. Restarting the interval at wake keeps
            // the quick retry (spec 010 FR-008, SC-001).
            MainActor.assumeIsolated {
                guard let self else { return }
                self.restartTimer(interval: self.currentInterval)
            }
            Task { await coordinator.requestRefresh(trigger: .wake) }
        }
    }
}
