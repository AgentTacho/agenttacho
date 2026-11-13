import Foundation

/// One usage-bearing line of Claude Code's Auto-mode decision log (spec 045
/// data-model "ClassifierRow", FR-004, FR-008, FR-009).
public struct ClassifierRow: Equatable, Sendable {
    /// `<canonical log path>#<byte offset of the line start>` (FR-008a).
    public var id: String
    /// From `ts`, epoch milliseconds.
    public var timestamp: Date
    /// `classifierModel` without a trailing context marker such as `[1m]`
    /// (FR-009).
    public var model: String
    /// `inputTokens`, absent counts as zero (FR-008).
    public var inputTokens: Int
    /// `cacheReadInputTokens`.
    public var cacheReadTokens: Int
    /// `cacheCreationInputTokens`, counted as the 5-minute tier (FR-008).
    public var cacheWrite5mTokens: Int
    /// `outputTokens`.
    public var outputTokens: Int

    public init(id: String, timestamp: Date, model: String, inputTokens: Int, cacheReadTokens: Int,
                cacheWrite5mTokens: Int, outputTokens: Int) {
        self.id = id
        self.timestamp = timestamp
        self.model = model
        self.inputTokens = inputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWrite5mTokens = cacheWrite5mTokens
        self.outputTokens = outputTokens
    }
}

/// What one decision log line is (spec 045 data-model
/// "ClassifierLineResult", FR-013).
public enum ClassifierLineResult: Equatable, Sendable {
    case row(ClassifierRow)
    /// A valid line with no counter above zero: a decision made without a
    /// classifier call.
    case withoutUsage
    /// Not JSON, no usable `ts`, no `classifierModel`, or an invalid counter.
    case malformed
}

/// Parses one decision log line (spec 045 FR-004, FR-009, FR-015, research
/// R3, R7). Only `ts`, `classifierModel` and the four token counters are
/// decoded; every other field, such as the tool name, the decision, its
/// reason and `costUSD`, is skipped by the decoder and never kept.
public enum ClassifierRowParser {
    private static let modelMarker = Data("\"classifierModel\"".utf8)
    private static let decoder = JSONDecoder()
    /// The largest counter a row may carry, 2^32 tokens, far above any
    /// model's context. A larger one makes the line malformed (FR-004), so a
    /// corrupt or hostile log in a working directory cannot overflow the
    /// totals' sums and crash every refresh (US4): even 120,000 rows at the
    /// limit stay far below `Int.max`.
    public static let maximumCounter = 1 << 32
    /// The longest model name a row may carry; a longer one, or one with
    /// spaces or control characters, makes the line malformed, so a crafted
    /// log cannot add arbitrary names to the totals (review finding of
    /// 2026-11-13).
    public static let maximumModelLength = 128

    /// A counter as found in the line: absent, a valid count, or invalid
    /// (negative, fractional, not a number). Absent and invalid differ, so
    /// a row without usage is told apart from a malformed one (research R7).
    enum Counter: Equatable {
        case absent
        case value(Int)
        case invalid
    }

    /// The only fields decoded from a line (FR-015).
    struct Fields: Decodable {
        enum CodingKeys: String, CodingKey, CaseIterable {
            case ts, classifierModel, inputTokens, cacheReadInputTokens, cacheCreationInputTokens, outputTokens
        }

        var ts: Double?
        var classifierModel: String?
        var inputTokens: Counter
        var cacheReadInputTokens: Counter
        var cacheCreationInputTokens: Counter
        var outputTokens: Counter

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            ts = try? container.decodeIfPresent(Double.self, forKey: .ts)
            classifierModel = try? container.decodeIfPresent(String.self, forKey: .classifierModel)
            func counter(_ key: CodingKeys) -> Counter {
                // A present counter must be a non-negative integer up to
                // the limit; `null` is present and invalid (FR-004).
                guard container.contains(key) else { return .absent }
                guard let value = try? container.decode(Int.self, forKey: key), value >= 0,
                      value <= ClassifierRowParser.maximumCounter else { return .invalid }
                return .value(value)
            }
            inputTokens = counter(.inputTokens)
            cacheReadInputTokens = counter(.cacheReadInputTokens)
            cacheCreationInputTokens = counter(.cacheCreationInputTokens)
            outputTokens = counter(.outputTokens)
        }
    }

    /// The JSON field names the parser reads, for the FR-015 test.
    static var decodedFieldNames: [String] { Fields.CodingKeys.allCases.map(\.rawValue) }

    /// `offset` is the byte offset of the line start in the log at
    /// `logPath`, the canonical path; together they form the row's id
    /// (FR-008a).
    public static func parse(line: Data, offset: Int, logPath: String) -> ClassifierLineResult {
        // A line without the model field cannot qualify: skip decoding it.
        guard line.range(of: modelMarker) != nil,
              let fields = try? decoder.decode(Fields.self, from: line),
              let ts = fields.ts, ts.isFinite,
              let rawModel = fields.classifierModel else {
            return .malformed
        }
        let model = normalizedModel(rawModel)
        guard !model.isEmpty, model.utf8.count <= maximumModelLength, PriceTable.isAcceptableImportedModelId(model) else {
            return .malformed
        }
        let counters = [fields.inputTokens, fields.cacheReadInputTokens, fields.cacheCreationInputTokens, fields.outputTokens]
        guard !counters.contains(.invalid) else { return .malformed }
        func count(_ counter: Counter) -> Int {
            if case .value(let value) = counter { return value }
            return 0
        }
        let row = ClassifierRow(id: logPath + "#" + String(offset), timestamp: Date(timeIntervalSince1970: ts / 1000),
                                model: model, inputTokens: count(fields.inputTokens),
                                cacheReadTokens: count(fields.cacheReadInputTokens),
                                cacheWrite5mTokens: count(fields.cacheCreationInputTokens),
                                outputTokens: count(fields.outputTokens))
        guard row.inputTokens > 0 || row.cacheReadTokens > 0 || row.cacheWrite5mTokens > 0 || row.outputTokens > 0 else {
            return .withoutUsage
        }
        return .row(row)
    }

    /// Removes one trailing Claude Code context marker in square brackets,
    /// such as `[1m]`, so classifier rows line up with the session's main
    /// records (FR-009, research R3).
    static func normalizedModel(_ model: String) -> String {
        guard model.hasSuffix("]"), let open = model.lastIndex(of: "[") else { return model }
        return String(model[..<open])
    }
}
