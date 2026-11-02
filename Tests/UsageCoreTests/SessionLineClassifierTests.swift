import Foundation
import Testing
@testable import UsageCore

/// A line's record type from its top-level `type` member, read by bounded
/// head and tail scans with today's whole-line marker search as the
/// fallback (spec 039 FR-013, FR-014, research R4).
@Suite struct SessionLineClassifierTests {
    static func kind(_ text: String) -> SessionLineKind { kind(Data(text.utf8)) }
    static func kind(_ data: Data) -> SessionLineKind { data.withUnsafeBytes { SessionLineClassifier.classify($0) } }
    static func head(_ text: String) -> SessionLineKind? { Data(text.utf8).withUnsafeBytes { SessionLineClassifier.headScan($0) } }
    static func head(_ data: Data) -> SessionLineKind? { data.withUnsafeBytes { SessionLineClassifier.headScan($0) } }
    static func tail(_ text: String) -> SessionLineKind? { Data(text.utf8).withUnsafeBytes { SessionLineClassifier.tailScan($0) } }
    static func tail(_ data: Data) -> SessionLineKind? { data.withUnsafeBytes { SessionLineClassifier.tailScan($0) } }
    static func fallback(_ data: Data) -> SessionLineKind { data.withUnsafeBytes { SessionLineClassifier.markerFallback($0) } }

