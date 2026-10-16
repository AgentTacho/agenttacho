import Foundation

/// Gatekeeper's answer for the disk image or the app (spec 013 FR-016;
/// research R4 steps 2 and 6).
public enum AssessmentResult: Equatable, Sendable {
    /// Accepted with `source=Notarized Developer ID`.
    case notarized
    /// Rejected, or accepted for another reason than notarization.
    case notNotarized
    /// Gatekeeper is turned off, or the ticket lookup failed (offline).
    case unavailable
}

/// The decisions of the verification chain (spec 013 FR-015, FR-016,
/// SC-003; research R4). The app runs the tools and feeds their results in;
/// nothing is replaced unless `allPassed` holds.
public enum UpdateVerification {
    /// The first failing step in R4 order, or nil when no step that ran so
    /// far failed. A nil step has not run yet. Order: checksum, disk image
    /// assessment, contents, signature and team, app assessment, signature of
    /// the staged copy.
    public static func verdict(checksumMatches: Bool, diskImageAssessment: AssessmentResult?,
                               contents: Result<String, UpdateBlockReason>?, signatureValid: Bool?,
                               appAssessment: AssessmentResult?, stagedSignatureValid: Bool?) -> UpdateBlockReason? {
        guard checksumMatches else { return .checksumMismatch }
        switch diskImageAssessment {
        case .notNotarized?: return .diskImageNotNotarized
        case .unavailable?: return .gatekeeperUnavailable
        case .notarized?, nil: break
        }
        if case .failure(let reason)? = contents { return reason }
        if signatureValid == false { return .signatureMismatch }
        switch appAssessment {
        case .notNotarized?: return .appNotNotarized
        case .unavailable?: return .gatekeeperUnavailable
        case .notarized?, nil: break
        }
        if stagedSignatureValid == false { return .signatureMismatch }
        return nil
    }

    /// True only when every step ran and passed: the condition for the swap
    /// (FR-017, SC-003).
    public static func allPassed(checksumMatches: Bool, diskImageAssessment: AssessmentResult?,
                                 contents: Result<String, UpdateBlockReason>?, signatureValid: Bool?,
                                 appAssessment: AssessmentResult?, stagedSignatureValid: Bool?) -> Bool {
        guard diskImageAssessment != nil, contents != nil, signatureValid != nil,
              appAssessment != nil, stagedSignatureValid != nil else { return false }
        return verdict(checksumMatches: checksumMatches, diskImageAssessment: diskImageAssessment, contents: contents,
                       signatureValid: signatureValid, appAssessment: appAssessment,
                       stagedSignatureValid: stagedSignatureValid) == nil
    }

    /// Classifies the output of `spctl --assess --verbose=2` (research R4).
    /// Assessments turned off (`override=security disabled`) and failed
    /// ticket lookups are "unavailable", not "not notarized"; either way
    /// nothing is replaced. The first line names the assessed path, which
    /// comes from the disk image, so only the following lines count, and
    /// the source must be a whole line.
    public static func classifyAssessment(output: String, exitStatus: Int32) -> AssessmentResult {
        // spctl ends lines with "\n"; Unicode line separators in a path
        // never start a new line here.
        let lines = output.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let details = lines.count > 1 ? Array(lines.dropFirst()) : lines.filter { !$0.contains(": ") }
        if details.contains(where: { $0.lowercased() == "override=security disabled" }) { return .unavailable }
        if exitStatus == 0 {
            return details.contains("source=Notarized Developer ID") ? .notarized : .notNotarized
        }
        let lookupFailures = ["could not validate ticket", "network", "offline", "internet connection"]
        if details.contains(where: { line in lookupFailures.contains(where: { line.lowercased().contains($0) }) }) {
            return .unavailable
        }
        return .notNotarized
    }

    /// The code requirement of research R4 step 5: the bundle identifier, a
    /// Developer ID Application certificate issued by Apple, and the running
    /// app's team. Nil when either value holds characters that could change
    /// the requirement's meaning.
    public static func designatedRequirement(bundleID: String, team: String) -> String? {
        guard isSafe(bundleID, extra: ".-"), isSafe(team, extra: "") else { return nil }
        return "identifier \"\(bundleID)\" and anchor apple generic"
            + " and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
            + " and certificate leaf[subject.OU] = \"\(team)\""
    }

    /// Compares two SHA-256 digests in hex, ignoring case; anything that is
    /// not 64 hex characters never matches (FR-015).
    public static func sha256Matches(actualHex: String, expectedHex: String) -> Bool {
        guard let actual = ReleaseEvaluator.normalizedSHA256(actualHex),
              let expected = ReleaseEvaluator.normalizedSHA256(expectedHex) else { return false }
        return actual == expected
    }

    private static func isSafe(_ text: String, extra: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || extra.contains($0)) }
    }
}
