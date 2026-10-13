import Foundation

/// How a record is recognized as belonging to an account (FR-013).
public enum DetectionRule: Equatable, Sendable {
    case requestIdPrefix(String)
    case rawContains(String)
    /// `req_` followed by no provider infix (`req_011...`), research R3.
    case directRequestId

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
        }
    }
}

extension Provider {
    /// Built-in rule per provider (research R3).
    public var builtInRule: DetectionRule {
        switch self {
        case .vertex: return .requestIdPrefix("req_vrtx_")
        }
    }
}

/// Resolves the account of each record.
///
/// Resolution order:
/// 1. An account with a custom marker matches only when the raw line contains
///    that marker; the marker replaces the account's built-in rule.
/// 2. Without a custom marker, a token-based account matches its provider's
///    built-in rule; a subscription account matches a direct request id
///    (`req_` with no provider infix) that matches no token-based rule.
/// 3. Custom-marker matches are more specific than built-in matches, so when
///    at least one account matched through its marker only those accounts are
///    considered.
/// 4. One remaining match wins. Several remaining subscription accounts are
///    separated by the configuration directory the file was found in. Anything
///    else is Unassigned (nil).
public struct Attributor: Sendable {
    private struct Candidate {
        let id: String
        let isSubscription: Bool
        let customMarker: String?
        let builtIn: DetectionRule?
        /// Canonical credential directory for the tie-breaker.
        let directory: String?
    }

    private let candidates: [Candidate]

    public init(configuration: Configuration, paths: Paths = Paths()) {
        var tokenRules: [DetectionRule] = []
        var result: [Candidate] = []
        for account in configuration.accounts {
            let marker = account.customMarker.flatMap { $0.isEmpty ? nil : $0 }
            switch account.kind {
            case .tokenBased(let settings):
                let rule = settings.provider.builtInRule
                if marker == nil { tokenRules.append(rule) }
                result.append(Candidate(id: account.id, isSubscription: false, customMarker: marker,
                                        builtIn: marker == nil ? rule : nil, directory: nil))
            case .subscription(let settings):
                result.append(Candidate(id: account.id, isSubscription: true, customMarker: marker,
                                        builtIn: marker == nil ? .directRequestId : nil,
                                        directory: Attributor.canonical(paths.expand(settings.credentialDirectory))))
            }
        }
        self.candidates = result
        self.tokenBasedRules = tokenRules
        self.fingerprint = result.map {
            "\($0.id)|\($0.isSubscription)|\($0.customMarker ?? "")|\($0.directory ?? "")|\(String(describing: $0.builtIn))"
        }.joined(separator: "\n")
    }

    private let tokenBasedRules: [DetectionRule]

    /// Changes whenever the attribution rules change; the index resets then.
    public let fingerprint: String

    public func accountId(for record: RawUsageRecord, rawLine: String, fileConfigDirectory: String) -> String? {
        var markerMatches: [Candidate] = []
        var builtInMatches: [Candidate] = []
        let matchesTokenRule = tokenBasedRules.contains { $0.matches(record: record, rawLine: rawLine) }

        for candidate in candidates {
            if let marker = candidate.customMarker {
                if DetectionRule.rawContains(marker).matches(record: record, rawLine: rawLine) {
                    markerMatches.append(candidate)
                }
            } else if let rule = candidate.builtIn, rule.matches(record: record, rawLine: rawLine) {
                if candidate.isSubscription && matchesTokenRule { continue }
                builtInMatches.append(candidate)
            }
        }

        let matches = markerMatches.isEmpty ? builtInMatches : markerMatches
        if matches.count == 1 { return matches[0].id }
        guard matches.count > 1, matches.allSatisfy(\.isSubscription) else { return nil }

        let fileDirectory = Attributor.canonical(fileConfigDirectory)
        let byDirectory = matches.filter { $0.directory == fileDirectory }
        return byDirectory.count == 1 ? byDirectory[0].id : nil
    }

    static func canonical(_ path: String) -> String {
        var p = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }
}
