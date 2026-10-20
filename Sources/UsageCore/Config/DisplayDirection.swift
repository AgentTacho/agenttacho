import Foundation

/// How every level value is shown (spec 030 FR-008, FR-009): as used, from
/// 0% to 100% (the default), or as remaining, from 100% down to 0% and below
/// for a budget over its limit. Presentation only: levels, stored
/// thresholds and when notifications fire never depend on it (FR-014,
/// FR-015, FR-016).
public enum DisplayDirection: String, Codable, CaseIterable, Sendable {
    case used
    case remaining
}
