import Foundation

// MARK: - Stored arrangement

/// Whether an entry reference names an account or a budget group. A group
/// and an account may share an id, so references are kind-qualified
/// (spec 008 research R1).
public enum EntryKind: String, Codable, Equatable, Hashable, Sendable {
    case account
    case group
}

/// One top-level entry of the arrangement, as stored in `config.json`
/// (spec 008 contracts/config-file.md).
public struct EntryRef: Codable, Equatable, Hashable, Sendable {
    public var kind: EntryKind
    public var id: String

    public init(kind: EntryKind, id: String) {
        self.kind = kind
        self.id = id
    }
}

/// The user-defined order of all entries, plus the member order inside each
/// group (spec 008 FR-001). It holds only order; visibility stays in the
/// shown-in-bar settings of accounts, own budgets, groups and members.
/// A stored arrangement may be stale or hand edited; `arrangedEntries`
/// resolves it tolerantly (FR-011).
public struct Arrangement: Codable, Equatable, Sendable {
    /// Order of the top-level entries.
    public var entries: [EntryRef]
    /// Group id to the ordered ids of its member accounts.
    public var members: [String: [String]]

    public init(entries: [EntryRef] = [], members: [String: [String]] = [:]) {
        self.entries = entries
        self.members = members
    }

    private enum CodingKeys: String, CodingKey {
        case entries, members
    }

    /// Never throws for content problems: a malformed reference (unknown
    /// kind, missing or non-string id, not an object) is dropped on its own,
    /// and a missing or malformed `entries` or `members` reads as empty
    /// (FR-011: none of these is a configuration error).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let lossyEntries = (try? c.decodeIfPresent([Lossy<EntryRef>].self, forKey: .entries)) ?? nil
        entries = (lossyEntries ?? []).compactMap(\.value)
        let lossyMembers = (try? c.decodeIfPresent([String: Lossy<[Lossy<String>]>].self, forKey: .members)) ?? nil
        members = (lossyMembers ?? [:]).compactMapValues { $0.value?.compactMap(\.value) }
    }
}

/// Decodes a value or nothing, so one bad element does not fail its array.
private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

// MARK: - Resolved arrangement

/// An entry in its resolved place: an account that is an entry of its own
/// (Claude subscription, Codex subscription, own budget) or a budget group
/// with its members in member order (spec 008 FR-001). Derived, never stored.
public enum ArrangedEntry: Equatable, Sendable, Identifiable {
    case account(Account)
    case group(BudgetGroup, members: [Account])

    /// Kind-qualified (`"account:<id>"`, `"group:<id>"`), so `ForEach`
    /// identity stays unique when a group and an account share an id
    /// (research R7).
    public var id: String { "\(ref.kind.rawValue):\(ref.id)" }

    /// The stored form of this entry.
    public var ref: EntryRef {
        switch self {
        case .account(let account): return EntryRef(kind: .account, id: account.id)
        case .group(let group, _): return EntryRef(kind: .group, id: group.id)
        }
    }
}

extension Configuration {
    /// True when the account has its own place in the arrangement: a Claude
    /// subscription, a Codex subscription, or a token-based account with its
    /// own budget (spec 008 FR-009). Group members and invalid accounts are not.
    public func isEntry(_ account: Account) -> Bool {
        switch account.kind {
        case .subscription, .codexSubscription: return true
        case .tokenBased(let settings): return settings.ownBudget != nil
        }
    }

    /// The effective order of all entries, each group with its members in
    /// member order (spec 008 FR-001, FR-011, research R2):
    /// 1. stored references naming an existing entry of that kind, first
    ///    occurrence only;
    /// 2. every other entry in default order, accounts that are entries in
    ///    accounts-list order, then groups in groups-list order;
    /// 3. per group, stored member ids of accounts that are members of that
    ///    group, first occurrence only, then the other members in
    ///    accounts-list order.
    /// With nothing stored this is the bar order of spec 004 FR-020. Nothing
    /// here throws: unknown, duplicate and misplaced references are ignored.
    public var arrangedEntries: [ArrangedEntry] {
        let entryAccounts = accounts.filter(isEntry)
        var placed = Set<EntryRef>()
        var order: [EntryRef] = []
        func place(_ ref: EntryRef) {
            if placed.insert(ref).inserted { order.append(ref) }
        }
        let accountIds = Set(entryAccounts.map(\.id))
        let groupIds = Set(groups.map(\.id))
        for ref in arrangement?.entries ?? [] {
            switch ref.kind {
            case .account where accountIds.contains(ref.id): place(ref)
            case .group where groupIds.contains(ref.id): place(ref)
            default: continue
            }
        }
        for account in entryAccounts { place(EntryRef(kind: .account, id: account.id)) }
        for group in groups { place(EntryRef(kind: .group, id: group.id)) }

        return order.compactMap { ref -> ArrangedEntry? in
            switch ref.kind {
            case .account:
                return entryAccounts.first { $0.id == ref.id }.map(ArrangedEntry.account)
            case .group:
                guard let group = group(id: ref.id) else { return nil }
                return .group(group, members: orderedMembers(of: group.id))
            }
        }
    }

