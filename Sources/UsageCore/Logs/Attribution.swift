import Foundation

/// How a record is recognized as belonging to an account (FR-013).
public enum DetectionRule: Equatable, Sendable {
    case rawContains(String)
    /// `req_` followed by no provider infix (`req_011...`), research R3.
    case directRequestId

    func matches(record: RawUsageRecord, rawLine: String) -> Bool {
        switch self {
        case .rawContains(let marker):
            return !marker.isEmpty && rawLine.contains(marker)
        case .directRequestId:
            guard record.requestId.hasPrefix("req_") else { return false }
            let remainder = record.requestId.dropFirst(4)
            return !remainder.isEmpty && !remainder.contains("_")
        }
    }
}

/// Resolves the account of each record.
///
/// Profile step (spec 037 FR-003 step 1, spec 038 FR-003), for Claude Code
/// records whose session file names a configuration directory: exactly one
/// account (a Claude subscription or a token-based Claude Code account) with
/// that main directory wins, whatever its kind and condition say; without
/// one, exactly one account listing it as an additional session directory
/// wins. Several claimants at the deciding rank restrict the rule step to
/// them; no claimant leaves all accounts in the rule step.
///
/// Rule step (spec 038 FR-004, FR-006, research R11):
/// 1. Kind: a token-based account matches the records of its session kind
///    (Directory only none, a kind that requires a condition only with
///    one); a Claude subscription matches Claude Code records with a direct
///    request id (`req_` with no provider infix); a Codex subscription
///    matches Codex records whose auth mode is the ChatGPT plan
///    (`providerHint == "chatgpt"`). The kinds are disjoint, so the rest of
///    the step only ever compares accounts of one kind.
/// 2. Condition: a token-based account's effective condition (through the
///    time-limited `MatchRuntime`) or a subscription's custom marker (the raw
///    line contains it, case-sensitive) narrows its kind; a candidate whose
///    condition does not match is out.
/// 3. Choice: the accounts whose condition matched, if any, else those
///    without a condition. One wins. Several subscription accounts of the
///    same kind are separated by the location the record was found in: the
///    Claude configuration directory, or the Codex home (spec 006 FR-015).
///    An account's additional session directories count as its own, ranked
///    below main directories: exactly one main claim wins, else exactly one
///    additional claim (spec 035 FR-012). Anything else is Unassigned (nil).
public struct Attributor: Sendable {
    private enum CandidateKind: Equatable, CustomStringConvertible {
        case anthropicSubscription
        case codexSubscription
        /// A token-based account's kind and effective condition (spec 038
        /// FR-004, research R10).
        case tokenBased(SessionKind, MatchCondition?)

        /// Part of the fingerprint, so a kind or condition change
        /// re-attributes (spec 038 FR-019).
        var description: String {
            switch self {
            case .anthropicSubscription: return "subscription"
            case .codexSubscription: return "codexSubscription"
            case .tokenBased(let kind, let condition):
                let text = condition.map { "\($0.field.rawValue),\($0.operator.rawValue),\($0.text)" } ?? "-"
                return "tokenBased(\(kind.rawValue),\(text))"
            }
        }

        var isSubscription: Bool { self == .anthropicSubscription || self == .codexSubscription }

        /// True when `record` is of this candidate's kind (spec 038 FR-002,
        /// research R11 step 1): a token-based kind's exact check, which an
        /// account whose kind requires a condition passes only with one; a
        /// direct request id for a Claude subscription; the ChatGPT-plan
        /// hint for a Codex subscription.
        func matchesKind(_ record: RawUsageRecord, rawLine: String) -> Bool {
            switch self {
            case .tokenBased(let kind, let condition):
                if kind.requiresCondition && condition == nil { return false }
                return kind.matches(record: record)
            case .anthropicSubscription:
                return record.harness == .claudeCode && DetectionRule.directRequestId.matches(record: record, rawLine: rawLine)
            case .codexSubscription:
                return record.harness == .codex && record.providerHint == Attributor.codexPlanHint
            }
        }
    }

    private struct Candidate {
        let id: String
        let kind: CandidateKind
        /// A subscription's custom marker; nil for token-based accounts,
        /// whose marker became a condition (spec 038 FR-011).
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

        /// True when the candidate has a condition: a token-based
        /// account's effective condition or a subscription's custom marker
        /// (spec 038 FR-004, FR-006).
        var hasCondition: Bool {
            if customMarker != nil { return true }
            if case .tokenBased(_, let condition) = kind { return condition != nil }
            return false
        }

        /// The candidate's condition matches `record`: a subscription's
        /// marker as a case-sensitive raw-line check, a token-based
        /// account's condition through `runtime`. Callers check the kind
        /// first, so a condition only runs, and only times out, on records
        /// of its kind (spec 038 FR-005, FR-007, research R11 step 2).
        func conditionMatch(_ record: RawUsageRecord, rawLine: String, runtime: MatchRuntime) -> Bool {
            if let marker = customMarker { return DetectionRule.rawContains(marker).matches(record: record, rawLine: rawLine) }
            return runtime.matches(candidateId: id, record: record, rawLine: rawLine)
        }
    }

    /// Codex auth mode hint for ChatGPT-plan sessions (spec 006 FR-014).
    public static let codexPlanHint = "chatgpt"
    /// Codex auth mode hint for API-key sessions (spec 006 FR-014).
    public static let codexAPIKeyHint = "apikey"

    private let candidates: [Candidate]
    /// The conditions of the token-based accounts with their time limit
    /// and sit-out state; one per attributor, so per source and refresh,
    /// and shared by copies (spec 038 FR-007, research R4).
    private let matchRuntime: MatchRuntime