    /// The four markers today's parser and shape detection search.
    static let assistantMarkers = [Data(#""type":"assistant""#.utf8), Data(#""type": "assistant""#.utf8)]
    static let shapeMarkers = [Data(#""type":"api-request-shape""#.utf8), Data(#""type": "api-request-shape""#.utf8)]
    static func hasMarker(_ line: Data, _ markers: [Data]) -> Bool { markers.contains { line.range(of: $0) != nil } }

    /// A message object of about `size` bytes, so the line's own `type`
    /// sits beyond the head window.
    static func message(_ size: Int = 400) -> String {
        #"{"id":"msg_c","model":"claude-opus-4-6","role":"assistant","content":[{"type":"text","text":"\#(String(repeating: "m", count: size))"}],"usage":{"input_tokens":1,"output_tokens":2}}"#
    }

    // MARK: Head and tail decisions

    @Test func headDecidesUserShapeAndSystemLines() {
        let user = #"{"type":"user","timestamp":"2026-10-15T10:00:00.000Z","message":{"role":"user","content":"hi"}}"#
        let shape = #"{"type":"api-request-shape","sessionId":"s","shape":{"system":[{"type":"text","text":"x"}]}}"#
        let system = #"{"type":"system","subtype":"turn_duration","durationMs":12}"#
        #expect(Self.head(user) == .other)
        #expect(Self.kind(user) == .other)
        #expect(Self.head(shape) == .shape)
        #expect(Self.kind(shape) == .shape)
        #expect(Self.head(system) == .other)
        #expect(Self.kind(system) == .other)
    }

    @Test func tailDecidesAnAssistantLine() {
        let line = #"{"parentUuid":"u1","message":\#(Self.message()),"requestId":"req_vrtx_1","timestamp":"2026-10-15T10:00:00.000Z","type":"assistant"}"#
        #expect(Self.head(line) == nil)
        #expect(Self.tail(line) == .assistant)
        #expect(Self.kind(line) == .assistant)
    }

    /// The four lines of the nested-type fixture (spec 039 T018).
    @Test func nestedTypeKeyFixtureLines() throws {
        let data = try Data(contentsOf: try Fixtures.url("scan/claude/projects/fixture-project/nested-type-key.jsonl"))
        let lines = data.split(separator: 0x0A).map { Data($0) }
        try #require(lines.count == 4)
        // (a) a nested {"type":"user"} in the head: the tail decides.
        #expect(Self.head(lines[0]) == nil)
        #expect(Self.kind(lines[0]) == .assistant)
        // (b) the line's own type outside both windows: the fallback.
        #expect(Self.head(lines[1]) == nil)
        #expect(Self.tail(lines[1]) == nil)
        #expect(Self.kind(lines[1]) == .undecided)
        // (c) the marker only as escaped text in a string.
        #expect(Self.kind(lines[2]) == .other)
        // (d) a user line with an unescaped nested assistant object.
        #expect(Self.head(lines[3]) == .other)
        #expect(Self.kind(lines[3]) == .other)
    }

    @Test func aSpaceAfterTheColonIsTheSameKey() {
        #expect(Self.kind(#"{"message":\#(Self.message()),"type": "assistant"}"#) == .assistant)
        #expect(Self.kind(#"{"type": "api-request-shape","shape":{}}"#) == .shape)
        #expect(Self.kind(#"{ "type" : "user" }"#) == .other)
    }

    /// A `"type"` key inside a string value never counts, also when the
    /// string ends in escaped backslashes, which the backward scan tells
    /// apart from an escaped quote by their parity.
    @Test func typeKeysInsideStringsDoNotCount() {
        let escapedInText = #"{"text":"say \"type\":\"assistant\" here","type":"user"}"#
        #expect(Self.kind(escapedInText) == .other)
        let trailingBackslashes = #"{"message":\#(Self.message()),"type":"assistant","path":"C:\\\\"}"#
        #expect(Self.head(trailingBackslashes) == nil)
        #expect(Self.tail(trailingBackslashes) == .assistant)
        let escapedTypeAfter = #"{"message":\#(Self.message()),"type":"assistant","note":"\"type\":\"user\" \\\\"}"#
        #expect(Self.tail(escapedTypeAfter) == .assistant)
        let escapedQuoteBeforeEnd = #"{"message":\#(Self.message()),"type":"assistant","note":"a \" b \\\" c"}"#
        #expect(Self.tail(escapedQuoteBeforeEnd) == .assistant)
        let headBackslashes = #"{"note":"x \\\\","type":"api-request-shape"}"#
        #expect(Self.head(headBackslashes) == .shape)
    }

    @Test func anUnknownTopLevelTypeIsOther() {
        #expect(Self.kind(#"{"type":"progress","data":{"type":"assistant"}}"#) == .other)
        #expect(Self.kind(#"{"type":"file-history-snapshot","snapshot":{}}"#) == .other)
    }

    /// A top-level `type` with a value that is not a string decides the
    /// line as `.other`; no nested key decides instead.
    @Test func aNonStringTopLevelTypeIsOther() {
        #expect(Self.kind(#"{"type":1,"message":{"type":"assistant","usage":{}}}"#) == .other)
        #expect(Self.kind(#"{"type":null,"x":{"type":"assistant"}}"#) == .other)
        #expect(Self.kind(#"{"x":\#(Self.message()),"type":{"inner":"assistant"},"y":"\#(String(repeating: "q", count: 300))"}"#) == .other)
    }

    @Test func aLineWithoutAnyTypeKeyIsOther() {
        #expect(Self.kind(#"{"a":1}"#) == .other)
        #expect(Self.kind(#"{"long":"\#(String(repeating: "z", count: 9000))"}"#) == .other)
    }

    /// The scans cannot decide; both markers occur: today's path decides.
    @Test func anUndecidableLineWithBothMarkersIsUndecided() {
        #expect(Self.kind(#"{"x":{"type":"assistant"},"y":{"type":"api-request-shape"}}"#) == .undecided)
    }

    /// An escaped top-level value cannot be compared as bytes, so today's
    /// path decides it.
    @Test func anEscapedTopLevelValueIsLeftToTodaysPath() {
        #expect(Self.kind(#"{"type":"assist\u0061nt","x":{"type":"assistant"}}"#) == .undecided)
        #expect(Self.kind(#"{"type":"assist\u0061nt"}"#) == .other)
    }

    @Test func linesShorterThanTheBudgets() {
        #expect(Self.kind(#"{"type":"assistant"}"#) == .assistant)
        #expect(Self.kind(#"{"type":"api-request-shape"}"#) == .shape)
        #expect(Self.kind("{}") == .other)
        #expect(Self.kind("x") == .other)
        #expect(Self.kind(#""type":"assistant""#) == .undecided)
        #expect(Self.kind(#"{"type":"assistant""#) == .assistant)
        #expect(Self.kind(#"[{"type":"assistant"}]"#) == .undecided)
    }

    // MARK: Equivalence with today's code over every fixture line

    @Test func everyFixtureLineIsClassifiedAsTodaysCodeDecidesIt() throws {
        let root = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        let parser = SessionRecordParser()
        let candidates = SessionProfile.Candidates(entries: [SessionProfile.Entry(accountId: "acc-max", path: "/fixture/claude-a", rank: .main)])
        var checked = 0
        var kinds: [SessionLineKind: Int] = [:]
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let data = try Data(contentsOf: url)
            for slice in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
                var line = Data(slice)
                if line.last == 0x0D { line.removeLast() }
                guard !line.isEmpty else { continue }
                checked += 1
                let kind = Self.kind(line)
                kinds[kind, default: 0] += 1
                let name = "\(url.lastPathComponent) line \(String(decoding: line.prefix(80), as: UTF8.self))"
                let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
                let topType = object?["type"] as? String
                let anyMarker = Self.hasMarker(line, Self.assistantMarkers + Self.shapeMarkers)
                if object != nil {
                    switch kind {
                    case .assistant: #expect(topType == "assistant", "\(name)")
                    case .shape: #expect(topType == "api-request-shape", "\(name)")
                    case .other: #expect((topType != "assistant" && topType != "api-request-shape") || !anyMarker, "\(name)")
                    case .undecided: #expect(anyMarker, "\(name)")
                    }
                } else {
                    if kind == .shape { #expect(Self.hasMarker(line, Self.shapeMarkers), "\(name)") }
                    let last = line.last { $0 != 0x20 && $0 != 0x09 && $0 != 0x0D }
                    if last != UInt8(ascii: "}") {
                        #expect(kind == (Self.head(line) ?? Self.fallback(line)), "\(name)")
                    }
                }
                if parser.parse(data: line) != nil {
                    #expect(kind == .assistant || kind == .undecided, "\(name)")
                }
                if SessionProfile.detect(line: line, candidates: candidates) != .notShape, topType == "api-request-shape" {
                    #expect(kind == .shape || kind == .undecided, "\(name)")
                }
            }
        }
        #expect(checked > 100)
        #expect((kinds[.assistant] ?? 0) > 20)
        #expect((kinds[.shape] ?? 0) >= 1)
        #expect((kinds[.undecided] ?? 0) >= 1)
    }
}
