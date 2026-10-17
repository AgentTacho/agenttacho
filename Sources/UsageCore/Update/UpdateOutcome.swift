import Foundation

/// The outcome of a replacement, left in the update's temporary folder for
/// the app that starts next, which reads, logs, shows and deletes it (spec
/// 013 FR-017, research R10).
public struct UpdateOutcome: Codable, Equatable, Sendable {
    public enum Result: String, Codable, Sendable {
        case installed
        case failed

        /// An unknown value counts as a failure.
        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Result(rawValue: raw) ?? .failed
        }
    }

    /// `outcome.json`.
    public static let fileName = "outcome.json"
    /// The folder under the user's temporary directory that holds the
    /// download, the mount point and the outcome.
    public static let folderName = "dev.rhuss.agenttacho-update"

    public let from: String
    public let to: String
    public let result: Result
    public let reason: String?

    public init(from: String, to: String, result: Result, reason: String?) {
        self.from = from
        self.to = to
        self.result = result
        self.reason = reason
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// The decoded marker, or nil when it is not readable.
    public static func decode(_ data: Data) -> UpdateOutcome? {
        try? JSONDecoder().decode(UpdateOutcome.self, from: data)
    }
}
