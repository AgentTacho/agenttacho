import Foundation

/// How a record is recognized as belonging to an account (FR-013).
public enum DetectionRule: Equatable, Sendable {
    case requestIdPrefix(String)
    case rawContains(String)
    /// `req_` followed by no provider infix (`req_011...`), research R3.
    case directRequestId
    /// The record's `providerHint` is one of the values (spec 006 FR-012).
    case providerHint(Set<String>)

    func matches(record: RawUsageRecord, rawLine: String) -> Bool {
        switch self {
        case .requestIdPrefix(let prefix):
            return record.requestId.hasPrefix(prefix)
        case .rawContains(let marker):
            return !marker.isEmpty && rawLine.contains(marker)
        case .directRequestId:
            guard record.requestId.hasPrefix("req_") else { return false }
            let remainder = record.requestId.dropFirst(4)
            return !remainder.isEmpty && !remainder.contains("_")
        case .providerHint(let hints):
            guard let hint = record.providerHint else { return false }
            return hints.contains(hint)
        }
    }
}

extension Provider {
    /// Built-in rule per provider and harness (spec 001 research R3, spec
    /// 006 FR-012, research R5). Nil when the provider has no built-in match
    /// for records of that harness.
    public func builtInRule(for harness: Harness) -> DetectionRule? {
        switch (harness, self) {
        case (.claudeCode, .vertex): return .requestIdPrefix("req_vrtx_")
        case (.claudeCode, .openai): return nil
        case (.openCode, .vertex): return .providerHint(["google-vertex", "google-vertex-anthropic"])
        case (.openCode, .openai): return .providerHint(["openai"])
        case (.codex, .vertex): return nil
        case (.codex, .openai): return .providerHint([Attributor.codexAPIKeyHint])
        }
    }
}

/// Resolves the account of each record.
///
/// Resolution order:
/// 1. An account with a custom marker matches only when the raw line contains
///    that marker; the marker replaces the account's built-in rule. Markers
///    apply to records of every harness (spec 006 FR-013).
/// 2. Without a custom marker, the built-in rule depends on the record's
///    harness (spec 006 FR-012, research R5):
///    - A token-based account matches `Provider.builtInRule(for:)`.
///    - A Claude subscription account matches a Claude Code record with a
///      direct request id (`req_` with no provider infix) that matches no
///      Claude Code token-based rule.
///    - A Codex subscription account matches a Codex record whose auth mode
///      is the ChatGPT plan (`providerHint == "chatgpt"`).
/// 3. Custom-marker matches are more specific than built-in matches, so when
///    at least one account matched through its marker only those accounts are
///    considered.
/// 4. One remaining match wins. Several remaining subscription accounts of
///    the same kind are separated by the location the record was found in:
///    the Claude configuration directory, or the Codex home (spec 006
///    FR-015). Anything else is Unassigned (nil).
public struct Attributor: Sendable {
    private enum CandidateKind: Equatable, CustomStringConvertible {
        case anthropicSubscription
        case codexSubscription
        case tokenBased(Provider)

        var description: String {
            switch self {
            case .anthropicSubscription: return "subscription"
            case .codexSubscription: return "codexSubscription"
            case .tokenBased(let provider): return "tokenBased(\(provider.rawValue))"
            }
        }

        var isSubscription: Bool { self == .anthropicSubscription || self == .codexSubscription }
    }

    private struct Candidate {
        let id: String
        let kind: CandidateKind
        let customMarker: String?
        /// Canonical credential directory or Codex home for the tie-breaker.
        let directory: String?
    }

    /// Codex auth mode hint for ChatGPT-plan sessions (spec 006 FR-014).
    public static let codexPlanHint = "chatgpt"
    /// Codex auth mode hint for API-key sessions (spec 006 FR-014).
    public static let codexAPIKeyHint = "apikey"

    private let candidates: [Candidate]
    /// Built-in rules of the token-based accounts without a custom marker,
    /// for Claude Code records only: a direct request id that matches one of
    /// them is not subscription usage.
    private let claudeCodeTokenRules: [DetectionRule]

    public init(configuration: Configuration, paths: Paths = Paths()) {
        var tokenRules: [DetectionRule] = []
        var result: [Candidate] = []
        for account in configuration.accounts {
            let marker = account.customMarker.flatMap { $0.isEmpty ? nil : $0 }
            switch account.kind {
            case .tokenBased(let settings):
                if marker == nil, let rule = settings.provider.builtInRule(for: .claudeCode) { tokenRules.append(rule) }
                result.append(Candidate(id: account.id, kind: .tokenBased(settings.provider), customMarker: marker, directory: nil))
            case .subscription(let settings):
                result.append(Candidate(id: account.id, kind: .anthropicSubscription, customMarker: marker,
                                        directory: Attributor.canonical(paths.expand(settings.credentialDirectory))))
            case .codexSubscription(let settings):
                result.append(Candidate(id: account.id, kind: .codexSubscription, customMarker: marker,
                                        directory: Attributor.canonical(paths.expand(settings.codexHome))))
            }
        }
        self.candidates = result
        self.claudeCodeTokenRules = tokenRules
        self.fingerprint = result.map {
            "\($0.id)|\($0.kind)|\($0.customMarker ?? "")|\($0.directory ?? "")"
        }.joined(separator: "\n")
    }

    /// Changes whenever the attribution rules change; the sources re-attribute then.
    public let fingerprint: String

    /// True when some account has a custom marker, so callers only build
    /// the raw line text when it can matter.
    public var usesCustomMarkers: Bool { candidates.contains { $0.customMarker != nil } }

    /// `fileConfigDirectory` is the location the record was found in: the
    /// Claude configuration directory, the Codex home, or the OpenCode data
    /// directory.
    public func accountId(for record: RawUsageRecord, rawLine: String, fileConfigDirectory: String) -> String? {
        var markerMatches: [Candidate] = []
        var builtInMatches: [Candidate] = []
        let matchesClaudeTokenRule = record.harness == .claudeCode
            && claudeCodeTokenRules.contains { $0.matches(record: record, rawLine: rawLine) }

        for candidate in candidates {
            if let marker = candidate.customMarker {
                if DetectionRule.rawContains(marker).matches(record: record, rawLine: rawLine) {
                    markerMatches.append(candidate)
                }
            } else if builtInMatch(candidate.kind, record: record, rawLine: rawLine, matchesClaudeTokenRule: matchesClaudeTokenRule) {
                builtInMatches.append(candidate)
            }
        }

        let matches = markerMatches.isEmpty ? builtInMatches : markerMatches
        if matches.count == 1 { return matches[0].id }
        guard matches.count > 1, let kind = matches.first?.kind, kind.isSubscription,
              matches.allSatisfy({ $0.kind == kind }) else { return nil }

        let fileDirectory = Attributor.canonical(fileConfigDirectory)
        let byDirectory = matches.filter { $0.directory == fileDirectory }
        return byDirectory.count == 1 ? byDirectory[0].id : nil
    }

    private func builtInMatch(_ kind: CandidateKind, record: RawUsageRecord, rawLine: String, matchesClaudeTokenRule: Bool) -> Bool {
        switch kind {
        case .tokenBased(let provider):
            return provider.builtInRule(for: record.harness)?.matches(record: record, rawLine: rawLine) ?? false
        case .anthropicSubscription:
            return record.harness == .claudeCode && !matchesClaudeTokenRule
                && DetectionRule.directRequestId.matches(record: record, rawLine: rawLine)
        case .codexSubscription:
            return record.harness == .codex && record.providerHint == Attributor.codexPlanHint
        }
    }

    static func canonical(_ path: String) -> String {
        var p = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }
}
