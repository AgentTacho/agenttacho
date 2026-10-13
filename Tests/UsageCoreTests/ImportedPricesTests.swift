import Foundation
import Testing
@testable import UsageCore

let liteLLMURLString = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"

func makeEntry(_ model: String, input: Decimal = 1, output: Decimal = 5, cw5m: Decimal? = nil, cw1h: Decimal? = nil,
               cr: Decimal? = nil) -> PriceEntry {
    PriceEntry(model: model, inputPerMTok: input, outputPerMTok: output,
               cacheWrite5mPerMTok: cw5m ?? input * Decimal(string: "1.25")!, cacheWrite1hPerMTok: cw1h ?? input * 2,
               cacheReadPerMTok: cr ?? input / 10)
}

func makeBatch(_ kind: ImportKind, _ entries: [PriceEntry], origin: String? = nil,
               at date: String = "2026-10-13T15:00:00Z") -> PriceBatch {
    PriceBatch(kind: kind, origin: origin ?? (kind == .csv ? "prices.csv" : liteLLMURLString),
               importedAt: isoDate(date), entries: entries)
}

@Suite struct ImportedPricesTests {
    static let contractJSON = """
    {
      "batches" : [
        {
          "entries" : [
            {
              "cacheReadPerMTok" : 0.2,
              "cacheWrite1hPerMTok" : 8,
              "cacheWrite5mPerMTok" : 5,
              "inputPerMTok" : 4,
              "model" : "claude-opus-5-5",
              "outputPerMTok" : 20
            }
          ],
          "importedAt" : "2026-10-13T15:00:00Z",
          "kind" : "anthropic",
          "origin" : "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
        }
      ],
      "version" : 1
    }
    """

    @Test func decodesContractExampleAndEncodesItBack() throws {
        let decoded = try JSONDecoder().decode(ImportedPrices.self, from: Data(Self.contractJSON.utf8))
        #expect(decoded.version == 1)
        #expect(decoded.batches.count == 1)
        let batch = try #require(decoded.batch(for: .anthropic))
        #expect(batch.kind == .anthropic)
        #expect(batch.importedAt == isoDate("2026-10-13T15:00:00Z"))
        #expect(batch.entries.count == 1)
        #expect(batch.entries[0].model == "claude-opus-5-5")
        #expect(batch.entries[0].cacheReadPerMTok == Decimal(string: "0.2"))
        #expect(batch.provenance == ImportProvenance(kind: .anthropic, origin: batch.origin, importedAt: batch.importedAt))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let text = String(decoding: try encoder.encode(decoded), as: UTF8.self)
        #expect(text.contains("\"importedAt\" : \"2026-10-13T15:00:00Z\""))
        #expect(text.contains("\"kind\" : \"anthropic\""))
        let again = try JSONDecoder().decode(ImportedPrices.self, from: Data(text.utf8))
        #expect(again == decoded)
    }

    @Test func replacingReplacesOnlyTheSameKind() {
        let anthropic = makeBatch(.anthropic, [makeEntry("claude-a")])
        let csv = makeBatch(.csv, [makeEntry("claude-b")])
        let newer = makeBatch(.anthropic, [makeEntry("claude-c")], at: "2026-10-14T10:00:00Z")
        let prices = ImportedPrices.empty.replacing(anthropic).replacing(csv).replacing(newer)
        #expect(prices.batches.count == 2)
        #expect(prices.batch(for: .anthropic)?.entries.map(\.model) == ["claude-c"])
        #expect(prices.batch(for: .csv)?.entries.map(\.model) == ["claude-b"])
        #expect(prices.batch(for: .openai) == nil)
    }

    @Test func removingDropsOnlyThatKind() {
        let prices = ImportedPrices.empty
            .replacing(makeBatch(.anthropic, [makeEntry("claude-a")]))
            .replacing(makeBatch(.openai, [makeEntry("gpt-x")]))
            .removing(.anthropic)
        #expect(prices.batch(for: .anthropic) == nil)
        #expect(prices.batch(for: .openai) != nil)
        #expect(prices.removing(.gemini) == prices)
    }

    @Test func negativePriceIsInvalidOnLoad() throws {
        let dir = try makeTempDirectory("imported-negative")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("imported-prices.json")
        try Data(Self.contractJSON.replacingOccurrences(of: "\"inputPerMTok\" : 4", with: "\"inputPerMTok\" : -4").utf8).write(to: file)
        let store = ImportedPriceStore(fileURL: file)
        let loaded = store.load()
        #expect(loaded == .empty)
        #expect(store.current == .empty)
        #expect(store.loadError != nil)
    }

    @Test func missingFileMeansNoImportsAndNoError() throws {
        let dir = try makeTempDirectory("imported-missing")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ImportedPriceStore(fileURL: dir.appendingPathComponent("imported-prices.json"))
        #expect(store.load() == .empty)
        #expect(store.loadError == nil)
    }

