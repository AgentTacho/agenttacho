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

/// Resolves the account of each record.
///
/// Profile step (spec 037 FR-003 step 1), for Claude Code records whose
/// session file names a configuration directory: exactly one account (a
/// Claude subscription or a token-based Claude Code account) with that main
/// directory wins; without one, exactly one account listing it as an
/// additional session directory wins. Several claimants at the deciding
/// rank restrict the rule step to them; no claimant leaves all accounts in
/// the rule step.
///
/// Rule step (spec 037 FR-003 step 2):
/// 1. Token-based accounts match only records of their own harness (spec
///    037 FR-008). A subscription's custom marker matches when the raw line
///    contains it and applies to records of every harness (spec 006
///    FR-013); a token-based account's custom rule compares its field
///    (spec 037 FR-007).
/// 2. Custom matches are more specific than built-in matches, so when at
///    least one account matched through its custom marker or rule only
///    those accounts are considered (spec 037 FR-010).
/// 3. Otherwise the built-in rules decide:
///    - A token-based account matches its preset; `none` never matches.
///    - A Claude subscription account matches a Claude Code record with a
///      direct request id (`req_` with no provider infix) that matches no
///      Claude Code token-based preset.
///    - A Codex subscription account matches a Codex record whose auth mode
///      is the ChatGPT plan (`providerHint == "chatgpt"`).
/// 4. One remaining match wins. Several remaining subscription accounts of
///    the same kind are separated by the location the record was found in:
///    the Claude configuration directory, or the Codex home (spec 006
///    FR-015). An account's additional session directories count as its
///    own, ranked below main directories: exactly one main claim wins,
///    else exactly one additional claim (spec 035 FR-012). Anything else is
///    Unassigned (nil).
public struct Attributor: Sendable {
    private enum CandidateKind: Equatable, CustomStringConvertible {
        case anthropicSubscription
        case codexSubscription
        case tokenBased(Harness, MatchRule)

        var description: String {
            switch self {
            case .anthropicSubscription: return "subscription"
            case .codexSubscription: return "codexSubscription"
            case .tokenBased(let harness, let rule): return "tokenBased(\(harness.rawValue),\(rule))"
            }
        }

        var isSubscription: Bool { self == .anthropicSubscription || self == .codexSubscription }
    }

    private struct Candidate {
        let id: String
        let kind: CandidateKind
        /// A subscription's custom marker; nil for token-based accounts,
        /// whose marker became their rule (spec 037 FR-014).
        let customMarker: String?
        /// Canonical credential directory or Codex home for the tie-breaker.
        let directory: String?
        /// Canonical additional session directories (literal entries and
        /// wildcard matches) of a subscription account, ranked below
        /// `directory` (spec 035 FR-012).
        var additional: Set<String> = []
        /// Canonical main Claude Code directory of a Claude subscription or
        /// a token-based Claude Code account, for the profile step (spec
        /// 037 FR-003); nil for other accounts.
        var profileDirectory: String? = nil
        /// Canonical additional Claude Code directories of any Claude Code
        /// account, for the profile step only (spec 037 FR-003).
        var profileAdditional: Set<String> = []

        /// The candidate's rule claims `record` through a custom marker or
        /// custom rule.
        func customMatch(_ record: RawUsageRecord, rawLine: String) -> Bool {
            if let marker = customMarker { return DetectionRule.rawContains(marker).matches(record: record, rawLine: rawLine) }
            if case .tokenBased(let harness, let rule) = kind, rule.isCustom {
                return harness == record.harness && rule.matches(record: record, rawLine: rawLine)
            }
            return false
        }

        /// True when the candidate has a custom marker or custom rule, which
        /// replaces its built-in rule.
        var isCustom: Bool {
            if customMarker != nil { return true }
            if case .tokenBased(_, let rule) = kind { return rule.isCustom }
            return false
        }
    }

