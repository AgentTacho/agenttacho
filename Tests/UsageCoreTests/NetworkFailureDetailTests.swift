import Foundation
import Testing
@testable import UsageCore

/// spec 021 FR-007, FR-008, SC-003: the technical detail of a failed usage
/// request, for the diagnostic log only.
@Suite struct NetworkFailureDetailTests {
    @Test func fullDetail() {
        let error = URLError(.notConnectedToInternet, userInfo: [
            NSUnderlyingErrorKey: NSError(domain: "kCFErrorDomainCFNetwork", code: -1009),
            "_kCFStreamErrorCodeKey": 50,
        ])
        let detail = NetworkFailureDetail(error)
        #expect(detail.domain == NSURLErrorDomain)
        #expect(detail.code == -1009)
        #expect(detail.underlyingDomain == "kCFErrorDomainCFNetwork")
        #expect(detail.underlyingCode == -1009)
        #expect(detail.streamErrorCode == 50)
        #expect(detail.description == "NSURLErrorDomain -1009; underlying kCFErrorDomainCFNetwork -1009; stream error 50")
    }

    @Test func withoutUnderlyingErrorOrStreamCode() {
        let detail = NetworkFailureDetail(URLError(.timedOut))
        #expect(detail.underlyingDomain == nil)
        #expect(detail.underlyingCode == nil)
        #expect(detail.streamErrorCode == nil)
        #expect(detail.description == "NSURLErrorDomain -1001")
    }

    @Test func eachPartIsOmittedOnItsOwn() {
        let underlying = URLError(.networkConnectionLost, userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 57)])
        #expect(NetworkFailureDetail(underlying).description == "NSURLErrorDomain -1005; underlying NSPOSIXErrorDomain 57")
        let stream = URLError(.cannotFindHost, userInfo: ["_kCFStreamErrorCodeKey": -72000])
        #expect(NetworkFailureDetail(stream).description == "NSURLErrorDomain -1003; stream error -72000")
    }

    /// FR-008: only domains and codes are read; no URL, header value or
    /// other user info text.
    @Test func neverContainsTheURLOrOtherUserInfo() {
        let secret = "SECRET-\(UUID().uuidString)"
        var error = offlineErrorWithDetail(secret: secret)
        error = URLError(error.code, userInfo: error.userInfo.merging([
            NSURLErrorFailingURLErrorKey: URL(string: "https://leak.example/?t=\(secret)")!,
            NSLocalizedDescriptionKey: "described with \(secret)",
        ]) { _, new in new })
        let text = NetworkFailureDetail(error).description
        #expect(text == "NSURLErrorDomain -1009; underlying kCFErrorDomainCFNetwork -1009; stream error 50")
        #expect(!text.contains(secret))
        #expect(!text.contains("leak.example"))
    }

    /// FR-007: the detail goes into the log text only; the description
    /// shown in the dropdown and in source errors keeps today's wording.
    @Test func logDescriptionAppendsTheDetail() {
        let detail = NetworkFailureDetail(URLError(.notConnectedToInternet))
        let error = UsageEndpointError.network("The Internet connection appears to be offline.", detail: detail)
        #expect(error.description == "usage endpoint unreachable: The Internet connection appears to be offline.")
        #expect(error.logDescription == "usage endpoint unreachable: The Internet connection appears to be offline. [NSURLErrorDomain -1009]")
        let plain = UsageEndpointError.network("no HTTP response")
        #expect(plain.logDescription == plain.description)
        #expect(UsageEndpointError.httpStatus(503).logDescription == "usage endpoint returned HTTP 503")
    }
}
