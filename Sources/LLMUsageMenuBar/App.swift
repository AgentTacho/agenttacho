import AppKit
import ServiceManagement
import SwiftUI
import UsageCore

@main
struct LLMUsageMenuBarApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            DropdownView(model: model)
        } label: {
            BarLabelView(segments: model.barSegments)
        }
        .menuBarExtraStyle(.window)

        Window("LLM Usage Settings", id: AppModel.settingsWindowId) {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 720, height: 560)
    }
}

/// Owns the configuration store, the refresh coordinator, the refresh timer
/// and the wake observer. Everything the views need comes from here.
@MainActor
@Observable
final class AppModel {
    static let settingsWindowId = "settings"

    let paths: Paths
    let configStore: ConfigStore
    let log: DiagnosticLog
    let coordinator: RefreshCoordinator
    let credentialReader: SecurityToolCredentialReader
    let builtInPrices: PriceTable

    private(set) var snapshot: UsageSnapshot?
    private(set) var configuration: Configuration

    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var consumerTask: Task<Void, Never>?
    @ObservationIgnored private var currentInterval: Int = Configuration.defaultRefreshIntervalSeconds
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var thresholdTracker = ThresholdTracker()
    @ObservationIgnored private lazy var notifications = NotificationPresenter(log: log)

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
        self.coordinator = RefreshCoordinator(configStore: store, log: log, resolver: WindowResolver(), aggregator: Aggregator())
        self.configuration = store.current
        log.append(source: "app", message: "launch, version \(UsageCore.version)")

        startConsumingSnapshots()
        observeWake()
        restartTimer(interval: configStore.current.refreshIntervalSeconds)

        // Register sources, then run the first refresh immediately (FR-024).
        let subscriptionSource = SubscriptionSource(credentialReader: reader, client: UsageEndpointClient(), log: log)
        let sessionLogSource: SessionLogSource?
        do {
            sessionLogSource = try SessionLogSource(paths: paths, log: log, builtInPrices: builtInPrices)
        } catch {
            sessionLogSource = nil
            log.append(source: SessionLogSource.sourceName, message: "disabled: \(error)")
        }
        let coordinator = self.coordinator
        Task {
            await coordinator.register(subscriptionSource)
            if let sessionLogSource {
                await coordinator.register(sessionLogSource)
            }
            await coordinator.requestRefresh()
        }
    }

    var barSegments: [BarSegment] {
        BarLabelBuilder.segments(snapshot: snapshot, configuration: configuration)
    }

    // MARK: Actions

    func refreshNow() {
        let coordinator = self.coordinator
        Task { await coordinator.requestRefresh() }
    }

    func openLog() {
        if !FileManager.default.fileExists(atPath: paths.logFileURL.path) {
            log.append(source: "app", message: "log opened")
        }
        NSWorkspace.shared.open(paths.logFileURL)
    }

    /// Validates and writes the configuration, restarts the timer with the
    /// saved interval, applies start-at-login, and refreshes (tasks T046).
    func saveConfiguration(_ config: Configuration) throws {
        try configStore.save(config)
        configuration = config
        log.append(source: "config", message: "saved from settings: \(config.accounts.count) account(s), \(config.groups.count) group(s), interval \(config.refreshIntervalSeconds) s")
        if config.refreshIntervalSeconds != currentInterval {
            restartTimer(interval: config.refreshIntervalSeconds)
        }
        applyStartAtLogin(config.startAtLogin)
        refreshNow()
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
        let firstSnapshot = self.snapshot == nil
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

        // Threshold notifications (FR-028): the first observation is the baseline.
        let crossings = thresholdTracker.observe(snapshot: snapshot, configuration: config)
        if !crossings.isEmpty {
            for crossing in crossings {
                log.append(source: "notifications", message: "crossing: \(crossing.entityName) \(crossing.windowKind.displayName) \(crossing.threshold)% (now \(crossing.percent)%)")
            }
            notifications.send(crossings)
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
                await coordinator.requestRefresh()
            }
        }
    }

    private func observeWake() {
        let coordinator = self.coordinator
        let log = self.log
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            log.append(source: "app", message: "wake from sleep, refreshing")
            Task { await coordinator.requestRefresh() }
        }
    }
}
