import Foundation
@testable import UsageCore

/// A `DirectoryFileSystem` in memory for the expander and resolver tests
/// (spec 035 research R3): folders, files, symlinks to folders and
/// unreadable folders. Mutable between calls, so a test can add or remove
/// folders between two refreshes.
final class InMemoryDirectoryFileSystem: DirectoryFileSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var folders: Set<String> = ["/"]
    private var files: Set<String> = []
    /// Link path to target path.
    private var symlinks: [String: String] = [:]
    private var unreadable: Set<String> = []
    private var listings = 0

    /// How many folders were listed so far.
    var listingCount: Int {
        lock.lock(); defer { lock.unlock() }
        return listings
    }

    init(folders: [String] = []) {
        for folder in folders { addFolder(folder) }
    }

    /// Adds `path` and every folder above it.
    func addFolder(_ path: String) {
        lock.lock(); defer { lock.unlock() }
        var current = ""
        for component in Self.components(path) {
            current += "/" + component
            folders.insert(current)
        }
    }

    func addFile(_ path: String) {
        addFolder((path as NSString).deletingLastPathComponent)
        lock.lock(); defer { lock.unlock() }
        files.insert(path)
    }

    func addSymlink(_ path: String, to target: String) {
        addFolder((path as NSString).deletingLastPathComponent)
        lock.lock(); defer { lock.unlock() }
        symlinks[path] = target
    }

    func makeUnreadable(_ path: String) {
        lock.lock(); defer { lock.unlock() }
        unreadable.insert(path)
    }

    /// Removes `path` and everything below it.
    func remove(_ path: String) {
        lock.lock(); defer { lock.unlock() }
        let prefix = path + "/"
        folders = folders.filter { $0 != path && !$0.hasPrefix(prefix) }
        files = files.filter { $0 != path && !$0.hasPrefix(prefix) }
        symlinks = symlinks.filter { $0.key != path && !$0.key.hasPrefix(prefix) }
    }

    func contents(ofDirectory path: String) -> DirectoryContents {
        lock.lock(); defer { lock.unlock() }
        listings += 1
        let resolved = resolve(path)
        if unreadable.contains(resolved) { return .unreadable("not readable") }
        guard folders.contains(resolved) else { return .missing }
        let prefix = resolved == "/" ? "/" : resolved + "/"
        var names = Set<String>()
        for entry in folders.union(files).union(symlinks.keys) where entry.hasPrefix(prefix) && entry != resolved {
            let rest = entry.dropFirst(prefix.count)
            if !rest.contains("/") { names.insert(String(rest)) }
        }
        return .names(names.sorted())
    }

    func isDirectory(_ path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return folders.contains(resolve(path))
    }

    func canonicalPath(_ path: String) -> String {
        lock.lock(); defer { lock.unlock() }
        return resolve(path)
    }

    /// `path` standardized with every symlink in it resolved.
    private func resolve(_ path: String) -> String {
        var parts = Self.standardized(Self.components(path))
        var rounds = 0
        var index = 0
        while index < parts.count && rounds < 40 {
            let prefix = "/" + parts[0...index].joined(separator: "/")
            if let target = symlinks[prefix] {
                parts = Self.standardized(Self.components(target) + parts[(index + 1)...])
                index = 0
                rounds += 1
                continue
            }
            index += 1
        }
        return "/" + parts.joined(separator: "/")
    }

    private static func components(_ path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    private static func standardized(_ parts: [String]) -> [String] {
        var result: [String] = []
        for part in parts {
            switch part {
            case ".": continue
            case "..": if !result.isEmpty { result.removeLast() }
            default: result.append(part)
            }
        }
        return result
    }
}
