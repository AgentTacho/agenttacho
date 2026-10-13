import Foundation

/// Price CSV import and export (FR-014 to FR-019, contracts/price-csv.md).
public enum PriceCSV {
    /// Export header, also the column names the import reads.
    public static let header = ["model"] + PriceField.allCases.map(\.csvColumn)

    /// Factors for cache prices derived from the input price (FR-015).
    static let derivationFactors: [PriceField: Decimal] = [
        .cacheWrite5m: Decimal(string: "1.25")!,
        .cacheWrite1h: 2,
        .cacheRead: Decimal(string: "0.1")!,
    ]

    private static let requiredColumns = ["model", "input", "output"]
    private static let numberPattern = try! Regex("^[+-]?([0-9]+(\\.[0-9]*)?|\\.[0-9]+)([eE][+-]?[0-9]+)?$")
    private static let posix = Locale(identifier: "en_US_POSIX")

    // MARK: Export

    /// The effective table as CSV in the import format: header, comma
    /// separator, dot decimals without trailing zeros, one row per model
    /// sorted by id, trailing newline (FR-019). An unchanged export
    /// re-imports without new, changed, removed or skipped rows (SC-005).
    public static func export(_ table: PriceTable) -> String {
        var lines = [header.joined(separator: ",")]
        for entry in table.entries.sorted(by: { $0.model < $1.model }) {
            let values = PriceField.allCases.map { format(entry[keyPath: $0.keyPath]) }
            lines.append(([quote(entry.model)] + values).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Plain decimal notation, locale independent, no trailing zeros.
    static func format(_ value: Decimal) -> String {
        var copy = value
        var normalized = Decimal()
        NSDecimalRound(&normalized, &copy, 12, .plain)
        return normalized.description
    }

    /// Quotes a field only when it contains a comma, quote or line break.
    static func quote(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: Import

    /// Reads a CSV file into a proposed import. Invalid rows are skipped and
    /// reported with their line number (FR-017); file errors throw
    /// `missingHeader`, `missingColumns` or `noValidRows` (FR-017b, FR-024).
    public static func parse(_ text: String, origin: String, importedAt: Date) throws -> ProposedImport {
        var scalars = Array(text.unicodeScalars)
        if scalars.first == "\u{FEFF}" { scalars.removeFirst() }
        let separator = detectSeparator(scalars)
        let records = splitRecords(scalars, separator: separator)

        guard let headerRecord = records.first else { throw PriceImportError.missingHeader }
        var columns: [String: Int] = [:]
        for (index, name) in headerRecord.fields.enumerated() {
            let key = name.lowercased()
            if columns[key] == nil { columns[key] = index }
        }
        let missing = requiredColumns.filter { columns[$0] == nil }
        guard missing.isEmpty else { throw PriceImportError.missingColumns(missing) }
        let fieldCount = headerRecord.fields.count

        var skipped: [SkippedRow] = []
        var byModel: [String: (line: Int, entry: PriceEntry, derived: Set<PriceField>)] = [:]
        for record in records.dropFirst() {
            guard record.fields.count == fieldCount else {
                skipped.append(SkippedRow(line: record.line, reason: "expected \(fieldCount) fields, found \(record.fields.count)"))
                continue
            }
            // Trimmed again after canonicalization: `foo -20250101` becomes
            // `foo`, as it would when an export of it is read back.
            let model = PriceTable.canonicalModel(record.fields[columns["model"]!]).trimmingCharacters(in: .whitespaces)
            guard !model.isEmpty else {
                skipped.append(SkippedRow(line: record.line, reason: "missing model"))
                continue
            }
            guard PriceTable.isAcceptableImportedModelId(model, allowingSpaces: true) else {
                skipped.append(SkippedRow(line: record.line, reason: "invalid model id"))
                continue
            }
            var entry = PriceEntry(model: model, inputPerMTok: 0, outputPerMTok: 0, cacheWrite5mPerMTok: 0, cacheWrite1hPerMTok: 0,
                                   cacheReadPerMTok: 0)
            var derived = Set<PriceField>()
            var problem: String?
            for field in PriceField.allCases {
                let cell = columns[field.csvColumn].map { record.fields[$0] } ?? ""
                // A missing or empty cache cell is derived from input (FR-015);
                // an empty input or output cell is an error.
                if cell.isEmpty {
                    if derivationFactors[field] != nil {
                        derived.insert(field)
                        continue
                    }
                    problem = "unparsable number in \(field.csvColumn)"
                    break
                }
                guard let value = number(cell, separator: separator) else {
                    problem = "unparsable number in \(field.csvColumn)"
                    break
                }
                guard value >= 0 else {
                    problem = "negative number in \(field.csvColumn)"
                    break
                }
                entry[keyPath: field.keyPath] = value
            }
            if let problem {
                skipped.append(SkippedRow(line: record.line, reason: problem))
                continue
            }
            for field in derived {
                entry[keyPath: field.keyPath] = entry.inputPerMTok * derivationFactors[field]!
            }
            // FR-017a: the last row wins, earlier rows are reported.
            if let earlier = byModel[model] {
                skipped.append(SkippedRow(line: earlier.line, reason: "duplicate model"))
            }
            byModel[model] = (record.line, entry, derived)
        }

        guard !byModel.isEmpty else { throw PriceImportError.noValidRows }
        let models = byModel.keys.sorted()
        let batch = PriceBatch(kind: .csv, origin: origin, importedAt: importedAt, entries: models.map { byModel[$0]!.entry })
        var derivedByModel: [String: Set<PriceField>] = [:]
        for model in models where !byModel[model]!.derived.isEmpty {
            derivedByModel[model] = byModel[model]!.derived
        }
        return ProposedImport(batch: batch, skippedRows: skipped.sorted { $0.line < $1.line }, derived: derivedByModel)
    }

    /// Semicolon when the first line has a `;` and no `,` outside quotes,
    /// otherwise comma (FR-016).
    private static func detectSeparator(_ scalars: [Unicode.Scalar]) -> Unicode.Scalar {
        var inQuotes = false
        var semicolons = 0
        var commas = 0
        var seenContent = false
        for c in scalars {
            if c == "\"" { inQuotes.toggle(); seenContent = true; continue }
            if inQuotes { continue }
            if c == "\n" || c == "\r" {
                if seenContent { break }
                continue
            }
            if c == ";" { semicolons += 1 }
            if c == "," { commas += 1 }
            if !CharacterSet.whitespaces.contains(c) { seenContent = true }
        }
        return semicolons > 0 && commas == 0 ? ";" : ","
    }

    private struct Record {
        let line: Int
        let fields: [String]
    }

    /// Splits into records on line breaks outside double quotes; `""` inside
    /// quotes is a literal quote. Fields are trimmed; empty lines are dropped.
    /// `line` is the 1-based line on which the record starts.
    private static func splitRecords(_ scalars: [Unicode.Scalar], separator: Unicode.Scalar) -> [Record] {
        var records: [Record] = []
        var fields: [String] = []
        var current = String.UnicodeScalarView()
        var inQuotes = false
        var quoted = false
        var line = 1
        var recordLine = 1

        func finishField() {
            fields.append(String(current).trimmingCharacters(in: .whitespaces))
            current = String.UnicodeScalarView()
        }
        func finishRecord() {
            finishField()
            if !(fields.count == 1 && fields[0].isEmpty && !quoted) {
                records.append(Record(line: recordLine, fields: fields))
            }
            fields = []
            quoted = false
        }

        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            let next: Unicode.Scalar? = i + 1 < scalars.count ? scalars[i + 1] : nil
            if inQuotes {
                if c == "\"" {
                    if next == "\"" {
                        current.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    if c == "\n" || (c == "\r" && next != "\n") { line += 1 }
                    current.append(c)
                }
            } else if c == "\"" {
                inQuotes = true
                quoted = true
            } else if c == separator {
                finishField()
            } else if c == "\r" && next == "\n" {
                // Handled by the following "\n".
            } else if c == "\n" || c == "\r" {
                finishRecord()
                line += 1
                recordLine = line
            } else {
                current.append(c)
            }
            i += 1
        }
        if !current.isEmpty || !fields.isEmpty || quoted {
            finishRecord()
        }
        return records
    }

    /// Dot decimals; with a semicolon separator a single decimal comma is
    /// accepted as well (`2,50`).
    private static func number(_ cell: String, separator: Unicode.Scalar) -> Decimal? {
        var text = cell
        if separator == ";", !text.contains("."), text.filter({ $0 == "," }).count == 1 {
            text = text.replacingOccurrences(of: ",", with: ".")
        }
        guard (try? numberPattern.wholeMatch(in: text)) != nil else { return nil }
        return Decimal(string: text, locale: posix)
    }
}