    /// The members of `groupId` in member order (FR-011 step 3).
    private func orderedMembers(of groupId: String) -> [Account] {
        let all = members(of: groupId)
        var seen = Set<String>()
        var result: [Account] = []
        for id in arrangement?.members[groupId] ?? [] {
            guard let member = all.first(where: { $0.id == id }), seen.insert(id).inserted else { continue }
            result.append(member)
        }
        result += all.filter { !seen.contains($0.id) }
        return result
    }

    /// The order resolved with nothing stored, as a complete arrangement
    /// (every entry, every group with all its members). Used to decide
    /// whether an order has to be stored at all (spec 008 FR-004a).
    public var defaultArrangement: Arrangement {
        var copy = self
        copy.arrangement = nil
        return copy.asArrangement(copy.arrangedEntries)
    }

    /// The stored form of a resolved order: every entry, and for every group
    /// its members (an empty list for a group without members).
    public func asArrangement(_ entries: [ArrangedEntry]) -> Arrangement {
        var members: [String: [String]] = [:]
        for entry in entries {
            if case .group(let group, let groupMembers) = entry {
                members[group.id] = groupMembers.map(\.id)
            }
        }
        return Arrangement(entries: entries.map(\.ref), members: members)
    }
}

// MARK: - Placement rules

extension Configuration {
    /// This configuration (the candidate Settings is about to apply) with
    /// its arrangement updated by the placement rules, judged against the
    /// last applied configuration `previous` (spec 008 research R3):
    /// 0. Same stored arrangement and same entries and members: returned
    ///    unchanged, so a stale hand-edited order is never rewritten (FR-004).
    /// 1. Base order: this arrangement when it differs from `previous`'s (a
    ///    reorder from the Menu Bar tab, or the default order when an undo
    ///    cleared it), otherwise `previous`'s resolved order.
    /// 2. Accounts that left a group for their own budget are placed right
    ///    after the group, or at its position when it was deleted (FR-006);
    ///    accounts that joined a group go last in it (FR-005, FR-007); new
    ///    entries go last (FR-005); removed items are dropped (FR-008).
    ///    Accounts that move together keep their previous member order
    ///    (spec 009 FR-011); accounts that were in no group follow in
    ///    accounts-list order.
    /// 3. The result is stored when an order was stored before, or when it
    ///    differs from the default order (FR-004a); otherwise nothing is
    ///    stored (FR-004), also after a reorder that ends at the default order.
    public func reconcilingArrangement(previous: Configuration) -> Configuration {
        if arrangement == previous.arrangement && arrangementStructure == previous.arrangementStructure {
            return self
        }
        // A candidate without an arrangement while `previous` has one (an
        // arrangement cleared back to the default order) takes the default
        // order as its base, so a cleared order does not return (FR-014).
        let reordered = arrangement != previous.arrangement
        var base = reordered ? arrangement ?? defaultArrangement : previous.asArrangement(previous.arrangedEntries)

        // 2.1: who moved, judged against the previous membership.
        var previousGroupOf: [String: String] = [:]
        for group in previous.groups {
            for member in previous.members(of: group.id) { previousGroupOf[member.id] = group.id }
        }
        let moved = accounts.filter { isEntry($0) && previousGroupOf[$0.id] != nil }
        var joined: [String: [String]] = [:]
        for account in accounts {
            guard let groupId = account.kind.tokenBased?.groupId, group(id: groupId) != nil,
                  previousGroupOf[account.id] != groupId else { continue }
            joined[groupId, default: []].append(account.id)
        }
        // Spec 009 FR-011, research R4: accounts moving together keep the
        // order they had, by (position of the former group in the previous
        // order, index in its previous member list). Accounts without a
        // previous position go last, in accounts-list order.
        var previousPosition: [String: (group: Int, member: Int)] = [:]
        for (groupIndex, entry) in previous.arrangedEntries.enumerated() {
            guard case .group(_, let members) = entry else { continue }
            for (memberIndex, member) in members.enumerated() {
                previousPosition[member.id] = (groupIndex, memberIndex)
            }
        }
        func inPreviousOrder(_ ids: [String]) -> [String] {
            ids.enumerated().sorted { lhs, rhs in
                switch (previousPosition[lhs.element], previousPosition[rhs.element]) {
                case let (l?, r?) where l != r: return l < r
                case (.some, nil): return true
                case (nil, .some): return false
                default: return lhs.offset < rhs.offset
                }
            }.map(\.element)
        }

        let displaced = Set(moved.map(\.id)).union(joined.values.joined())
        base.entries.removeAll { $0.kind == .account && displaced.contains($0.id) }
        base.members = base.members.mapValues { $0.filter { !displaced.contains($0) } }

        // 2.2: accounts that got their own budget follow their former group.
        let previousOrder = previous.arrangedEntries.map(\.ref)
        var lastInserted: [EntryRef?: EntryRef] = [:]
        for groupRef in previousOrder where groupRef.kind == .group {
            let leaving = inPreviousOrder(moved.filter { previousGroupOf[$0.id] == groupRef.id }.map(\.id))
                .map { EntryRef(kind: .account, id: $0) }
            guard let lastLeaving = leaving.last else { continue }
            let anchor: EntryRef?
            if base.entries.contains(groupRef) {
                anchor = groupRef
            } else {
                let before = previousOrder.prefix(while: { $0 != groupRef })
                anchor = before.last { base.entries.contains($0) }
            }
            let after = lastInserted[anchor] ?? anchor
            let position = after.flatMap { base.entries.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            base.entries.insert(contentsOf: leaving, at: position)
            lastInserted[anchor] = lastLeaving
        }

        // 2.3: accounts that joined a group go last in it.
        for (groupId, ids) in joined {
            base.members[groupId, default: []].append(contentsOf: inPreviousOrder(ids))
        }

        // 2.4, 2.5: resolution appends missing entries and members in default
        // order and drops references that are no longer entries or members.
        var result = self
        result.arrangement = base
        let resolved = result.asArrangement(result.arrangedEntries)
        let store = previous.arrangement != nil || resolved != defaultArrangement
        result.arrangement = store ? resolved : nil
        return result
    }

    /// The configuration Settings applies for this draft (spec 008 FR-004a
    /// to FR-008, FR-014): the placement rules run against the state the
    /// user last saw, and groups without members are kept (spec 009 FR-002).
    /// That state is the configuration an undo just restored, when there is
    /// one, and otherwise the last applied configuration. An undo target
    /// applied unchanged passes through as it is (step 0 of
    /// `reconcilingArrangement`), and an edit made right after an undo is
    /// never judged against the undone state, so Undo restores exactly the
    /// previous order.
    public func settingsCandidate(applied: Configuration, undoTarget: Configuration?) -> Configuration {
        reconcilingArrangement(previous: undoTarget ?? applied)
    }

    /// The entries and the members of every group, ignoring order: what the
    /// no-op check of `reconcilingArrangement` compares.
    private var arrangementStructure: ArrangementStructure {
        ArrangementStructure(
            entries: Set(accounts.filter(isEntry).map { EntryRef(kind: .account, id: $0.id) } + groups.map { EntryRef(kind: .group, id: $0.id) }),
            // A draft may hold duplicate group ids until validation rejects it.
            members: Dictionary(groups.map { ($0.id, Set(members(of: $0.id).map(\.id))) }, uniquingKeysWith: { first, _ in first }))
    }
}

private struct ArrangementStructure: Equatable {
    let entries: Set<EntryRef>
    let members: [String: Set<String>]
}

// MARK: - Shown in bar

extension Configuration {
    /// The setting behind a row's "Show in bar" checkbox (spec 008 FR-012,
    /// research R6): `shownInBar` of a Claude or Codex subscription, of an
    /// own budget, or of a group, and a member's share setting. False for a
    /// row that names nothing.
    public func isShownInBar(_ row: ArrangementRow) -> Bool {
        switch row {
        case .entry(let ref) where ref.kind == .group:
            return group(id: ref.id)?.shownInBar ?? false
        case .entry(let ref):
            switch account(id: ref.id)?.kind {
            case .subscription(let settings)?: return settings.shownInBar
            case .codexSubscription(let settings)?: return settings.shownInBar
            case .tokenBased(let settings)?: return settings.ownBudget?.shownInBar ?? false
            case nil: return false
            }
        case .member(let groupId, let accountId):
            guard let settings = account(id: accountId)?.kind.tokenBased, settings.groupId == groupId else { return false }
            return settings.memberShownInBar
        }
    }

