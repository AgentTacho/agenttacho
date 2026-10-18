import Foundation

/// What the update line and Settings > About show (spec 013 FR-003, FR-009,
/// FR-011, FR-013, FR-018; contracts/update-ui.md).
public enum UpdateState: Equatable, Sendable {
    case notCheckedYet
    /// A development build never checks (FR-008).
    case developmentBuild
    /// The demo build never checks and never downloads (spec 024 FR-007).
    case demoBuild
    /// A check started by the user runs (an automatic check changes
    /// nothing while it runs).
    case checking
    case upToDate(checkedAt: Date)
    /// A manual check failed; the short error (FR-003).
    case checkFailed(String)
    case available(AvailableRelease, UpdateAction)
    /// The Homebrew command is on the clipboard (FR-013).
    case commandCopied(AvailableRelease)
    case downloading(AvailableRelease, fraction: Double)
    case verifying(AvailableRelease)
    case installing(AvailableRelease)
    /// The replacement of a previous run failed; read from the outcome file
    /// at launch (FR-017).
    case installFailed(String)
    /// The new version is in place but could not be started; the user quits
    /// and opens AgentTacho again (FR-017, Edge Cases).
    case restartRequired(AvailableRelease)

    public static let homebrewCommand = "brew upgrade --cask agenttacho"

    /// The line text without the Download reason.
    public var title: String {
        switch self {
        case .notCheckedYet: return "Not checked yet"
        case .developmentBuild: return "Development build: updates are not checked"
        case .demoBuild: return "Demo build: updates are off"
        case .checking: return "Checking for updates\u{2026}"
        case .upToDate: return "AgentTacho is up to date"
        case .checkFailed(let error): return "Could not check for updates: \(error)"
        case .available(let release, _): return "AgentTacho \(release.version) available"
        case .commandCopied:
            return "Copied \"\(Self.homebrewCommand)\". If Homebrew finds nothing new yet, try again later."
        case .downloading(let release, let fraction):
            let percent = Int((min(max(fraction, 0), 1) * 100).rounded(.down))
            return "Downloading AgentTacho \(release.version)\u{2026} \(percent)%"
        case .verifying(let release): return "Verifying AgentTacho \(release.version)\u{2026}"
        case .installing(let release): return "Installing AgentTacho \(release.version)\u{2026}"
        case .installFailed(let reason): return "Could not install the update: \(reason)"
        case .restartRequired(let release):
            return "AgentTacho \(release.version) is installed; quit AgentTacho and open it again to use it"
        }
    }

    /// Why Install is not offered, for `.available` with a Download or Try
    /// again action.
    public var reason: String? {
        if case .available(_, let action) = self { return action.reason?.text }
        return nil
    }

    /// Title and reason joined by a middle dot (contracts/update-ui.md);
    /// the one text the update line shows.
    public var lineText: String {
        guard let reason else { return title }
        return "\(title) \u{00B7} \(reason)"
    }

    /// Settings > About wording: "Up to date (checked HH:mm)" with the time
    /// formatted by the caller; everything else as on the line, reason
    /// included (FR-011).
    public func settingsText(formatTime: (Date) -> String) -> String {
        if case .upToDate(let date) = self { return "Up to date (checked \(formatTime(date)))" }
        return lineText
    }

    /// The release the state is about, if any.
    public var release: AvailableRelease? {
        switch self {
        case .available(let release, _), .commandCopied(let release), .downloading(let release, _),
             .verifying(let release), .installing(let release), .restartRequired(let release):
            return release
        default:
            return nil
        }
    }

    /// Downloading, verifying or installing: further Install clicks have no
    /// effect (FR-018).
    public var isInstallRunning: Bool {
        switch self {
        case .downloading, .verifying, .installing: return true
        default: return false
        }
    }

    /// Cancel is offered while downloading and verifying (FR-018).
    public var isCancellable: Bool {
        switch self {
        case .downloading, .verifying: return true
        default: return false
        }
    }

