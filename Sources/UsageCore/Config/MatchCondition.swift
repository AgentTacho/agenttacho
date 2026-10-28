import Foundation

/// The record field a condition compares (spec 038 FR-004, data-model
/// "MatchField").
public enum MatchField: String, CaseIterable, Equatable, Hashable, Sendable {
    case model
    case requestId
    case messageId
    /// The raw record line, including tool inputs and outputs.
    case anywhere

    /// The value of `condition.field` in the configuration file.
    public var storedValue: String { rawValue }

    /// The fields offered for `harness`, in pop-up order: "Anywhere in the
    /// record line" always comes last (spec 037 FR-007).
    public static func fields(for harness: Harness) -> [MatchField] {
        switch harness {
        case .claudeCode: return [.model, .requestId, .messageId, .anywhere]
        case .codex, .openCode: return [.model, .anywhere]
        }
    }

    /// The value a condition compares: the record's field, or for `anywhere` the
    /// raw record line (spec 038 FR-004).
    func value(of record: RawUsageRecord, rawLine: String) -> String {
        switch self {
        case .model: return record.model
        case .requestId: return record.requestId
        case .messageId: return record.messageId
        case .anywhere: return rawLine
        }
    }
}

/// How a condition compares its text with the field (spec 038 FR-005,
/// data-model "MatchOperator").
public enum MatchOperator: String, CaseIterable, Equatable, Hashable, Sendable {
    case startsWith
    case contains
    case regex

    /// The value of `condition.operator` in the configuration file
    /// (spec 038 FR-010, contracts/configuration.md).
    public var storedValue: String { rawValue }

    /// The operators `field` offers, in pop-up order: Anywhere in the
    /// record line offers contains and regex only (spec 038 FR-005).
    public static func operators(for field: MatchField) -> [MatchOperator] {
        field == .anywhere ? [.contains, .regex] : [.startsWith, .contains, .regex]
    }

    /// The operator of a new or migrated condition on `field`: starts
    /// with for the named fields, contains for Anywhere (spec 038 FR-011,
    /// FR-014).
    public static func `default`(for field: MatchField) -> MatchOperator {
        field == .anywhere ? .contains : .startsWith
    }
}

/// A field, an operator and a text that narrows a session kind and never
/// widens it (spec 038 FR-004, FR-005, data-model "MatchCondition").
public struct MatchCondition: Equatable, Hashable, Sendable {
    public var field: MatchField
    public var `operator`: MatchOperator
    public var text: String

    public init(field: MatchField, operator op: MatchOperator, text: String) {
        self.field = field
        self.operator = op
        self.text = text
    }

    /// The condition "Only when" shows the first time: Model, starts with,
    /// empty text (spec 038 FR-014).
    public static let initial = MatchCondition(field: .model, operator: .startsWith, text: "")

    /// True when the Condition row of a `harness` account offers this
    /// condition: a field of that harness with an operator the field
    /// offers (spec 038 FR-004, FR-005).
    public func isOffered(for harness: Harness) -> Bool {
        MatchField.fields(for: harness).contains(field) && MatchOperator.operators(for: field).contains(self.operator)
    }

    /// True when matching reads the raw record line, so callers only build
    /// it when it can matter (spec 037 plan "Attribution").
    public var needsRawLine: Bool { field == .anywhere }

    /// True when the text is blank after trimming, which Settings refuses
    /// (spec 038 FR-008, edge case "Blank condition text").
    public var hasBlankText: Bool { Self.isBlank(text) }

    /// True when the condition matches `record`: its field, or the raw line
    /// for Anywhere, satisfies the operator with the text (spec 038 FR-004,
    /// FR-005). The caller checks the kind first.
    public func matches(record: RawUsageRecord, rawLine: String) -> Bool {
        Self.matches(self.operator, text, in: field.value(of: record, rawLine: rawLine))
    }

    /// The condition with `field` instead of its field: the text stays, the
    /// operator stays when `field` offers it, else it becomes the field's
    /// default, so starts with on Anywhere becomes contains (spec 038
    /// FR-014).
    public func withField(_ field: MatchField) -> MatchCondition {
        let kept = MatchOperator.operators(for: field).contains(self.operator) ? self.operator : MatchOperator.default(for: field)
        return MatchCondition(field: field, operator: kept, text: text)
    }

    /// For a regex whose pattern does not compile, the note (spec 038
    /// FR-008); nil for every other condition, including a blank text,
    /// which has its own message.
    public var patternProblem: String? {
        guard self.operator == .regex, !Self.isBlank(text), Self.compile(text) == nil else { return nil }
        return SessionMatchText.invalidPattern
    }

