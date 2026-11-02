import Foundation

/// Visits the lines of a file's unread bytes in place (spec 039 FR-012,
/// research R3). Line ends are found with `memchr`; each line is handed to
/// the caller as a slice of the same buffer, so no line is copied unless the
/// caller copies it. The rules are those of the index's earlier per-line
/// split (spec 001 FR-018): only complete lines, the ones that end with a
/// newline, are visited; one trailing CR is trimmed (CRLF files); empty
/// lines are skipped; bytes that are not valid UTF-8 pass through.
enum SessionLineReader {
    /// Calls `body` for each complete, non-empty line and returns the bytes
    /// consumed: through the last newline, 0 when the buffer has none. An
    /// incomplete last line is left for the next read.
    @discardableResult
    static func forEachLine(in buffer: UnsafeRawBufferPointer, body: (UnsafeRawBufferPointer) -> Void) -> Int {
        guard let base = buffer.baseAddress else { return 0 }
        let count = buffer.count
        var start = 0
        while start < count, let found = memchr(base + start, 0x0A, count - start) {
            let newline = base.distance(to: UnsafeRawPointer(found))
            var end = newline
            if end > start, buffer[end - 1] == 0x0D { end -= 1 }
            if end > start {
                body(UnsafeRawBufferPointer(rebasing: buffer[start..<end]))
            }
            start = newline + 1
        }
        return start
    }
}