    /// `additionalDirectories` maps a subscription account id to the
    /// canonical additional directories of the current refresh (spec 035
    /// FR-012, research R5). `profileAdditionalDirectories` maps the id of
    /// any Claude Code account, token-based ones included, to its canonical
    /// additional Claude Code directories, for the profile step only; the
    /// rule-step tie-breaker stays limited to subscriptions (spec 037
    /// FR-003). `matchTimeLimit` bounds a condition's regex per record
    /// (spec 038 FR-007); tests inject a shorter one.
    public init(configuration: Configuration, paths: Paths = Paths(), additionalDirectories: [String: Set<String>] = [:],
                profileAdditionalDirectories: [String: Set<String>] = [:], matchTimeLimit: Duration = MatchCondition.regexLimit,
                matchMemory: MatchMemory = MatchMemory()) {
        var result: [Candidate] = []
        var conditions: [MatchRuntime.Entry] = []
        for account in configuration.accounts {
            let marker = account.customMarker.flatMap { $0.isEmpty ? nil : $0 }
            switch account.kind {
            case .tokenBased(let settings):
                let condition = settings.effectiveCondition
                if let condition {
                    conditions.append(MatchRuntime.Entry(id: account.id, name: account.displayName, condition: condition))
                }
                var candidate = Candidate(id: account.id, kind: .tokenBased(settings.sessionKind, condition),
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
        // Additional directories stay out of the fingerprint, so neither a
        // new sandbox folder nor an edited list rereads the whole index; the
        // sources compare `claimKey(forDirectory:)` per directory instead
        // (spec 035 FR-012, research R5). Kind, effective condition and the
        // main directory of the profile step are in it (spec 037 plan
        // "Attribution", spec 038 FR-019).
        self.fingerprint = result.map {
            "\($0.id)|\($0.kind)|\($0.customMarker ?? "")|\($0.directory ?? "")|\($0.profileDirectory ?? "")"
        }.joined(separator: "\n")
        // The memory of the source's last refresh, unless the rules changed
        // since (spec 038 FR-007, SC-005).
        self.matchRuntime = MatchRuntime(rules: conditions, limit: matchTimeLimit,
                                         memory: matchMemory.fingerprint == fingerprint ? matchMemory : MatchMemory(fingerprint: fingerprint))
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
    /// account's effective condition searches the raw line, so callers only
    /// build the raw line text when it can matter (spec 037 plan
    /// "Attribution", spec 038 FR-004).
    public var needsRawLine: Bool {
        candidates.contains { candidate in
            if candidate.customMarker != nil { return true }
            if case .tokenBased(_, let condition) = candidate.kind { return condition?.needsRawLine ?? false }
            return false
        }
    }

    /// How many conditions timed out in this attributor; a source that
    /// keeps attributed records attributes them again on the next refresh
    /// when it is not zero (spec 038 FR-007, research R5).
    public var timeOuts: Int { matchRuntime.timeOuts }

    /// Grows on every time-out and on every record a sat-out rule was
    /// skipped for, so `LogIndex` re-reads exactly the files such a rule
    /// could have decided differently (spec 038 research R5).
    public var skippedDecisions: Int { matchRuntime.skippedDecisions }

    /// Runs `attribute` over the records of one file, session or message
    /// and tells whether they must be attributed again on the next
    /// refresh: a rule sat out or timed out while they were attributed.
    /// A `retry` (that next attribution) is not marked again for a rule
    /// that timed out in it, so a record a rule is always slow on costs
    /// one retry, while records that only sat out because of another
    /// file's slow record, or of another rule, are tried again (spec 038
    /// FR-007, SC-005).
    public func tracking<T>(retry: Bool, _ attribute: () -> T) -> (result: T, reattribute: Bool) {
        let before = matchRuntime.snapshot()
        let result = attribute()
        let after = matchRuntime.snapshot()
        return (result, matchRuntime.needsReattribution(from: before, to: after, retry: retry))
    }

    /// What the source keeps for its next attributor (spec 038 FR-007,
    /// SC-005).
    public var matchMemory: MatchMemory { matchRuntime.memory }

    /// The display names of the accounts whose rule started sitting out
    /// since the last call, for one log line each per refresh (spec 038
    /// FR-007).
    public func drainSitOutAccounts() -> [String] { matchRuntime.drainSitOutAccounts() }

    /// The log line for an account whose condition sat out (spec 038
    /// FR-007, research R5).
    public static func sitOutLogLine(account name: String) -> String {
        "account \"\(Configuration.clipped(name))\": condition took longer than 50 ms on one record and was skipped for the rest of this refresh"
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

    /// The rule step over `pool` (spec 038 FR-004, FR-006, research R11).
    private func ruleStep(_ record: RawUsageRecord, rawLine: String, fileConfigDirectory: String,
                          among pool: [Candidate]) -> String? {
        var conditioned: [Candidate] = []
        var plain: [Candidate] = []
        for candidate in pool {
            // Kind first: a condition or marker only narrows its kind and
            // never takes a record of another kind (spec 038 FR-004, FR-006).
            guard candidate.kind.matchesKind(record, rawLine: rawLine) else { continue }
            if candidate.hasCondition {
                if candidate.conditionMatch(record, rawLine: rawLine, runtime: matchRuntime) { conditioned.append(candidate) }
            } else {
                plain.append(candidate)
            }
        }

        let matches = conditioned.isEmpty ? plain : conditioned
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

    static func canonical(_ path: String) -> String {
        var p = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }
}
