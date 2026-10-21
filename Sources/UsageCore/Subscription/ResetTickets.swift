import Foundation

/// One usable free limit reset of a subscription account: a ticket that
/// resets a usage limit early when the user redeems it (spec 033 Key
/// Entities). Only the expiry time is kept; no identifier from the service
/// is decoded or stored (FR-006). Nil means the ticket never expires.
public struct ResetTicket: Equatable, Hashable, Sendable {
    public var expiresAt: Date?

    public init(expiresAt: Date?) {
        self.expiresAt = expiresAt
    }
}

/// The result of one attempt to read an account's tickets (spec 033 FR-003,
/// data-model.md). The associated string of a failure is a short label for
/// the diagnostic log: `transport`, `http-<code>`, `unexpected-location`,
/// `undecodable`, `malformed`, `implausible`, `flag-dropped-http-<code>`,
/// `flag-suspended-http-<code>` or `skipped` (FR-019).
public enum ResetTicketRead: Equatable, Sendable {
    /// A successful read, possibly empty: replaces the account's tickets.
    case tickets([ResetTicket])
    /// A failed request: the account keeps the tickets of its last
    /// successful read in this run, minus expired ones.
    case temporaryFailure(String)
    /// A malformed or implausible answer, or a dropped flag (FR-004): the
    /// account's tickets are cleared until the next successful read.
    case clearingFailure(String)

    /// The log label of a failure; nil for a successful read.
    public var failureKind: String? {
        switch self {
        case .tickets: return nil
        case .temporaryFailure(let kind), .clearingFailure(let kind): return kind
        }
    }

    /// The account's tickets after this read, given the tickets it had
    /// (spec 033 FR-003).
    public func applied(to previous: [ResetTicket], now: Date) -> [ResetTicket] {
        switch self {
        case .tickets(let tickets): return tickets
        case .temporaryFailure: return previous.usable(at: now)
        case .clearingFailure: return []
        }
    }

    /// The temporary failure of a request that threw (spec 033 FR-003):
    /// `http-<code>` for an HTTP answer, `http-429` for a rate limit,
    /// `undecodable` for an answer that is not a usage answer (kept apart
    /// from the clearing `malformed`, so each is logged once, FR-019),
    /// `transport` otherwise. Never holds text from the error.
    static func requestFailure(_ error: Error) -> ResetTicketRead {
        switch error as? UsageEndpointError {
        case .httpStatus(let code)?: return .temporaryFailure("http-\(code)")
        case .rateLimited?: return .temporaryFailure("http-429")
        case .decoding?: return .temporaryFailure("undecodable")
        case .network?, nil: return .temporaryFailure("transport")
        }
    }
}

/// Decoders of the two undocumented ticket sources (spec 033 FR-002, FR-003,
/// research R1, R3, contracts/external-sources.md). Only the fields named
/// there are read; `id`, `usable_now`, `available_count` and every other
/// field are ignored.
public enum ResetTicketDecoding {
    /// More grant records than this make a Claude block implausible, and
    /// more credit records a Codex list (research R1, R3).
    static let maximumGrants = 200
    /// More usable tickets than this for one account make a read
    /// implausible (spec 033 edge case "Implausible data").
    static let maximumTickets = 50

    private struct Failure: Error {
        let kind: String
        static let malformed = Failure(kind: "malformed")
        static let implausible = Failure(kind: "implausible")
    }

    /// The Claude `cedar_ember` block, as `JSONSerialization` read it; nil
    /// or `NSNull` when the response has none (spec 033 FR-002, FR-003). An
    /// account that is not eligible, or a block without grants, has no
    /// tickets. A grant counts when it is not paused, its start time (if
    /// any) is at or before `now` and its end time (if any) after `now`; it
    /// contributes `resets_left` tickets that expire at its end time.
    public static func claude(cedarEmber: Any?, now: Date) -> ResetTicketRead {
        guard let cedarEmber, !(cedarEmber is NSNull) else { return .tickets([]) }
        do {
            guard let block = cedarEmber as? [String: Any] else { throw Failure.malformed }
            guard try optionalBool(block["eligible"]) == true else { return .tickets([]) }
            guard let rawGrants = present(block["grants"]) else { return .tickets([]) }
            guard let grants = rawGrants as? [Any] else { throw Failure.malformed }
            guard grants.count <= maximumGrants else { throw Failure.implausible }
            var tickets: [ResetTicket] = []
            for raw in grants {
                guard let grant = raw as? [String: Any], let left = present(grant["resets_left"]) else { throw Failure.malformed }
                guard let count = integer(left) else { throw Failure.malformed }
                guard count >= 0 else { throw Failure.implausible }
                let paused = try optionalBool(grant["paused"]) ?? false
                let startsAt = try time(grant["starts_at"])
                let endsAt = try time(grant["ends_at"])
                guard !paused, startsAt.map({ $0 <= now }) ?? true, endsAt.map({ $0 > now }) ?? true else { continue }
                guard count <= maximumTickets - tickets.count else { throw Failure.implausible }
                tickets += Array(repeating: ResetTicket(expiresAt: endsAt), count: count)
            }
            return .tickets(tickets)
        } catch let failure as Failure {
            return .clearingFailure(failure.kind)
        } catch {
            return .clearingFailure(Failure.malformed.kind)
        }
    }

