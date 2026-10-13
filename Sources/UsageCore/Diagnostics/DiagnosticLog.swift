import Foundation

/// Append-only diagnostic log with a size cap (FR-036). When the file would
/// exceed `maxBytes` it is renamed to `<name>.1` (replacing the previous
/// generation) and a fresh file is started.
public final class DiagnosticLog: @unchecked Sendable {
    public static let defaultMaxBytes = 5 * 1024 * 1024

    public let fileURL: URL
    public let maxBytes: Int
    private let lock = NSLock()
    private let formatter: ISO8601DateFormatter

    public init(fileURL: URL, maxBytes: Int = DiagnosticLog.defaultMaxBytes) {
        self.fileURL = fileURL
        self.maxBytes = maxBytes
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        self.formatter = f
    }

    public var rolledOverURL: URL {
        fileURL.appendingPathExtension("1")
    }

    public func append(source: String, message: String, at date: Date = Date()) {
        let line = "\(formatter.string(from: date)) [\(source)] \(message)\n"
        let data = Data(line.utf8)
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let currentSize = (try? fm.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
            if currentSize > 0 && currentSize + data.count > maxBytes {
                try? fm.removeItem(at: rolledOverURL)
                try fm.moveItem(at: fileURL, to: rolledOverURL)
            }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: fileURL)
            }
        } catch {
            // The log is best effort; a failure to write must never affect a refresh.
        }
    }
}
