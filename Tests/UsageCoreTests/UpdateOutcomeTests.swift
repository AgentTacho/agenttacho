import Foundation
import Testing
@testable import UsageCore

/// spec 013 FR-017, research R10: the outcome marker the next launch reads.
@Suite struct UpdateOutcomeTests {
    @Test func namesAreFixed() {
        #expect(UpdateOutcome.fileName == "outcome.json")
        #expect(UpdateOutcome.folderName == "dev.rhuss.agenttacho-update")
    }

    @Test func roundTrips() throws {
        let installed = UpdateOutcome(from: "0.3.0", to: "0.3.1", result: .installed, reason: nil)
        #expect(UpdateOutcome.decode(try installed.encoded()) == installed)
        let failed = UpdateOutcome(from: "0.3.0", to: "0.3.1", result: .failed, reason: "disk full")
        #expect(UpdateOutcome.decode(try failed.encoded()) == failed)
    }

    @Test func encodesTheDocumentedKeys() throws {
        let data = try UpdateOutcome(from: "0.3.0", to: "0.3.1", result: .failed, reason: "disk full").encoded()
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(object == ["from": "0.3.0", "to": "0.3.1", "result": "failed", "reason": "disk full"])
    }

    @Test func unknownResultDecodesAsFailed() {
        let outcome = UpdateOutcome.decode(Data(#"{"from":"0.3.0","to":"0.3.1","result":"exploded"}"#.utf8))
        #expect(outcome?.result == .failed)
        #expect(outcome?.reason == nil)
    }

    @Test func garbageDecodesAsNil() {
        #expect(UpdateOutcome.decode(Data("nope".utf8)) == nil)
    }
}
