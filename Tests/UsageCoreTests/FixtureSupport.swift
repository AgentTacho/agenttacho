import Foundation
import Testing
@testable import UsageCore

enum Fixtures {
    static func url(_ name: String) throws -> URL {
        let parts = name.split(separator: "/").map(String.init)
        let file = parts.last!
        let subdirectory = (["Fixtures"] + parts.dropLast()).joined(separator: "/")
        let base = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        return try #require(Bundle.module.url(forResource: base, withExtension: ext, subdirectory: subdirectory),
                            "missing fixture \(name)")
    }

    static func lines(_ name: String) throws -> [String] {
        let data = try Data(contentsOf: url(name))
        return String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    /// Copies a fixture into `<root>/projects/<relativePath>`.
    @discardableResult
    static func install(_ name: String, into root: URL, as relativePath: String) throws -> URL {
        let target = root.appendingPathComponent("projects").appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: url(name), to: target)
        return target
    }
}

func isoDate(_ text: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: text) { return d }
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: text)!
}

func makeRaw(id: String = "msg_1", requestId: String = "req_vrtx_1", model: String = "claude-opus-5-5",
             timestamp: Date = isoDate("2026-10-12T10:00:00Z"),
             input: Int = 0, output: Int = 0, cw5m: Int = 0, cw1h: Int = 0, cr: Int = 0, cwd: String? = nil) -> RawUsageRecord {
    RawUsageRecord(messageId: id, timestamp: timestamp, model: model, requestId: requestId,
                   inputTokens: input, outputTokens: output, cacheWrite5mTokens: cw5m, cacheWrite1hTokens: cw1h, cacheReadTokens: cr,
                   cwd: cwd)
}

func makeRecord(id: String = "msg_1", accountId: String?, model: String = "claude-opus-5-5",
                timestamp: Date = isoDate("2026-10-12T10:00:00Z"),
                input: Int = 0, output: Int = 0, cw5m: Int = 0, cw1h: Int = 0, cr: Int = 0, cost: Decimal?) -> UsageRecord {
    UsageRecord(messageId: id, timestamp: timestamp, model: model, canonicalModel: PriceTable.canonicalModel(model),
                requestId: "req_x", accountId: accountId,
                inputTokens: input, outputTokens: output, cacheWrite5mTokens: cw5m, cacheWrite1hTokens: cw1h, cacheReadTokens: cr,
                costUSD: cost)
}
