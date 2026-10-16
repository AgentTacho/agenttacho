import Foundation
import UserNotifications
import UsageCore

/// Sends one macOS notification per threshold crossing (FR-028) and
/// delivers and withdraws credential notifications (spec 014 FR-007,
/// FR-011, FR-014).
///
/// `UNUserNotificationCenter.add` fails while the authorization status is
/// still undetermined, so notifications that arrive before the user answered
/// the permission prompt are queued and posted once authorization is
/// granted. `prepare()` triggers the prompt at launch so it is normally
/// answered long before the first notification.
@MainActor
final class NotificationPresenter {
    private enum Authorization {
        case unknown
        case requesting
        case granted
        case denied
    }

    private let log: DiagnosticLog
    private var authorization: Authorization = .unknown
    /// Crossings and credential alerts waiting for authorization (spec 014
    /// FR-014).
    private var pending = PendingNotificationQueue()
    /// Credential notifications posted in this run; only their withdrawal
    /// is logged, and a post that completes after its withdrawal is removed
    /// again (spec 014 FR-007, FR-010).
    private var credentialPosts = CredentialPostLedger()
    /// `UNUserNotificationCenter` needs an app bundle; without one (for example
    /// `swift run`) notifications are only logged.
    private let available = Bundle.main.bundleIdentifier != nil
    /// The notification center's delegate; the center holds it weakly.
    private var clickHandler: NotificationClickHandler?

