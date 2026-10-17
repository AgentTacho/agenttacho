import AppKit
import Foundation
import Observation
import UsageCore

/// Runs the update check on its schedule and on demand, and holds what the
/// update line and Settings > About show (spec 013 FR-001 to FR-003, FR-007,
/// FR-007a, FR-008, FR-021; research R9, R13). All decisions come from
/// `UsageCore` (`UpdateSchedule`, `UpdatePolicy`, `UpdateDisplay`); this class
/// only sequences them, makes the requests and logs.
@MainActor
@Observable
final class Updater {
    /// What the line and Settings show.
    private(set) var display = UpdateDisplay()

    @ObservationIgnored let log: DiagnosticLog
    @ObservationIgnored let launchedAt = Date()
    /// The last automatic check attempt in this session; never stored on
    /// disk (FR-001).
    @ObservationIgnored private(set) var lastCheck: Date?
    @ObservationIgnored private var automaticEnabled = false
    /// Decided once in `start()`: false for a development build (FR-008).
    @ObservationIgnored private var checksAllowed = false
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    /// The origin of the running check, nil when none runs. "Check for
    /// Updates…" chosen while a check runs joins it, and the result is
    /// reported for the joined origin (FR-003).
    @ObservationIgnored private var runningOrigin: CheckOrigin?
    @ObservationIgnored private let installer = UpdateInstaller()
    @ObservationIgnored private var installTask: Task<Void, Never>?

    /// Re-evaluates the schedule at least this often (research R9).
    static let maximumSleep: TimeInterval = 3600
    /// After wake, the check waits this long so the network is up (FR-001).
    static let wakeDelay: TimeInterval = 60

    init(log: DiagnosticLog) {
        self.log = log
    }

    // MARK: Lifecycle

    /// Called once after launch: cleans up after a previous install, and a
    /// development build shows its state (FR-008). The schedule starts with
    /// the first `apply(automatic:)` from the loaded configuration, so a
    /// saved "off" never starts it (FR-002, SC-005).
    func start() {
        Task { await cleanUpAfterLaunch() }
        let context = InstallEnvironment.current()
        checksAllowed = UpdatePolicy.checksAllowed(context: context)
        if !checksAllowed {
            display = display.markingDevelopmentBuild(origin: .automatic)
            log.append(source: "update", message: "updates are not checked: \(context.logSummary)")
        }
    }

    /// Starts or stops the automatic schedule from the configuration's
    /// `checksForUpdates` (FR-002, SC-005); `lastCheck` is kept. Manual
    /// checks run either way (FR-003). Development builds never schedule;
    /// whether checks are allowed is decided once in `start()`, because a
    /// build cannot change kind while it runs and this runs on every
    /// snapshot.
    func apply(automatic: Bool) {
        guard checksAllowed else { return }
        guard automatic != automaticEnabled || (automatic && loopTask == nil) else { return }
        automaticEnabled = automatic
        loopTask?.cancel()
        loopTask = nil
        guard automatic else {
            log.append(source: "update", message: "automatic check off")
            return
        }
        log.append(source: "update", message: "automatic check on")
        startLoop(firstWait: nil)
    }