    /// States that appear on the line only right after a check from the
    /// dropdown (or a launch that found a failed install) until the dropdown
    /// closes (FR-003).
    var isTransient: Bool {
        switch self {
        case .checking, .upToDate, .checkFailed, .developmentBuild, .demoBuild, .installFailed: return true
        default: return false
        }
    }
}

/// A newer release known from the last successful check, with its action
/// (spec 013 FR-007a).
public struct KnownUpdate: Equatable, Sendable {
    public var release: AvailableRelease
    public var action: UpdateAction

    public init(release: AvailableRelease, action: UpdateAction) {
        self.release = release
        self.action = action
    }
}

/// Where a check was started (spec 013 FR-003): the schedule, the
/// dropdown's gear menu, or Settings > About. Only a check from the dropdown
/// puts its transient result ("Checking", "up to date", an error) on the
/// dropdown line; a check from Settings shows its result in Settings only, so
/// it never surprises the user on the line hours later.
public enum CheckOrigin: Equatable, Sendable {
    case automatic
    case dropdown
    case settings

    /// Started by the user: its failure is shown, and "Checking" with it
    /// (FR-003, FR-007).
    public var isManual: Bool { self != .automatic }

    /// Its transient result appears on the dropdown line until the dropdown
    /// closes (FR-003).
    public var showsResultOnLine: Bool { self == .dropdown }

    /// A check started while another one runs joins it; the joined check
    /// reports like the more visible of the two (dropdown, then Settings).
    public func joining(_ other: CheckOrigin) -> CheckOrigin {
        if self == .dropdown || other == .dropdown { return .dropdown }
        if self == .settings || other == .settings { return .settings }
        return .automatic
    }
}

/// The result of one check as the updater hands it to `UpdateDisplay`
/// (spec 013 FR-003, FR-007).
public enum CheckOutcome: Equatable, Sendable {
    /// `action` is nil unless the result is `.available`.
    case result(ReleaseCheckResult, action: UpdateAction?)
    /// The short error of a failed check.
    case failure(String)
}

/// What Settings shows (`state`) and what the dropdown line shows
/// (`lineState`), with the transition rules of spec 013 FR-003, FR-007,
/// FR-007a and data-model.md UpdateState.
public struct UpdateDisplay: Equatable, Sendable {
    public var state: UpdateState
    /// Set by a check from the dropdown (and a launch that found a failed
    /// install), cleared when the dropdown closes (FR-003).
    public var lineShowsTransient: Bool
    /// The newer release from the last successful check; it stays known
    /// while later checks fail (FR-007a).
    public var known: KnownUpdate?

    public init(state: UpdateState = .notCheckedYet, lineShowsTransient: Bool = false, known: KnownUpdate? = nil) {
        self.state = state
        self.lineShowsTransient = lineShowsTransient
        self.known = known
    }

    /// The state the dropdown line shows; nil hides the line. A transient
    /// state shows only while `lineShowsTransient`; otherwise a known update
    /// stays on the line (FR-007a).
    public var lineState: UpdateState? {
        if !state.isTransient && state != .notCheckedYet { return state }
        if state.isTransient && lineShowsTransient { return state }
        return known.map { .available($0.release, $0.action) }
    }

    /// The known update Settings shows next to a state that does not carry
    /// it (a failed manual check, or a check in progress), so the version,
    /// action and release notes stay visible there (FR-007a, FR-011).
    public var settingsKnownUpdate: KnownUpdate? {
        guard let known, state.release == nil else { return nil }
        return known
    }

    /// A manual check shows "Checking for updates…" (also in place of
    /// the copied Homebrew command), on the line only when started from the
    /// dropdown; an automatic check changes nothing while it runs. Ignored
    /// during an install and while a restart is required, because the
    /// running old process would report the installed version as new
    /// (FR-003, FR-017).
    public func beginningCheck(origin: CheckOrigin) -> UpdateDisplay {
        guard origin.isManual, !state.isInstallRunning else { return self }
        if case .restartRequired = state { return self }
        var next = self
        next.state = .checking
        next.lineShowsTransient = origin.showsResultOnLine
        return next
    }

