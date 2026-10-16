import AppKit
import CryptoKit
import Foundation
import Security
import UsageCore

/// Runs the tools and file operations of a one-click install (spec 013
/// FR-014 to FR-018; research R4, R8, R10). Its decisions come from
/// `UsageCore`: every verification result goes to `UpdateVerification`, and
/// nothing is staged or swapped unless that verdict is clean (SC-003). Tools
/// run with absolute paths and argument arrays, never through a shell with
/// interpolated paths. It writes only the update folder in the user's
/// temporary directory, a system staging folder (`TemporaryItems`) on the
/// app's volume, the app bundle and the Trash.
final class UpdateInstaller: @unchecked Sendable {
    struct ToolResult {
        let status: Int32
        let output: String
    }

    enum InstallerError: Error, CustomStringConvertible {
        case tool(String, Int32, String)
        case file(String)

        var description: String {
            switch self {
            case .tool(let name, let status, let output):
                let detail = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").last.map(String.init) ?? ""
                return "\(name) failed (\(status))" + (detail.isEmpty ? "" : ": \(detail)")
            case .file(let detail):
                return detail
            }
        }
    }

    private let lock = NSLock()
    private var runningProcess: Process?
    private var cancelled = false

    // MARK: Locations (research R10)

    /// `$TMPDIR/dev.rhuss.agentmeter-update/`.
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent(UpdateOutcome.folderName, isDirectory: true)
    var downloadURL: URL { folder.appendingPathComponent("download.dmg") }
    var mountPoint: URL { folder.appendingPathComponent("mnt", isDirectory: true) }
    var outcomeURL: URL { folder.appendingPathComponent(UpdateOutcome.fileName) }
    /// Records the staging folder, so launch cleanup can remove a leftover.
    private var stagingRecordURL: URL { folder.appendingPathComponent("staging-path") }