    @Test func damagedFileIsIgnoredAndLeftInPlace() throws {
        let dir = try makeTempDirectory("imported-damaged")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("imported-prices.json")
        try Data("{".utf8).write(to: file)
        let store = ImportedPriceStore(fileURL: file)
        #expect(store.load() == .empty)
        #expect(store.loadError != nil)
        #expect(try String(contentsOf: file, encoding: .utf8) == "{")

        // The next applied import writes a file holding only that batch.
        let batch = makeBatch(.csv, [makeEntry("claude-x")])
        try store.save(store.current.replacing(batch))
        #expect(store.loadError == nil)
        let fresh = ImportedPriceStore(fileURL: file)
        let reloaded = fresh.load()
        #expect(fresh.loadError == nil)
        #expect(reloaded.batches.count == 1)
        #expect(reloaded.batch(for: .csv)?.entries.map(\.model) == ["claude-x"])
    }

    @Test func twoBatchesOfOneKindAreInvalid() throws {
        let dir = try makeTempDirectory("imported-dup")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("imported-prices.json")
        let one = makeBatch(.anthropic, [makeEntry("claude-a")])
        let two = makeBatch(.anthropic, [makeEntry("claude-b")])
        let encoder = JSONEncoder()
        try encoder.encode(ImportedPrices(version: 1, batches: [one, two])).write(to: file)
        let store = ImportedPriceStore(fileURL: file)
        #expect(store.load() == .empty)
        #expect(store.loadError != nil)
    }

    @Test func saveWritesAtomicallyAndRoundTrips() throws {
        let dir = try makeTempDirectory("imported-save")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("sub/imported-prices.json")
        let store = ImportedPriceStore(fileURL: file)
        let prices = ImportedPrices.empty
            .replacing(makeBatch(.anthropic, [makeEntry("claude-a", input: Decimal(string: "0.3")!)]))
            .replacing(makeBatch(.csv, [makeEntry("claude-b")], at: "2026-10-14T08:30:00Z"))
        try store.save(prices)
        #expect(store.current == prices)
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("\"version\" : 1"))
        let fresh = ImportedPriceStore(fileURL: file)
        #expect(fresh.load() == prices)
        #expect(fresh.loadError == nil)
        // No temporary files left behind next to the target.
        let names = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
        #expect(names == ["imported-prices.json"])
    }

    @Test func failedSaveKeepsCurrentAndFile() throws {
        let dir = try makeTempDirectory("imported-readonly")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }
        let file = dir.appendingPathComponent("imported-prices.json")
        let store = ImportedPriceStore(fileURL: file)
        let first = ImportedPrices.empty.replacing(makeBatch(.anthropic, [makeEntry("claude-a")]))
        try store.save(first)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        let second = first.replacing(makeBatch(.csv, [makeEntry("claude-b")]))
        #expect(throws: (any Error).self) { try store.save(second) }
        #expect(store.current == first)
        let fresh = ImportedPriceStore(fileURL: file)
        #expect(fresh.load() == first)
    }

    @Test func saveOfAnInvalidValueThrowsAndKeepsCurrentAndFile() throws {
        let dir = try makeTempDirectory("imported-invalid-save")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("imported-prices.json")
        let store = ImportedPriceStore(fileURL: file)
        let first = ImportedPrices.empty.replacing(makeBatch(.anthropic, [makeEntry("claude-a")]))
        try store.save(first)
        let before = try Data(contentsOf: file)
        let invalid = ImportedPrices.empty.replacing(makeBatch(.csv, [makeEntry("claude-a", input: -1)]))
        #expect(throws: ImportedPrices.InvalidFile.self) { try store.save(invalid) }
        #expect(store.current == first)
        #expect(try Data(contentsOf: file) == before)
    }

    @Test func unsupportedVersionAndContractViolationsAreInvalidOnLoad() throws {
        let dir = try makeTempDirectory("imported-invalid-load")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("imported-prices.json")
        let cases: [ImportedPrices] = [
            ImportedPrices(version: 2, batches: []),
            ImportedPrices.empty.replacing(makeBatch(.csv, [makeEntry("claude-a-20260101")])),
            ImportedPrices.empty.replacing(makeBatch(.csv, [makeEntry("claude-a"), makeEntry("claude-a", input: 2)])),
            ImportedPrices.empty.replacing(makeBatch(.csv, [makeEntry("claude-a")], origin: "")),
        ]
        for value in cases {
            // The encoder does not validate, so each broken value reaches the file.
            try JSONEncoder().encode(value).write(to: file)
            let store = ImportedPriceStore(fileURL: file)
            #expect(store.load() == .empty)
            #expect(store.loadError != nil)
        }
    }
}