    /// The one schedule loop (research R9): it sleeps until the next check
    /// is due, at most `maximumSleep`, and asks `UpdateSchedule` whether a
    /// check is due. It sleeps on the suspending clock, which stops while the
    /// Mac sleeps, so a wait never ends at the moment of wake before the
    /// network is up; `handleWake` restarts the loop to look again
    /// `wakeDelay` after wake (FR-001).
    private func startLoop(firstWait: TimeInterval?) {
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            var next = firstWait
            while !Task.isCancelled {
                guard let wait = next ?? self?.secondsUntilDue() else { return }
                next = nil
                try? await Task.sleep(for: .seconds(wait), clock: .suspending)
                if Task.isCancelled { return }
                await self?.checkIfDue()
            }
        }
    }

    /// After wake, a check that came due during sleep runs `wakeDelay` later
    /// (FR-001, research R9).
    func handleWake() {
        guard automaticEnabled else { return }
        startLoop(firstWait: Self.wakeDelay)
    }

    /// The dropdown closed: transient results leave the line (FR-003).
    func dismissTransient() {
        if display.lineShowsTransient {
            display = display.dismissingTransient()
        }
    }

    /// While an install or another check runs, a due automatic check waits
    /// `wakeDelay` instead of polling every second.
    private func secondsUntilDue() -> TimeInterval {
        let due = UpdateSchedule.nextDue(launchedAt: launchedAt, lastCheck: lastCheck)
        let minimum = display.state.isInstallRunning || runningOrigin != nil ? Self.wakeDelay : 1
        return min(max(due.timeIntervalSinceNow, minimum), Self.maximumSleep)
    }

    private func checkIfDue() async {
        guard automaticEnabled, UpdateSchedule.isDue(now: Date(), launchedAt: launchedAt, lastCheck: lastCheck) else { return }
        // In its own task, so a loop restart (wake, toggle) never cancels a
        // check in flight after `lastCheck` moved.
        await Task { await self.runCheck(origin: .automatic) }.value
    }

    // MARK: Check

    /// "Check for Updates…" from the dropdown's gear menu or from Settings >
    /// About: runs regardless of the toggle; only a check from the dropdown
    /// shows its result on the line (FR-003).
    func checkNow(from origin: CheckOrigin) {
        Task { await runCheck(origin: origin) }
    }

    /// For the log.
    private static func describe(_ origin: CheckOrigin) -> String {
        switch origin {
        case .automatic: return "automatic"
        case .dropdown: return "manual (dropdown)"
        case .settings: return "manual (Settings)"
        }
    }

    /// One check at a time. A development build never makes a request
    /// (FR-008); failures of an automatic check only reach the log (FR-007).
    private func runCheck(origin: CheckOrigin) async {
        let name = Self.describe(origin)
        guard !display.state.isInstallRunning else {
            if origin.isManual { log.append(source: "update", message: "\(name) check skipped: an install is running") }
            return
        }
        if let running = runningOrigin {
            if origin.isManual {
                let joined = running.joining(origin)
                runningOrigin = joined
                display = display.beginningCheck(origin: joined)
                log.append(source: "update", message: "\(name) check joined the running check")
            }
            return
        }
        let context = InstallEnvironment.current()
        guard UpdatePolicy.checksAllowed(context: context), let running = context.runningVersion else {
            display = display.markingDevelopmentBuild(origin: origin)
            log.append(source: "update", message: "\(name) check skipped, development build: \(context.logSummary)")
            return
        }
        runningOrigin = origin
        defer { runningOrigin = nil }
        // Only automatic checks move the schedule, so a manual check never
        // replaces the check 5 minutes after launch (FR-001).
        if origin == .automatic { lastCheck = Date() }
        display = display.beginningCheck(origin: origin)
        let source = InstallEnvironment.releaseSource
        log.append(source: "update", message: "\(name) check of \(source.owner)/\(source.repo): \(context.logSummary)")

        let client = UpdateClient(owner: source.owner, repo: source.repo, appVersion: running.description)
        let outcome: CheckOutcome
        do {
            let result = try await client.check(runningVersion: running)
            switch result {
            case .available(let release):
                let action = UpdatePolicy.action(context: context, release: release)
                outcome = .result(result, action: action)
                log.append(source: "update", message: "available \(release.version) (running \(running)), action \(Self.describe(action))")
            case .notNewer:
                outcome = .result(result, action: nil)
                log.append(source: "update", message: "up to date (running \(running))")
            case .ignored(let reason):
                outcome = .result(result, action: nil)
                log.append(source: "update", message: "latest release ignored: \(reason) (running \(running))")
            }
        } catch {
            let text = (error as? UpdateClientError)?.description ?? String(describing: error)
            outcome = .failure(text)
            log.append(source: "update", message: "\(name) check failed: \(text)")
        }
        // A check that joined meanwhile reports for the joined origin.
        display = display.applying(outcome, origin: runningOrigin ?? origin, at: Date())
    }

    /// The action and its reason, for the log (FR-021).
    static func describe(_ action: UpdateAction) -> String {
        switch action {
        case .install: return "install"
        case .homebrew: return "homebrew"
        case .download(let reason): return "download (\(reason.text))"
        case .retry(_, let reason): return "try again (\(reason.text))"
        }
    }

    // MARK: Actions

    /// "Release notes" and "Download" open the release page (FR-009).
    func openReleasePage(_ release: AvailableRelease) {
        log.append(source: "update", message: "release page of \(release.version) opened")
        NSWorkspace.shared.open(release.pageURL)
    }

    /// The release page after a failed install from the previous run, where
    /// the release itself is no longer known (FR-019).
    func openLatestReleasePage() {
        let source = InstallEnvironment.releaseSource
        let client = UpdateClient(owner: source.owner, repo: source.repo, appVersion: "")
        guard let url = client.latestReleasePageURL else { return }
        log.append(source: "update", message: "latest release page opened")
        NSWorkspace.shared.open(url)
    }

    /// The line's action button (FR-012).
    func perform(_ action: UpdateAction, release: AvailableRelease) {
        switch action {
        case .install, .retry:
            install()
        case .homebrew:
            copyHomebrewCommand()
        case .download:
            openReleasePage(release)
        }
    }

    // MARK: Homebrew (FR-013)

    /// How long the line confirms the copied command.
    static let commandCopiedDuration: TimeInterval = 8

    /// Puts `brew upgrade --cask agenttacho` on the clipboard and confirms it
    /// on the line with the hint that Homebrew may need longer. Never runs
    /// Homebrew, downloads or touches a file (FR-013, SC-006).
    func copyHomebrewCommand() {
        guard let copied = display.copyingHomebrewCommand(), let release = copied.state.release else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(UpdateState.homebrewCommand, forType: .string)
        display = copied
        log.append(source: "update", message: "Homebrew command copied for \(release.version)")
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.commandCopiedDuration))
            guard let self else { return }
            self.display = self.display.endingCommandCopied()
        }
    }

    // MARK: Install (FR-014 to FR-020)

    /// Starts the one-click install of the shown update. Only one install
    /// runs at a time; further clicks have no effect (FR-018).
    func install() {
        guard installTask == nil, let started = display.startingInstall(),
              let update = display.installableUpdate else { return }
        let release = update.release
        let target = update.target
        let context = InstallEnvironment.current()
        // The facts may have changed since the check (the app was moved, or
        // Homebrew now manages it): the line then offers the new action
        // instead of an Install that does nothing (FR-012).
        let action = UpdatePolicy.action(context: context, release: release)
        guard case .install = action else {
            log.append(source: "update", message: "install of \(release.version) not possible now: \(Self.describe(action))")
            display = display.changingAction(to: action)
            return
        }
        guard let running = context.runningVersion, let team = context.teamIdentifier,
              let requirement = UpdateVerification.designatedRequirement(bundleID: context.bundleIdentifier ?? "", team: team) else {
            log.append(source: "update", message: "install of \(release.version) not possible: running identity incomplete")
            display = display.failingInstall(.runningNotNotarized)
            return
        }
        display = started
        let installed = URL(fileURLWithPath: context.bundlePath)
        let bundleID = context.bundleIdentifier ?? ""
        log.append(source: "update", message: "install \(running) -> \(release.version) started: \(context.logSummary)")
        installTask = Task { [weak self] in
            await self?.runInstall(release: release, target: target, running: running, bundleID: bundleID,
                                   requirement: requirement, installed: installed)
            self?.installTask = nil
        }
    }

    /// "Cancel" while downloading or verifying: stops the download or the
    /// running tool, cleans up, and returns to the available update (FR-018).
    func cancelInstall() {
        guard display.state.isCancellable else { return }
        log.append(source: "update", message: "install cancelled by the user")
        installTask?.cancel()
        installer.cancel()
    }

    private func runInstall(release: AvailableRelease, target: DownloadTarget, running: ReleaseVersion, bundleID: String,
                            requirement: String, installed: URL) async {
        let installer = self.installer
        do {
            // Download (FR-014).
            do {
                try installer.prepareFolder()
            } catch {
                throw UpdateBlockReason.downloadFailed("the temporary folder could not be created")
            }
            let file = installer.downloadURL
            let source = InstallEnvironment.releaseSource
            let client = UpdateClient(owner: source.owner, repo: source.repo, appVersion: running.description)
            let progress = ProgressRelay { [weak self] fraction in self?.downloadProgressed(fraction) }
            let received: Int
            do {
                received = try await client.download(target, to: file) { progress.send($0) }
            } catch let error as UpdateClientError {
                throw UpdateBlockReason.forDownload(error)
            }
            log.append(source: "update", message: "downloaded \(received) bytes (release lists \(target.size))")

            // Verification, in the order of research R4 (FR-015, FR-016).
            display = display.withInstallStep(.verifying)
            let actual: String
            do {
                actual = try await Task.detached { try installer.sha256(of: file) }.value
            } catch {
                throw UpdateBlockReason.downloadFailed("the download could not be read")
            }
            let checksumMatches = UpdateVerification.sha256Matches(actualHex: actual, expectedHex: target.sha256)
            try check(checksumMatches: checksumMatches, step: "checksum")

            let dmgResult = try await verificationStep { try await installer.assess(path: file, type: "open") }
            let dmgAssessment = UpdateVerification.classifyAssessment(output: dmgResult.output, exitStatus: dmgResult.status)
            try check(checksumMatches: true, dmg: dmgAssessment, step: "disk image assessment (\(dmgAssessment))")

            // The checksum already matched, so an image hdiutil cannot mount
            // is a tool problem, not unexpected contents.
            try await verificationStep { try await installer.attach(dmg: file) }
            let entries: [DiskImageEntry]
            do {
                entries = try installer.entries(of: installer.mountPoint)
            } catch {
                throw UpdateBlockReason.unexpectedContents("the disk image could not be read")
            }
            let contents = DiskImageCheck.check(entries: entries, expectedBundleID: bundleID, expectedVersion: release.version)
            let appName = try verifiedAppName(contents)
            let app = installer.mountPoint.appendingPathComponent(appName, isDirectory: true)

            // Signature checks hash the whole bundle; off the main actor.
            let signatureValid = await Task.detached { installer.checkSignature(app: app, requirement: requirement) }.value
            try check(checksumMatches: true, dmg: dmgAssessment, contents: contents, signature: signatureValid, step: "signature and team")

            let appResult = try await verificationStep { try await installer.assess(path: app, type: "execute") }
            let appAssessment = UpdateVerification.classifyAssessment(output: appResult.output, exitStatus: appResult.status)
            try check(checksumMatches: true, dmg: dmgAssessment, contents: contents, signature: signatureValid,
                      app: appAssessment, step: "app assessment (\(appAssessment))")

            // Past this point there is no Cancel (FR-018).
            try Task.checkCancellation()
            display = display.withInstallStep(.installing)
            // The staged copy is verified again before the swap, so a copy
            // that cannot be made is a verification failure; nothing has been
            // replaced yet.
            let staged = try await verificationStep { try await installer.stage(app: app, besides: installed) }
            await installer.detach(mountPoint: installer.mountPoint)
            let stagedValid = await Task.detached { installer.checkSignature(app: staged, requirement: requirement) }.value
            let approved = UpdateVerification.allPassed(checksumMatches: checksumMatches, diskImageAssessment: dmgAssessment,
                                                        contents: contents, signatureValid: signatureValid,
                                                        appAssessment: appAssessment, stagedSignatureValid: stagedValid)
            guard approved else {
                try? FileManager.default.removeItem(at: staged.deletingLastPathComponent())
                throw UpdateVerification.verdict(checksumMatches: checksumMatches, diskImageAssessment: dmgAssessment,
                                                 contents: contents, signatureValid: signatureValid,
                                                 appAssessment: appAssessment, stagedSignatureValid: stagedValid)
                    ?? UpdateBlockReason.signatureMismatch
            }
            log.append(source: "update", message: "verified \(release.version): checksum, notarized disk image, contents, signature and team, notarized app, staged copy")

            // Replacement (FR-017). A marker covers an unexpected end
            // between the swap and the relaunch.
            installer.writeOutcome(UpdateOutcome(from: running.description, to: release.version.description,
                                                 result: .failed, reason: "the update was interrupted"))
            switch installer.swap(installed: installed, staged: staged) {
            case .failure(let reason):
                if case .previousVersionInTrash = reason {
                    // The app is gone from its place: whichever copy starts
                    // next reads and shows the reason (FR-017). Only the
                    // outcome stays in the update folder (FR-018).
                    if installer.isMounted() { await installer.detach(mountPoint: installer.mountPoint, force: true) }
                    installer.removeDownloadFiles()
                    installer.writeOutcome(UpdateOutcome(from: running.description, to: release.version.description,
                                                         result: .failed, reason: reason.text))
                    log.append(source: "update", message: "install of \(release.version) failed and the previous version could not be put back: \(reason.text)")
                    display = display.failingInstall(reason)
                    return
                }
                installer.removeOutcome()
                throw reason
            case .success(let trashed):
                log.append(source: "update", message: "replaced \(installed.path), previous version in the Trash at \(trashed?.path ?? "?")")
            }
            // The disk image is not needed any more; only the outcome stays
            // for the new version (FR-018, research R10).
            installer.removeDownloadFiles()
            installer.writeOutcome(UpdateOutcome(from: running.description, to: release.version.description,
                                                 result: .installed, reason: nil))
            log.append(source: "update", message: "relaunching as \(release.version)")
            do {
                try installer.relaunch(appPath: installed.path)
            } catch {
                // The new version is in place; it starts with the next launch.
                log.append(source: "update", message: "relaunch failed: \(error.localizedDescription); start AgentTacho again to use \(release.version)")
                display = display.requiringRestart()
            }
        } catch is CancellationError {
            if installer.isMounted() { await installer.detach(mountPoint: installer.mountPoint, force: true) }
            installer.removeFolder()
            log.append(source: "update", message: "install of \(release.version) cancelled, nothing changed")
            display = display.cancellingInstall()
        } catch {
            if installer.isMounted() { await installer.detach(mountPoint: installer.mountPoint, force: true) }
            installer.removeFolder()
            // Every step maps its own errors; this is the last resort. The
            // swap reports its failures itself, so nothing was replaced.
            let reason = (error as? UpdateBlockReason) ?? .verificationFailed(Self.text(of: error))
            if Task.isCancelled, display.state.isCancellable {
                log.append(source: "update", message: "install of \(release.version) cancelled, nothing changed")
                display = display.cancellingInstall()
                return
            }
            log.append(source: "update", message: "install of \(release.version) failed, nothing replaced: \(reason.text)")
            display = display.failingInstall(reason)
        }
    }

    /// Runs a verification tool step. A tool that cannot be launched or run
    /// (spctl, hdiutil, ditto) is a verification failure, never a replacement
    /// failure: nothing has been replaced (FR-016, FR-019).
    private func verificationStep<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as CancellationError {
            throw error
        } catch {
            let reason = UpdateBlockReason.verificationFailed(Self.text(of: error))
            log.append(source: "update", message: "verification step could not run: \(reason.text)")
            throw reason
        }
    }

    /// The short text of a tool or file error.
    private static func text(of error: Error) -> String {
        if let error = error as? UpdateInstaller.InstallerError { return error.description }
        return error.localizedDescription
    }

    /// The app name from the contents check, or its reason (FR-016).
    private func verifiedAppName(_ contents: Result<String, UpdateBlockReason>) throws -> String {
        switch contents {
        case .success(let name):
            log.append(source: "update", message: "verified contents")
            try Task.checkCancellation()
            return name
        case .failure(let reason):
            log.append(source: "update", message: "verification failed at contents: \(reason.text)")
            throw reason
        }
    }

    /// Throws the verdict's reason when a step failed (SC-003).
    private func check(checksumMatches: Bool, dmg: AssessmentResult? = nil,
                       contents: Result<String, UpdateBlockReason>? = nil, signature: Bool? = nil,
                       app: AssessmentResult? = nil, step: String) throws {
        if let reason = UpdateVerification.verdict(checksumMatches: checksumMatches, diskImageAssessment: dmg, contents: contents,
                                                   signatureValid: signature, appAssessment: app, stagedSignatureValid: nil) {
            log.append(source: "update", message: "verification failed at \(step): \(reason.text)")
            throw reason
        }
        log.append(source: "update", message: "verified \(step)")
        try Task.checkCancellation()
    }

    private func downloadProgressed(_ fraction: Double) {
        guard case .downloading(_, let previous) = display.state else { return }
        // Whole percent steps are enough for the line.
        guard Int(fraction * 100) != Int(previous * 100) else { return }
        display = display.withInstallStep(.downloading(fraction: fraction))
    }

    /// Reads, logs and deletes the outcome of a previous run's install and
    /// removes leftovers of an interrupted one (FR-017, FR-018, research R10).
    private func cleanUpAfterLaunch() async {
        guard let outcome = await installer.cleanUpAfterLaunch() else { return }
        switch outcome.result {
        case .installed:
            log.append(source: "update", message: "updated from \(outcome.from) to \(outcome.to)")
        case .failed:
            let reason = outcome.reason ?? "unknown reason"
            log.append(source: "update", message: "update from \(outcome.from) to \(outcome.to) failed: \(reason)")
            display = display.showingInstallFailure(reason)
        }
    }
}

/// Hands download progress from the network task to the main actor.
private final class ProgressRelay: @unchecked Sendable {
    private let handler: @MainActor (Double) -> Void

    init(_ handler: @escaping @MainActor (Double) -> Void) {
        self.handler = handler
    }

    func send(_ fraction: Double) {
        let handler = self.handler
        Task { @MainActor in handler(fraction) }
    }
}
