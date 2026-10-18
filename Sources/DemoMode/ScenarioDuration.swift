import Foundation

/// A time relative to the demo app's launch, written like `2h10m`, `-3d` or
/// `12s`: an optional minus, then one or more of `Nd`, `Nh`, `Nm`, `Ns` in
/// this order, each at most once (spec 024 FR-011, data-model "Durations").
public struct ScenarioDuration: Equatable, Sendable, Decodable {
    public let seconds: TimeInterval

    public init(seconds: TimeInterval) {
        self.seconds = seconds
    }

    private static let units: [(Character, TimeInterval)] = [("d", 86_400), ("h", 3600), ("m", 60), ("s", 1)]

    /// Throws a `ScenarioError` without a path; the scenario decoder adds it.
    public init(parsing text: String) throws {
        let invalid = ScenarioError(path: "", message: "\"\(text)\" is not a duration such as 2h10m, -3d or 12s")
        var rest = Substring(text)
        let negative = rest.first == "-"
        if negative { rest = rest.dropFirst() }
        guard !rest.isEmpty else { throw invalid }
        var total: TimeInterval = 0
        var nextUnit = 0
        while !rest.isEmpty {
            let digits = rest.prefix { $0.isASCII && $0.isNumber }
            guard !digits.isEmpty, let value = Int(digits) else { throw invalid }
            rest = rest.dropFirst(digits.count)
            guard let unit = rest.first,
                  let index = Self.units[nextUnit...].firstIndex(where: { $0.0 == unit }) else { throw invalid }
            total += TimeInterval(value) * Self.units[index].1
            nextUnit = index + 1
            rest = rest.dropFirst()
        }
        seconds = negative ? -total : total
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        do {
            try self.init(parsing: text)
        } catch let error as ScenarioError {
            throw ScenarioError(path: ScenarioError.path(decoder.codingPath), message: error.message)
        }
    }
}
