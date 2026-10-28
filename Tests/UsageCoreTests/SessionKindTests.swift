import Foundation
import Testing
@testable import UsageCore

/// spec 038 FR-001, FR-002, SC-002, data-model "SessionKind".
@Suite struct SessionKindTests {
    private func record(_ harness: Harness = .claudeCode, requestId: String = "", hint: String? = nil) -> RawUsageRecord {
        var r = makeRaw(id: "msg_1", requestId: requestId, model: "intranet/glm-5")
        r.harness = harness
        r.providerHint = hint
        return r
    }

    /// FR-001: the kinds per harness in pop-up order, the first the default.
    @Test func kindsPerHarnessInOrder() {
        #expect(SessionKind.kinds(for: .claudeCode) == [.claudeCodeDirectoryOnly, .claudeCodeVertex, .claudeCodeOtherProvider])
        #expect(SessionKind.kinds(for: .codex) == [.codexAPIKey])
        #expect(SessionKind.kinds(for: .openCode) == [.openCodeVertex, .openCodeOpenAI, .openCodeAnthropic, .openCodeOtherProvider])
        #expect(SessionKind.default(for: .claudeCode) == .claudeCodeDirectoryOnly)
        #expect(SessionKind.default(for: .codex) == .codexAPIKey)
        #expect(SessionKind.default(for: .openCode) == .openCodeVertex)
        for kind in SessionKind.allCases {
            #expect(SessionKind.kinds(for: kind.harness).contains(kind))
        }
    }

    /// FR-010, contracts/configuration.md: stored values, read together
    /// with the harness.
    @Test func storedValuesAreReadTogetherWithTheHarness() {
        #expect(SessionKind.claudeCodeDirectoryOnly.storedValue == "directoryOnly")
        #expect(SessionKind.claudeCodeVertex.storedValue == "vertex")
        #expect(SessionKind.claudeCodeOtherProvider.storedValue == "otherProvider")
        #expect(SessionKind.codexAPIKey.storedValue == "apiKey")
        #expect(SessionKind.openCodeVertex.storedValue == "vertex")
        #expect(SessionKind.openCodeOpenAI.storedValue == "openai")
        #expect(SessionKind.openCodeAnthropic.storedValue == "anthropic")
        #expect(SessionKind.openCodeOtherProvider.storedValue == "otherProvider")
        #expect(SessionKind.kind(stored: "vertex", harness: .claudeCode) == .claudeCodeVertex)
        #expect(SessionKind.kind(stored: "vertex", harness: .openCode) == .openCodeVertex)
        #expect(SessionKind.kind(stored: "otherProvider", harness: .claudeCode) == .claudeCodeOtherProvider)
        #expect(SessionKind.kind(stored: "otherProvider", harness: .openCode) == .openCodeOtherProvider)
        #expect(SessionKind.kind(stored: "directoryOnly", harness: .claudeCode) == .claudeCodeDirectoryOnly)
        #expect(SessionKind.kind(stored: "apiKey", harness: .codex) == .codexAPIKey)
        #expect(SessionKind.kind(stored: "openai", harness: .openCode) == .openCodeOpenAI)
        #expect(SessionKind.kind(stored: "anthropic", harness: .openCode) == .openCodeAnthropic)
        #expect(SessionKind.kind(stored: "anthropic", harness: .claudeCode) == nil)
        // Unknown values and values of another harness.
        #expect(SessionKind.kind(stored: "vertex", harness: .codex) == nil)
        #expect(SessionKind.kind(stored: "directoryOnly", harness: .openCode) == nil)
        #expect(SessionKind.kind(stored: "apiKey", harness: .claudeCode) == nil)
        #expect(SessionKind.kind(stored: "Vertex", harness: .claudeCode) == nil)
        #expect(SessionKind.kind(stored: "", harness: .claudeCode) == nil)
    }

    /// FR-012: the pop-up item and the account list subtitle.
    @Test func displayNames() {
        #expect(SessionKind.claudeCodeDirectoryOnly.displayName == "Directory only")
        #expect(SessionKind.claudeCodeVertex.displayName == "Vertex")
        #expect(SessionKind.claudeCodeOtherProvider.displayName == "Other provider")
        #expect(SessionKind.codexAPIKey.displayName == "API key")
        #expect(SessionKind.openCodeVertex.displayName == "Vertex")
        #expect(SessionKind.openCodeOpenAI.displayName == "OpenAI")
        #expect(SessionKind.openCodeAnthropic.displayName == "Anthropic")
        #expect(SessionKind.openCodeOtherProvider.displayName == "Other provider")
    }

