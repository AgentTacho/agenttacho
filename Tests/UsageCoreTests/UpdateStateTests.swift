import Foundation
import Testing
@testable import UsageCore

/// spec 013 FR-003, FR-007, FR-007a, FR-009, FR-013, FR-018;
/// contracts/update-ui.md. Checks start only from the schedule or Settings >
/// About since spec 025 FR-028; the line shows a transient state only for a
/// failed install found at launch.
@Suite struct UpdateStateTests {
    static let page = URL(string: "https://github.com/AgentTacho/agenttacho/releases/tag/v0.3.0")!
    static let target = DownloadTarget(url: URL(string: "https://github.com/AgentTacho/agenttacho/releases/download/v0.3.0/AgentTacho-0.3.0.dmg")!,
                                       size: 1, sha256: String(repeating: "a", count: 64))

    static func release(_ minor: Int = 3) -> AvailableRelease {
        AvailableRelease(version: ReleaseVersion(major: 0, minor: minor, patch: 0),
                         pageURL: page, download: target, infoProblem: nil)
    }

    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func availableOutcome(_ minor: Int = 3, action: UpdateAction = .install(target)) -> CheckOutcome {
        .result(.available(release(minor)), action: action)
    }

    // MARK: Texts

    @Test func lineTexts() {
        let r = Self.release()
        #expect(UpdateState.available(r, .install(Self.target)).lineText == "AgentTacho 0.3.0 available")
        #expect(UpdateState.available(r, .homebrew).lineText == "AgentTacho 0.3.0 available")
        let download = UpdateState.available(r, .download(.notWritable))
        #expect(download.title == "AgentTacho 0.3.0 available")
        #expect(download.reason == "AgentTacho cannot replace itself in this folder")
        #expect(download.lineText == "AgentTacho 0.3.0 available \u{00B7} AgentTacho cannot replace itself in this folder")
        #expect(UpdateState.checking.lineText == "Checking for updates\u{2026}")
        #expect(UpdateState.upToDate(checkedAt: Self.now).lineText == "AgentTacho is up to date")
        #expect(UpdateState.checkFailed("offline").lineText == "Could not check for updates: offline")
        #expect(UpdateState.developmentBuild.lineText == "Development build: updates are not checked")
        #expect(UpdateState.verifying(r).lineText == "Verifying AgentTacho 0.3.0\u{2026}")
        #expect(UpdateState.installing(r).lineText == "Installing AgentTacho 0.3.0\u{2026}")
        #expect(UpdateState.installFailed("disk full").lineText == "Could not install the update: disk full")
        #expect(UpdateState.notCheckedYet.lineText == "Not checked yet")
    }

    /// The demo build never checks; it behaves like a development build on
    /// the line (spec 024 FR-007).
    @Test func demoBuildSaysUpdatesAreOff() {
        #expect(UpdateState.demoBuild.title == "Demo build: updates are off")
        #expect(UpdateState.demoBuild.lineText == "Demo build: updates are off")
        #expect(UpdateDisplay(state: .demoBuild).lineState == nil)
        #expect(UpdateDisplay(state: .demoBuild, lineShowsTransient: true).lineState == .demoBuild)
        let demo = UpdateDisplay().markingDemoBuild()
        #expect(demo.state == .demoBuild)
        #expect(demo.lineState == nil)
    }

    @Test func downloadingShowsWholePercent() {
        let r = Self.release()
        #expect(UpdateState.downloading(r, fraction: 0.426).lineText == "Downloading AgentTacho 0.3.0\u{2026} 42%")
        #expect(UpdateState.downloading(r, fraction: 0).lineText == "Downloading AgentTacho 0.3.0\u{2026} 0%")
        #expect(UpdateState.downloading(r, fraction: 1.7).lineText == "Downloading AgentTacho 0.3.0\u{2026} 100%")
        #expect(UpdateState.downloading(r, fraction: -1).lineText == "Downloading AgentTacho 0.3.0\u{2026} 0%")
    }

    @Test func commandCopiedIncludesTheHomebrewHint() {
        let text = UpdateState.commandCopied(Self.release()).lineText
        #expect(text == "Copied \"brew upgrade --cask agenttacho\". If Homebrew finds nothing new yet, try again later.")
    }