    /// Creates the update folder, removing an earlier one first.
    func prepareFolder() throws {
        lock.lock(); cancelled = false; lock.unlock()
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: folder)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
    }

    /// Removes the update folder (download and mount point).
    func removeFolder() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Removes the download and the mount point, keeping the outcome.
    func removeDownloadFiles() {
        try? FileManager.default.removeItem(at: downloadURL)
        try? FileManager.default.removeItem(at: mountPoint)
    }

    // MARK: Checksum (R4 step 1)

    /// SHA-256 of a file in lowercase hex, read in 1 MB chunks.
    func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Tools

    /// `spctl --assess --type <open|execute> [--context context:primary-signature] --verbose=2 <path>`.
    func assess(path: URL, type: String) async throws -> ToolResult {
        var arguments = ["--assess", "--type", type]
        if type == "open" { arguments += ["--context", "context:primary-signature"] }
        arguments += ["--verbose=2", path.path]
        return try await run("/usr/sbin/spctl", arguments)
    }

    /// Mounts the disk image read-only and hidden at `mountPoint` (R4 step 3).
    func attach(dmg: URL) async throws {
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        let result = try await run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-noautoopen",
                                                       "-mountpoint", mountPoint.path, dmg.path])
        guard result.status == 0 else { throw InstallerError.tool("hdiutil attach", result.status, result.output) }
    }

    /// Detaches the image; with `force` also when files are open. Never
    /// cancelled, so a mount is not left behind.
    func detach(mountPoint: URL, force: Bool = false) async {
        var arguments = ["detach", mountPoint.path]
        if force { arguments.append("-force") }
        _ = try? await run("/usr/bin/hdiutil", arguments, cancellable: false)
    }

    /// True when something is mounted at the update's mount point.
    func isMounted() -> Bool {
        let values = try? mountPoint.resourceValues(forKeys: [.isVolumeKey])
        return values?.isVolume == true
    }

    /// The top-level entries of the mounted image, with the Info.plist data
    /// of each `.app` (R4 step 4). Symbolic links are not followed.
    func entries(of mount: URL) throws -> [DiskImageEntry] {
        let urls = try FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let isDirectory = values?.isDirectory == true && values?.isSymbolicLink != true
            var identifier: String?
            var version: String?
            if isDirectory, url.pathExtension.lowercased() == "app",
               let plist = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) {
                identifier = plist["CFBundleIdentifier"] as? String
                version = plist["CFBundleShortVersionString"] as? String
            }
            return DiskImageEntry(name: url.lastPathComponent, isDirectory: isDirectory,
                                  bundleIdentifier: identifier, shortVersion: version)
        }
    }

    // MARK: Code signature (R4 step 5)

    /// Validates the app's signature, nested code included, against the
    /// requirement (bundle identifier, Developer ID, same team).
    func checkSignature(app: URL, requirement: String) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return false }
        var parsed: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &parsed) == errSecSuccess, let parsed else { return false }
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        var error: Unmanaged<CFError>?
        let status = SecStaticCodeCheckValidityWithErrors(code, flags, parsed, &error)
        error?.release()
        return status == errSecSuccess
    }

    // MARK: Stage and swap (R8)

    /// Copies the verified app with `ditto` into a staging folder on the
    /// installed app's volume. Returns the staged app.
    func stage(app: URL, besides installed: URL) async throws -> URL {
        let staging = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                  appropriateFor: installed, create: true)
        try? Data(staging.path.utf8).write(to: stagingRecordURL)
        let staged = staging.appendingPathComponent(installed.lastPathComponent, isDirectory: true)
        let result = try await run("/usr/bin/ditto", [app.path, staged.path])
        guard result.status == 0 else {
            try? FileManager.default.removeItem(at: staging)
            throw InstallerError.tool("ditto", result.status, result.output)
        }
        return staged
    }

    /// Moves the installed app to the Trash and the staged app into its
    /// place. If the move fails, the trashed app is moved back (FR-017);
    /// when that fails too, `.previousVersionInTrash` says where it is. The
    /// staging folder is removed afterwards in every case.
    func swap(installed: URL, staged: URL) -> Result<URL?, UpdateBlockReason> {
        let fileManager = FileManager.default
        defer { removeStaging(staged.deletingLastPathComponent()) }
        var trashed: NSURL?
        do {
            try fileManager.trashItem(at: installed, resultingItemURL: &trashed)
        } catch {
            return .failure(Self.replacementReason(error))
        }
        do {
            try fileManager.moveItem(at: staged, to: installed)
        } catch {
            guard let trashedURL = trashed as URL? else {
                return .failure(.previousVersionInTrash(nil))
            }
            do {
                try fileManager.moveItem(at: trashedURL, to: installed)
            } catch {
                return .failure(.previousVersionInTrash(trashedURL.path))
            }
            return .failure(Self.replacementReason(error))
        }
        return .success(trashed as URL?)
    }

    /// The FR-019 reason for a failed move, decided by
    /// `UpdateBlockReason.forReplacement` (FR-017, FR-023).
    static func replacementReason(_ error: Error) -> UpdateBlockReason {
        let nsError = error as NSError
        let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        return .forReplacement(domain: nsError.domain, code: nsError.code, underlyingDomain: underlying?.domain,
                               underlyingCode: underlying?.code, description: nsError.localizedDescription)
    }

    private func removeStaging(_ staging: URL) {
        try? FileManager.default.removeItem(at: staging)
        try? FileManager.default.removeItem(at: stagingRecordURL)
    }

    // MARK: Outcome (R10)

    func writeOutcome(_ outcome: UpdateOutcome) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? outcome.encoded().write(to: outcomeURL, options: .atomic)
    }

    func removeOutcome() {
        try? FileManager.default.removeItem(at: outcomeURL)
    }

    /// Launch cleanup: returns the outcome of a previous run, detaches a
    /// leftover mount, and removes the update folder and a leftover staging
    /// folder (FR-017, FR-018).
    func cleanUpAfterLaunch() async -> UpdateOutcome? {
        let fileManager = FileManager.default
        let outcome = (try? Data(contentsOf: outcomeURL)).flatMap(UpdateOutcome.decode)
        if isMounted() {
            await detach(mountPoint: mountPoint, force: true)
        }
        if let data = try? Data(contentsOf: stagingRecordURL),
           let path = String(data: data, encoding: .utf8),
           InstallLocation.isRemovableStagingPath(path), fileManager.fileExists(atPath: path) {
            try? fileManager.removeItem(atPath: path)
        }
        if fileManager.fileExists(atPath: folder.path) {
            try? fileManager.removeItem(at: folder)
        }
        return outcome
    }

    // MARK: Relaunch (R8 step 4)

    /// Starts the app at `appPath` once this process has exited, then quits
    /// (FR-017, spec 005 single instance).
    @MainActor
    func relaunch(appPath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$2\"",
                             "sh", String(ProcessInfo.processInfo.processIdentifier), appPath]
        try process.run()
        NSApplication.shared.terminate(nil)
    }

    // MARK: Cancel

    /// Stops a running tool (spctl, hdiutil, ditto) and refuses new ones
    /// until the next `prepareFolder` (FR-018).
    func cancel() {
        lock.lock()
        cancelled = true
        let process = runningProcess
        lock.unlock()
        if let process, process.isRunning { process.terminate() }
    }

    /// Runs a tool and returns its status and combined output. The process
    /// is kept so `cancel()` can terminate it.
    private func run(_ executable: String, _ arguments: [String], cancellable: Bool = true) async throws -> ToolResult {
        if cancellable { try Task.checkCancellation() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        // Output goes to a file, not a pipe: a helper that inherits the
        // descriptor cannot keep the read waiting after the tool exited.
        // It lives in the update folder, the only temporary folder used.
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let outputURL = folder.appendingPathComponent("tool-\(UUID().uuidString).log")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
              let output = try? FileHandle(forWritingTo: outputURL) else {
            throw InstallerError.file("cannot create the tool output file")
        }
        defer {
            try? output.close()
            try? FileManager.default.removeItem(at: outputURL)
        }
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        lock.lock()
        if cancellable && cancelled {
            lock.unlock()
            throw CancellationError()
        }
        if cancellable { runningProcess = process }
        lock.unlock()
        defer {
            if cancellable {
                lock.lock(); runningProcess = nil; lock.unlock()
            }
        }
        let result: ToolResult = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = (try? Data(contentsOf: outputURL)) ?? Data()
                    continuation.resume(returning: ToolResult(status: process.terminationStatus,
                                                              output: String(decoding: data.prefix(65_536), as: UTF8.self)))
                } catch {
                    continuation.resume(throwing: InstallerError.file("cannot run \(executable): \(error.localizedDescription)"))
                }
            }
        }
        if cancellable {
            lock.lock(); let wasCancelled = cancelled; lock.unlock()
            if wasCancelled { throw CancellationError() }
            try Task.checkCancellation()
        }
        return result
    }
}
