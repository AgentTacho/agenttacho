import Foundation

/// One session log file found by the scanner.
public struct ScannedFile: Equatable, Sendable {
    public let canonicalPath: String
    /// The configured directory (canonical) whose `projects` tree reached this file.
    public let configDirectory: String
    public let size: Int
    public let modificationDate: Date

    public init(canonicalPath: String, configDirectory: String, size: Int, modificationDate: Date) {
        self.canonicalPath = canonicalPath
        self.configDirectory = configDirectory
        self.size = size
        self.modificationDate = modificationDate
    }
}

public struct ScanResult: Sendable {
    public var files: [ScannedFile]
    /// Problems of main directories only; they can fail the source.
    public var errors: [String]
    /// Log lines for problems of additional directories, which never fail
    /// the source or add a problem to the dropdown (spec 035 FR-008).
    public var additionalNotes: [String]
    /// Configured directories that existed and were readable, main and
    /// additional.
    public var scannedDirectories: Int

    public init(files: [ScannedFile] = [], errors: [String] = [], additionalNotes: [String] = [], scannedDirectories: Int = 0) {
        self.files = files
        self.errors = errors
        self.additionalNotes = additionalNotes
        self.scannedDirectories = scannedDirectories
    }
}

/// One directory to scan: a main directory of spec 034 or an additional
/// session directory (spec 035 FR-008, research R6).
public struct ScanTarget: Equatable, Sendable {
    /// Tilde-expanded.
    public let path: String
    public let isMain: Bool
    /// The canonical path the resolver already computed; nil to compute it.
    public let canonical: String?

    public init(path: String, isMain: Bool, canonical: String? = nil) {
        self.path = path
        self.isMain = isMain
        self.canonical = canonical
    }
}

/// Enumerates `<dir>/projects/**/*.jsonl` for every configured directory,
/// resolving symlinks so a shared tree is counted once (research R1).
public struct LogDirectoryScanner: Sendable {
    public init() {}

    /// Every directory as a main directory, for tests; the sources call
    /// `scan(targets:)`.
    func scan(directories: [String]) -> ScanResult {
        scan(targets: directories.map { ScanTarget(path: $0, isMain: true) })
    }

    /// Scans the `projects` tree of each target in order, so a file reached
    /// through a main and an additional directory is found in the main one
    /// (spec 035 FR-012). Problems of a main target go to `errors`, those of
    /// an additional target only to `additionalNotes` (spec 035 FR-008).
    public func scan(targets: [ScanTarget]) -> ScanResult {
        let fm = FileManager.default
        var result = ScanResult()
        var seen = Set<String>()
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]

        for target in targets {
            let directory = target.path
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: directory, isDirectory: &isDir), isDir.boolValue else {
                if target.isMain {
                    result.errors.append("log directory not found: \(directory)")
                } else {
                    result.additionalNotes.append("\(directory): skipped, not found")
                }
                continue
            }
            guard fm.isReadableFile(atPath: directory) else {
                if target.isMain {
                    result.errors.append("log directory not readable: \(directory)")
                } else {
                    result.additionalNotes.append("\(directory): error: not readable")
                }
                continue
            }
            result.scannedDirectories += 1
            let configDirectory = target.canonical ?? Attributor.canonical(directory)
            let projects = URL(fileURLWithPath: directory).appendingPathComponent("projects")
            guard fm.fileExists(atPath: projects.path, isDirectory: &isDir), isDir.boolValue else {
                continue  // no projects tree yet: nothing to scan, not an error
            }
            let projectsCanonical = projects.resolvingSymlinksInPath().standardizedFileURL
            // An additional directory, often a copy of a sandbox, is read
            // only below itself: a `projects` link that leads elsewhere (to
            // the home folder or `/`) is skipped (spec 035 FR-006, FR-009).
            if !target.isMain && !projectsCanonical.path.hasPrefix(configDirectory == "/" ? "/" : configDirectory + "/") {
                result.additionalNotes.append("\(directory): skipped, projects is a link outside the directory")
                continue
            }
            guard let enumerator = fm.enumerator(at: projectsCanonical, includingPropertiesForKeys: Array(keys),
                                                 options: [.skipsHiddenFiles],
                                                 errorHandler: { url, error in
                                                     if target.isMain {
                                                         result.errors.append("cannot read \(url.path): \(error.localizedDescription)")
                                                     } else {
                                                         result.additionalNotes.append(
                                                             "\(directory): error: cannot read \(url.path): \(error.localizedDescription)")
                                                     }
                                                     return true
                                                 }) else {
                if target.isMain {
                    result.errors.append("cannot enumerate \(projects.path)")
                } else {
                    result.additionalNotes.append("\(directory): error: not readable")
                }
                continue
            }
            while let url = enumerator.nextObject() as? URL {
                guard url.pathExtension == "jsonl" else { continue }
                guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
                let path = url.standardizedFileURL.path
                guard seen.insert(path).inserted else { continue }
                result.files.append(ScannedFile(canonicalPath: path,
                                                configDirectory: configDirectory,
                                                size: values.fileSize ?? 0,
                                                modificationDate: values.contentModificationDate ?? .distantPast))
            }
        }
        return result
    }

}