    @Test func settingsTexts() {
        let format: (Date) -> String = { _ in "09:41" }
        #expect(UpdateState.notCheckedYet.settingsText(formatTime: format) == "Not checked yet")
        #expect(UpdateState.upToDate(checkedAt: Self.now).settingsText(formatTime: format) == "Up to date (checked 09:41)")
        #expect(UpdateState.developmentBuild.settingsText(formatTime: format) == "Development build: updates are not checked")
        #expect(UpdateState.checking.settingsText(formatTime: format) == "Checking for updates\u{2026}")
        #expect(UpdateState.available(Self.release(), .homebrew).settingsText(formatTime: format) == "AgentTacho 0.3.0 available")
        // Settings shows the Download reason like the line, from one source.
        let download = UpdateState.available(Self.release(), .download(.notWritable))
        #expect(download.settingsText(formatTime: format) == download.lineText)
    }

    @Test func installRunningStates() {
        let r = Self.release()
        #expect(UpdateState.downloading(r, fraction: 0.1).isInstallRunning)
        #expect(UpdateState.verifying(r).isInstallRunning)
        #expect(UpdateState.installing(r).isInstallRunning)
        #expect(!UpdateState.available(r, .install(Self.target)).isInstallRunning)
        #expect(UpdateState.downloading(r, fraction: 0.1).isCancellable)
        #expect(UpdateState.verifying(r).isCancellable)
        #expect(!UpdateState.installing(r).isCancellable)
    }

    // MARK: Line visibility

    @Test func hiddenStates() {
        #expect(UpdateDisplay().lineState == nil)
        #expect(UpdateDisplay(state: .checking).lineState == nil)
        #expect(UpdateDisplay(state: .upToDate(checkedAt: Self.now)).lineState == nil)
        #expect(UpdateDisplay(state: .developmentBuild).lineState == nil)
    }

    @Test func persistentStatesAlwaysShow() {
        let r = Self.release()
        for state in [UpdateState.available(r, .homebrew), .commandCopied(r), .downloading(r, fraction: 0.5), .verifying(r), .installing(r)] {
            #expect(UpdateDisplay(state: state).lineState == state)
        }
    }

    // MARK: Applying check outcomes

    @Test func availableResultShowsTheLine() {
        let display = UpdateDisplay().applying(Self.availableOutcome(), origin: .automatic, at: Self.now)
        #expect(display.state == .available(Self.release(), .install(Self.target)))
        #expect(display.lineState == display.state)
        #expect(display.known == KnownUpdate(release: Self.release(), action: .install(Self.target)))
    }

    @Test func failedAutomaticCheckKeepsAKnownUpdate() {
        let shown = UpdateDisplay().applying(Self.availableOutcome(), origin: .automatic, at: Self.now)
        let after = shown.applying(.failure("offline"), origin: .automatic, at: Self.now)
        #expect(after == shown)
    }

    @Test func failedAutomaticCheckRecordsNothing() {
        let after = UpdateDisplay().applying(.failure("offline"), origin: .automatic, at: Self.now)
        #expect(after.state == .notCheckedYet)
        #expect(after.lineState == nil)
    }

    /// FR-007a, FR-011: Settings keeps the known update next to a failed
    /// manual check's error.
    @Test func settingsKeepsTheKnownUpdateAfterAFailedManualCheck() {
        let shown = UpdateDisplay().applying(Self.availableOutcome(), origin: .automatic, at: Self.now)
        #expect(shown.settingsKnownUpdate == nil)
        let failed = shown.beginningCheck(origin: .settings).applying(.failure("offline"), origin: .settings, at: Self.now)
        #expect(failed.state == .checkFailed("offline"))
        #expect(failed.settingsKnownUpdate == KnownUpdate(release: Self.release(), action: .install(Self.target)))
        let upToDate = failed.applying(.result(.notNewer, action: nil), origin: .settings, at: Self.now)
        #expect(upToDate.settingsKnownUpdate == nil)
    }

    @Test func notNewerClearsAvailable() {
        let shown = UpdateDisplay().applying(Self.availableOutcome(), origin: .automatic, at: Self.now)
        let later = shown.applying(.result(.notNewer, action: nil), origin: .automatic, at: Self.now)
        #expect(later.state == .upToDate(checkedAt: Self.now))
        #expect(later.known == nil)
        #expect(later.lineState == nil)
        let ignored = shown.applying(.result(.ignored(.noReleaseInfo), action: nil), origin: .automatic, at: Self.now)
        #expect(ignored.known == nil)
        #expect(ignored.lineState == nil)
    }

