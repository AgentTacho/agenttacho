import Foundation

/// The texts of a threshold notification (spec 030 FR-016, FR-017). A
/// crossing carries only used percents; the wording follows the direction
/// the presenter passes when it posts, so a queued crossing reads in the
/// direction of the moment it is shown. When notifications fire never
/// depends on the direction (spec 001 FR-028, spec 015).
public enum ThresholdNotificationText {
    /// Direction used, as before: "<name> reached T%", "<window> window at
    /// P%". Direction remaining: "<name> has <100 − T>% left" for T up to
    /// 100, "<name> is <T − 100>% over" above it; the body depends only on
    /// the current value, "<window> window at <100 − P>% left" up to 100%
    /// used, "<window> window at <P − 100>% over" above it.
    public static func make(_ crossing: ThresholdCrossing, direction: DisplayDirection) -> (title: String, body: String) {
        let name = crossing.entityName
        let window = crossing.windowKind.displayName
        let threshold = crossing.threshold
        let percent = crossing.percent
        switch direction {
        case .used:
            return ("\(name) reached \(threshold)%", "\(window) window at \(percent)%")
        case .remaining:
            let title = threshold > 100 ? "\(name) is \(threshold - 100)% over" : "\(name) has \(100 - threshold)% left"
            let body = percent > 100 ? "\(window) window at \(percent - 100)% over" : "\(window) window at \(100 - percent)% left"
            return (title, body)
        }
    }

    /// The diagnostic log's description of a crossing, always in used
    /// percent, so logs compare whatever the direction (FR-017).
    public static func logDescription(_ crossing: ThresholdCrossing) -> String {
        "\(crossing.entityName) (\(crossing.entityId)) \(crossing.windowKind.displayName) crossed \(crossing.threshold)% at \(crossing.percent)%"
    }
}