    /// With an app bundle, handles clicks from now on (spec 014 FR-013) and
    /// removes credential notifications left from an earlier run, which this
    /// run's baseline would never withdraw (FR-007, FR-008, SC-005).
    init(log: DiagnosticLog) {
        self.log = log
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        let handler = NotificationClickHandler(log: log)
        clickHandler = handler
        center.delegate = handler
        center.getDeliveredNotifications { notifications in
            let leftovers = notifications.map(\.request.identifier).filter { $0.hasPrefix(CredentialAlert.identifierPrefix) }
            if !leftovers.isEmpty {
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: leftovers)
            }
            log.append(source: "notifications", message: "credential leftovers removed: \(leftovers.count)")
        }
    }

    /// Requests authorization (showing the system prompt on first use) without
    /// posting anything. Safe to call more than once.
    func prepare() {
        guard available, authorization == .unknown else { return }
        requestAuthorization()
    }

    func send(_ crossings: [ThresholdCrossing]) {
        guard !crossings.isEmpty else { return }
        guard available else {
            for c in crossings {
                log.append(source: "notifications", message: "not sent (no app bundle): \(describe(c))")
            }
            return
        }
        switch authorization {
        case .granted:
            post(crossings)
        case .requesting:
            crossings.forEach { pending.add($0) }
        case .unknown, .denied:
            // A denial is not final: the user may enable notifications in
            // System Settings later. requestAuthorization does not prompt
            // again once answered; it just reports the current status.
            crossings.forEach { pending.add($0) }
            requestAuthorization()
        }
    }

    /// Acts on the credential tracker's events (spec 014 FR-007, FR-010,
    /// FR-012, FR-014).
    func handle(_ events: [CredentialAlertEvent]) {
        for event in events {
            switch event {
            case .deliver(let alert):
                deliver(alert, event: event)
            case .suppressed:
                log.append(source: "notifications", message: "credential not sent (switch off): \(event.logMessage)")
            case .withdraw(let accountId):
                withdraw(accountId: accountId)
            }
        }
    }

    private func deliver(_ alert: CredentialAlert, event: CredentialAlertEvent) {
        guard available else {
            log.append(source: "notifications", message: "credential not sent (no app bundle): \(event.logMessage)")
            return
        }
        switch authorization {
        case .granted:
            post(alert)
        case .requesting:
            pending.add(alert)
        case .unknown, .denied:
            pending.add(alert)
            requestAuthorization()
        }
    }

    /// Removes the account's delivered notification, a request not shown
    /// yet and a queued alert (spec 014 FR-007, FR-008, FR-014).
    private func withdraw(accountId: String) {
        if pending.removeCredential(accountId: accountId) {
            log.append(source: "notifications", message: "credential dropped from queue: \(accountId)")
        }
        guard available else { return }
        let identifier = CredentialAlert.identifier(accountId: accountId)
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        if credentialPosts.withdraw(identifier) {
            log.append(source: "notifications", message: "credential withdrawn: \(CredentialAlertEvent.withdraw(accountId: accountId).logMessage)")
        }
    }

    private func requestAuthorization() {
        authorization = .requesting
        let log = self.log
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            if let error {
                log.append(source: "notifications", message: "authorization error: \(error.localizedDescription)")
            } else {
                log.append(source: "notifications", message: "authorization \(granted ? "granted" : "denied")")
            }
            Task { @MainActor in
                self?.finishAuthorization(granted: granted && error == nil)
            }
        }
    }

    private func finishAuthorization(granted: Bool) {
        authorization = granted ? .granted : .denied
        let queued = pending.drain()
        if granted {
            post(queued.crossings)
            queued.alerts.forEach { post($0) }
        } else {
            for c in queued.crossings {
                log.append(source: "notifications", message: "not sent (authorization denied): \(describe(c))")
            }
            for alert in queued.alerts {
                log.append(source: "notifications",
                           message: "credential not sent (authorization denied): \(CredentialAlertEvent.deliver(alert).logMessage)")
            }
        }
    }

    private func post(_ crossings: [ThresholdCrossing]) {
        let center = UNUserNotificationCenter.current()
        for crossing in crossings {
            let content = UNMutableNotificationContent()
            content.title = "\(crossing.entityName) reached \(crossing.threshold)%"
            content.body = "\(crossing.windowKind.displayName) window at \(crossing.percent)%"
            content.sound = .default
            let identifier = "\(crossing.entityId)-\(crossing.windowKind.rawValue)-\(crossing.threshold)-\(Int(Date().timeIntervalSince1970))"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            let log = self.log
            let description = describe(crossing)
            center.add(request) { error in
                if let error {
                    log.append(source: "notifications", message: "failed: \(description): \(error.localizedDescription)")
                } else {
                    log.append(source: "notifications", message: "sent: \(description)")
                }
            }
        }
    }

    /// Posts under the account's stable identifier, replacing an earlier
    /// one (spec 014 FR-011). Texts come from UsageCore (FR-009, FR-010).
    private func post(_ alert: CredentialAlert) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        let identifier = alert.identifier
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        let generation = credentialPosts.begin(identifier)
        let log = self.log
        let subject = CredentialAlertEvent.deliver(alert).logMessage
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error {
                log.append(source: "notifications", message: "credential failed: \(subject): \(error.localizedDescription)")
            } else {
                log.append(source: "notifications", message: "credential sent: \(subject)")
                // Only a posted notification that is still current logs its
                // withdrawal (FR-010, contracts/notification-texts.md).
                Task { @MainActor in self?.recordPosted(alert.accountId, generation: generation) }
            }
        }
    }

    /// Records a completed post. A post withdrawn while `add` was still
    /// running may have reached Notification Center after the removal, so
    /// it is removed again, unless a newer post replaced it (FR-007, FR-011).
    private func recordPosted(_ accountId: String, generation: Int) {
        let identifier = CredentialAlert.identifier(accountId: accountId)
        if credentialPosts.completed(identifier, generation: generation) == .withdrawn {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
            log.append(source: "notifications", message: "credential withdrawn: \(accountId)")
        }
    }

    private func describe(_ c: ThresholdCrossing) -> String {
        "\(c.entityName) (\(c.entityId)) \(c.windowKind.displayName) crossed \(c.threshold)% at \(c.percent)%"
    }
}

/// Opens the dropdown on a click on any AgentMeter notification and shows
/// notifications also while AgentMeter is the active app, which it is while
/// the dropdown is open (spec 014 FR-013, contracts/notification-texts.md).
final class NotificationClickHandler: NSObject, UNUserNotificationCenterDelegate {
    private let log: DiagnosticLog

    init(log: DiagnosticLog) {
        self.log = log
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let log = self.log
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                MenuBarOpener.open(log: log)
            }
            completionHandler()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
