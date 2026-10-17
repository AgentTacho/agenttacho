import Foundation

/// The one-time copy of AgentMeter's settings into AgentTacho's folders
/// (spec 023 FR-008 to FR-011, FR-027, contracts/legacy-data-move.md).
///
/// It runs only while AgentTacho's configuration folder does not exist and
/// copies `config.json`, `imported-prices.json` and `last-good.json` byte for
/// byte. AgentMeter's folders are only read: nothing there is created,
/// changed, renamed or deleted (FR-009), and a destination folder that
/// resolves into one of them is refused. A symbolic link at a legacy name is
/// followed and the bytes of its target are copied; anything that is not a
/// regular file (a folder, a FIFO, a dangling link) is a failure, read
/// without blocking. Each file goes to a temporary file in the destination
/// folder first, readable only by the user, and is then moved into place, so
/// a carried-over name never holds a partial copy (FR-010). The content is
/// not judged here; the stores validate it when they load it.
public enum LegacyDataMove {
    /// A file that could not be copied, with the error's description.
    public struct Failure: Equatable, Sendable {
        public let file: String
        public let reason: String

        public init(file: String, reason: String) {
            self.file = file
            self.reason = reason
        }
    }

    public enum Outcome: Equatable, Sendable {
        /// The configuration folder exists; nothing was looked at.
        case skipped
        /// The configuration folder is missing and AgentMeter left no file;
        /// nothing was created.
        case nothingToMove
        /// File names, in the order config, prices, last good.
        case moved(copied: [String], failed: [Failure])
    }

    /// Failure reason for a legacy name that is not a regular file, or a
    /// symbolic link to none.
    public static let notARegularFile = RegularFile.Failure.notRegular.reason
    /// Failure reason for a destination folder that resolves into one of
    /// AgentMeter's folders, which must never be written (FR-009).
    public static let destinationIsLegacy = "the destination is one of AgentMeter's folders"
    /// Largest file copied; real files are a few KB.
    public static let maximumFileSize = 16 * 1_048_576
    /// Failure reason for a legacy file above `maximumFileSize`.
    public static let tooLarge = "larger than 16 MB"

    public static func run(paths: Paths, fileManager: FileManager = .default) -> Outcome {
        guard !fileManager.fileExists(atPath: paths.configDirectoryURL.path) else { return .skipped }
        // The Application Support folder holds last-good.json: created with
        // 0700, and an existing one only loses permissions (contract
        // guarantee 3).
        let items: [(source: URL, destination: URL, folderMode: Int?)] = [
            (paths.legacyConfigFileURL, paths.configFileURL, nil),
            (paths.legacyImportedPricesFileURL, paths.importedPricesFileURL, nil),
            (paths.legacyLastGoodFileURL, paths.lastGoodFileURL, 0o700),
        // Present means the name exists, also as a dangling link, which then
        // is reported rather than skipped (lstat, not following links).
        ].filter { (try? fileManager.attributesOfItem(atPath: $0.source.path)) != nil }
        guard !items.isEmpty else { return .nothingToMove }
        let legacyFolders = [paths.legacyConfigFileURL.deletingLastPathComponent(),
                             paths.legacyLastGoodFileURL.deletingLastPathComponent(),
                             paths.legacyLogDirectoryURL]

        var copied: [String] = []
        var failed: [Failure] = []
        for item in items {
            do {
                try copy(item.source, to: item.destination, folderMode: item.folderMode,
                         legacyFolders: legacyFolders, fileManager: fileManager)
                copied.append(item.destination.lastPathComponent)
            } catch let error as MoveError {
                failed.append(Failure(file: item.destination.lastPathComponent, reason: error.reason))
            } catch {
                failed.append(Failure(file: item.destination.lastPathComponent, reason: error.localizedDescription))
            }
        }
        // The folder marks the move as done, also when only last-good.json
        // was there or a copy failed (contract guarantee 7).
        // Never inside AgentMeter's folders, as for the copies.
        if !isInside(paths.configDirectoryURL, anyOf: legacyFolders, fileManager: fileManager) {
            try? fileManager.createDirectory(at: paths.configDirectoryURL, withIntermediateDirectories: true)
        }
        return .moved(copied: copied, failed: failed)
    }

