import Foundation

/// Turns one JSONL line of a Claude Code session log into a `RawUsageRecord`
/// (contracts/external-sources.md section 2). Tolerant: anything that is not
/// a complete assistant record with usage yields nil.
public struct SessionRecordParser: Sendable {
    public init() {}

    public func parse(line: String) -> RawUsageRecord? {
        parse(data: Data(line.utf8))
    }

    private static let assistantMarkers = [Data("\"type\":\"assistant\"".utf8), Data("\"type\": \"assistant\"".utf8)]

    /// Byte-level entry point used by the index: the pre-filter runs on the
    /// raw bytes so non-assistant lines are never decoded or converted.
    public func parse(data: Data) -> RawUsageRecord? {
        // Cheap pre-filter: skip user, system, attachment and other record types
        // without decoding them.
        guard Self.assistantMarkers.contains(where: { data.range(of: $0) != nil }) else { return nil }
        guard let envelope = try? Self.decoder.decode(Envelope.self, from: data),
              envelope.type == "assistant",
              let message = envelope.message,
              let usage = message.usage,
              let timestampText = envelope.timestamp,
              let timestamp = Self.parseDate(timestampText) else {
            return nil
        }
        let requestId = envelope.requestId ?? ""
        let messageId = message.id ?? ""
        guard !messageId.isEmpty || !requestId.isEmpty else { return nil }

        let write5m: Int
        let write1h: Int
        if let split = usage.cache_creation, split.ephemeral_5m_input_tokens != nil || split.ephemeral_1h_input_tokens != nil {
            write5m = split.ephemeral_5m_input_tokens ?? 0
            write1h = split.ephemeral_1h_input_tokens ?? 0
        } else {
            write5m = usage.cache_creation_input_tokens ?? 0
            write1h = 0
        }
        let record = RawUsageRecord(messageId: messageId,
                                    timestamp: timestamp,
                                    model: message.model ?? "",
                                    requestId: requestId,
                                    inputTokens: usage.input_tokens ?? 0,
                                    outputTokens: usage.output_tokens ?? 0,
                                    cacheWrite5mTokens: write5m,
                                    cacheWrite1hTokens: write1h,
                                    cacheReadTokens: usage.cache_read_input_tokens ?? 0)
        // Claude Code writes placeholder assistant records for API errors
        // (model "<synthetic>", all counts zero). They carry no usage, so they
        // must not surface as unpriced models or Unassigned rows.
        guard record.inputTokens + record.outputTokens + record.cacheWrite5mTokens
                + record.cacheWrite1hTokens + record.cacheReadTokens > 0 else { return nil }
        return record
    }

    /// Several records share one `message.id` (one per content block) with
    /// cumulative usage; the last one wins. Falls back to `requestId` when the
    /// message id is empty. Order of first appearance is preserved.
    public static func dedupe(_ records: [RawUsageRecord]) -> [RawUsageRecord] {
        var index: [String: Int] = [:]
        var result: [RawUsageRecord] = []
        for record in records {
            let key = record.messageId.isEmpty ? "req:" + record.requestId : "msg:" + record.messageId
            if let i = index[key] {
                result[i] = record
            } else {
                index[key] = result.count
                result.append(record)
            }
        }
        return result
    }

    // MARK: Decoding

    private static let decoder = JSONDecoder()

    private struct Envelope: Decodable {
        let type: String?
        let timestamp: String?
        let requestId: String?
        let message: Message?
    }

    private struct Message: Decodable {
        let id: String?
        let model: String?
        let usage: Usage?
    }

    private struct Usage: Decodable {
        let input_tokens: Int?
        let output_tokens: Int?
        let cache_creation_input_tokens: Int?
        let cache_read_input_tokens: Int?
        let cache_creation: CacheCreation?
    }

    private struct CacheCreation: Decodable {
        let ephemeral_5m_input_tokens: Int?
        let ephemeral_1h_input_tokens: Int?
    }

    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDate(_ text: String) -> Date? {
        fractional.date(from: text) ?? plain.date(from: text)
    }
}
