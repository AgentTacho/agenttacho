import Foundation
import Testing
@testable import UsageCore

/// spec 013 FR-006: `X.Y.Z` parsing and numeric comparison.
@Suite struct ReleaseVersionTests {
    @Test func parsesThreeNumericParts() throws {
        let version = try #require(ReleaseVersion("0.3.0"))
        #expect(version.major == 0 && version.minor == 3 && version.patch == 0)
        let big = try #require(ReleaseVersion("10.0.12"))
        #expect(big.major == 10 && big.minor == 0 && big.patch == 12)
    }

    @Test(arguments: ["v0.3.0", "0.3", "0.3.0-dev", "0.3.0.1", "a.b.c", "", " 0.3.0", "0.3.0 ", "0..3", "1.2.", "-1.2.3", "+1.2.3", "１.2.3"])
    func rejectsAnythingElse(_ text: String) {
        #expect(ReleaseVersion(text) == nil)
    }

    @Test func tagStripsOneLeadingV() {
        #expect(ReleaseVersion(tag: "v0.3.0") == ReleaseVersion("0.3.0"))
        #expect(ReleaseVersion(tag: "0.3.0") == ReleaseVersion("0.3.0"))
        #expect(ReleaseVersion(tag: "vv0.3.0") == nil)
        #expect(ReleaseVersion(tag: "v0.3") == nil)
        #expect(ReleaseVersion(tag: "v") == nil)
    }

    /// FR-004: a tag counts only when its text is the version's text, so
    /// the tag and release-info.json can be compared as text.
    @Test func tagMustBeWrittenLikeItsVersion() {
        #expect(ReleaseVersion(tag: "v0.3.00") == nil)
        #expect(ReleaseVersion(tag: "v00.3.0") == nil)
        #expect(ReleaseVersion(tag: "0.03.0") == nil)
        #expect(ReleaseVersion(tag: "v10.0.12") == ReleaseVersion("10.0.12"))
    }

    @Test func comparesNumericallyPartByPart() throws {
        let v = { (s: String) throws -> ReleaseVersion in try #require(ReleaseVersion(s)) }
        #expect(try v("0.10.0") > v("0.9.9"))
        #expect(try v("1.0.0") > v("0.99.99"))
        #expect(try v("0.3.1") > v("0.3.0"))
        #expect(try !(v("0.3.0") > v("0.3.0")))
        #expect(try v("0.3.0") == v("0.3.0"))
        #expect(try v("0.2.1") < v("0.3.0"))
    }

    @Test func descriptionRoundTrips() throws {
        for text in ["0.3.0", "10.0.12", "1.2.3"] {
            #expect(try #require(ReleaseVersion(text)).description == text)
        }
    }
}