    /// Codex auth mode hint for ChatGPT-plan sessions (spec 006 FR-014).
    public static let codexPlanHint = "chatgpt"
    /// Codex auth mode hint for API-key sessions (spec 006 FR-014).
    public static let codexAPIKeyHint = "apikey"

    private let candidates: [Candidate]
    /// Presets of the token-based Claude Code accounts: a direct request id
    /// that matches one of them is not subscription usage.
    private let claudeCodeTokenRules: [DetectionRule]

    /// `additionalDirectories` maps a subscription account id to the
    /// canonical additional directories of the current refresh (spec 035
    /// FR-012, research R5). `profileAdditionalDirectories` maps the id of
    /// any Claude Code account, token-based ones included, to its canonical
    /// additional Claude Code directories, for the profile step only; the
    /// rule-step tie-breaker stays limited to subscriptions (spec 037
    /// FR-003).
    public init(configuration: Configuration, paths: Paths = Paths(), additionalDirectories: [String: Set<String>] = [:],
                profileAdditionalDirectories: [String: Set<String>] = [:]) {
        var tokenRules: [DetectionRule] = []
        var result: [Candidate] = []
        for account in configuration.accounts {
            let marker = account.customMarker.flatMap { $0.isEmpty ? nil : $0 }
            switch account.kind {
            case .tokenBased(let settings):
                if case .preset(let preset) = settings.matchRule, settings.harness == .claudeCode, preset.harness == .claudeCode {
                    tokenRules.append(preset.detectionRule)
                }
                var candidate = Candidate(id: account.id, kind: .tokenBased(settings.harness, settings.matchRule),
                                          customMarker: nil, directory: nil)
                if settings.harness == .claudeCode, let main = settings.effectiveSessionDirectory {
                    candidate.profileDirectory = Attributor.canonical(paths.expand(main))
                    candidate.profileAdditional = profileAdditionalDirectories[account.id] ?? []
                }
                result.append(candidate)
            case .subscription(let settings):
                let main = Attributor.canonical(paths.expand(settings.credentialDirectory))
                result.append(Candidate(id: account.id, kind: .anthropicSubscription, customMarker: marker,
                                        directory: main, additional: additionalDirectories[account.id] ?? [],
                                        profileDirectory: main,
                                        profileAdditional: profileAdditionalDirectories[account.id] ?? additionalDirectories[account.id] ?? []))
            case .codexSubscription(let settings):
                result.append(Candidate(id: account.id, kind: .codexSubscription, customMarker: marker,
                                        directory: Attributor.canonical(paths.expand(settings.codexHome)),
                                        additional: additionalDirectories[account.id] ?? []))
            }
        }
        self.candidates = result
        self.claudeCodeTokenRules = tokenRules
        // Additional directories stay out of the fingerprint, so neither a
        // new sandbox folder nor an edited list rereads the whole index; the
        // sources compare `claimKey(forDirectory:)` per directory instead
        // (spec 035 FR-012, research R5). Harness, rule and the main
        // directory of the profile step are in it (spec 037 FR-011, plan
        // "Attribution").
        self.fingerprint = result.map {
            "\($0.id)|\($0.kind)|\($0.customMarker ?? "")|\($0.directory ?? "")|\($0.profileDirectory ?? "")"
        }.joined(separator: "\n")
        var counts: [String: Int] = [:]
        for candidate in result where candidate.kind.isSubscription { counts[candidate.kind.description, default: 0] += 1 }
        self.tieBreakKinds = Set(counts.filter { $0.value > 1 }.keys)
    }

    /// Subscription kinds with more than one account: only there can an
    /// additional directory decide a record (spec 035 FR-012).
    private let tieBreakKinds: Set<String>

