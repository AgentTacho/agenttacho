import Foundation
import Testing
@testable import UsageCore

/// Mapping per contracts/litellm-mapping.md (FR-006 to FR-013), against a
/// trimmed copy of the real price list. Never touches the network.
@Suite struct LiteLLMImporterTests {
    static let importedAt = isoDate("2026-10-13T15:00:00Z")

    private func fixture() throws -> Data {
        try Data(contentsOf: Fixtures.url("litellm/excerpt.json"))
    }

    private func batch(_ kind: ImportKind) throws -> PriceBatch {
        try LiteLLMImporter.batch(from: fixture(), kind: kind, origin: liteLLMURLString, importedAt: Self.importedAt)
    }

    private func entry(_ batch: PriceBatch, _ model: String) -> PriceEntry? {
        batch.entries.first { $0.model == model }
    }

    // MARK: Selection per kind

    @Test func anthropicSelectionExcludesVertexClaude() throws {
        let b = try batch(.anthropic)
        let models = Set(b.entries.map(\.model))
        #expect(models == ["claude-sonnet-5-5", "claude-opus-4-7", "claude-opus-5-5", "claude-haiku-5-5", "claude-test-dated",
                           "claude-test-nocache", "claude-test-variant"])
        #expect(!models.contains { $0.contains("vertex") })
        #expect(b.kind == .anthropic)
        #expect(b.origin == liteLLMURLString)
        #expect(b.importedAt == Self.importedAt)
    }

    @Test func openaiSelectionIncludesResponsesAndVertexModels() throws {
        let b = try batch(.openai)
        let models = Set(b.entries.map(\.model))
        #expect(models == ["gpt-5-codex", "gpt-6-sol", "gpt-5.6", "openai/gpt-oss-120b-maas", "openai/gpt-oss-20b-maas"])
        #expect(!models.contains("text-embedding-3-large"))
    }

    @Test func geminiSelectionStripsPrefixAndExcludesImageModels() throws {
        let b = try batch(.gemini)
        #expect(b.entries.map(\.model) == ["gemini-2.5-pro"])
        #expect(entry(b, "gemini-2.5-pro")?.cacheReadPerMTok == Decimal(string: "0.125"))
    }

    @Test func csvKindIsNotAProviderImport() throws {
        #expect(throws: PriceImportError.noUsableEntries(.csv)) { try batch(.csv) }
    }

    // MARK: Conversion (FR-008, SC-007)

    @Test func convertsToDollarsPerMillionTokensExactly() throws {
        let b = try batch(.anthropic)
        let opus = try #require(entry(b, "claude-opus-5-5"))
        #expect(opus.inputPerMTok == 4)
        #expect(opus.outputPerMTok == 20)
        #expect(opus.cacheWrite5mPerMTok == 5)
        #expect(opus.cacheWrite1hPerMTok == 8)
        #expect(opus.cacheReadPerMTok == Decimal(string: "0.2"))
        #expect(entry(b, "claude-sonnet-5-5")?.cacheReadPerMTok == Decimal(string: "0.1"))
        #expect(entry(b, "claude-haiku-5-5")?.cacheReadPerMTok == Decimal(string: "0.01"))
        #expect(entry(b, "claude-haiku-5-5")?.cacheWrite5mPerMTok == Decimal(string: "0.125"))
        #expect(entry(try batch(.openai), "openai/gpt-oss-20b-maas")?.cacheReadPerMTok == Decimal(string: "0.007"))
    }

    @Test func anthropicEntriesMatchBuiltInTableExceptKnownDiscrepancy() throws {
        let builtIn = try PriceTable.builtIn()
        for e in try batch(.anthropic).entries {
            guard let reference = builtIn.entry(exactly: e.model) else { continue }
            if e.model == "claude-sonnet-5-5" {
                #expect(e.cacheReadPerMTok != reference.cacheReadPerMTok)
            } else {
                #expect(e.samePrices(as: reference), "\(e.model)")
            }
        }
    }

    @Test func missingCacheFieldsTakeTheInputPrice() throws {
        let nocache = try #require(entry(try batch(.anthropic), "claude-test-nocache"))
        #expect(nocache.inputPerMTok == Decimal(string: "1.5"))
        #expect(nocache.cacheWrite5mPerMTok == Decimal(string: "1.5"))
        #expect(nocache.cacheWrite1hPerMTok == Decimal(string: "1.5"))
        #expect(nocache.cacheReadPerMTok == Decimal(string: "1.5"))
        let oss = try #require(entry(try batch(.openai), "openai/gpt-oss-120b-maas"))
        #expect(oss.inputPerMTok == Decimal(string: "0.09"))
        #expect(oss.outputPerMTok == Decimal(string: "0.36"))
        #expect(oss.cacheReadPerMTok == Decimal(string: "0.09"))
        let sol = try #require(entry(try batch(.openai), "gpt-6-sol"))
        #expect(sol.cacheWrite5mPerMTok == Decimal(string: "2.5"))
        #expect(sol.cacheWrite1hPerMTok == 2)
    }

    // MARK: Skipped entries (FR-009, FR-013)

    @Test func malformedAndIncompleteEntriesAreSkipped() throws {
        let models = Set(try batch(.anthropic).entries.map(\.model))
        for skipped in ["claude-test-malformed", "claude-test-no-output", "claude-test-not-object", "sample_spec", "claude-test-negative"] {
            #expect(!models.contains(skipped))
        }
    }

    // MARK: Variants (FR-011)

    @Test func datedVariantsMergeUnderTheCanonicalId() throws {
        let b = try batch(.anthropic)
        #expect(b.entries.filter { $0.model.hasPrefix("claude-opus-4-7") }.map(\.model) == ["claude-opus-4-7"])
        let dated = try #require(entry(b, "claude-test-dated"))
        #expect(dated.inputPerMTok == 2)
        #expect(dated.outputPerMTok == 10)
        let variant = try #require(entry(b, "claude-test-variant"))
        #expect(variant.inputPerMTok == 3)
        #expect(variant.outputPerMTok == 15)
        #expect(Set(b.entries.map(\.model)).count == b.entries.count)
    }

    // MARK: Errors

    @Test func noUsableEntriesForBodyWithoutMatches() {
        let body = Data(#"{"gpt-x": {"litellm_provider": "openai", "mode": "chat", "input_cost_per_token": 1e-6, "output_cost_per_token": 2e-6}}"#.utf8)
        #expect(throws: PriceImportError.noUsableEntries(.anthropic)) {
            try LiteLLMImporter.batch(from: body, kind: .anthropic, origin: "x", importedAt: Self.importedAt)
        }
    }

    @Test func arrayBodyIsNotJSONObject() {
        #expect(throws: PriceImportError.notJSON) {
            try LiteLLMImporter.batch(from: Data("[1, 2]".utf8), kind: .anthropic, origin: "x", importedAt: Self.importedAt)
        }
        #expect(throws: PriceImportError.notJSON) {
            try LiteLLMImporter.batch(from: Data("<html>".utf8), kind: .anthropic, origin: "x", importedAt: Self.importedAt)
        }
    }

    // MARK: Fetch (FR-012)

    private func stubbed(_ name: String, maxBytes: Int = 20 * 1024 * 1024,
                         handler: @escaping StubURLProtocol.Handler) -> (LiteLLMImporter, String) {
        let url = "https://stub.invalid/litellm/\(name)-\(UUID().uuidString).json"
        StubURLProtocol.register(key: url, handler: handler)
        return (LiteLLMImporter(session: StubURLProtocol.makeSession(), url: URL(string: url)!, maxBytes: maxBytes), url)
    }

    @Test func fetchReturnsBodyOn200() async throws {
        let body = try fixture()
        let (importer, key) = stubbed("ok") { _ in (200, body) }
        defer { StubURLProtocol.unregister(key: key) }
        #expect(try await importer.fetch() == body)
        let requests = StubURLProtocol.recordedRequests(key: key)
        #expect(requests.count == 1)
        #expect(requests.first?.httpMethod == "GET")
        #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func fetchMapsHTTPStatus() async throws {
        let (importer, key) = stubbed("404") { _ in (404, Data("not found".utf8)) }
        defer { StubURLProtocol.unregister(key: key) }
        await #expect(throws: PriceImportError.httpStatus(404)) { try await importer.fetch() }
    }

    @Test func fetchEnforcesSizeCap() async throws {
        let (importer, key) = stubbed("large", maxBytes: 100) { _ in (200, Data(repeating: 0x20, count: 1000)) }
        defer { StubURLProtocol.unregister(key: key) }
        await #expect(throws: PriceImportError.tooLarge) { try await importer.fetch() }
    }

    @Test func fetchMapsTimeout() async throws {
        let (importer, key) = stubbed("timeout") { _ in throw URLError(.timedOut) }
        defer { StubURLProtocol.unregister(key: key) }
        await #expect(throws: PriceImportError.timeout) { try await importer.fetch() }
    }

    @Test func fetchMapsTransportErrors() async throws {
        let (importer, key) = stubbed("offline") { _ in throw URLError(.notConnectedToInternet) }
        defer { StubURLProtocol.unregister(key: key) }
        do {
            _ = try await importer.fetch()
            Issue.record("expected an error")
        } catch let error as PriceImportError {
            guard case .network = error else {
                Issue.record("expected network, got \(error)")
                return
            }
        }
    }

    @Test func defaultsMatchTheContract() {
        #expect(LiteLLMImporter.defaultURL.absoluteString == liteLLMURLString)
        let config = LiteLLMImporter.priceListSession.configuration
        #expect(config.urlCache == nil)
        #expect(config.timeoutIntervalForResource == 30)
        #expect(config.timeoutIntervalForRequest == 30)
        #expect(config.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(LiteLLMImporter().maxBytes == 20 * 1024 * 1024)
        #expect(LiteLLMImporter().url == LiteLLMImporter.defaultURL)
    }

    // MARK: Rounding, non-numbers and malformed ids

    private func inlineBatch(_ json: String) throws -> PriceBatch {
        try LiteLLMImporter.batch(from: Data(json.utf8), kind: .anthropic, origin: liteLLMURLString, importedAt: Self.importedAt)
    }

    @Test func roundsToSixDecimalsAndTreatsNonNumbersAsMissing() throws {
        let b = try inlineBatch("""
        {
          "claude-round": {"litellm_provider": "anthropic", "mode": "chat", "input_cost_per_token": 1.2345678e-6,
                           "output_cost_per_token": 3.33333333e-6, "cache_read_input_token_cost": 4e-13,
                           "cache_creation_input_token_cost": null, "cache_creation_input_token_cost_above_1hr": true},
          "claude-negcache": {"litellm_provider": "anthropic", "mode": "chat", "input_cost_per_token": 1e-6,
                              "output_cost_per_token": 2e-6, "cache_read_input_token_cost": -1e-7}
        }
        """)
        #expect(b.entries.map(\.model) == ["claude-round"])
        let e = try #require(b.entries.first)
        #expect(e.inputPerMTok == Decimal(string: "1.234568"))
        #expect(e.outputPerMTok == Decimal(string: "3.333333"))
        #expect(e.cacheReadPerMTok == 0)
        #expect(e.cacheWrite5mPerMTok == e.inputPerMTok)
        #expect(e.cacheWrite1hPerMTok == e.inputPerMTok)
    }

    @Test func malformedModelIdsAreSkipped() throws {
        let entry = #"{"litellm_provider": "anthropic", "mode": "chat", "input_cost_per_token": 1e-6, "output_cost_per_token": 2e-6}"#
        let b = try inlineBatch("""
        {"claude-ok": \(entry), "=HYPERLINK(1)": \(entry), "@claude": \(entry), "-claude": \(entry),
         "claude bad": \(entry), "claude\\nline": \(entry), "\(String(repeating: "c", count: 201))": \(entry)}
        """)
        #expect(b.entries.map(\.model) == ["claude-ok"])
    }

    @Test func atDatedVariantsMergeLikeDashDatedOnes() throws {
        let b = try inlineBatch("""
        {
          "claude-at@20260101": {"litellm_provider": "anthropic", "mode": "chat", "input_cost_per_token": 1e-6, "output_cost_per_token": 2e-6},
          "claude-at@20260601": {"litellm_provider": "anthropic", "mode": "chat", "input_cost_per_token": 3e-6, "output_cost_per_token": 4e-6}
        }
        """)
        #expect(b.entries.map(\.model) == ["claude-at"])
        #expect(b.entries.first?.inputPerMTok == 3)
    }
}