    /// Applies a finished check (FR-003, FR-007, FR-007a).
    public func applying(_ outcome: CheckOutcome, origin: CheckOrigin, at date: Date) -> UpdateDisplay {
        if state.isInstallRunning { return self }
        // The installed new version waits for a restart; checks of the old
        // running version have nothing to add (FR-017).
        if case .restartRequired = state { return self }
        var next = self
        // The automatic check after launch keeps a previous run's failure on
        // the line until the dropdown closes; it only refreshes the known
        // update (contracts/update-ui.md, FR-017).
        if case .installFailed = state, !origin.isManual {
            switch outcome {
            case .result(.available(let release), let action):
                next.known = KnownUpdate(release: release, action: action ?? Self.fallbackAction(release))
            case .result(.notNewer, _), .result(.ignored, _):
                next.known = nil
            case .failure:
                break
            }
            return next
        }
        // A newer release keeps the copied confirmation on the line; any
        // other result replaces it as usual (FR-003, FR-007a).
        if case .commandCopied = state, case .result(.available(let release), let action) = outcome {
            let known = KnownUpdate(release: release, action: action ?? Self.fallbackAction(release))
            next.known = known
            next.state = .commandCopied(release)
            return next
        }
        switch outcome {
        case .result(.available(let release), let action):
            let known = KnownUpdate(release: release, action: action ?? Self.fallbackAction(release))
            next.known = known
            next.state = .available(known.release, known.action)
            next.lineShowsTransient = false
        case .result(.notNewer, _), .result(.ignored, _):
            next.known = nil
            next.state = .upToDate(checkedAt: date)
            next.lineShowsTransient = origin.showsResultOnLine
        case .failure(let error):
            guard origin.isManual else {
                // An automatic failure never shows anything (FR-007); a known
                // update stays (FR-007a). It completes a check, so an earlier
                // manual result leaves the line (FR-003).
                if case .checking = state, let known { next.state = .available(known.release, known.action) }
                next.lineShowsTransient = false
                return next
            }
            next.state = .checkFailed(error)
            next.lineShowsTransient = origin.showsResultOnLine
        }
        return next
    }

    /// A development build: the state for Settings, and on the line only
    /// after "Check for Updates…" from the dropdown (FR-003, FR-008).
    public func markingDevelopmentBuild(origin: CheckOrigin) -> UpdateDisplay {
        markingChecksOff(.developmentBuild, origin: origin)
    }

    /// The demo build: like a development build, on the line only after
    /// "Check for Updates…" from the dropdown (spec 024 FR-007).
    public func markingDemoBuild(origin: CheckOrigin) -> UpdateDisplay {
        markingChecksOff(.demoBuild, origin: origin)
    }

    /// A build that never checks: its state for Settings, and on the line
    /// only after a check from the dropdown.
    private func markingChecksOff(_ state: UpdateState, origin: CheckOrigin) -> UpdateDisplay {
        var next = self
        next.state = state
        next.lineShowsTransient = origin.showsResultOnLine
        return next
    }

    /// Shows the failure of a previous run's install on the line (FR-017).
    public func showingInstallFailure(_ reason: String) -> UpdateDisplay {
        var next = self
        next.state = .installFailed(reason)
        next.lineShowsTransient = true
        return next
    }

    /// The new version was swapped in but could not be started (FR-017):
    /// the line says it is installed and asks for a restart; nothing else is
    /// offered.
    public func requiringRestart() -> UpdateDisplay {
        guard let release = state.release ?? known?.release else { return self }
        var next = self
        next.known = nil
        next.state = .restartRequired(release)
        next.lineShowsTransient = false
        return next
    }

    /// "Upgrade with Homebrew" clicked: the line confirms the copied command
    /// (FR-013). Nil unless a Homebrew update is shown.
    public func copyingHomebrewCommand() -> UpdateDisplay? {
        guard case .available(let release, .homebrew) = state else { return nil }
        var next = self
        next.state = .commandCopied(release)
        return next
    }

