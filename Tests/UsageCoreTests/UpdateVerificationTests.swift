import Foundation
import Testing
@testable import UsageCore

/// spec 013 FR-015, FR-016, SC-003: the verification chain of research R4
/// stops at the first failure, and nothing passes unless every step passed.
@Suite struct UpdateVerificationTests {
    typealias Contents = Result<String, UpdateBlockReason>

    private func verdict(checksum: Bool = true, dmg: AssessmentResult? = .notarized,
                         contents: Contents? = .success("AgentMeter.app"), signature: Bool? = true,
                         app: AssessmentResult? = .notarized, staged: Bool? = true) -> UpdateBlockReason? {
        UpdateVerification.verdict(checksumMatches: checksum, diskImageAssessment: dmg, contents: contents,
                                   signatureValid: signature, appAssessment: app, stagedSignatureValid: staged)
    }

    @Test func allStepsPassing() {
        #expect(verdict() == nil)
        #expect(UpdateVerification.allPassed(checksumMatches: true, diskImageAssessment: .notarized, contents: .success("A.app"),
                                             signatureValid: true, appAssessment: .notarized, stagedSignatureValid: true))
    }

    @Test func stepsNotRunYetAreNotFailures() {
        #expect(verdict(dmg: nil, contents: nil, signature: nil, app: nil, staged: nil) == nil)
        #expect(verdict(staged: nil) == nil)
        #expect(!UpdateVerification.allPassed(checksumMatches: true, diskImageAssessment: .notarized, contents: .success("A.app"),
                                              signatureValid: true, appAssessment: .notarized, stagedSignatureValid: nil))
        #expect(!UpdateVerification.allPassed(checksumMatches: true, diskImageAssessment: nil, contents: .success("A.app"),
                                              signatureValid: true, appAssessment: .notarized, stagedSignatureValid: true))
    }

    @Test func checksumMismatchComesFirst() {
        #expect(verdict(checksum: false, dmg: .notNotarized, contents: .failure(.unexpectedContents("x")), signature: false,
                        app: .notNotarized, staged: false) == .checksumMismatch)
    }

    @Test func diskImageNotNotarized() {
        #expect(verdict(dmg: .notNotarized, signature: false) == .diskImageNotNotarized)
        #expect(verdict(dmg: .unavailable, signature: false) == .gatekeeperUnavailable)
    }

    @Test func contentsFailurePassesItsReasonThrough() {
        #expect(verdict(contents: .failure(.unexpectedContents("2 apps")), signature: false) == .unexpectedContents("2 apps"))
    }

    @Test func signatureOrTeamMismatch() {
        #expect(verdict(signature: false, app: .notNotarized) == .signatureMismatch)
    }

    @Test func appNotNotarized() {
        #expect(verdict(app: .notNotarized, staged: false) == .appNotNotarized)
        #expect(verdict(app: .unavailable) == .gatekeeperUnavailable)
    }

    @Test func stagedCopySignatureFailure() {
        #expect(verdict(staged: false) == .signatureMismatch)
    }

    struct Steps: Sendable, CustomTestStringConvertible {
        var checksum = true
        var dmg: AssessmentResult = .notarized
        var contents: Contents = .success("AgentMeter.app")
        var signature = true
        var app: AssessmentResult = .notarized
        var staged = true
        let expected: UpdateBlockReason
        var testDescription: String { "\(expected)" }
    }

    /// SC-003: one tampered step, all others passing, never passes the gate
    /// before the swap, and the verdict names that step.
    @Test(arguments: [
        Steps(checksum: false, expected: .checksumMismatch),
        Steps(dmg: .notNotarized, expected: .diskImageNotNotarized),
        Steps(dmg: .unavailable, expected: .gatekeeperUnavailable),
        Steps(contents: .failure(.unexpectedContents("2 apps in the disk image")), expected: .unexpectedContents("2 apps in the disk image")),
        Steps(signature: false, expected: .signatureMismatch),
        Steps(app: .notNotarized, expected: .appNotNotarized),
        Steps(app: .unavailable, expected: .gatekeeperUnavailable),
        Steps(staged: false, expected: .signatureMismatch),
    ])
    func oneTamperedStepNeverPasses(_ steps: Steps) {
        #expect(!UpdateVerification.allPassed(checksumMatches: steps.checksum, diskImageAssessment: steps.dmg, contents: steps.contents,
                                              signatureValid: steps.signature, appAssessment: steps.app,
                                              stagedSignatureValid: steps.staged))
        #expect(UpdateVerification.verdict(checksumMatches: steps.checksum, diskImageAssessment: steps.dmg, contents: steps.contents,
                                           signatureValid: steps.signature, appAssessment: steps.app,
                                           stagedSignatureValid: steps.staged) == steps.expected)
    }

    // MARK: Gatekeeper output

    @Test func notarizedAssessment() {
        let output = "/tmp/x.dmg: accepted\nsource=Notarized Developer ID\norigin=Developer ID Application: Roland Huss (EC5BHUKA6K)"
        #expect(UpdateVerification.classifyAssessment(output: output, exitStatus: 0) == .notarized)
    }

    /// The first line names the assessed path, which comes from the disk
    /// image: a source in the path never counts (FR-016).
    @Test func sourceInTheAssessedPathDoesNotCount() {
        let output = "/tmp/mnt/source=Notarized Developer ID.app: accepted\nsource=Developer ID"
        #expect(UpdateVerification.classifyAssessment(output: output, exitStatus: 0) == .notNotarized)
        let separated = "/tmp/mnt/x\u{2028}source=Notarized Developer ID\u{2028}A.app: accepted\nsource=Developer ID"
        #expect(UpdateVerification.classifyAssessment(output: separated, exitStatus: 0) == .notNotarized)
        let offline = "/tmp/mnt/network offline.app: rejected\nsource=Unnotarized Developer ID"
        #expect(UpdateVerification.classifyAssessment(output: offline, exitStatus: 3) == .notNotarized)
    }

    @Test func gatekeeperOffIsUnavailable() {
        #expect(UpdateVerification.classifyAssessment(output: "/tmp/x.app: accepted\noverride=security disabled", exitStatus: 0) == .unavailable)
    }

    @Test func ticketLookupFailureIsUnavailable() {
        #expect(UpdateVerification.classifyAssessment(output: "/tmp/x.app: rejected\nCould not validate ticket: network unavailable",
                                                      exitStatus: 3) == .unavailable)
    }

    @Test(arguments: [
        ("/tmp/x.app: accepted\nsource=Developer ID", Int32(0)),
        ("/tmp/x.app: rejected\nsource=Unnotarized Developer ID", Int32(3)),
        ("/tmp/x.app: rejected", Int32(3)),
        ("/tmp/x.app: a sealed resource is missing or invalid", Int32(1)),
        ("source=Notarized Developer ID", Int32(3)),
    ])
    func notNotarizedAssessments(_ output: String, _ status: Int32) {
        #expect(UpdateVerification.classifyAssessment(output: output, exitStatus: status) == .notNotarized)
    }

    // MARK: Requirement and checksum

    @Test func designatedRequirementIsExact() {
        let requirement = UpdateVerification.designatedRequirement(bundleID: "dev.rhuss.agentmeter", team: "EC5BHUKA6K")
        #expect(requirement == "identifier \"dev.rhuss.agentmeter\" and anchor apple generic"
                + " and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
                + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
                + " and certificate leaf[subject.OU] = \"EC5BHUKA6K\"")
    }

    @Test func requirementRefusesUnsafeInput() {
        #expect(UpdateVerification.designatedRequirement(bundleID: "dev.rhuss.agentmeter", team: "EC5\" or true") == nil)
        #expect(UpdateVerification.designatedRequirement(bundleID: "a\"b", team: "EC5BHUKA6K") == nil)
        #expect(UpdateVerification.designatedRequirement(bundleID: "dev.rhuss.agentmeter", team: "") == nil)
    }

    @Test func checksumComparison() {
        let lower = String(repeating: "ab", count: 32)
        #expect(UpdateVerification.sha256Matches(actualHex: lower, expectedHex: lower.uppercased()))
        #expect(!UpdateVerification.sha256Matches(actualHex: lower, expectedHex: String(repeating: "ac", count: 32)))
        #expect(!UpdateVerification.sha256Matches(actualHex: "ab", expectedHex: "ab"))
        #expect(!UpdateVerification.sha256Matches(actualHex: lower + "00", expectedHex: lower + "00"))
        #expect(!UpdateVerification.sha256Matches(actualHex: "", expectedHex: ""))
    }
}
