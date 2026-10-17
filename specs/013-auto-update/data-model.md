# Data Model: Auto-Update

All types live in `Sources/UsageCore/Update/` unless marked app-side. Pure value types, `Sendable`, `Equatable`.

## ReleaseVersion

`X.Y.Z` with three non-negative integers. `init?(_ string: String)` accepts exactly `^[0-9]+\.[0-9]+\.[0-9]+$` (no "v", no suffix); `init?(tag:)` additionally strips one leading "v" and accepts the rest only when it is written exactly like the version's `description` (no leading zeros), so `ReleaseEvaluator` can compare tag and `release-info.json` version as text (FR-004). `Comparable` part by part numerically (FR-006). `description` gives `X.Y.Z`.

## GitHubRelease (decoded from the API)

| Field | Source | Rule |
|---|---|---|
| tag | `tag_name` | required |
| pageURL | `html_url` | required, https |
| draft, prerelease | `draft`, `prerelease` | must both be false, else ignored |
| assets | `assets[]` of `{name, size, browser_download_url}` | url must be https |

## ReleaseInfo (decoded from `release-info.json`, spec 005 contract)

`version`, `dmg`, `sha256`, `tier`, `notarized`. Decoding is lenient per field so a valid version can survive other bad fields (FR-004).

## ReleaseCheckResult

Output of `ReleaseEvaluator.evaluate(release:info:runningVersion:)`:

- `.ignored(reason)`: no line. Reasons: no release-info asset, info unreadable, info version missing or not `X.Y.Z`, info version not equal to tag without "v", draft or prerelease.
- `.notNewer`: release version is not higher than the running version.
- `.available(AvailableRelease)`.

`AvailableRelease`: `version: ReleaseVersion`, `pageURL: URL`, `download: DownloadTarget?`, `infoProblem: UpdateBlockReason?`.

`UpdateSource`: `owner`, `repo`; `official` is `rhuss/agenttacho`; `parse(_:)` accepts `^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$` (contracts/make-targets.md) and `resolve(_:)` falls back to `official`. Only an update-test build reads a stamped source (FR-025).

`DownloadTarget`: `url: URL`, `size: Int`, `sha256: String` (64 lowercase hex). Present only when `dmg == "AgentTacho-<version>.dmg"`, that asset exists, its size is at most 100 MB, `sha256` is valid, `tier == "developer-id"` and `notarized == true`. Otherwise `download` is nil and `infoProblem` names why (`.releaseInfoIncomplete`, `.releaseNotNotarized`, or `.downloadTooLarge` for a disk image above 100 MB).

## InstallContext (facts, gathered app-side)

| Field | Meaning |
|---|---|
| runningVersion | `ReleaseVersion(CFBundleShortVersionString)`; nil disables checks |
| isReleaseBuild | bundle has `AgentTachoReleaseTag` |
| isUpdateTestBuild | compiled with `AGENTTACHO_UPDATE_TEST` (R11) |
| signing | `AppVersionInfo.Signing?` stamp |
| teamIdentifier | from the running code signature, may be nil |
| bundleIdentifier, bundlePath | running bundle |
| isHomebrewManaged | result of `HomebrewDetector` (R7) |
| isTranslocated, isOnReadOnlyVolume | R6 |
| isBundleWritable, isParentWritable | R6 |

## UpdateAction (from `UpdatePolicy.action(context:release:)`)

- `.install(DownloadTarget)`: all of release build or update-test build, Developer ID notarized stamp (not required for update-test), team identifier present, not Homebrew, not translocated, not read-only, both writable, and `release.download != nil`.
- `.homebrew`: Homebrew-managed (wins over every location fact; FR-013).
- `.download(UpdateBlockReason)`: everything else, with the first failing condition as reason.

Development builds never reach this: `UpdatePolicy.checksAllowed(context:)` is false for a non-release build without the update-test flag (FR-008).

## UpdateBlockReason

`public enum UpdateBlockReason: Error, Equatable, Sendable` in its own file `UpdateBlockReason.swift` (used by ReleaseEvaluator, UpdatePolicy, DiskImageCheck and UpdateVerification). Short user text per case (FR-019), including `gatekeeperUnavailable` ("Gatekeeper could not confirm the notarization; check your connection, or Gatekeeper may be turned off"): `runsFromDiskImage` ("Move AgentTacho to Applications to install updates"), `translocated` (same text), `notWritable` ("AgentTacho cannot replace itself in this folder"), `runningNotNotarized` ("This build cannot verify updates"), `releaseNotNotarized`, `releaseInfoIncomplete`, `downloadFailed(String)`, `downloadTooLarge`, `unexpectedHost`, `checksumMismatch`, `diskImageNotNotarized`, `unexpectedContents(String)`, `signatureMismatch`, `appNotNotarized`, `verificationFailed(String)` ("The update could not be verified: <detail>", a verification tool that could not run or a staged copy that could not be made; nothing replaced), `replacementDenied`, `replacementFailed(String)` (only the swap), `previousVersionInTrash(String?)`. `allowsRetry` is true for `downloadFailed` and `gatekeeperUnavailable` only.

