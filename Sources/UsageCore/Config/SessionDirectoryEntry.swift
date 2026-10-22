import Foundation

/// The list an entry belongs to: an account's additional session
/// directories or the OpenCode data directories of General > Sources
/// (spec 035 FR-006, FR-013).
public enum SessionDirectoryList: Sendable {
    case account
    case openCode
}

/// Why an entry of a session directory list is refused (spec 035 FR-006,
/// contracts/configuration.md "Entry rules").
public enum SessionDirectoryRefusal: Equatable, Sendable {
    /// Starts with neither `~/` nor `/`: an app has no meaningful working
    /// folder.
    case relative
    /// Holds `**`; `*` covers one folder level only.
    case doubleStar
    /// Is the home folder or `/` itself.
    case homeOrRoot
    /// A bare `*` folder directly under the home folder or `/`.
    case bareStarAtTop

    /// The reason shown in the "Not applied" line and the load note.
    public var reason: String {
        switch self {
        case .relative: return "it must start with ~/ or /"
        case .doubleStar: return "** is not supported, * covers one folder level"
        case .homeOrRoot: return "the home folder or / is not a session directory"
        case .bareStarAtTop: return "* may not stand for a whole folder directly under the home folder or /"
        }
    }
}

/// The entry rules of the additional session directory lists and of the
/// OpenCode list (spec 035 FR-002, FR-006, research R2). String work only:
/// Settings and `Configuration.validate()` never touch the file system.
public enum SessionDirectoryEntry {
    /// The refusal of `entry` in `list`, nil when it is accepted. Checked on
    /// the trimmed entry in this order: relative (in an account list always,
    /// in the OpenCode list only with `*`), `**`, the home folder or `/`
    /// (after expanding `~` and removing `.` and `..`, without resolving
    /// symlinks), a bare `*` directly under the home folder or `/`.
    public static func refusal(of entry: String, in list: SessionDirectoryList, paths: Paths) -> SessionDirectoryRefusal? {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        let isAbsolute = trimmed == "~" || trimmed.hasPrefix("~/") || trimmed.hasPrefix("/")
        if !isAbsolute {
            // Literal relative OpenCode entries keep their spec 006 behavior.
            if list == .account || trimmed.contains("*") { return .relative }
            return nil
        }
        if trimmed.contains("**") { return .doubleStar }
        let components = Self.components(of: normalized(trimmed, paths: paths))
        let home = Self.components(of: normalized(paths.home.path, paths: paths))
        if components.isEmpty || components == home { return .homeOrRoot }
        if components.first == "*" { return .bareStarAtTop }
        if components.count > home.count, Array(components.prefix(home.count)) == home, components[home.count] == "*" {
            return .bareStarAtTop
        }
        return nil
    }

    /// `list` with `entry` added, trimmed of whitespace and newlines; blank
    /// input and an entry already in the list leave it unchanged (spec 035
    /// FR-002). A refused entry is added, so the draft's "Not applied" line
    /// names it.
    public static func adding(_ entry: String, to list: [String]) -> [String] {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !list.contains(trimmed) else { return list }
        return list + [trimmed]
    }

    /// `list` with the entry at `index` replaced by `entry`, trimmed like an
    /// added one: blank text, another entry's text or an index outside the
    /// list leaves it unchanged (spec 035 FR-002, editing a row in place).
    /// A refused entry is written, so the draft's "Not applied" line names it.
    public static func replacing(at index: Int, with entry: String, in list: [String]) -> [String] {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard list.indices.contains(index), !trimmed.isEmpty else { return list }
        guard !list.enumerated().contains(where: { $0.offset != index && $0.element == trimmed }) else { return list }
        var result = list
        result[index] = trimmed
        return result
    }

    /// The entry for a folder picked with "Choose Folder…": the home folder
    /// written as `~`, a trailing slash dropped, any other path unchanged
    /// (spec 035 FR-002).
    public static func entry(forChosenFolder path: String, paths: Paths) -> String {
        let folder = paths.expand(path)
        let home = paths.expand(paths.home.path)
        if folder == home { return "~" }
        if folder.hasPrefix(home + "/") { return "~" + folder.dropFirst(home.count) }
        return folder
    }

    /// `entry` with `~` expanded, `.` and `..` removed, repeated and
    /// trailing slashes dropped; no symlink is resolved and nothing is read.
    /// A relative entry stays relative.
    public static func normalized(_ entry: String, paths: Paths) -> String {
        let expanded = paths.expand(entry)
        let isAbsolute = expanded.hasPrefix("/")
        var result: [String] = []
        for component in expanded.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".": continue
            case "..":
                if !result.isEmpty && result.last != ".." { result.removeLast() } else if !isAbsolute { result.append("..") }
            default: result.append(String(component))
            }
        }
        return (isAbsolute ? "/" : "") + result.joined(separator: "/")
    }

    /// The folder names of a normalized absolute path; empty for `/`.
    static func components(of path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }
}
