import Foundation
import Testing
@testable import UsageCore

@Suite struct ReleaseChangesTests {
    private func changes(_ json: String) -> ReleaseChanges {
        ReleaseChanges(data: Data(json.utf8))
    }

    @Test func decodesTheEntriesOfChangesJSON() {
        let decoded = changes("""
        [
          {"type": "fix", "scope": "prices", "subject": "count models used in this window", "hash": "7975e1b"},
          {"type": "feat", "scope": null, "subject": "an About tab", "hash": "1234567"}
        ]
        """)
        #expect(decoded.entries == [
            ReleaseChange(kind: .feature, scope: nil, subject: "an About tab", hash: "1234567"),
            ReleaseChange(kind: .fix, scope: "prices", subject: "count models used in this window", hash: "7975e1b"),
        ])
    }

    @Test func missingOrBrokenFileIsEmpty() {
        #expect(ReleaseChanges(data: nil).entries.isEmpty)
        #expect(changes("").entries.isEmpty)
        #expect(changes("{\"type\": \"feat\"}").entries.isEmpty)
        #expect(changes("[").entries.isEmpty)
        #expect(changes("[]").isEmpty)
    }

    @Test func unknownTypesAndMalformedEntriesAreSkipped() {
        let decoded = changes("""
        [
          {"type": "chore", "scope": null, "subject": "tidy up", "hash": "aaaaaaa"},
          {"type": "feat", "subject": "no hash"},
          {"type": "feat", "scope": 3, "subject": "bad scope", "hash": "bbbbbbb"},
          "not an object",
          {"type": "perf", "subject": "faster scans", "hash": "ccccccc"}
        ]
        """)
        #expect(decoded.entries == [
            ReleaseChange(kind: .performance, scope: nil, subject: "faster scans", hash: "ccccccc"),
        ])
    }

    @Test func groupsFeaturesBeforeFixesBeforePerformanceKeepingTheirOrder() {
        let decoded = changes("""
        [
          {"type": "perf", "scope": null, "subject": "p1", "hash": "0000001"},
          {"type": "fix", "scope": null, "subject": "x1", "hash": "0000002"},
          {"type": "feat", "scope": null, "subject": "f1", "hash": "0000003"},
          {"type": "fix", "scope": null, "subject": "x2", "hash": "0000004"},
          {"type": "feat", "scope": null, "subject": "f2", "hash": "0000005"}
        ]
        """)
        #expect(decoded.entries.map(\.subject) == ["f1", "f2", "x1", "x2", "p1"])
        let groups = decoded.groups(limit: 10)
        #expect(groups.map(\.kind) == [.feature, .fix, .performance])
        #expect(groups.map(\.title) == ["Features", "Fixes", "Performance"])
        #expect(groups.map { $0.entries.map(\.subject) } == [["f1", "f2"], ["x1", "x2"], ["p1"]])
    }

    @Test func groupsAreLimitedToTheFirstEntries() {
        let decoded = changes("""
        [
          {"type": "fix", "scope": null, "subject": "x1", "hash": "0000002"},
          {"type": "feat", "scope": null, "subject": "f1", "hash": "0000003"},
          {"type": "feat", "scope": null, "subject": "f2", "hash": "0000005"}
        ]
        """)
        #expect(decoded.groups(limit: 2).map { $0.entries.map(\.subject) } == [["f1", "f2"]])
        #expect(decoded.groups(limit: 0).isEmpty)
        #expect(decoded.count == 3)
    }

    @Test func sentenceCapitalizesTheSubject() {
        let change = ReleaseChange(kind: .fix, scope: "prices", subject: "count models (#3)", hash: "7975e1b")
        #expect(change.sentence == "Count models (#3)")
        #expect(ReleaseChange(kind: .fix, scope: nil, subject: "", hash: "7975e1b").sentence == "")
    }
}
