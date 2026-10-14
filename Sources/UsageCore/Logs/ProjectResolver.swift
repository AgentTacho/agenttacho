import Foundation

/// The project a usage record belongs to: the git repository root of the
/// session's working directory, or that directory itself outside a
/// repository (spec 2026-10-14 project breakdown).
public struct Project: Equatable, Hashable, Sendable {
    /// Standardized absolute path; the project's identity.
    public var rootPath: String
    /// Last path component of `rootPath` ("/" for the file system root).
    public var name: String

    public init(rootPath: String) {
        self.rootPath = rootPath
        self.name = (rootPath as NSString).lastPathComponent
    }
}

/// Maps a session's working directory to its `Project`. Results are cached
/// per `cwd` string, so each directory touches the file system once per
/// resolver lifetime. Not thread-safe; `LogIndex` owns one and calls it from
/// its sequential merge phase.
public final class ProjectResolver {
    private let fileManager: FileManager
    private var cache: [String: Project] = [:]
    private var notes: [String] = []
    /// File system walks performed so far (cache misses).
    public private(set) var lookups = 0

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// nil for a missing or empty `cwd` (shown as "Unknown").
    public func project(forCwd cwd: String?) -> Project? {
        guard let cwd, !cwd.isEmpty else { return nil }
        if let cached = cache[cwd] { return cached }
        lookups += 1
        let project = resolve((cwd as NSString).standardizingPath)
        cache[cwd] = project
        return project
    }

    /// Returns and clears the fallback notes collected since the last call.
    public func drainNotes() -> [String] {
        defer { notes = [] }
        return notes
    }

    private func resolve(_ cwd: String) -> Project {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: cwd, isDirectory: &isDirectory), isDirectory.boolValue else {
            notes.append("project fallback for \(cwd): directory not found")
            return Project(rootPath: cwd)
        }
        var dir = cwd
        while true {
            let git = (dir as NSString).appendingPathComponent(".git")
            var gitIsDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: git, isDirectory: &gitIsDirectory) {
                return gitIsDirectory.boolValue ? Project(rootPath: dir) : project(forGitFile: git, in: dir, cwd: cwd)
            }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir || parent.isEmpty { return Project(rootPath: cwd) }
            dir = parent
        }
    }

    /// A `.git` file points at the real git directory. A worktree's points at
    /// `<common>/worktrees/<name>`, whose `commondir` leads back to the main
    /// repository; anything else (a submodule) is its own project.
    private func project(forGitFile git: String, in dir: String, cwd: String) -> Project {
        guard let text = try? String(contentsOfFile: git, encoding: .utf8),
              let line = text.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("gitdir:") }) else {
            notes.append("project fallback for \(cwd): unreadable .git file at \(git)")
            return Project(rootPath: cwd)
        }
        var gitdir = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        guard !gitdir.isEmpty else {
            notes.append("project fallback for \(cwd): empty gitdir in \(git)")
            return Project(rootPath: cwd)
        }
        if !gitdir.hasPrefix("/") { gitdir = (dir as NSString).appendingPathComponent(gitdir) }
        gitdir = (gitdir as NSString).standardizingPath

        let container = ((gitdir as NSString).deletingLastPathComponent as NSString).lastPathComponent
        guard container == "worktrees",
              let raw = try? String(contentsOfFile: (gitdir as NSString).appendingPathComponent("commondir"), encoding: .utf8) else {
            return Project(rootPath: dir)
        }
        var common = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !common.isEmpty else { return Project(rootPath: dir) }
        if !common.hasPrefix("/") { common = (gitdir as NSString).appendingPathComponent(common) }
        common = (common as NSString).standardizingPath
        return Project(rootPath: (common as NSString).deletingLastPathComponent)
    }
}