    /// Sets the same setting the account and group editors change
    /// (FR-012). Visibility only: the arrangement is left as it is.
    public func settingShownInBar(_ row: ArrangementRow, _ shown: Bool) -> Configuration {
        var copy = self
        switch row {
        case .entry(let ref) where ref.kind == .group:
            guard let index = groups.firstIndex(where: { $0.id == ref.id }) else { return self }
            copy.groups[index].shownInBar = shown
        case .entry(let ref):
            guard let index = accounts.firstIndex(where: { $0.id == ref.id }) else { return self }
            switch accounts[index].kind {
            case .subscription(var settings):
                settings.shownInBar = shown
                copy.accounts[index].kind = .subscription(settings)
            case .codexSubscription(var settings):
                settings.shownInBar = shown
                copy.accounts[index].kind = .codexSubscription(settings)
            case .tokenBased(var settings):
                guard case .ownBudget(var budget) = settings.membership else { return self }
                budget.shownInBar = shown
                settings.membership = .ownBudget(budget)
                copy.accounts[index].kind = .tokenBased(settings)
            }
        case .member(let groupId, let accountId):
            guard let index = accounts.firstIndex(where: { $0.id == accountId }),
                  var settings = accounts[index].kind.tokenBased, settings.groupId == groupId else { return self }
            settings.membership = .group(id: groupId, shownInBar: shown)
            copy.accounts[index].kind = .tokenBased(settings)
        }
        return copy
    }
}