    @Test func newerReleaseReplacesAnOlderOne() {
        let shown = UpdateDisplay().applying(Self.availableOutcome(3), origin: .automatic, at: Self.now)
        let newer = shown.applying(Self.availableOutcome(4, action: .homebrew), origin: .automatic, at: Self.now)
        #expect(newer.state == .available(Self.release(4), .homebrew))
    }

    @Test func resultsDuringAnInstallAreIgnored() {
        let r = Self.release()
        for state in [UpdateState.downloading(r, fraction: 0.3), .verifying(r), .installing(r)] {
            let display = UpdateDisplay(state: state, known: KnownUpdate(release: r, action: .install(Self.target)))
            #expect(display.applying(Self.availableOutcome(4), origin: .automatic, at: Self.now) == display)
            #expect(display.applying(.result(.notNewer, action: nil), origin: .settings, at: Self.now) == display)
            #expect(display.applying(.failure("x"), origin: .settings, at: Self.now) == display)
            #expect(display.beginningCheck(origin: .settings) == display)
        }
    }

    /// A newer release keeps the copied confirmation; no newer release ends
    /// it and clears the update (FR-007a); an automatic failure changes
    /// nothing (FR-007).
    @Test func resultsDuringCommandCopied() {
        let r = Self.release()
        let display = UpdateDisplay(state: .commandCopied(r), known: KnownUpdate(release: r, action: .homebrew))
        let newer = display.applying(Self.availableOutcome(4, action: .homebrew), origin: .automatic, at: Self.now)
        #expect(newer.state == .commandCopied(Self.release(4)))
        #expect(newer.known?.release == Self.release(4))
        let current = display.applying(.result(.notNewer, action: nil), origin: .automatic, at: Self.now)
        #expect(current.state == .upToDate(checkedAt: Self.now))
        #expect(current.known == nil)
        #expect(current.lineState == nil)
        #expect(current.endingCommandCopied() == current)
        #expect(display.applying(.failure("x"), origin: .automatic, at: Self.now) == display)
    }

    /// FR-003: a manual check during the copied confirmation shows its
    /// progress and its result in Settings; the line goes back to the known
    /// update.
    @Test func manualCheckDuringCommandCopiedShowsItsResultInSettings() {
        let r = Self.release()
        let display = UpdateDisplay(state: .commandCopied(r), known: KnownUpdate(release: r, action: .homebrew))
        let checking = display.beginningCheck(origin: .settings)
        #expect(checking.state == .checking)
        #expect(checking.lineState == .available(r, .homebrew))
        let failed = checking.applying(.failure("offline"), origin: .settings, at: Self.now)
        #expect(failed.state == .checkFailed("offline"))
        #expect(failed.lineState == .available(r, .homebrew))
    }

    @Test func automaticCheckDoesNotChangeTheDisplayWhileItRuns() {
        let shown = UpdateDisplay().applying(Self.availableOutcome(), origin: .automatic, at: Self.now)
        #expect(shown.beginningCheck(origin: .automatic) == shown)
        #expect(UpdateDisplay().beginningCheck(origin: .automatic) == UpdateDisplay())
    }

    // MARK: Check origin (FR-003)

    /// A check started from Settings > About shows its result in Settings
    /// only; the dropdown line never shows it, now or when the dropdown
    /// opens later.
    @Test func settingsCheckStaysOffTheLine() {
        let checking = UpdateDisplay().beginningCheck(origin: .settings)
        #expect(checking.state == .checking)
        #expect(checking.lineState == nil)
        let upToDate = checking.applying(.result(.notNewer, action: nil), origin: .settings, at: Self.now)
        #expect(upToDate.state == .upToDate(checkedAt: Self.now))
        #expect(upToDate.lineState == nil)
        let failed = UpdateDisplay().beginningCheck(origin: .settings).applying(.failure("offline"), origin: .settings, at: Self.now)
        #expect(failed.state == .checkFailed("offline"))
        #expect(failed.lineState == nil)
        let development = UpdateDisplay().markingDevelopmentBuild()
        #expect(development.state == .developmentBuild)
        #expect(development.lineState == nil)
    }

