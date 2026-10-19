import Foundation

/// The background of one dropdown band (spec 028 FR-002, FR-005, FR-006):
/// a section is plain or tinted, the pinned footer has its own band.
public enum BandStyle: Equatable, Hashable, Sendable {
    case plain, tinted, footer

    /// The fill strength as a fraction of the panel's foreground color
    /// (spec 028 FR-005, FR-006): plain none, tinted 0.04, footer 0.07, and
    /// with "Increase contrast" 0.08 and 0.12, so plain < tinted < footer in
    /// both modes and each band is stronger with increased contrast.
    public func opacity(increasedContrast: Bool) -> Double {
        switch self {
        case .plain: return 0
        case .tinted: return increasedContrast ? 0.08 : 0.04
        case .footer: return increasedContrast ? 0.12 : 0.07
        }
    }
}

/// Which stripe each dropdown section gets (spec 028 FR-002, FR-003). Both
/// the dropdown and the demo coverage use it.
public enum SectionBands {
    /// One style per shown section in dropdown order: the arranged entries,
    /// then Unassigned when it is shown. The first is plain, the second
    /// tinted, and so on; a group with its members is one section, and
    /// Unassigned takes the next stripe after the last entry. Never
    /// `.footer`; a negative count counts as 0. Error lines and "No accounts
    /// configured" are not sections (spec 028 FR-003).
    public static func stripes(arrangedCount: Int, unassignedShown: Bool) -> [BandStyle] {
        let count = max(arrangedCount, 0) + (unassignedShown ? 1 : 0)
        return (0..<count).map { $0.isMultiple(of: 2) ? .plain : .tinted }
    }

    /// True when the snapshot has Unassigned usage with a non-empty
    /// breakdown, the dropdown's rule for showing the Unassigned section
    /// (spec 008 FR-003, unchanged by spec 028 FR-003).
    public static func showsUnassigned(_ snapshot: UsageSnapshot?) -> Bool {
        guard let snapshot else { return false }
        return !snapshot.unassigned.breakdown.isEmpty
    }
}
