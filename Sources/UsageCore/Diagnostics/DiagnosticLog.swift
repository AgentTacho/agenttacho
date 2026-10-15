import Foundation

/// Append-only diagnostic log with a size cap (FR-036). When the file would
/// exceed `maxBytes` it is renamed to `<name>.1` (replacing the previous
/// generation) and a fresh file is started, so the log takes at most twice
/// `maxBytes` on disk.
public final class DiagnosticLog: @unchecked Sendable {
    /// 2.5 MB per file: the current file and its rolled-over generation
    /// together stay within 5 MB.
    public static let defaultMaxBytes = 5 * 1024 * 1024 / 2

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

    /// Escapes line breaks (including U+2028 and U+2029) and other control
    /// characters, so that text from files or the network (CSV file names,
    /// model ids) cannot add or forge log lines: one call, one line.
    static func singleLine(_ text: String) -> String {
        func needsEscape(_ scalar: Unicode.Scalar) -> Bool {
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator: return true
            default: return false
            }
        }
        guard text.unicodeScalars.contains(where: needsEscape) else { return text }
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\n": out.append(contentsOf: "\\n".unicodeScalars)
            case "\r": out.append(contentsOf: "\\r".unicodeScalars)
            case "\t": out.append(contentsOf: "\\t".unicodeScalars)
            case _ where needsEscape(scalar):
                out.append(contentsOf: String(format: "\\u{%04X}", scalar.value).unicodeScalars)
            default:
                out.append(scalar)
            }
        }
        return String(out)
    }

    public var rolledOverURL: URL {
        fileURL.appendingPathExtension("1")
    }

    /// The newest `lines` lines of the current file, oldest first, for the
    /// Log tab in Settings. Reads at most the last `maxBytes` bytes, so the
    /// cost stays small even at the size cap; a line cut by that window is
    /// dropped. Empty when the file does not exist or cannot be read.
    public func tail(lines: Int, maxBytes: Int = 256 * 1024) -> [String] {
        guard lines > 0, let handle = try? FileHandle(forReadingFrom: fileURL) else { return [] }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return [] }
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil,
              let data = try? handle.readToEnd() else { return [] }
        var all = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true)
        if start > 0, !all.isEmpty { all.removeFirst() }
        return all.suffix(lines).map(String.init)
    }

    public func append(source: String, message: String, at date: Date = Date()) {
        let line = "\(formatter.string(from: date)) [\(DiagnosticLog.singleLine(source))] \(DiagnosticLog.singleLine(message))\n"
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
