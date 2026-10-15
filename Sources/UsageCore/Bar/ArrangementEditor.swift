import Foundation

/// One row of the Menu Bar settings tab, in display order: an entry, or a
/// member indented under its group (spec 008 FR-009).
public enum ArrangementRow: Equatable, Hashable, Sendable, Identifiable {
    case entry(EntryRef)
    case member(groupId: String, accountId: String)

    /// `"account:<id>"`, `"group:<id>"` or `"member:<accountId>"`: unique
    /// when a group and an account share an id, and stable across moves, so
    /// a moved row stays selected (FR-010a). A member row needs only the
    /// account id, since an account belongs to at most one group; joining
    /// the group id in would let two rows collide for ids containing the
    /// separator.
    public var id: String {
        switch self {
        case .entry(let ref): return "\(ref.kind.rawValue):\(ref.id)"
        case .member(_, let accountId): return "member:\(accountId)"
        }
    }

    var isEntry: Bool {
        if case .entry = self { return true }
        return false
    }
}

/// The reorder operations of the Menu Bar tab (spec 008 FR-010, FR-010a,
/// research R4). Pure: each takes the configuration being edited and returns
/// the new arrangement, always complete (every entry, every member), or nil
/// when the move is rejected or changes nothing.
public enum ArrangementEditor {
    /// Entries in arrangement order, each group followed by its members in
    /// member order (FR-009).
    public static func rows(_ configuration: Configuration) -> [ArrangementRow] {
        configuration.arrangedEntries.flatMap { arranged -> [ArrangementRow] in
            switch arranged {
            case .account:
                return [.entry(arranged.ref)]
            case .group(let group, let members):
                return [.entry(arranged.ref)] + members.map { .member(groupId: group.id, accountId: $0.id) }
            }
        }
    }

    /// A drag in `onMove` coordinates: `destination` is a row index before
    /// the moved row is removed (`Array.move(fromOffsets:toOffset:)`).
    /// - A member row is accepted only for destinations within its group's
    ///   member rows f...l+1, and reorders the group's members.
    /// - An entry row (a group with its member rows) is accepted only before
    ///   another entry row or at the end, never inside or at the start of a
    ///   member block (FR-010).
    /// - More than one source row, and destinations that leave everything in
    ///   place, return nil.
    public static func move(_ configuration: Configuration, from source: IndexSet, to destination: Int) -> Arrangement? {
        let rows = rows(configuration)
        guard source.count == 1, let index = source.first, rows.indices.contains(index),
              (0...rows.count).contains(destination) else { return nil }
        var arrangement = configuration.asArrangement(configuration.arrangedEntries)
        switch rows[index] {
        case .member(let groupId, _):
            guard let first = rows.firstIndex(where: { $0.groupId == groupId }),
                  let last = rows.lastIndex(where: { $0.groupId == groupId }),
                  (first...last + 1).contains(destination),
                  destination != index, destination != index + 1 else { return nil }
            var members = arrangement.members[groupId] ?? []
            members.moveElement(at: index - first, to: destination - first)
            arrangement.members[groupId] = members
        case .entry:
            var blockEnd = index
            while blockEnd + 1 < rows.count, !rows[blockEnd + 1].isEntry { blockEnd += 1 }
            guard destination == rows.count || rows[destination].isEntry,
                  !(index...blockEnd + 1).contains(destination) else { return nil }
            let entryIndex = rows[..<index].filter(\.isEntry).count
            let entryDestination = rows[..<destination].filter(\.isEntry).count
            arrangement.entries.moveElement(at: entryIndex, to: entryDestination)
        }
        return arrangement
    }

    /// One position up within the row's level; a group moves with its
    /// members (FR-010a). Nil when the row is first in its level or unknown.
    public static func moveUp(_ configuration: Configuration, row: ArrangementRow) -> Arrangement? {
        shift(configuration, row: row, by: -1)
    }

    /// One position down within the row's level (FR-010a). Nil when the row
    /// is last in its level or unknown.
    public static func moveDown(_ configuration: Configuration, row: ArrangementRow) -> Arrangement? {
        shift(configuration, row: row, by: 1)
    }

    /// False for no selection, an unknown row, and the first row of its level.
    public static func canMoveUp(_ configuration: Configuration, row: ArrangementRow?) -> Bool {
        row.map { moveUp(configuration, row: $0) != nil } ?? false
    }

    /// False for no selection, an unknown row, and the last row of its level.
    public static func canMoveDown(_ configuration: Configuration, row: ArrangementRow?) -> Bool {
        row.map { moveDown(configuration, row: $0) != nil } ?? false
    }

    private static func shift(_ configuration: Configuration, row: ArrangementRow, by offset: Int) -> Arrangement? {
        var arrangement = configuration.asArrangement(configuration.arrangedEntries)
        switch row {
        case .entry(let ref):
            guard let index = arrangement.entries.firstIndex(of: ref),
                  arrangement.entries.indices.contains(index + offset) else { return nil }
            arrangement.entries.swapAt(index, index + offset)
        case .member(let groupId, let accountId):
            guard var members = arrangement.members[groupId],
                  let index = members.firstIndex(of: accountId),
                  members.indices.contains(index + offset) else { return nil }
            members.swapAt(index, index + offset)
            arrangement.members[groupId] = members
        }
        return arrangement
    }
}

private extension ArrangementRow {
    var groupId: String? {
        if case .member(let groupId, _) = self { return groupId }
        return nil
    }
}

private extension Array {
    /// Moves one element with the semantics of SwiftUI's
    /// `move(fromOffsets:toOffset:)`: `destination` counts positions before
    /// the element is removed.
    mutating func moveElement(at index: Int, to destination: Int) {
        let element = remove(at: index)
        insert(element, at: destination > index ? destination - 1 : destination)
    }
}
