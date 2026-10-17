import AppKit
import CoreGraphics
import Foundation
import UsageCore

/// Reads the system state that slows the refresh timer and publishes every
/// change (spec 016 FR-008, FR-009, FR-011, research R8). Uses only APIs
/// that need no permission prompt (FR-020): the process power and thermal
/// state, the seconds since the last input event, the screen lock
/// notifications and display sleep.
@MainActor
final class SystemConditionsMonitor {
    /// No keyboard or mouse input for this long counts as idle (FR-008).
    static let idleThreshold: TimeInterval = 600
    /// How often the input idle time is read; a return from idle is seen
    /// within this time (FR-011).
    static let pollInterval: TimeInterval = 60

    private(set) var conditions = SystemConditions()
    private let onChange: (SystemConditions) -> Void
    private var screenLocked = false
    private var displaysAsleep = false
    /// The last unlock counts like an input event.
    private var unlockedAt: Date?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var pollTask: Task<Void, Never>?

    init(onChange: @escaping (SystemConditions) -> Void) {
        self.onChange = onChange
    }

    /// Reads the current state, publishes it once, and starts observing.
    func start() {
        let center = NotificationCenter.default
        observe(center, ProcessInfo.thermalStateDidChangeNotification) { $0.update() }
        observe(center, .NSProcessInfoPowerStateDidChange) { $0.update() }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.screenLocked = true; $0.update() }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) {
            // An unlock is a return (FR-011) even without keyboard or mouse
            // input, as with Touch ID or an Apple Watch.
            $0.screenLocked = false
            $0.unlockedAt = Date()
            $0.update()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.displaysAsleep = true; $0.update() }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.displaysAsleep = false; $0.update() }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.pollInterval))
                if Task.isCancelled { break }
                self?.update()
            }
        }
        update(force: true)
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ handler: @escaping @MainActor (SystemConditionsMonitor) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self)
            }
        }
        observers.append((center, token))
    }

    /// Reads every condition and publishes them when they changed.
    private func update(force: Bool = false) {
        let info = ProcessInfo.processInfo
        // Seconds since the last keyboard or mouse event of the session.
        let anyInput = CGEventType(rawValue: ~0)!
        var idleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        if let unlockedAt { idleSeconds = min(idleSeconds, Date().timeIntervalSince(unlockedAt)) }
        let inputIdle = idleSeconds >= Self.idleThreshold
        let thermal = info.thermalState
        let next = SystemConditions(idle: inputIdle || screenLocked || displaysAsleep,
                                    lowPowerMode: info.isLowPowerModeEnabled,
                                    thermalPressure: thermal == .serious || thermal == .critical)
        guard force || next != conditions else { return }
        conditions = next
        onChange(next)
    }
}
