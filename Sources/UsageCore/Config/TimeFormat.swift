import Foundation

/// How a section's reset and run-out times read in the dropdown (spec 025
/// FR-016, FR-021): relative ("resets in 2h 26m", the default) or absolute
/// ("resets 17:20"). Stored per account and group as `timeFormat`.
public enum TimeFormat: String, Codable, CaseIterable, Sendable {
    case relative
    case absolute
}
