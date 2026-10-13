import Foundation
import Testing
@testable import UsageCore

/// CSV import per contracts/price-csv.md (FR-014 to FR-017b).
@Suite struct PriceCSVTests {
    static let importedAt = isoDate("2026-10-13T15:00:00Z")

    private func parse(_ text: String) throws -> ProposedImport {
        try PriceCSV.parse(text, origin: "prices.csv", importedAt: Self.importedAt)
    }

    private func entry(_ p: ProposedImport, _ model: String) -> PriceEntry? {
        p.batch.entries.first { $0.model == model }
    }

    @Test func commaSeparatedWithAllColumns() throws {
        let p = try parse("model,input,output,cache_write_5m,cache_write_1h,cache_read\nclaude-opus-5-5,4,20,5,8,0.2\n")
        #expect(p.batch.kind == .csv)
        #expect(p.batch.origin == "prices.csv")
        #expect(p.batch.importedAt == Self.importedAt)
        #expect(p.batch.entries == [PriceEntry(model: "claude-opus-5-5", inputPerMTok: 4, outputPerMTok: 20, cacheWrite5mPerMTok: 5,
                                               cacheWrite1hPerMTok: 8, cacheReadPerMTok: Decimal(string: "0.2")!)])
        #expect(p.skippedRows.isEmpty)
        #expect(p.derived.isEmpty)
    }

    @Test func semicolonWithDecimalComma() throws {
        let p = try parse("model;input;output\nclaude-test-model;2,50;10\n")
        let e = try #require(entry(p, "claude-test-model"))
        #expect(e.inputPerMTok == Decimal(string: "2.5"))
        #expect(e.outputPerMTok == 10)
    }

    @Test func quickstartScenarioFour() throws {
        let p = try parse("model;input;output\nclaude-test-model;2,50;10\n;1;1\n")
        let e = try #require(entry(p, "claude-test-model"))
        #expect(e.cacheWrite5mPerMTok == Decimal(string: "3.125"))
        #expect(e.cacheWrite1hPerMTok == 5)
        #expect(e.cacheReadPerMTok == Decimal(string: "0.25"))
        #expect(p.derived["claude-test-model"] == [.cacheWrite5m, .cacheWrite1h, .cacheRead])
        #expect(p.skippedRows == [SkippedRow(line: 3, reason: "missing model")])
    }

    @Test func quotedFieldsWithSeparatorAndEscapedQuotes() throws {
        let p = try parse("model,input,output\n\"model, with comma\",\"1\",2\n\"say \"\"hi\"\"\",3,4\n")
        #expect(entry(p, "model, with comma")?.inputPerMTok == 1)
        #expect(entry(p, "say \"hi\"")?.outputPerMTok == 4)
    }

    @Test func byteOrderMarkCRLFAndEmptyLines() throws {
        let p = try parse("\u{FEFF}model,input,output\r\n\r\nclaude-a,1,2\r\n\r\n")
        #expect(p.batch.entries.map(\.model) == ["claude-a"])
        #expect(p.skippedRows.isEmpty)
    }

    @Test func columnsAreCaseInsensitiveInAnyOrderAndUnknownOnesIgnored() throws {
        let p = try parse(" Output ,NOTE,Cache_Read,MODEL,Input\n20,hello,0.3,claude-x,4\n")
        let e = try #require(entry(p, "claude-x"))
        #expect(e.inputPerMTok == 4)
        #expect(e.outputPerMTok == 20)
        #expect(e.cacheReadPerMTok == Decimal(string: "0.3"))
        #expect(e.cacheWrite5mPerMTok == 5)
        #expect(p.derived["claude-x"] == [.cacheWrite5m, .cacheWrite1h])
    }

    @Test func emptyOptionalCellIsDerived() throws {
        let p = try parse("model,input,output,cache_write_5m,cache_write_1h,cache_read\nclaude-y,2,10,,4,\n")
        let e = try #require(entry(p, "claude-y"))
        #expect(e.cacheWrite5mPerMTok == Decimal(string: "2.5"))
        #expect(e.cacheWrite1hPerMTok == 4)
        #expect(e.cacheReadPerMTok == Decimal(string: "0.2"))
        #expect(p.derived["claude-y"] == [.cacheWrite5m, .cacheRead])
    }

    @Test func rowErrorsCarryLineNumbersAndReasons() throws {
        let text = """
        model,input,output
        claude-ok,1,2
        ,1,2
        claude-bad,abc,2
        claude-neg,1,-1
        claude-short,1
        claude-ok-2,3,4
        """
        let p = try parse(text)
        #expect(p.batch.entries.map(\.model) == ["claude-ok", "claude-ok-2"])
        #expect(p.skippedRows == [
            SkippedRow(line: 3, reason: "missing model"),
            SkippedRow(line: 4, reason: "unparsable number in input"),
            SkippedRow(line: 5, reason: "negative number in output"),
            SkippedRow(line: 6, reason: "expected 3 fields, found 2"),
        ])
    }

    @Test func numbersMustBeComplete() throws {
        let p = try parse("model,input,output\nclaude-a,12abc,2\nclaude-b,1.2.3,2\nclaude-c,1e-1,2\n")
        #expect(p.skippedRows.map(\.line) == [2, 3])
        #expect(entry(p, "claude-c")?.inputPerMTok == Decimal(string: "0.1"))
    }

    @Test func duplicateModelLastRowWins() throws {
        let p = try parse("model,input,output\nclaude-a,1,2\nclaude-b,1,1\nclaude-a-20260101,3,4\n")
        #expect(entry(p, "claude-a")?.inputPerMTok == 3)
        #expect(p.batch.entries.count == 2)
        #expect(p.skippedRows == [SkippedRow(line: 2, reason: "duplicate model")])
    }

    @Test func modelIdsAreCanonicalized() throws {
        let p = try parse("model,input,output\nclaude-opus-5-5@20251101,4,20\n")
        #expect(p.batch.entries.map(\.model) == ["claude-opus-5-5"])
    }

    @Test func fileErrors() {
        #expect(throws: PriceImportError.missingHeader) { try parse("") }
        #expect(throws: PriceImportError.missingHeader) { try parse("\u{FEFF}\n\n") }
        #expect(throws: PriceImportError.missingColumns(["input", "output"])) { try parse("model,price\nclaude-a,1\n") }
        #expect(throws: PriceImportError.missingColumns(["model", "input", "output"])) { try parse("claude-a,1,2\n") }
        #expect(throws: PriceImportError.noValidRows) { try parse("model,input,output\n,1,2\nclaude-a,x,1\n") }
        #expect(throws: PriceImportError.noValidRows) { try parse("model,input,output\n") }
    }
    // MARK: Export (FR-019, SC-005)

    @Test func exportFormat() {
        let table = PriceTable(entries: [
            PriceEntry(model: "claude-b", inputPerMTok: Decimal(string: "2.50")!, outputPerMTok: 10, cacheWrite5mPerMTok: Decimal(string: "3.125")!,
                       cacheWrite1hPerMTok: 5, cacheReadPerMTok: Decimal(string: "0.25")!),
            PriceEntry(model: "a, \"quoted\" model", inputPerMTok: 1, outputPerMTok: 2, cacheWrite5mPerMTok: Decimal(string: "0.000001")!,
                       cacheWrite1hPerMTok: 2, cacheReadPerMTok: Decimal(string: "0.1")!),
            PriceEntry(model: "claude-a", inputPerMTok: 1234, outputPerMTok: 20, cacheWrite5mPerMTok: 5, cacheWrite1hPerMTok: 8,
                       cacheReadPerMTok: Decimal(string: "0.2")!),
        ])
        let text = PriceCSV.export(table)
        #expect(text == """
        model,input,output,cache_write_5m,cache_write_1h,cache_read
        "a, ""quoted"" model",1,2,0.000001,2,0.1
        claude-a,1234,20,5,8,0.2
        claude-b,2.5,10,3.125,5,0.25

        """)
    }

    @Test func exportRoundTripReportsNoChanges() throws {
        let builtIn = try PriceTable.builtIn()
        let provider = makeBatch(.anthropic, [makeEntry("claude-opus-5-5", input: 7), makeEntry("claude-new-1", input: Decimal(string: "0.3")!)])
        let oldCSV = makeBatch(.csv, [makeEntry("claude-csv-only", input: 2)], origin: "old.csv")
        let imported = ImportedPrices.empty.replacing(provider).replacing(oldCSV)
        let overrides = [makeEntry("claude-sonnet-5-5", input: 9), makeEntry("claude-manual-1", input: 1)]
        let table = PriceTable.effective(builtIn: builtIn, imported: imported, overrides: overrides)

        let reimported = try PriceCSV.parse(PriceCSV.export(table), origin: "prices.csv", importedAt: Date())
        #expect(reimported.skippedRows.isEmpty)
        #expect(reimported.derived.isEmpty)
        #expect(reimported.batch.entries.count == table.entries.count)
        let diff = PriceDiff.compute(current: imported, proposed: reimported.batch, kind: .csv, builtIn: builtIn,
                                     overrides: overrides, usedModels: nil)
        #expect(diff.newModels.isEmpty)
        #expect(diff.changed.isEmpty)
        #expect(diff.removed.isEmpty)
        #expect(diff.isEmpty)
        #expect(diff.unchangedCount == table.entries.count)
    }

    @Test func lineNumbersAcrossQuotedLineBreaksBlankLinesAndCRLF() throws {
        let text = "model,input,output,cache_read\r\n\"multi\nline\",1,2,\r\n\r\nbad,x,2,\r\nmore,1,2,3,4\r\n"
            + "neg,1,2,-1\r\nabc,1,2,abc\r\nempty,,2,\r\nok,1,2,\r\n"
        let p = try PriceCSV.parse(text, origin: "prices.csv", importedAt: Date())
        #expect(p.batch.entries.map(\.model) == ["ok"])
        #expect(p.skippedRows == [
            SkippedRow(line: 2, reason: "invalid model id"),
            SkippedRow(line: 5, reason: "unparsable number in input"),
            SkippedRow(line: 6, reason: "expected 4 fields, found 5"),
            SkippedRow(line: 7, reason: "negative number in cache_read"),
            SkippedRow(line: 8, reason: "unparsable number in cache_read"),
            SkippedRow(line: 9, reason: "unparsable number in input"),
        ])
    }

    @Test func idIsTrimmedAfterCanonicalization() throws {
        let p = try PriceCSV.parse("model,input,output\nfoo -20250101,1,2\n", origin: "prices.csv", importedAt: Date())
        #expect(p.batch.entries.map(\.model) == ["foo"])
    }

    @Test func formulaLikeModelIdsAreSkipped() throws {
        let p = try PriceCSV.parse("model,input,output\n=HYPERLINK(1),1,2\n@x,1,2\nclaude-a,1,2\n", origin: "prices.csv", importedAt: Date())
        #expect(p.batch.entries.map(\.model) == ["claude-a"])
        #expect(p.skippedRows == [SkippedRow(line: 2, reason: "invalid model id"), SkippedRow(line: 3, reason: "invalid model id")])
    }

    @Test func quotedSemicolonHeaderWithDecimalComma() throws {
        let p = try PriceCSV.parse("\"model\";\"input\";\"output\"\nclaude-a;2,5;10\n", origin: "prices.csv", importedAt: Date())
        let e = try #require(p.batch.entries.first)
        #expect(e.inputPerMTok == Decimal(string: "2.5"))
        #expect(e.outputPerMTok == 10)
        #expect(p.derived["claude-a"] == [.cacheWrite5m, .cacheWrite1h, .cacheRead])
    }
}