    /// The subscription accounts that claim `directory` as an additional
    /// directory and could use the claim in the tie-breaker, as one text.
    /// A source keeps the key a directory's records were attributed with
    /// and attributes them again when it changes, for example when a
    /// wildcard match appears, disappears or leaves the cap (spec 035
    /// FR-005, FR-012). Empty for a directory no such account claims.
    public func claimKey(forDirectory directory: String) -> String {
        guard !tieBreakKinds.isEmpty else { return "" }
        let canonical = Attributor.canonical(directory)
        return candidates
            .filter { tieBreakKinds.contains($0.kind.description) && $0.additional.contains(canonical) }
            .map(\.id).sorted().joined(separator: ",")
    }

    /// Changes whenever the attribution rules change; the sources re-attribute then.
    public let fingerprint: String

    /// True when some subscription has a custom marker or some token-based
    /// rule searches the raw line, so callers only build the raw line text
    /// when it can matter (spec 037 plan "Attribution").
    public var needsRawLine: Bool {
        candidates.contains { candidate in
            if candidate.customMarker != nil { return true }
            if case .tokenBased(_, let rule) = candidate.kind { return rule.needsRawLine }
            return false
        }
    }

    /// `fileConfigDirectory` is the location the record was found in: the
    /// Claude configuration directory, the Codex home, or the OpenCode data
    /// directory. `profileDirectory` is the canonical configuration
    /// directory the record's session file names (spec 037 FR-001), nil
    /// when it names none; only Claude Code records use it (FR-005).
    public func accountId(for record: RawUsageRecord, rawLine: String, fileConfigDirectory: String,
                          profileDirectory: String? = nil) -> String? {
        var pool = candidates
        if record.harness == .claudeCode, let profile = profileDirectory {
            let mains = candidates.filter { $0.profileDirectory == profile }
            if mains.count == 1 { return mains[0].id }
            if mains.count > 1 {
                pool = mains
            } else {
                let additional = candidates.filter { $0.profileDirectory != nil && $0.profileAdditional.contains(profile) }
                if additional.count == 1 { return additional[0].id }
                if additional.count > 1 { pool = additional }
            }
        }
        return ruleStep(record, rawLine: rawLine, fileConfigDirectory: fileConfigDirectory, among: pool)
    }

    /// The rule step over `pool` (spec 037 FR-003 step 2).
    private func ruleStep(_ record: RawUsageRecord, rawLine: String, fileConfigDirectory: String,
                          among pool: [Candidate]) -> String? {
        var customMatches: [Candidate] = []
        var builtInMatches: [Candidate] = []
        let matchesClaudeTokenRule = record.harness == .claudeCode
            && claudeCodeTokenRules.contains { $0.matches(record: record, rawLine: rawLine) }

        for candidate in pool {
            if candidate.isCustom {
                if candidate.customMatch(record, rawLine: rawLine) { customMatches.append(candidate) }
            } else if builtInMatch(candidate.kind, record: record, rawLine: rawLine, matchesClaudeTokenRule: matchesClaudeTokenRule) {
                builtInMatches.append(candidate)
            }
        }

        let matches = customMatches.isEmpty ? builtInMatches : customMatches
        if matches.count == 1 { return matches[0].id }
        guard matches.count > 1, let kind = matches.first?.kind, kind.isSubscription,
              matches.allSatisfy({ $0.kind == kind }) else { return nil }

        let fileDirectory = Attributor.canonical(fileConfigDirectory)
        let byDirectory = matches.filter { $0.directory == fileDirectory }
        if byDirectory.count == 1 { return byDirectory[0].id }
        guard byDirectory.isEmpty else { return nil }
        // No main claim: exactly one additional claim decides (spec 035 FR-012).
        let byAdditional = matches.filter { $0.additional.contains(fileDirectory) }
        return byAdditional.count == 1 ? byAdditional[0].id : nil
    }

    private func builtInMatch(_ kind: CandidateKind, record: RawUsageRecord, rawLine: String, matchesClaudeTokenRule: Bool) -> Bool {
        switch kind {
        case .tokenBased(let harness, let rule):
            return harness == record.harness && rule.matches(record: record, rawLine: rawLine)
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