    /// FR-004, FR-012: which kinds offer, require or show what.
    @Test func conditionAndPopUpFlags() {
        for kind in SessionKind.allCases {
            #expect(kind.offersCondition == (kind != .claudeCodeDirectoryOnly))
            #expect(kind.requiresCondition == (kind == .openCodeOtherProvider))
            #expect(kind.showsPopUp == (kind != .codexAPIKey))
        }
    }

    /// FR-011, research R7: the fallback of an unreadable setting.
    @Test func fallbackPerHarness() {
        #expect(SessionKind.fallback(for: .claudeCode) == .claudeCodeDirectoryOnly)
        #expect(SessionKind.fallback(for: .codex) == .codexAPIKey)
        #expect(SessionKind.fallback(for: .openCode) == .openCodeOtherProvider)
    }

    /// contracts/settings-ui.md: the icon follows the kind.
    @Test func defaultIcons() {
        #expect(SessionKind.claudeCodeVertex.defaultIcon == IconDefaults.vertex)
        #expect(SessionKind.openCodeVertex.defaultIcon == IconDefaults.vertex)
        #expect(SessionKind.codexAPIKey.defaultIcon == IconDefaults.openai)
        #expect(SessionKind.openCodeOpenAI.defaultIcon == IconDefaults.openai)
        #expect(SessionKind.openCodeAnthropic.defaultIcon == IconDefaults.subscription)
        #expect(SessionKind.claudeCodeDirectoryOnly.defaultIcon == IconDefaults.subscription)
        #expect(SessionKind.claudeCodeOtherProvider.defaultIcon == IconDefaults.subscription)
        #expect(SessionKind.openCodeOtherProvider.defaultIcon == IconDefaults.openCode)
    }

    /// The records of the matrix, named for the kind they belong to.
    private var samples: [(name: String, record: RawUsageRecord, kind: SessionKind?)] {
        [
            ("claude vertex", record(requestId: "req_vrtx_1"), .claudeCodeVertex),
            ("claude direct", record(requestId: "req_011abc"), nil),
            ("claude gateway", record(requestId: ""), .claudeCodeOtherProvider),
            ("claude other infix", record(requestId: "req_other_1"), nil),
            ("codex api key", record(.codex, hint: "apikey"), .codexAPIKey),
            ("codex plan", record(.codex, hint: "chatgpt"), nil),
            ("opencode vertex", record(.openCode, hint: "google-vertex"), .openCodeVertex),
            ("opencode vertex anthropic", record(.openCode, hint: "google-vertex-anthropic"), .openCodeVertex),
            ("opencode openai", record(.openCode, hint: "openai"), .openCodeOpenAI),
            ("opencode anthropic", record(.openCode, hint: "anthropic"), .openCodeAnthropic),
            ("opencode other", record(.openCode, hint: "openrouter-like-x"), .openCodeOtherProvider),
            ("opencode no provider", record(.openCode, hint: nil), nil),
            ("opencode empty provider", record(.openCode, hint: ""), nil),
            ("codex no auth", record(.codex, hint: nil), nil),
        ]
    }

    /// FR-002, SC-002: every kind matches exactly its own records, never a
    /// record of another harness; Directory only matches none.
    @Test func everyKindMatchesExactlyItsOwnRecords() {
        for kind in SessionKind.allCases {
            for sample in samples {
                let expected = sample.kind == kind
                #expect(kind.matches(record: sample.record) == expected, "\(kind) on \(sample.name)")
            }
        }
    }

    /// SC-002: the kinds of one harness are pairwise disjoint.
    @Test func kindsOfOneHarnessAreDisjoint() {
        for harness in Harness.allCases {
            for sample in samples {
                let matching = SessionKind.kinds(for: harness).filter { $0.matches(record: sample.record) }
                #expect(matching.count <= 1, "\(sample.name): \(matching)")
            }
        }
    }

    /// FR-002: the checks are exact and case-sensitive. An upper-case
    /// Vertex id is no Vertex record, and since it does not start with
    /// `req_` it counts as Other provider (research R9).
    @Test func checksAreCaseSensitive() {
        let upper = record(requestId: "REQ_VRTX_1")
        #expect(!SessionKind.claudeCodeVertex.matches(record: upper))
        #expect(SessionKind.claudeCodeOtherProvider.matches(record: upper))
        #expect(!SessionKind.openCodeOpenAI.matches(record: record(.openCode, hint: "OpenAI")))
        #expect(SessionKind.openCodeOtherProvider.matches(record: record(.openCode, hint: "OpenAI")))
        #expect(!SessionKind.codexAPIKey.matches(record: record(.codex, hint: "APIKEY")))
        #expect(!SessionKind.openCodeAnthropic.matches(record: record(.openCode, hint: "Anthropic")))
    }
}
