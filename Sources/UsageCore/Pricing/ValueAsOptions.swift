import Foundation

/// The entries of the "Value as" pop-up of a No limit account (spec 041
/// FR-017, clarification 2, research R8). "None" is the view's first item
/// and maps to nil; every model appears once, by its model id as the Prices
/// tab shows it, under its effective source.
public struct ValueAsOptions: Equatable, Sendable {
    /// Built-in and manually priced models, sorted by model id.
    public let primary: [String]
    /// Imported models (provider and CSV imports), sorted by model id, for
    /// the "More" submenu.
    public let more: [String]
    /// The selected id when it is priced only through normalization or the
    /// prefix fallback (`claude-opus-5-5@default`): shown selected as
    /// stored, never rewritten.
    public let unlisted: String?
    /// The selected id when the table has no price for it: shown selected
    /// and marked as missing, so opening the editor does not change it.
    public let missing: String?

    public static func make(prices: PriceTable, selected: String?) -> ValueAsOptions {
        var primary: [String] = []
        var more: [String] = []
        for entry in prices.entries {
            switch entry.source {
            case .builtIn, .override: primary.append(entry.model)
            case .imported: more.append(entry.model)
            }
        }
        var unlisted: String?
        var missing: String?
        if let selected, !primary.contains(selected), !more.contains(selected) {
            if prices.price(for: selected) != nil {
                unlisted = selected
            } else {
                missing = selected
            }
        }
        return ValueAsOptions(primary: primary, more: more, unlisted: unlisted, missing: missing)
    }

    /// The label of the missing selection: "<model id> (no price)"
    /// (contracts/ui-strings.md).
    public static func missingLabel(_ model: String) -> String {
        "\(model) (no price)"
    }
}
