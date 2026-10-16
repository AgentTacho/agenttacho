import Foundation

/// A release version `X.Y.Z` of three non-negative integers, compared
/// numerically part by part (spec 013 FR-006). Anything that is not exactly
/// `X.Y.Z` (no "v", no suffix, no spaces) does not parse.
public struct ReleaseVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses `^[0-9]+\.[0-9]+\.[0-9]+$`; nil for anything else.
    public init?(_ string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }),
                  let number = Int(part) else { return nil }
            numbers.append(number)
        }
        self.init(major: numbers[0], minor: numbers[1], patch: numbers[2])
    }

    /// Parses a release tag: one leading "v" is stripped, then `init?(_:)`.
    /// The rest must be written exactly like the version's `description`
    /// (no leading zeros), so a tag that parses equals its version as text
    /// (spec 013 FR-004).
    public init?(tag: String) {
        let text = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard let version = ReleaseVersion(text), version.description == text else { return nil }
        self = version
    }

    public static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    /// `X.Y.Z`.
    public var description: String { "\(major).\(minor).\(patch)" }
}
