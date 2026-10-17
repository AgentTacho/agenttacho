import Foundation
import Testing
@testable import UsageCore

/// spec 013 FR-016: the disk image holds exactly one app with the running
/// app's bundle identifier and the release's version.
@Suite struct DiskImageCheckTests {
    static let bundleID = "dev.rhuss.agenttacho"
    static let version = ReleaseVersion(major: 0, minor: 3, patch: 0)

    static func app(_ name: String = "AgentTacho.app", id: String? = bundleID, version: String? = "0.3.0") -> DiskImageEntry {
        DiskImageEntry(name: name, isDirectory: true, bundleIdentifier: id, shortVersion: version)
    }

    /// The layout of the real disk image (spec 005 make-dmg.sh).
    static let extras = [
        DiskImageEntry(name: "Applications", isDirectory: false),
        DiskImageEntry(name: ".background", isDirectory: true),
        DiskImageEntry(name: ".DS_Store", isDirectory: false),
        DiskImageEntry(name: ".VolumeIcon.icns", isDirectory: false),
        DiskImageEntry(name: ".fseventsd", isDirectory: true),
        DiskImageEntry(name: ".Trashes", isDirectory: true),
    ]

    private func check(_ entries: [DiskImageEntry]) -> Result<String, UpdateBlockReason> {
        DiskImageCheck.check(entries: entries, expectedBundleID: Self.bundleID, expectedVersion: Self.version)
    }

    private func failureDetail(_ result: Result<String, UpdateBlockReason>) -> String? {
        if case .failure(.unexpectedContents(let detail)) = result { return detail }
        return nil
    }

    @Test func realLayoutPasses() {
        #expect(check(Self.extras + [Self.app()]) == .success("AgentTacho.app"))
    }

    @Test func noApp() {
        #expect(failureDetail(check(Self.extras))?.contains("no app") == true)
    }

    @Test func twoApps() {
        let detail = failureDetail(check(Self.extras + [Self.app(), Self.app("Other.app")]))
        #expect(detail?.contains("2 apps") == true)
    }

    @Test func appThatIsNotAFolder() {
        let detail = failureDetail(check([DiskImageEntry(name: "AgentTacho.app", isDirectory: false)]))
        #expect(detail?.contains("not an app bundle") == true)
    }

    @Test func wrongBundleIdentifier() {
        let detail = failureDetail(check(Self.extras + [Self.app(id: "com.example.evil")]))
        #expect(detail?.contains("com.example.evil") == true)
    }

    @Test func missingBundleIdentifier() {
        let detail = failureDetail(check(Self.extras + [Self.app(id: nil)]))
        #expect(detail?.contains("no bundle identifier") == true)
    }

    @Test func wrongVersion() {
        let detail = failureDetail(check(Self.extras + [Self.app(version: "0.2.9")]))
        #expect(detail?.contains("0.2.9") == true)
        let missing = failureDetail(check(Self.extras + [Self.app(version: nil)]))
        #expect(missing?.contains("no version") == true)
    }

    @Test func appMayHaveAnotherName() {
        #expect(check([Self.app("AgentTacho 2.app")]) == .success("AgentTacho 2.app"))
    }

    /// The app's name reaches Gatekeeper's output, which is parsed line by
    /// line: a name with a line break is refused (FR-016).
    @Test func appNameWithControlCharactersIsRefused() {
        for separator in ["\n", "\u{2028}", "\u{2029}", "\u{0085}", "\r"] {
            let result = check([Self.app("x\(separator)source=Notarized Developer ID\(separator)AgentTacho.app")] + Self.extras)
            #expect(result == .failure(.unexpectedContents("the app name contains control characters")))
        }
    }
}