    /// Log lines for `AppModel` (source "move"); empty for `.skipped` and
    /// `.nothingToMove` (FR-010, FR-011). No values are logged.
    public static func logLines(for outcome: Outcome) -> [String] {
        guard case .moved(let copied, let failed) = outcome else { return [] }
        var lines: [String] = []
        if !copied.isEmpty {
            lines.append("copied from AgentMeter: " + copied.joined(separator: ", "))
        }
        for failure in failed {
            lines.append("could not copy \(failure.file) from AgentMeter: \(failure.reason), starting with defaults")
        }
        return lines
    }

    /// A failure with a reason for the log.
    private struct MoveError: Error {
        let reason: String

        static func posix(_ code: Int32) -> MoveError {
            MoveError(reason: RegularFile.Failure.unreadable(code).reason)
        }
    }

    /// Reads the bytes of a legacy file, following a symbolic link to its
    /// target, which must be a regular file (RegularFile).
    private static func readLegacyFile(_ url: URL) throws -> Data {
        do {
            return try RegularFile.read(url.resolvingSymlinksInPath(), maximumSize: maximumFileSize)
        } catch let failure as RegularFile.Failure {
            switch failure {
            // A link to a file that is gone, or a file removed since it was
            // found.
            case .missing, .notRegular: throw MoveError(reason: notARegularFile)
            case .tooLarge: throw MoveError(reason: tooLarge)
            case .unreadable: throw MoveError(reason: failure.reason)
            }
        }
    }

    /// Whether a folder is, or resolves into, one of the given folders. A
    /// folder that does not exist yet is judged by its deepest existing
    /// ancestor, so a linked parent is resolved too.
    private static func isInside(_ folder: URL, anyOf folders: [URL], fileManager: FileManager) -> Bool {
        let path = resolvedPath(folder, fileManager: fileManager)
        return folders.contains { other in
            let otherPath = resolvedPath(other, fileManager: fileManager)
            return path == otherPath || path.hasPrefix(otherPath + "/")
        }
    }

    private static func resolvedPath(_ url: URL, fileManager: FileManager) -> String {
        var existing = url.standardizedFileURL
        var missing: [String] = []
        while !fileManager.fileExists(atPath: existing.path) && existing.path != "/" {
            missing.insert(existing.lastPathComponent, at: 0)
            existing = existing.deletingLastPathComponent()
        }
        var resolved = existing.resolvingSymlinksInPath()
        for component in missing { resolved.appendPathComponent(component) }
        return resolved.standardizedFileURL.path
    }

    /// Writes the source's bytes to a uniquely named temporary file (mode
    /// 0600) next to the destination, then moves it into place, replacing a
    /// file that is already there; the temporary file is removed on any error.
    private static func copy(_ source: URL, to destination: URL, folderMode: Int?, legacyFolders: [URL],
                             fileManager: FileManager) throws {
        let folder = destination.deletingLastPathComponent()
        guard !isInside(folder, anyOf: legacyFolders, fileManager: fileManager) else {
            throw MoveError(reason: destinationIsLegacy)
        }
        let data = try readLegacyFile(source)
        try fileManager.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true,
                                        attributes: folderMode.map { [.posixPermissions: $0] })
        if let folderMode {
            // Only removes permissions from a folder that already existed,
            // never adds any.
            let current = try fileManager.attributesOfItem(atPath: folder.path)[.posixPermissions] as? Int ?? folderMode
            try fileManager.setAttributes([.posixPermissions: current & folderMode], ofItemAtPath: folder.path)
        }
        let temporary = folder.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw MoveError.posix(errno) }
        do {
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            try handle.write(contentsOf: data)
            try handle.close()
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: temporary, options: .usingNewMetadataOnly)
            } else {
                try fileManager.moveItem(at: temporary, to: destination)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }
}
