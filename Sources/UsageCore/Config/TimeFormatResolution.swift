import Foundation

extension Configuration {
    /// The time format of a dropdown section (spec 025 FR-016): the
    /// account's for a subscription section or an own budget, the group's
    /// for a group section. The value is read from this configuration, so
    /// an entry arranged from an earlier draft follows the current one.
    public func timeFormat(for entry: ArrangedEntry) -> TimeFormat {
        switch entry {
        case .account(let entryAccount): account(id: entryAccount.id)?.timeFormat ?? entryAccount.timeFormat
        case .group(let entryGroup, _): group(id: entryGroup.id)?.timeFormat ?? entryGroup.timeFormat
        }
    }
}

extension KeyedDecodingContainer {
    /// The `timeFormat` key of an account or group (spec 025 FR-021,
    /// contracts/config-file.md): absent is relative; an unreadable or
    /// unknown value is relative with a load note for the diagnostic log and
    /// no problem notice, as `levelColor` is decoded (spec 012 FR-003).
    func decodeTimeFormat(forKey key: Key, notes: ConfigurationLoadNotes?) -> TimeFormat {
        guard contains(key) else { return .relative }
        guard let raw = (try? decodeIfPresent(String.self, forKey: key)) ?? nil else {
            notes?.append("timeFormat is not readable, using relative")
            return .relative
        }
        guard let format = TimeFormat(rawValue: raw) else {
            notes?.append("timeFormat \"\(Configuration.clipped(raw))\" is not known, using relative")
            return .relative
        }
        return format
    }
}
