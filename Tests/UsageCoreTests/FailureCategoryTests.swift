import Foundation
import Testing
@testable import UsageCore

/// spec 010 FR-001: every failed request falls into exactly one category.
@Suite struct FailureCategoryTests {
    struct SomeOtherError: Error {}

    @Test func networkErrorsAreTransport() {
        #expect(FailureCategory.classify(UsageEndpointError.network("offline")) == .transport)
    }

    @Test func serverErrorsAreTransport() {
        for code in [500, 503, 599] {
            #expect(FailureCategory.classify(UsageEndpointError.httpStatus(code)) == .transport, "HTTP \(code)")
        }
    }

    @Test func unauthorizedAndForbiddenAreRejectedSignIns() {
        #expect(FailureCategory.classify(UsageEndpointError.httpStatus(401)) == .signInRejected)
        #expect(FailureCategory.classify(UsageEndpointError.httpStatus(403)) == .signInRejected)
    }

    @Test func rateLimitIsRateLimited() {
        #expect(FailureCategory.classify(UsageEndpointError.rateLimited(retryAfter: nil)) == .rateLimited)
        #expect(FailureCategory.classify(UsageEndpointError.rateLimited(retryAfter: 30)) == .rateLimited)
    }

    @Test func unreadableAnswersRedirectsAndOtherStatusesMeanTheServiceChanged() {
        #expect(FailureCategory.classify(UsageEndpointError.decoding("bad")) == .serviceChanged)
        #expect(FailureCategory.classify(UsageEndpointError.httpStatus(302)) == .serviceChanged)
        #expect(FailureCategory.classify(UsageEndpointError.httpStatus(404)) == .serviceChanged)
        #expect(FailureCategory.classify(UsageEndpointError.httpStatus(600)) == .serviceChanged)
        #expect(FailureCategory.classify(CodexUsageError.noLimits) == .serviceChanged)
    }

    @Test func unknownErrorTypesAreTransport() {
        #expect(FailureCategory.classify(SomeOtherError()) == .transport)
        #expect(FailureCategory.classify(URLError(.timedOut)) == .transport)
    }

    /// spec 010 FR-005: the grace note names the failure.
    @Test func graceNoteWording() {
        #expect(GraceNote.reason(claudeError: UsageEndpointError.network("offline").description) == "Couldn't reach the usage service")
        #expect(GraceNote.reason(claudeError: UsageEndpointError.httpStatus(503).description) == "usage endpoint returned HTTP 503")
        #expect(GraceNote.reason(claudeError: "SomeOtherError()") == "Couldn't reach the usage service")
        #expect(GraceNote.reason(codexReason: "offline") == "Couldn't reach the usage service")
        #expect(GraceNote.reason(codexReason: "usage service unavailable (HTTP 503)") == "usage service unavailable (HTTP 503)")
    }

    /// spec 010 FR-010: the note names a non-default credential directory.
    @Test func signInRejectedNoteNamesANonDefaultDirectory() {
        let paths = Paths(home: URL(fileURLWithPath: "/Users/someone"))
        #expect(SignInRejectedNote.text(credentialDirectory: "~/.claude", paths: paths) == "Sign-in rejected, run claude to sign in again")
        #expect(SignInRejectedNote.text(credentialDirectory: "/Users/someone/.claude/", paths: paths) == "Sign-in rejected, run claude to sign in again")
        #expect(SignInRejectedNote.text(credentialDirectory: "~/.claude-work", paths: paths)
                == "Sign-in rejected, run CLAUDE_CONFIG_DIR=~/.claude-work claude to sign in again")
    }
}