    /// The Codex credit list answer (spec 033 FR-002, FR-003): one ticket
    /// per credit with status `available` whose expiry time (if any) lies
    /// after `now`. An answer without `credits` has no tickets.
    public static func codex(data: Data, now: Date) -> ResetTicketRead {
        do {
            guard let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw Failure.malformed }
            guard let rawCredits = present(body["credits"]) else { return .tickets([]) }
            guard let credits = rawCredits as? [Any] else { throw Failure.malformed }
            guard credits.count <= maximumGrants else { throw Failure.implausible }
            var tickets: [ResetTicket] = []
            for raw in credits {
                guard let credit = raw as? [String: Any] else { throw Failure.malformed }
                let status = present(credit["status"])
                guard status == nil || status is String else { throw Failure.malformed }
                let expiresAt = try time(credit["expires_at"])
                guard status as? String == "available", expiresAt.map({ $0 > now }) ?? true else { continue }
                guard tickets.count < maximumTickets else { throw Failure.implausible }
                tickets.append(ResetTicket(expiresAt: expiresAt))
            }
            return .tickets(tickets)
        } catch let failure as Failure {
            return .clearingFailure(failure.kind)
        } catch {
            return .clearingFailure(Failure.malformed.kind)
        }
    }

    // MARK: - Lenient field access

    /// The value, or nil for an absent key or JSON `null`.
    private static func present(_ value: Any?) -> Any? {
        guard let value, !(value is NSNull) else { return nil }
        return value
    }

    private static func isBoolean(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    /// A JSON boolean, nil when absent; any other type is malformed.
    private static func optionalBool(_ value: Any?) throws -> Bool? {
        guard let value = present(value) else { return nil }
        guard isBoolean(value), let flag = value as? Bool else { throw Failure.malformed }
        return flag
    }

    /// A JSON number without a fractional part; nil for anything else,
    /// booleans included.
    private static func integer(_ value: Any) -> Int? {
        guard let number = value as? NSNumber, !isBoolean(number) else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double.rounded() == double, abs(double) < 1e15 else { return nil }
        return number.intValue
    }

    /// An ISO 8601 time truncated to whole seconds, so one expiry keeps one
    /// notification record key (FR-016); nil when absent. Any other type or
    /// an unparsable text is malformed.
    private static func time(_ value: Any?) throws -> Date? {
        guard let value = present(value) else { return nil }
        guard let text = value as? String, let date = UsageEndpointClient.parseDate(text) else { throw Failure.malformed }
        return Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }
}

extension Array where Element == ResetTicket {
    /// The tickets whose expiry (if any) lies after `now` (spec 033 FR-012).
    public func usable(at now: Date) -> [ResetTicket] {
        filter { ticket in ticket.expiresAt.map { $0 > now } ?? true }
    }

    /// Soonest expiry first, tickets without expiry last; equal tickets
    /// keep their order (spec 033 FR-008).
    public var sortedForDisplay: [ResetTicket] {
        enumerated().sorted { a, b in
            switch (a.element.expiresAt, b.element.expiresAt) {
            case (let x?, let y?): return x != y ? x < y : a.offset < b.offset
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return a.offset < b.offset
            }
        }
        .map(\.element)
    }

    /// The usable tickets in display order: at most three shown as glyphs,
    /// the rest behind the "+N" marker (spec 033 FR-008, FR-012).
    public func glyphs(at now: Date) -> (shown: [ResetTicket], overflow: [ResetTicket]) {
        let ordered = usable(at: now).sortedForDisplay
        return (Array(ordered.prefix(3)), Array(ordered.dropFirst(3)))
    }

    /// The number of usable tickets per expiry time; tickets without expiry
    /// are left out (spec 033 FR-014).
    public func groupedByExpiry(at now: Date) -> [Date: Int] {
        usable(at: now).reduce(into: [:]) { groups, ticket in
            if let expiresAt = ticket.expiresAt { groups[expiresAt, default: 0] += 1 }
        }
    }
}
