import Foundation

/// Decisions about where the running app and the update's files are (spec
/// 013 FR-012, FR-018, FR-023; research R6, R8). The app reads the file
/// system's facts and passes them in.
public enum InstallLocation {
    /// macOS runs a quarantined app that was not moved from a randomized,
    /// read-only path containing this component.
    public static let translocationComponent = "/AppTranslocation/"

    /// True for a translocated app path (FR-012).
    public static func isTranslocated(path: String) -> Bool {
        path.contains(translocationComponent)
    }

    /// True when the app runs from a read-only volume (a mounted disk
    /// image, or the read-only mount of a translocated app), or from a path
    /// under `/Volumes/` that is not on the root file system (FR-012).
    public static func isOnDiskImage(path: String, volumeIsReadOnly: Bool?, volumeIsRootFileSystem: Bool?) -> Bool {
        if volumeIsReadOnly == true { return true }
        return path.hasPrefix("/Volumes/") && volumeIsRootFileSystem != true
    }

    /// True only for a staging folder the system created for the swap:
    /// `.../TemporaryItems/NSIRD_*`, as returned for
    /// `FileManager.url(for: .itemReplacementDirectory, ...)`, absolute and
    /// without `.` or `..` components. Launch cleanup deletes a leftover
    /// staging folder only when its recorded path passes (FR-018).
    public static func isRemovableStagingPath(_ path: String) -> Bool {
        guard path.hasPrefix("/") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        guard components.count >= 2, !components.contains(where: { $0 == "." || $0 == ".." || $0.isEmpty }) else {
            return false
        }
        let name = components[components.endIndex - 1]
        let parent = components[components.endIndex - 2]
        return parent == "TemporaryItems" && name.hasPrefix("NSIRD_") && name.count > "NSIRD_".count
    }
}
