import Foundation
import Testing
@testable import UsageCore

/// spec 033 FR-006, FR-015, FR-019, SC-004: a Claude and a Codex refresh
/// whose answers carry sentinel grant and credit identifiers, with sentinel
/// tokens, leave no sentinel in the entries, the log, the expiry alerts or
/// the notice record.
@Suite struct ResetTicketNoTokenTests {
    static let tokenSentinel = "TOKEN-SENTINEL-033"
    static let idSentinel = "SERVICE-ID-SENTINEL-033"
    static let accountIdSentinel = "CHATGPT-ACCOUNT-SENTINEL-033"

    @Test func noSentinelLeavesTheSources() async throws {
        let root = try makeTempDirectory("tickets-no-token")
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = MutableClock(isoDate("2026-10-21T08:00:00Z"))
        let expiry = ISO8601DateFormatter().string(from: clock.now().addingTimeInterval(20 * 3600))
        let log = DiagnosticLog(fileURL: root.appendingPathComponent("usage.log"))
        let store = LastGoodStore(fileURL: root.appendingPathComponent("last-good.json"), initial: nil, log: nil)

        // Claude: a usage answer with a free-reset block.
        let claudeToken = "claude-\(UUID().uuidString)-\(Self.tokenSentinel)"
        StubURLProtocol.register(key: "Bearer \(claudeToken)") { _ in
            (200, Data("""
            { "five_hour": { "utilization": 8.0, "resets_at": "2026-10-21T10:00:00Z" },
              "seven_day": { "utilization": 50.0, "resets_at": "2026-10-24T10:00:00Z" },
              "cedar_ember": { "eligible": true, "grants": [
                { "id": "\(Self.idSentinel)", "usable_now": true, "resets_left": 1, "ends_at": "\(expiry)", "paused": false } ] } }
            """.utf8))
        }
        defer { StubURLProtocol.unregister(key: "Bearer \(claudeToken)") }
        let reader = FakeCredentialReader()
        reader.credentials["~/.claude"] = OAuthCredential(accessToken: claudeToken, expiresAt: Date(timeIntervalSince1970: 4_000_000_000))
        let claude = SubscriptionSource(credentialReader: reader,
                                        client: UsageEndpointClient(session: StubURLProtocol.makeSession(), clock: { clock.now() }),
                                        log: log, clock: { clock.now() }, store: store, paths: Paths(home: root))

        // Codex: plan limits, then a credit list.
        let codexToken = "codex-\(UUID().uuidString)-\(Self.tokenSentinel)"
        StubURLProtocol.register(key: "Bearer \(codexToken)") { request in
            if request.url?.path.contains("rate-limit-reset-credits") == true {
                return (200, Data("""
                { "available_count": 1, "credits": [
                  { "id": "\(Self.idSentinel)", "reset_type": "\(Self.idSentinel)", "status": "available", "expires_at": "\(expiry)",
                    "title": "\(Self.idSentinel)", "description": "\(Self.idSentinel)" } ] }
                """.utf8))
            }
            return (200, Data(codexUsageSampleJSON.utf8))
        }
        defer { StubURLProtocol.unregister(key: "Bearer \(codexToken)") }
        let codexReader = FakeCodexCredentialReader()
        let home = root.appendingPathComponent(".codex").path
        codexReader.set(home, .success(.found(CodexCredential(accessToken: codexToken, accountId: Self.accountIdSentinel, expiresAt: nil))))
        let codex = CodexLimitsSource(credentialReader: codexReader,
                                      client: CodexUsageClient(session: StubURLProtocol.makeSession(), clock: { clock.now() }),
                                      log: log, paths: Paths(home: root), clock: { clock.now() }, store: store)

        let configuration = Configuration(accounts: [
            Account(id: "acc-max", displayName: "Max",
                    kind: .subscription(SubscriptionSettings(credentialDirectory: "~/.claude", shownInBar: true, thresholds: []))),
            Account(id: "acc-codex", displayName: "Plus", harness: .codex,
                    kind: .codexSubscription(CodexSubscriptionSettings(codexHome: home, liveLimits: true))),
        ])
        let context = RefreshContext(configuration: configuration, window: DateInterval(start: clock.now(), duration: 1),
                                     now: clock.now(), trigger: .scheduled)
        guard case .subscriptions(let subscriptions) = try await claude.collect(context: context),
              case .codexLimits(let limits) = try await codex.collect(context: context) else {
            Issue.record("unexpected outputs")
            return
        }
        #expect(subscriptions["acc-max"]?.resetTickets.count == 1)
        #expect(limits["acc-codex"]?.resetTickets.count == 1)

        // A failing read is logged too.
        StubURLProtocol.register(key: "Bearer \(claudeToken)") { _ in (200, Data("{ \"cedar_ember\": [\"\(Self.idSentinel)\"] }".utf8)) }
        _ = try await claude.collect(context: context)

        let noticeStore = InMemoryResetTicketNoticeStore()
        var tracker = ResetTicketExpiryTracker(store: noticeStore)
        let snapshot = UsageSnapshot(generatedAt: clock.now(), window: context.window, windowSource: .fallback,
                                     subscriptions: subscriptions, codexLimits: limits)
        let events = tracker.observe(snapshot: snapshot, configuration: configuration, now: clock.now())
        #expect(events.count == 2)
        let times = TimeText(format: .absolute, now: clock.now(), calendar: Calendar(identifier: .gregorian), locale: Locale(identifier: "en_US_POSIX"))
        var texts = [String(describing: subscriptions), String(describing: limits), String(describing: noticeStore.load())]
        for event in events {
            guard case .deliver(let alert) = event else { continue }
            texts += [alert.title, alert.body(times: times), alert.identifier, alert.logMessage(suppressed: false), String(describing: alert)]
        }
        texts.append((try? String(contentsOf: log.fileURL, encoding: .utf8)) ?? "")
        texts.append((try? String(contentsOf: root.appendingPathComponent("last-good.json"), encoding: .utf8)) ?? "")
        #expect(texts.last?.isEmpty == false)
        for text in texts {
            #expect(!text.contains(Self.tokenSentinel))
            #expect(!text.contains(Self.idSentinel))
            #expect(!text.contains(Self.accountIdSentinel))
        }
    }
}