    /// A failed check from Settings keeps a known update on the line and
    /// next to the error in Settings (FR-007a).
    @Test func failedSettingsCheckKeepsTheKnownUpdateOnTheLine() {
        let shown = UpdateDisplay().applying(Self.availableOutcome(), origin: .automatic, at: Self.now)
        let failed = shown.beginningCheck(origin: .settings).applying(.failure("offline"), origin: .settings, at: Self.now)
        #expect(failed.lineState == .available(Self.release(), .install(Self.target)))
        #expect(failed.settingsKnownUpdate == shown.known)
    }

    /// A check from Settings ends a failed install found at launch on the
    /// line; Settings shows the check instead.
    @Test func settingsCheckEndsTheLaunchFailureOnTheLine() {
        let failed = UpdateDisplay().showingInstallFailure("disk full")
        #expect(failed.lineState == .installFailed("disk full"))
        let checking = failed.beginningCheck(origin: .settings)
        #expect(checking.state == .checking)
        #expect(checking.lineState == nil)
    }

    /// A Settings check that joins an automatic one makes it manual.
    @Test func originsJoinToTheManualOne() {
        #expect(CheckOrigin.automatic.joining(.settings) == .settings)
        #expect(CheckOrigin.settings.joining(.automatic) == .settings)
        #expect(CheckOrigin.settings.joining(.settings) == .settings)
        #expect(CheckOrigin.automatic.joining(.automatic) == .automatic)
        #expect(!CheckOrigin.automatic.isManual)
        #expect(CheckOrigin.settings.isManual)
    }

    // MARK: Install transitions (FR-017 to FR-019)

    @Test func installStartsOnlyFromAnInstallAction() {
        let shown = UpdateDisplay().applying(Self.availableOutcome(), origin: .automatic, at: Self.now)
        #expect(shown.startingInstall()?.state == .downloading(Self.release(), fraction: 0))
        let homebrew = UpdateDisplay().applying(Self.availableOutcome(action: .homebrew), origin: .automatic, at: Self.now)
        #expect(homebrew.startingInstall() == nil)
        let running = UpdateDisplay(state: .verifying(Self.release()), known: shown.known)
        #expect(running.startingInstall() == nil)
    }

    /// The line and Settings show the known update after a failed manual
    /// check; its Install must still start (FR-007a, FR-018).
    @Test func installStartsFromTheKnownUpdateAfterAFailedManualCheck() {
        let shown = UpdateDisplay().applying(Self.availableOutcome(), origin: .automatic, at: Self.now)
        let failed = shown.beginningCheck(origin: .settings).applying(.failure("offline"), origin: .settings, at: Self.now)
        #expect(failed.startingInstall()?.state == .downloading(Self.release(), fraction: 0))
        let checking = shown.beginningCheck(origin: .settings)
        #expect(checking.startingInstall()?.state == .downloading(Self.release(), fraction: 0))
        let installFailedEarlier = UpdateDisplay(state: .installFailed("x"), known: shown.known)
        #expect(installFailedEarlier.startingInstall() != nil)
    }

    @Test func installProgressStepsKeepTheRelease() {
        let downloading = UpdateDisplay().applying(Self.availableOutcome(), origin: .automatic, at: Self.now).startingInstall()!
        #expect(downloading.withInstallStep(.downloading(fraction: 0.5)).state == .downloading(Self.release(), fraction: 0.5))
        #expect(downloading.withInstallStep(.verifying).state == .verifying(Self.release()))
        #expect(downloading.withInstallStep(.installing).state == .installing(Self.release()))
        #expect(UpdateDisplay().withInstallStep(.verifying) == UpdateDisplay())
    }

    @Test func cancelReturnsToAvailable() {
        let shown = UpdateDisplay().applying(Self.availableOutcome(), origin: .automatic, at: Self.now)
        let cancelled = shown.startingInstall()!.withInstallStep(.verifying).cancellingInstall()
        #expect(cancelled.state == .available(Self.release(), .install(Self.target)))
    }

    /// US2 scenario 4: a failed download offers to try again, with the
    /// reason, next to the release notes; Try again starts the install.
    @Test(arguments: [UpdateBlockReason.downloadFailed("timed out"), .gatekeeperUnavailable])
    func retryableFailureOffersTryAgain(_ reason: UpdateBlockReason) {
        let shown = UpdateDisplay().applying(Self.availableOutcome(), origin: .automatic, at: Self.now)
        let failed = shown.startingInstall()!.withInstallStep(.verifying).failingInstall(reason)
        #expect(failed.state == .available(Self.release(), .retry(Self.target, reason)))
        #expect(failed.lineState?.lineText == "AgentTacho 0.3.0 available \u{00B7} \(reason.text)")
        #expect(failed.startingInstall()?.state == .downloading(Self.release(), fraction: 0))
        let again = failed.startingInstall()!.failingInstall(reason)
        #expect(again.state == .available(Self.release(), .retry(Self.target, reason)))
    }

