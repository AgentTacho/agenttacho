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
    public var errors: [String]
    /// Configured directories that existed and were readable.
    public var scannedDirectories: Int

    public init(files: [ScannedFile] = [], errors: [String] = [], scannedDirectories: Int = 0) {
        self.files = files
        self.errors = errors
        self.scannedDirectories = scannedDirectories
    }
}

/// Enumerates `<dir>/projects/**/*.jsonl` for every configured directory,
/// resolving symlinks so a shared tree is counted once (research R1).
public struct LogDirectoryScanner: Sendable {
    public init() {}

    /// `directories` are already tilde-expanded. The first directory that
    /// reaches a file wins.
    public func scan(directories: [String]) -> ScanResult {
        let fm = FileManager.default
        var result = ScanResult()
        var seen = Set<String>()
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]

        for directory in directories {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: directory, isDirectory: &isDir), isDir.boolValue else {
                result.errors.append("log directory not found: \(directory)")
                continue
            }
            guard fm.isReadableFile(atPath: directory) else {
                result.errors.append("log directory not readable: \(directory)")
                continue
            }
            result.scannedDirectories += 1
            let configDirectory = canonical(directory)
            let projects = URL(fileURLWithPath: directory).appendingPathComponent("projects")
            guard fm.fileExists(atPath: projects.path, isDirectory: &isDir), isDir.boolValue else {
                continue  // no projects tree yet: nothing to scan, not an error
            }
            let projectsCanonical = projects.resolvingSymlinksInPath().standardizedFileURL
            guard let enumerator = fm.enumerator(at: projectsCanonical, includingPropertiesForKeys: Array(keys),
                                                 options: [.skipsHiddenFiles],
                                                 errorHandler: { url, error in
                                                     result.errors.append("cannot read \(url.path): \(error.localizedDescription)")
                                                     return true
                                                 }) else {
                result.errors.append("cannot enumerate \(projects.path)")
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

    private func canonical(_ path: String) -> String {
        var p = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }
}