    /// The confirmation ends: back to the (possibly newer) update.
    public func endingCommandCopied() -> UpdateDisplay {
        guard case .commandCopied(let release) = state else { return self }
        var next = self
        next.state = .available(release, known?.action ?? .homebrew)
        return next
    }

    /// A step of a running install (FR-018).
    public enum InstallStep: Equatable, Sendable {
        case downloading(fraction: Double)
        case verifying
        case installing
    }

    /// The update an Install click refers to: the shown available update,
    /// or the known one while the state carries no release (a manual check
    /// running or failed), as the line and Settings show it (FR-007a).
    public var installableUpdate: (release: AvailableRelease, target: DownloadTarget)? {
        if case .available(let release, let action) = state, let target = action.installTarget { return (release, target) }
        guard state.release == nil, let known, let target = known.action.installTarget else { return nil }
        return (known.release, target)
    }

    /// Install (or Try again) clicked: only for an update with that action
    /// and no install running (FR-018); nil otherwise.
    public func startingInstall() -> UpdateDisplay? {
        guard let release = installableUpdate?.release else { return nil }
        var next = self
        next.state = .downloading(release, fraction: 0)
        next.lineShowsTransient = false
        return next
    }

    /// Install clicked, but the installation's action changed since the
    /// check (Homebrew now manages the app, or it was moved; FR-012): the
    /// line and Settings show the new action, so the button and what it does
    /// agree. The new action is not performed for the user, who asked for an
    /// install; its own button is there now. Unchanged when no update is
    /// shown or an install runs.
    public func changingAction(to action: UpdateAction) -> UpdateDisplay {
        guard !state.isInstallRunning, let release = state.release ?? known?.release else { return self }
        var next = self
        let known = KnownUpdate(release: release, action: action)
        next.known = known
        next.state = .available(release, known.action)
        next.lineShowsTransient = false
        return next
    }

    /// Moves a running install to its next step; unchanged when no install
    /// runs.
    public func withInstallStep(_ step: InstallStep) -> UpdateDisplay {
        guard state.isInstallRunning, let release = state.release else { return self }
        var next = self
        switch step {
        case .downloading(let fraction): next.state = .downloading(release, fraction: fraction)
        case .verifying: next.state = .verifying(release)
        case .installing: next.state = .installing(release)
        }
        return next
    }

    /// Cancel: back to the available update, nothing changed (FR-018). A
    /// cancelled Try again offers Install again, without the old reason.
    public func cancellingInstall() -> UpdateDisplay {
        guard let release = state.release ?? known?.release else { return self }
        var next = self
        var action = known?.action ?? .download(.releaseInfoIncomplete)
        if case .retry(let target, _) = action {
            action = .install(target)
            next.known?.action = action
        }
        next.state = .available(release, action)
        return next
    }

    /// A failed install: the line shows the reason and offers the release
    /// page (FR-019); a failure that may pass on a second try also offers
    /// "Try again" (US2 scenario 4).
    public func failingInstall(_ reason: UpdateBlockReason) -> UpdateDisplay {
        guard let release = state.release ?? known?.release else { return self }
        var next = self
        let target = known?.release == release ? known?.action.installTarget : nil
        let action: UpdateAction
        if reason.allowsRetry, let target {
            action = .retry(target, reason)
        } else {
            action = .download(reason)
        }
        let known = KnownUpdate(release: release, action: action)
        next.known = known
        next.state = .available(release, known.action)
        next.lineShowsTransient = false
        return next
    }

    /// The dropdown closed: transient states leave the line, Settings keeps
    /// them until the next check (FR-003).
    public func dismissingTransient() -> UpdateDisplay {
        var next = self
        next.lineShowsTransient = false
        return next
    }

    private static func fallbackAction(_ release: AvailableRelease) -> UpdateAction {
        .download(release.infoProblem ?? .releaseInfoIncomplete)
    }
}
