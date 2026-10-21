import Foundation
import Testing
@testable import UsageCore

/// spec 033 FR-002, FR-003, FR-008, FR-012, research R1, R3,
/// contracts/external-sources.md: decoding the Claude free-reset block and
/// the Codex credit list, and the list helpers of the dropdown and the
/// expiry tracker.
@Suite struct ResetTicketsTests {
    /// Wed 21 Oct 2026, 12:00 UTC.
    static let now = isoDate("2026-10-21T12:00:00Z")

    static func object(_ json: String) -> Any? {
        try? JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed])
    }

    static func claude(_ json: String) -> ResetTicketRead {
        ResetTicketDecoding.claude(cedarEmber: object(json), now: now)
    }

    static func codex(_ json: String) -> ResetTicketRead {
        ResetTicketDecoding.codex(data: Data(json.utf8), now: now)
    }

    static func isClearing(_ read: ResetTicketRead) -> Bool {
        if case .clearingFailure = read { return true }
        return false
    }

    static func grant(left: Any = 1, starts: String? = nil, ends: String? = nil, paused: Any = false) -> String {
        func text(_ value: String?) -> String { value.map { "\"\($0)\"" } ?? "null" }
        return """
        { "id": "grant-1", "usable_now": true, "resets_left": \(left), "resets_total": 1,
          "starts_at": \(text(starts)), "ends_at": \(text(ends)), "paused": \(paused) }
        """
    }

    static func block(eligible: String = "true", grants: [String]) -> String {
        "{ \"eligible\": \(eligible), \"grants\": [\(grants.joined(separator: ","))] }"
    }

    // MARK: - Claude

    @Test func claudeValidBlockGivesOneTicketPerGrant() {
        let read = Self.claude(Self.block(grants: [
            Self.grant(starts: "2026-10-20T08:00:00Z", ends: "2026-10-24T08:00:00Z"),
            Self.grant(),
        ]))
        #expect(read == .tickets([ResetTicket(expiresAt: isoDate("2026-10-24T08:00:00Z")), ResetTicket(expiresAt: nil)]))
    }

    @Test func claudeResetsLeftGivesThatManyTicketsWithTheGrantsEnd() {
        let read = Self.claude(Self.block(grants: [Self.grant(left: 2, ends: "2026-10-24T08:00:00.250Z")]))
        let end = isoDate("2026-10-24T08:00:00Z")
        #expect(read == .tickets([ResetTicket(expiresAt: end), ResetTicket(expiresAt: end)]))
    }

    @Test func claudeZeroResetsLeftGivesNone() {
        #expect(Self.claude(Self.block(grants: [Self.grant(left: 0, ends: "2026-10-24T08:00:00Z")])) == .tickets([]))
    }

    @Test func claudePausedFutureAndEndedGrantsGiveNone() {
        let read = Self.claude(Self.block(grants: [
            Self.grant(ends: "2026-10-24T08:00:00Z", paused: true),
            Self.grant(starts: "2026-10-22T08:00:00Z", ends: "2026-10-30T08:00:00Z"),
            Self.grant(ends: "2026-10-21T12:00:00Z"),
            Self.grant(ends: "2026-10-20T08:00:00Z"),
        ]))
        #expect(read == .tickets([]))
    }

    @Test func claudeStartAtNowCounts() {
        let read = Self.claude(Self.block(grants: [Self.grant(starts: "2026-10-21T12:00:00Z")]))
        #expect(read == .tickets([ResetTicket(expiresAt: nil)]))
    }

    @Test func claudeNotEligibleMissingOrEmptyGivesNoTickets() {
        #expect(Self.claude(Self.block(eligible: "false", grants: [Self.grant()])) == .tickets([]))
        #expect(ResetTicketDecoding.claude(cedarEmber: nil, now: Self.now) == .tickets([]))
        #expect(ResetTicketDecoding.claude(cedarEmber: NSNull(), now: Self.now) == .tickets([]))
        #expect(Self.claude(Self.block(grants: [])) == .tickets([]))
        #expect(Self.claude("{ \"eligible\": true }") == .tickets([]))
    }

    @Test func claudeMalformedBlocksClear() {
        #expect(Self.isClearing(Self.claude("[]")))
        #expect(Self.isClearing(Self.claude("\"yes\"")))
        #expect(Self.isClearing(Self.claude("{ \"eligible\": \"true\", \"grants\": [] }")))
        #expect(Self.isClearing(Self.claude("{ \"eligible\": 1, \"grants\": [] }")))
        #expect(Self.isClearing(Self.claude("{ \"eligible\": true, \"grants\": {} }")))
        #expect(Self.isClearing(Self.claude(Self.block(grants: ["7"]))))
        #expect(Self.isClearing(Self.claude(Self.block(grants: [Self.grant(left: "\"1\"")]))))
        #expect(Self.isClearing(Self.claude(Self.block(grants: [Self.grant(left: 1.5)]))))
        #expect(Self.isClearing(Self.claude(Self.block(grants: [Self.grant(paused: "\"no\"")]))))
        #expect(Self.isClearing(Self.claude(Self.block(grants: ["{ \"paused\": false }"]))))
    }

    @Test func claudeNegativeResetsLeftClears() {
        #expect(Self.isClearing(Self.claude(Self.block(grants: [Self.grant(left: -1)]))))
    }

    @Test func claudeUnparsableTimeClears() {
        #expect(Self.isClearing(Self.claude(Self.block(grants: [Self.grant(ends: "next Friday")]))))
        #expect(Self.isClearing(Self.claude(Self.block(grants: [Self.grant(starts: "2026-13-40")]))))
    }

    @Test func claudeTooManyGrantsClears() {
        let grants = Array(repeating: Self.grant(left: 0), count: 201)
        #expect(Self.isClearing(Self.claude(Self.block(grants: grants))))
        let allowed = Array(repeating: Self.grant(left: 0), count: 200)
        #expect(Self.claude(Self.block(grants: allowed)) == .tickets([]))
    }

    @Test func claudeTooManyUsableTicketsClears() {
        #expect(Self.isClearing(Self.claude(Self.block(grants: [Self.grant(left: 51)]))))
        #expect(Self.isClearing(Self.claude(Self.block(grants: Array(repeating: Self.grant(), count: 51)))))
        #expect(Self.isClearing(Self.claude(Self.block(grants: [Self.grant(left: 1_000_000_000_000)]))))
        if case .tickets(let tickets) = Self.claude(Self.block(grants: [Self.grant(left: 50)])) {
            #expect(tickets.count == 50)
        } else {
            Issue.record("50 tickets are plausible")
        }
    }

    /// Unusable grants never count toward the cap of usable tickets.
    @Test func claudeCapCountsUsableTicketsOnly() {
        let read = Self.claude(Self.block(grants: [Self.grant(left: 40, ends: "2026-10-20T08:00:00Z"), Self.grant(left: 40, paused: true),
                                                   Self.grant(left: 2)]))
        #expect(read == .tickets([ResetTicket(expiresAt: nil), ResetTicket(expiresAt: nil)]))
    }

    // MARK: - Codex

    @Test func codexAvailableCreditsWithFutureOrNoExpiryCount() {
        let read = Self.codex("""
        { "available_count": 3, "credits": [
          { "id": "c1", "reset_type": "weekly", "status": "available", "granted_at": "2026-10-18T10:00:00Z", "expires_at": "2026-10-25T10:00:00Z" },
          { "id": "c2", "status": "available" },
          { "id": "c3", "status": "available", "expires_at": null }
        ] }
        """)
        #expect(read == .tickets([ResetTicket(expiresAt: isoDate("2026-10-25T10:00:00Z")), ResetTicket(expiresAt: nil),
                                  ResetTicket(expiresAt: nil)]))
    }

    @Test func codexOtherStatusesAndPastExpiriesDoNotCount() {
        let read = Self.codex("""
        { "credits": [
          { "id": "c1", "status": "redeemed", "expires_at": "2026-10-30T10:00:00Z" },
          { "id": "c2", "status": "redeeming", "expires_at": "2026-10-30T10:00:00Z" },
          { "id": "c3", "status": "expired" },
          { "id": "c4", "status": "available", "expires_at": "2026-10-21T11:59:59Z" },
          { "id": "c5", "status": "available", "expires_at": "2026-10-21T12:00:00Z" },
          { "id": "c6" }
        ] }
        """)
        #expect(read == .tickets([]))
    }

    @Test func codexMissingOrEmptyListGivesNoTickets() {
        #expect(Self.codex("{ \"available_count\": 0 }") == .tickets([]))
        #expect(Self.codex("{ \"credits\": null }") == .tickets([]))
        #expect(Self.codex("{ \"credits\": [] }") == .tickets([]))
    }

    @Test func codexMalformedListsClear() {
        #expect(Self.isClearing(Self.codex("not json")))
        #expect(Self.isClearing(Self.codex("[]")))
        #expect(Self.isClearing(Self.codex("{ \"credits\": {} }")))
        #expect(Self.isClearing(Self.codex("{ \"credits\": [7] }")))
        #expect(Self.isClearing(Self.codex("{ \"credits\": [ { \"status\": 1 } ] }")))
        #expect(Self.isClearing(Self.codex("{ \"credits\": [ { \"status\": \"available\", \"expires_at\": 1761386400 } ] }")))
        #expect(Self.isClearing(Self.codex("{ \"credits\": [ { \"status\": \"available\", \"expires_at\": \"soon\" } ] }")))
    }

    /// spec 033 edge case "Implausible data": the raw credit list is capped
    /// like Claude's grant records, usable or not.
    @Test func codexTooManyCreditRecordsClears() {
        let redeemed = "{ \"status\": \"redeemed\" }"
        let tooMany = Self.codex("{ \"credits\": [\(Array(repeating: redeemed, count: 201).joined(separator: ","))] }")
        #expect(tooMany == .clearingFailure("implausible"))
        #expect(Self.codex("{ \"credits\": [\(Array(repeating: redeemed, count: 200).joined(separator: ","))] }") == .tickets([]))
    }

    @Test func codexTooManyUsableCreditsClears() {
        let one = "{ \"status\": \"available\" }"
        #expect(Self.isClearing(Self.codex("{ \"credits\": [\(Array(repeating: one, count: 51).joined(separator: ","))] }")))
        if case .tickets(let tickets) = Self.codex("{ \"credits\": [\(Array(repeating: one, count: 50).joined(separator: ","))] }") {
            #expect(tickets.count == 50)
        } else {
            Issue.record("50 credits are plausible")
        }
    }

    // MARK: - Read kinds (FR-019 log labels)

    @Test func failureKindsAreShortLabels() {
        #expect(ResetTicketRead.tickets([]).failureKind == nil)
        #expect(ResetTicketRead.temporaryFailure("http-500").failureKind == "http-500")
        #expect(ResetTicketRead.clearingFailure("malformed").failureKind == "malformed")
        if case .clearingFailure(let kind) = Self.claude("[]") { #expect(kind == "malformed") }
        if case .clearingFailure(let kind) = Self.claude(Self.block(grants: [Self.grant(left: 51)])) { #expect(kind == "implausible") }
    }

    // MARK: - Applying a read (FR-003)

    @Test func applyingAReadFollowsFR003() {
        let past = ResetTicket(expiresAt: Self.now.addingTimeInterval(-1))
        let future = ResetTicket(expiresAt: Self.now.addingTimeInterval(3600))
        let previous = [past, future]
        #expect(ResetTicketRead.tickets([future]).applied(to: [], now: Self.now) == [future])
        #expect(ResetTicketRead.temporaryFailure("transport").applied(to: previous, now: Self.now) == [future])
        #expect(ResetTicketRead.clearingFailure("malformed").applied(to: previous, now: Self.now) == [])
    }

    // MARK: - List helpers

    @Test func usableDropsExpiredTickets() {
        let tickets = [ResetTicket(expiresAt: Self.now), ResetTicket(expiresAt: Self.now.addingTimeInterval(1)), ResetTicket(expiresAt: nil)]
        #expect(tickets.usable(at: Self.now) == [ResetTicket(expiresAt: Self.now.addingTimeInterval(1)), ResetTicket(expiresAt: nil)])
    }

    @Test func sortedForDisplayPutsTheSoonestFirstAndNoExpiryLast() {
        let a = ResetTicket(expiresAt: Self.now.addingTimeInterval(7200))
        let b = ResetTicket(expiresAt: Self.now.addingTimeInterval(3600))
        let none = ResetTicket(expiresAt: nil)
        #expect([none, a, b].sortedForDisplay == [b, a, none])
    }

    @Test func glyphsShowThreeAndOverflowTheRest() {
        let tickets = (1...5).map { ResetTicket(expiresAt: Self.now.addingTimeInterval(Double(6 - $0) * 3600)) }
            + [ResetTicket(expiresAt: Self.now.addingTimeInterval(-60))]
        let glyphs = tickets.glyphs(at: Self.now)
        #expect(glyphs.shown == [1, 2, 3].map { ResetTicket(expiresAt: Self.now.addingTimeInterval(Double($0) * 3600)) })
        #expect(glyphs.overflow == [4, 5].map { ResetTicket(expiresAt: Self.now.addingTimeInterval(Double($0) * 3600)) })
        let two = [ResetTicket(expiresAt: nil), ResetTicket(expiresAt: Self.now.addingTimeInterval(60))]
        #expect(two.glyphs(at: Self.now).shown == [ResetTicket(expiresAt: Self.now.addingTimeInterval(60)), ResetTicket(expiresAt: nil)])
        #expect(two.glyphs(at: Self.now).overflow.isEmpty)
        #expect([ResetTicket]().glyphs(at: Self.now).shown.isEmpty)
    }

    @Test func groupedByExpiryCountsUsableTicketsWithExpiry() {
        let t1 = Self.now.addingTimeInterval(3600)
        let t2 = Self.now.addingTimeInterval(7200)
        let tickets = [ResetTicket(expiresAt: t1), ResetTicket(expiresAt: t1), ResetTicket(expiresAt: t2), ResetTicket(expiresAt: nil),
                       ResetTicket(expiresAt: Self.now)]
        #expect(tickets.groupedByExpiry(at: Self.now) == [t1: 2, t2: 1])
    }
}

/// spec 033 FR-006, research R4: the entries carry their tickets through
/// every copy a refresh without a request makes.
@Suite struct ResetTicketEntryTests {
    static let now = isoDate("2026-10-21T12:00:00Z")
    static let tickets = [ResetTicket(expiresAt: isoDate("2026-10-24T08:00:00Z")), ResetTicket(expiresAt: nil)]

    @Test func entriesDefaultToNoTickets() {
        #expect(SubscriptionEntry(status: nil, state: .ok).resetTickets.isEmpty)
        #expect(CodexLimitsEntry(observation: nil, state: .live).resetTickets.isEmpty)
    }

    @Test func subscriptionCopiesKeepTheTickets() {
        let retryAt = Self.now.addingTimeInterval(-120)
        let entry = SubscriptionEntry(status: nil, state: .retrying(lastGoodAt: nil, error: "offline", retryAt: retryAt),
                                      quickRetryAt: retryAt, resetTickets: Self.tickets)
        #expect(entry.resetTickets == Self.tickets)
        #expect(entry.endingGrace(now: Self.now).resetTickets == Self.tickets)
        #expect(entry.reused(now: Self.now).resetTickets == Self.tickets)
        let ok = SubscriptionEntry(status: nil, state: .ok, resetTickets: Self.tickets)
        #expect(ok.reused(now: Self.now).resetTickets == Self.tickets)
        #expect(ok.endingGrace(now: Self.now).resetTickets == Self.tickets)
    }

    @Test func codexStaleCopyKeepsTheTickets() {
        let entry = CodexLimitsEntry(observation: nil, state: .live, resetTickets: Self.tickets)
        #expect(entry.markedStale(reason: "offline").resetTickets == Self.tickets)
    }

    @Test func ticketsTakePartInEquality() {
        #expect(SubscriptionEntry(status: nil, state: .ok, resetTickets: Self.tickets) != SubscriptionEntry(status: nil, state: .ok))
        #expect(CodexLimitsEntry(observation: nil, state: .live, resetTickets: Self.tickets) != CodexLimitsEntry(observation: nil, state: .live))
    }
}

/// spec 033 FR-003, FR-019: the log labels of a failed request.
@Suite struct ResetTicketRequestFailureTests {
    @Test func labels() {
        #expect(ResetTicketRead.requestFailure(UsageEndpointError.httpStatus(503)) == .temporaryFailure("http-503"))
        #expect(ResetTicketRead.requestFailure(UsageEndpointError.rateLimited(retryAfter: 30)) == .temporaryFailure("http-429"))
        #expect(ResetTicketRead.requestFailure(UsageEndpointError.decoding("x")) == .temporaryFailure("undecodable"))
        #expect(ResetTicketRead.requestFailure(UsageEndpointError.network("offline")) == .temporaryFailure("transport"))
        #expect(ResetTicketRead.requestFailure(CancellationError()) == .temporaryFailure("transport"))
    }
}