    /// What the overlap warning compares: field, operator and text, a
    /// literal text ignoring case (matching ignores case) and a pattern as
    /// written, since case carries meaning in a pattern (`\d` is not `\D`).
    /// The condition's own equality stays exact for undo, drafts and the
    /// fingerprint (spec 038 FR-009).
    public var overlapKey: MatchConditionOverlapKey {
        let key = self.operator == .regex ? text : text.folding(options: .caseInsensitive, locale: nil)
        return MatchConditionOverlapKey(field: field, operator: self.operator, text: key)
    }

    /// True when `value` satisfies `op` with `text`. Starts with and
    /// contains compare literally and ignore case, including Unicode case,
    /// but not diacritics (spec 038 FR-005, research R1). The
    /// matcher is compiled on the fly here; the attributor uses a
    /// precompiled one (`CompiledCondition`, research R4), with the same
    /// `compile(_:_:)` and the same search, so both decide alike. A blank
    /// text never matches (spec 038 FR-008).
    static func matches(_ op: MatchOperator, _ text: String, in value: String) -> Bool {
        guard !isBlank(text), let matcher = compile(op, text) else { return false }
        return find(matcher, op, in: value) == .match
    }

    /// The ICU pattern `text`, ignoring case, or nil when it is not a
    /// valid pattern (spec 038 FR-005, research R2).
    static func compile(_ text: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: text, options: [.caseInsensitive])
    }

    /// The matcher of `op` with `text`: the pattern for a regex, and for
    /// starts with and contains the text taken literally
    /// (`.ignoreMetacharacters`), ignoring case. A precompiled ICU literal
    /// search is several times faster than `String.range(of:options:)`
    /// over long raw lines (spec 038 SC-005).
    static func compile(_ op: MatchOperator, _ text: String) -> NSRegularExpression? {
        switch op {
        case .regex: return compile(text)
        case .startsWith, .contains:
            return try? NSRegularExpression(pattern: text, options: [.caseInsensitive, .ignoreMetacharacters])
        }
    }

    /// Runs the matcher of `op` on `value`: a literal search is linear and
    /// needs no time limit; starts with only matches at the start of the
    /// value, contains anywhere; a regex goes through the bounded `search`.
    static func find(_ matcher: NSRegularExpression, _ op: MatchOperator, in value: String,
                     limit: Duration = regexLimit) -> RegexOutcome {
        switch op {
        case .regex:
            return search(matcher, in: value, limit: limit)
        case .startsWith, .contains:
            let options: NSRegularExpression.MatchingOptions = op == .startsWith ? [.anchored] : []
            let found = matcher.firstMatch(in: value, options: options, range: NSRange(value.startIndex..., in: value))
            return found == nil ? .noMatch : .match
        }
    }

    /// The outcome of one bounded regex search.
    enum RegexOutcome: Equatable, Sendable {
        case match
        case noMatch
        /// The search ran longer than its limit and was stopped; it counts
        /// as no match (spec 038 FR-007).
        case timedOut
    }

    /// The regex time limit per record (spec 038 FR-007).
    public static let regexLimit: Duration = .milliseconds(50)

    /// How many progress calls pass between two looks at the clock. ICU
    /// calls the block about once per start position of a scan, so reading
    /// the clock on every call made a normal search several times slower;
    /// every 16th call keeps a catastrophic pattern stopping within a few
    /// milliseconds of the limit (spec 038 FR-007, SC-005).
    static let clockInterval = 16

    /// Searches `regex` anywhere in `value`, stopping at the first match or
    /// once `limit` has passed (spec 038 FR-005, FR-007, research R3). ICU
    /// calls the block on every match and, with `.reportProgress`, from
    /// inside long searches, so a catastrophic pattern stops near the
    /// limit. An empty value never matches (edge case "Regex that matches
    /// the empty string").
    static func search(_ regex: NSRegularExpression, in value: String, limit: Duration = regexLimit) -> RegexOutcome {
        guard !value.isEmpty else { return .noMatch }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: limit)
        var outcome = RegexOutcome.noMatch
        var calls = 0
        regex.enumerateMatches(in: value, options: [.reportProgress], range: NSRange(value.startIndex..., in: value)) { result, _, stop in
            if result != nil {
                outcome = .match
                stop.pointee = true
                return
            }
            calls &+= 1
            if calls % clockInterval == 0, clock.now >= deadline {
                outcome = .timedOut
                stop.pointee = true
            }
        }
        return outcome
    }

    static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The value two conditions share when the overlap warning treats them as
/// the same condition (spec 038 FR-009).
public struct MatchConditionOverlapKey: Hashable, Sendable {
    public let field: MatchField
    public let `operator`: MatchOperator
    public let text: String
}
