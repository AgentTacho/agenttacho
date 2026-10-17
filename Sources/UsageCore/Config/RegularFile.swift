import Foundation

/// Reads a file only when it is a regular file of a sane size, for
/// LastGoodStore (spec 010 FR-018). One descriptor for the checks and the
/// read, so the file cannot be swapped in between: no symbolic link is
/// followed, a FIFO does not block the open, the size is checked before
/// reading, and at most `maximumSize + 1` bytes are read.
public enum RegularFile {
    public enum Failure: Error, Equatable {
        case missing
        /// A folder, a FIFO or a symbolic link (also a dangling one).
        case notRegular
        /// The size in bytes, above the limit.
        case tooLarge(Int)
        /// `errno` of the failing call.
        case unreadable(Int32)

        /// The reason for a log line; never file content.
        public var reason: String {
            switch self {
            case .missing: return "no such file"
            case .notRegular: return "not a regular file"
            case .tooLarge(let size): return "too large (\(size) bytes)"
            case .unreadable(let code): return String(cString: strerror(code))
            }
        }
    }

    public static func read(_ url: URL, maximumSize: Int) throws -> Data {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else {
            let code = errno
            switch code {
            case ENOENT: throw Failure.missing
            case ELOOP: throw Failure.notRegular
            default: throw Failure.unreadable(code)
            }
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw Failure.unreadable(errno) }
        guard info.st_mode & S_IFMT == S_IFREG else { throw Failure.notRegular }
        guard info.st_size <= maximumSize else { throw Failure.tooLarge(Int(info.st_size)) }
        let data: Data
        do {
            // nil at end of file: an empty file.
            data = try handle.read(upToCount: maximumSize + 1) ?? Data()
        } catch {
            throw Failure.unreadable(EIO)
        }
        // The file grew after the size check.
        guard data.count <= maximumSize else { throw Failure.tooLarge(data.count) }
        return data
    }
}
