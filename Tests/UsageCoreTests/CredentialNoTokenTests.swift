import Foundation
import Testing
@testable import UsageCore

/// spec 014 SC-006, FR-010: the token strings used in a refresh never reach
/// a credential notification's title, body, identifier or log text. The
/// real sources produce the snapshots; the tracker turns them into events.
@Suite struct CredentialNoTokenTests {
    static let sentinel = "SENTINEL-TOKEN-7f3a"
    static let window = DateInterval(start: isoDate("2026-10-12T00:00:00Z"), end: isoDate("2026-10-19T00:00:00Z"))

    /// Every text an event carries.
    static func texts(_ events: [CredentialAlertEvent]) -> [String] {
        events.flatMap { event -> [String] in
            switch event {
            case .deliver(let alert), .suppressed(let alert):
                return [alert.title, alert.body, alert.identifier, event.logMessage]
            case .withdraw:
                return [event.logMessage]
            }
        }
    }

    /// The events in order, as `deliver <kind>` and `withdraw <account>`, so
    /// a regression in a source's classification fails the test instead of
    /// leaving fewer texts to search.
    static func summary(_ events: [CredentialAlertEvent]) -> [String] {
        events.map { event in
            switch event {
            case .deliver(let alert): return "deliver \(alert.kind.rawValue)"
            case .suppressed(let alert): return "suppressed \(alert.kind.rawValue)"
            case .withdraw(let accountId): return "withdraw \(accountId)"
            }
        }
    }

    @Test func claudeEventsCarryNoToken() async throws {
        let dir = try makeTempDirectory("cred-no-token-claude")
        let working = "working-\(Self.sentinel)", renewed = "renewed-\(Self.sentinel)", expired = "expired-\(Self.sentinel)"
        defer {
            try? FileManager.default.removeItem(at: dir)
            for token in [working, renewed, expired] { StubURLProtocol.unregister(key: "Bearer \(token)") }
        }
        let clock = MutableClock(isoDate("2026-10-14T12:00:00Z"))
        let reader = FakeCredentialReader()
        let source = SubscriptionSource(credentialReader: reader, client: UsageEndpointClient(session: StubURLProtocol.makeSession()),
                                        log: DiagnosticLog(fileURL: dir.appendingPathComponent("usage.log")), clock: { clock.now() })
        let directory = "~/.claude-work"
        let config = Configuration(accounts: [Account(id: "acc-claude", displayName: "Claude (Work)",
                                                      kind: .subscription(SubscriptionSettings(credentialDirectory: directory)))])
        let far = clock.now().addingTimeInterval(365 * 86400)
        var tracker = CredentialAlertTracker()
        var events: [CredentialAlertEvent] = []

        func refresh(_ credential: OAuthCredential?) async throws {
            reader.credentials[directory] = credential
            let context = RefreshContext(configuration: config, window: Self.window, now: clock.now(), trigger: .scheduled)
            guard case .subscriptions(let entries) = try await source.collect(context: context) else {
                Issue.record("expected subscriptions"); return
            }
            let snapshot = UsageSnapshot(generatedAt: clock.now(), window: Self.window, windowSource: .fallback, subscriptions: entries)
            events += tracker.observe(snapshot: snapshot, configuration: config)
            clock.advance(300)
        }

        StubURLProtocol.register(key: "Bearer \(working)") { _ in (200, Data(usageResponseJSON.utf8)) }
        StubURLProtocol.register(key: "Bearer \(renewed)") { _ in (200, Data(usageResponseJSON.utf8)) }
        try await refresh(OAuthCredential(accessToken: working, expiresAt: far))
        StubURLProtocol.register(key: "Bearer \(working)") { _ in (401, Data("{\"token\":\"\(Self.sentinel)\"}".utf8)) }
        try await refresh(OAuthCredential(accessToken: working, expiresAt: far))   // rejected
        try await refresh(OAuthCredential(accessToken: renewed, expiresAt: far))   // working again
        try await refresh(nil)                                                     // not signed in
        try await refresh(OAuthCredential(accessToken: renewed, expiresAt: far))   // working again
        try await refresh(OAuthCredential(accessToken: expired, expiresAt: clock.now().addingTimeInterval(-30 * 3600)))

        #expect(Self.summary(events) == ["deliver rejected", "withdraw acc-claude", "deliver notSignedIn", "withdraw acc-claude",
                                         "deliver expired"])
        for text in Self.texts(events) {
            #expect(!text.contains(Self.sentinel), "\(text)")
        }
    }

    @Test func codexEventsCarryNoToken() async throws {
        let h = try CodexLimitsHarness("cred-no-token-codex")
        let working = "codex-working-\(Self.sentinel)", rejected = "codex-rejected-\(Self.sentinel)"
        let renewed = "codex-renewed-\(Self.sentinel)", expired = "codex-expired-\(Self.sentinel)"
        defer {
            h.cleanUp()
            for token in [working, rejected, renewed, expired] { StubURLProtocol.unregister(key: "Bearer \(token)") }
        }
        for token in [working, renewed, expired] {
            StubURLProtocol.register(key: "Bearer \(token)") { _ in (200, Data(codexUsageSampleJSON.utf8)) }
        }
        StubURLProtocol.register(key: "Bearer \(rejected)") { _ in (401, Data("{\"token\":\"\(Self.sentinel)\"}".utf8)) }
        let config = Configuration(accounts: [CodexLimitsHarness.account(home: h.home())])
        var tracker = CredentialAlertTracker(paths: Paths(home: h.root))
        var events: [CredentialAlertEvent] = []
        var offset: TimeInterval = 0

        func refresh(_ token: String?, expiresAt: Date? = nil) async throws {
            if let token {
                h.signIn(h.home(), token: token, accountId: "acct-\(Self.sentinel)", expiresAt: expiresAt)
            } else {
                h.reader.set(h.home(), .success(.missing(reason: CodexCredentialLookup.noPlanSignIn)))
            }
            let entries = try await h.collect(config, at: offset)
            let snapshot = UsageSnapshot(generatedAt: CodexLimitsHarness.start.addingTimeInterval(offset), window: Self.window,
                                         windowSource: .fallback, codexLimits: entries)
            events += tracker.observe(snapshot: snapshot, configuration: config)
            offset += 300
        }

        try await refresh(working)
        try await refresh(rejected)                 // rejected
        try await refresh(renewed)                  // working again
        try await refresh(nil)                      // not signed in
        try await refresh(renewed)                  // working again
        try await refresh(expired, expiresAt: CodexLimitsHarness.start.addingTimeInterval(-30 * 3600))

        #expect(Self.summary(events) == ["deliver rejected", "withdraw acc-codex", "deliver notSignedIn", "withdraw acc-codex",
                                         "deliver expired"])
        for text in Self.texts(events) {
            #expect(!text.contains(Self.sentinel), "\(text)")
            #expect(!text.contains("acct-"), "\(text)")
        }
    }
}