    /// FR-018: cancelling a Try again returns to the plain available update.
    @Test func cancellingATryAgainOffersInstall() {
        let shown = UpdateDisplay().applying(Self.availableOutcome(), origin: .automatic, at: Self.now)
        let failed = shown.startingInstall()!.failingInstall(.downloadFailed("timed out"))
        let cancelled = failed.startingInstall()!.cancellingInstall()
        #expect(cancelled.state == .available(Self.release(), .install(Self.target)))
        #expect(cancelled.known?.action == .install(Self.target))
        #expect(cancelled.state.reason == nil)
    }

    /// Without a known install target there is nothing to try again.
    @Test func retryableFailureWithoutATargetOffersDownload() {
        let r = Self.release()
        let display = UpdateDisplay(state: .downloading(r, fraction: 0.4), known: KnownUpdate(release: r, action: .homebrew))
        #expect(display.failingInstall(.downloadFailed("x")).state == .available(r, .download(.downloadFailed("x"))))
    }

    @Test func failureOffersDownloadWithTheReason() {
        let shown = UpdateDisplay().applying(Self.availableOutcome(), origin: .automatic, at: Self.now)
        let failed = shown.startingInstall()!.failingInstall(.checksumMismatch)
        #expect(failed.state == .available(Self.release(), .download(.checksumMismatch)))
        #expect(failed.known?.action == .download(.checksumMismatch))
        #expect(failed.lineState?.lineText == "AgentTacho 0.3.0 available \u{00B7} \(UpdateBlockReason.checksumMismatch.text)")
    }

    /// FR-012: Install clicked after the installation changed (Homebrew now
    /// manages it, or it was moved): the line shows the new action, so the
    /// button and what it does agree.
    @Test func changedActionReplacesTheShownInstall() {
        let shown = UpdateDisplay().applying(Self.availableOutcome(), origin: .automatic, at: Self.now)
        let homebrew = shown.changingAction(to: .homebrew)
        #expect(homebrew.state == .available(Self.release(), .homebrew))
        #expect(homebrew.lineState == .available(Self.release(), .homebrew))
        #expect(homebrew.known == KnownUpdate(release: Self.release(), action: .homebrew))
        #expect(homebrew.startingInstall() == nil)
        #expect(homebrew.copyingHomebrewCommand() != nil)
        let moved = shown.changingAction(to: .download(.translocated))
        #expect(moved.state == .available(Self.release(), .download(.translocated)))
        #expect(moved.lineState?.lineText == "AgentTacho 0.3.0 available \u{00B7} \(UpdateBlockReason.translocated.text)")
    }

    /// Settings shows the known update next to a failed manual check; a
    /// changed action replaces both.
    @Test func changedActionAfterAFailedManualCheck() {
        let shown = UpdateDisplay().applying(Self.availableOutcome(), origin: .automatic, at: Self.now)
        let failed = shown.beginningCheck(origin: .settings).applying(.failure("offline"), origin: .settings, at: Self.now)
        let changed = failed.changingAction(to: .homebrew)
        #expect(changed.state == .available(Self.release(), .homebrew))
        #expect(changed.settingsKnownUpdate == nil)
    }

    @Test func changedActionIsIgnoredWithoutAnUpdateOrDuringAnInstall() {
        #expect(UpdateDisplay().changingAction(to: .homebrew) == UpdateDisplay())
        let running = UpdateDisplay().applying(Self.availableOutcome(), origin: .automatic, at: Self.now).startingInstall()!
        #expect(running.changingAction(to: .homebrew) == running)
    }

    // MARK: Homebrew (FR-013)

