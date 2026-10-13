import Foundation

/// Fetches the provider-reported limits for every subscription account
/// (FR-011). Keeps the last good status per account so a failure yields
/// `.stale` with the previous values (SC-007). Never logs or returns a token.
public actor SubscriptionSource: UsageSource {
    public static let sourceName = "subscription"
    public nonisolated let name = SubscriptionSource.sourceName

    private let credentialReader: CredentialReader
    private let client: UsageEndpointClient
    private let log: DiagnosticLog?
    private let clock: @Sendable () -> Date
    private var lastGood: [String: SubscriptionStatus] = [:]

    public init(credentialReader: CredentialReader, client: UsageEndpointClient, log: DiagnosticLog? = nil,
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.credentialReader = credentialReader
        self.client = client
        self.log = log
        self.clock = clock
    }

    public func collect(context: RefreshContext) async throws -> SourceOutput {
        let accounts = context.configuration.subscriptionAccounts
        let now = clock()
        var entries: [String: SubscriptionEntry] = [:]

        let results: [(String, SubscriptionEntry, String)] = await withTaskGroup(of: (String, SubscriptionEntry, String).self) { group in
            for account in accounts {
                guard let settings = account.kind.subscription else { continue }
                let previous = lastGood[account.id]
                group.addTask { [credentialReader, client] in
                    let (entry, note) = await Self.fetch(account: account, settings: settings, previous: previous,
                                                         reader: credentialReader, client: client, now: now)
                    return (account.id, entry, note)
                }
            }
            var collected: [(String, SubscriptionEntry, String)] = []
            for await r in group { collected.append(r) }
            return collected
        }

        for (id, entry, note) in results {
            entries[id] = entry
            if entry.state.isOk, let status = entry.status {
                lastGood[id] = status
            }
            log?.append(source: name, message: "\(id): \(note)")
        }
        // Forget accounts that disappeared from the configuration.
        lastGood = lastGood.filter { entries[$0.key] != nil }
        return .subscriptions(entries)
    }

    private static func fetch(account: Account, settings: SubscriptionSettings, previous: SubscriptionStatus?,
                              reader: CredentialReader, client: UsageEndpointClient, now: Date) async -> (SubscriptionEntry, String) {
        let credential: OAuthCredential?
        do {
            credential = try reader.read(configDirectory: settings.credentialDirectory)
        } catch {
            let message = "credential read failed: \(describe(error))"
            return (SubscriptionEntry(status: previous, state: .stale(lastGoodAt: previous?.fetchedAt, error: message)), message)
        }
        guard let credential else {
            return (SubscriptionEntry(status: nil, state: .notSignedIn), "not signed in (no credential for \(settings.credentialDirectory))")
        }
        if credential.isExpired(now: now) {
            return (SubscriptionEntry(status: previous, state: .credentialsExpired), "credentials expired at \(credential.expiresAt)")
        }
        do {
            var status = try await client.fetch(token: credential.accessToken)
            status.subscriptionType = credential.subscriptionType
            status.fetchedAt = now
            let five = status.fiveHour.map { "\(PercentFormatter.rounded($0.utilizationPercent))%" } ?? "n/a"
            let seven = status.sevenDay.map { "\(PercentFormatter.rounded($0.utilizationPercent))%" } ?? "n/a"
            return (SubscriptionEntry(status: status, state: .ok), "ok (5h \(five), 7d \(seven))")
        } catch {
            let message = describe(error)
            return (SubscriptionEntry(status: previous, state: .stale(lastGoodAt: previous?.fetchedAt, error: message)),
                    "fetch failed: \(message)" + (previous == nil ? "" : ", keeping values from \(previous!.fetchedAt)"))
        }
    }

    /// Error text that can never contain a credential: only our own error
    /// types and generic type names are used.
    private static func describe(_ error: Error) -> String {
        if let endpoint = error as? UsageEndpointError { return endpoint.description }
        return String(describing: error)
    }
}