## UpdateState (shown on the line and in Settings)

```text
notCheckedYet ──check──▶ checking ──▶ upToDate(at:) | available(AvailableRelease, UpdateAction) | checkFailed(String)
developmentBuild (terminal for non-release builds)
available ──Install──▶ downloading(fraction) ──▶ verifying ──▶ installing ──▶ (app quits)
                     │ Cancel                 │ Cancel                 │ failure
                     ▼                        ▼                        ▼
                 available                available             available with .download(reason) or .retry(target, reason)
available(.install) ──Install, action changed──▶ available(.homebrew | .download(reason))
available(.homebrew) ──click──▶ commandCopied → available (after a few seconds)
(launch, outcome "failed") ──▶ installFailed(reason) with `Release page`
installing ──relaunch failed──▶ restartRequired (no action; later checks leave it alone)
```

Types (`UpdateState.swift`):

```swift
public enum UpdateState: Equatable, Sendable {
    case notCheckedYet
    case developmentBuild
    case checking
    case upToDate(checkedAt: Date)
    case checkFailed(String)
    case available(AvailableRelease, UpdateAction)
    case commandCopied(AvailableRelease)
    case downloading(AvailableRelease, fraction: Double)
    case verifying(AvailableRelease)
    case installing(AvailableRelease)
    case installFailed(String)        // the previous run's install failed
    case restartRequired(AvailableRelease) // swapped in, but the relaunch failed
}

public enum CheckOrigin: Equatable, Sendable {
    case automatic, dropdown, settings  // isManual, showsResultOnLine, joining(_:)
}

public enum CheckOutcome: Equatable, Sendable {
    case result(ReleaseCheckResult, action: UpdateAction?)   // action nil unless .available
    case failure(String)
}

/// What Settings shows (`state`) and what the dropdown line shows (`lineState`).
public struct UpdateDisplay: Equatable, Sendable {
    public var state: UpdateState
    public var lineShowsTransient: Bool
    public var lineState: UpdateState? { get }          // nil hides the line
    public func beginningCheck(origin: CheckOrigin) -> UpdateDisplay
    public func applying(_ outcome: CheckOutcome, origin: CheckOrigin, at: Date) -> UpdateDisplay
    public func changingAction(to: UpdateAction) -> UpdateDisplay  // Install clicked, action changed (FR-012)
    public func dismissingTransient() -> UpdateDisplay  // dropdown closed
}
```

An automatic check does not replace `installFailed` (it only refreshes the known update), so the previous run's failure stays until the dropdown closes. `restartRequired` is not transient and ignores later check results.

Rules: an automatic check failure keeps a known `available` (FR-007a) and never records `checkFailed`; a manual check failure records `checkFailed`. Transient states (`checking`, `upToDate`, `checkFailed`, `developmentBuild`, `installFailed`) appear on the line only while `lineShowsTransient` is true (set by a check from the dropdown and by a launch that found a failed install, cleared by `dismissingTransient()`), while `state` keeps them for Settings until the next check (FR-003). A check from Settings never sets `lineShowsTransient`. A check that another one joins reports for the more visible origin (dropdown, then Settings). There is no `cancelled` state: Cancel returns to `available`, and a cancelled Try again offers Install again. A successful check that finds nothing newer clears `available`. A check result arriving during `downloading`, `verifying` or `installing` is ignored; during `commandCopied` it only replaces the release. An automatic check does not change the display while it runs (no `checking` state is shown; a known `available` stays on the line).

## UpdateSchedule

`isDue(now:launchedAt:lastCheck:) -> Bool`: true when `lastCheck == nil` and `now >= launchedAt + 300 s`, or `lastCheck != nil` and `now >= lastCheck + 86_400 s`, or `lastCheck > now` (clock moved back) (FR-001).

## UpdateHostPolicy

`allows(_ url: URL) -> Bool`: https scheme and host (lowercased) in the four allowed hosts. Applied to every starting URL (including asset URLs from the API) and every redirect (FR-005, FR-014).

## DiskImageCheck

`check(entries: [DiskImageEntry], expectedBundleID:, expectedVersion:) -> Result<String /* app name */, UpdateBlockReason>`; `DiskImageEntry` = name, isDirectory, bundleIdentifier?, shortVersion? (FR-016).

## UpdateVerification

`verdict(checksumMatches:, diskImageAssessment:, contents:, signatureValid:, appAssessment:, stagedSignatureValid: Bool?) -> UpdateBlockReason?` (`stagedSignatureValid` is nil before staging) in the order of research R4, where assessments are `AssessmentResult` (`.notarized`, `.notNotarized`, `.unavailable`) from `classifyAssessment(output:exitStatus:)`; `.unavailable` maps to `gatekeeperUnavailable`. The staged copy's signature is checked again before the swap (`signatureMismatch` on failure).

## UpdateOutcome (app writes, next launch reads)

JSON `{ "from": "0.3.0", "to": "0.3.1", "result": "installed" | "failed", "reason": "..." }` in the update folder (R10).

## Configuration

`checksForUpdates: Bool = true` (R12).