    @Test func copyingTheCommandOnlyForAHomebrewUpdate() {
        let homebrew = UpdateDisplay().applying(Self.availableOutcome(action: .homebrew), origin: .automatic, at: Self.now)
        let copied = homebrew.copyingHomebrewCommand()
        #expect(copied?.state == .commandCopied(Self.release()))
        #expect(copied?.lineState == .commandCopied(Self.release()))
        let install = UpdateDisplay().applying(Self.availableOutcome(), origin: .automatic, at: Self.now)
        #expect(install.copyingHomebrewCommand() == nil)
    }

    @Test func commandConfirmationEndsBackOnTheUpdate() {
        let homebrew = UpdateDisplay().applying(Self.availableOutcome(action: .homebrew), origin: .automatic, at: Self.now)
        let ended = homebrew.copyingHomebrewCommand()!.endingCommandCopied()
        #expect(ended.state == .available(Self.release(), .homebrew))
        #expect(homebrew.endingCommandCopied() == homebrew)
        // A newer release arrived meanwhile: the line shows it.
        let newer = homebrew.copyingHomebrewCommand()!
            .applying(Self.availableOutcome(4, action: .homebrew), origin: .automatic, at: Self.now)
            .endingCommandCopied()
        #expect(newer.state == .available(Self.release(4), .homebrew))
    }

    /// The one transient state the line still shows (spec 013 FR-017,
    /// spec 025 FR-026): a failed install reported by the previous run,
    /// from launch until the dropdown closes; Settings keeps it.
    @Test func installFailureFromThePreviousRunShowsUntilDismissed() {
        let display = UpdateDisplay().showingInstallFailure("disk full")
        #expect(display.lineShowsTransient)
        #expect(display.lineState == .installFailed("disk full"))
        let closed = display.dismissingTransient()
        #expect(closed.lineState == nil)
        #expect(closed.state == .installFailed("disk full"))
        // A known update returns to the line once the failure leaves it.
        let known = KnownUpdate(release: Self.release(), action: .install(Self.target))
        let withUpdate = UpdateDisplay(known: known).showingInstallFailure("disk full")
        #expect(withUpdate.lineState == .installFailed("disk full"))
        #expect(withUpdate.dismissingTransient().lineState == .available(Self.release(), .install(Self.target)))
    }

    /// The automatic check 5 minutes after launch must not hide the previous
    /// run's failure before the user saw it (contracts/update-ui.md); it
    /// still updates the known release.
    @Test func automaticCheckKeepsThePreviousRunsFailure() {
        let failed = UpdateDisplay().showingInstallFailure("disk full")
        let afterUpdate = failed.applying(Self.availableOutcome(), origin: .automatic, at: Self.now)
        #expect(afterUpdate.lineState == .installFailed("disk full"))
        #expect(afterUpdate.known?.release == Self.release())
        let afterFailure = failed.applying(.failure("offline"), origin: .automatic, at: Self.now)
        #expect(afterFailure.lineState == .installFailed("disk full"))
        let afterNothing = failed.applying(.result(.notNewer, action: nil), origin: .automatic, at: Self.now)
        #expect(afterNothing.lineState == .installFailed("disk full"))
        // A check from Settings replaces it, off the line.
        let manual = failed.applying(.result(.notNewer, action: nil), origin: .settings, at: Self.now)
        #expect(manual.state == .upToDate(checkedAt: Self.now))
        #expect(manual.lineState == nil)
    }

    /// The new version is in place but did not start (spec 013 FR-017, Edge
    /// Cases): the line says it is installed, offers no action, and later
    /// checks leave it alone.
    @Test func restartRequiredAfterAFailedRelaunch() {
        let installing = UpdateDisplay().applying(Self.availableOutcome(), origin: .automatic, at: Self.now)
            .startingInstall()!.withInstallStep(.installing)
        let restart = installing.requiringRestart()
        #expect(restart.state == .restartRequired(Self.release()))
        #expect(restart.lineState == .restartRequired(Self.release()))
        #expect(restart.state.lineText == "AgentTacho 0.3.0 is installed; quit AgentTacho and open it again to use it")
        #expect(restart.startingInstall() == nil)
        #expect(restart.applying(Self.availableOutcome(), origin: .settings, at: Self.now) == restart)
        #expect(restart.dismissingTransient().lineState == .restartRequired(Self.release()))
        // A check from either origin leaves it alone too.
        for origin in [CheckOrigin.automatic, .settings] {
            let checked = restart.beginningCheck(origin: origin)
                .applying(Self.availableOutcome(), origin: origin, at: Self.now)
            #expect(checked == restart)
        }
    }
}
