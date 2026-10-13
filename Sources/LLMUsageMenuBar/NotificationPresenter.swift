import Foundation
import UserNotifications
import UsageCore

/// Sends one macOS notification per threshold crossing (FR-028).
///
/// `UNUserNotificationCenter.add` fails while the authorization status is
/// still undetermined, so crossings that arrive before the user answered the
/// permission prompt are queued and posted once authorization is granted.
/// `prepare()` triggers the prompt at launch so it is normally answered long
/// before the first crossing.
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
    private var pending: [ThresholdCrossing] = []
    /// `UNUserNotificationCenter` needs an app bundle; without one (for example
    /// `swift run`) the crossings are only logged.
    private let available = Bundle.main.bundleIdentifier != nil

    init(log: DiagnosticLog) {
        self.log = log
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
            enqueue(crossings)
        case .unknown, .denied:
            // A denial is not final: the user may enable notifications in
            // System Settings later. requestAuthorization does not prompt
            // again once answered; it just reports the current status.
            enqueue(crossings)
            requestAuthorization()
        }
    }

    /// Keeps the newest crossing per threshold and window while authorization
    /// is pending, so a prompt left unanswered for a long time does not end in
    /// a burst of stale notifications.
    private func enqueue(_ crossings: [ThresholdCrossing]) {
        for crossing in crossings {
            pending.removeAll {
                $0.entityId == crossing.entityId && $0.windowKind == crossing.windowKind && $0.threshold == crossing.threshold
            }
            pending.append(crossing)
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
        let queued = pending
        pending = []
        if granted {
            post(queued)
        } else {
            for c in queued {
                log.append(source: "notifications", message: "not sent (authorization denied): \(describe(c))")
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

    private func describe(_ c: ThresholdCrossing) -> String {
        "\(c.entityName) (\(c.entityId)) \(c.windowKind.displayName) crossed \(c.threshold)% at \(c.percent)%"
    }
}
