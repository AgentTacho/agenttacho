# Contract: Direction Presentation

UsageCore API for the used or remaining direction (FR-008 to FR-017). Views pass `configuration.displayDirection` and render the results.

```swift
public enum DisplayDirection: String, Codable, Sendable { case used, remaining }

public struct DirectedPercent: Equatable, Sendable {
    public enum Kind { case budget, window }
    public init(usedPercent: Int, direction: DisplayDirection)
    public var value: Int
    public var text: String
    public func accessibilityText(_ kind: Kind) -> String
    public static func fill(usedPercent: Double, direction: DisplayDirection) -> Double
    public static func tick(expectedPercent: Double, direction: DisplayDirection) -> Double
}

public enum RunOutGlyph {
    public static func text(burnsFast: Bool, direction: DisplayDirection) -> String
}

public enum BudgetAmountLine: Equatable, Sendable {
    case of(spent: Decimal), left(Decimal), over(Decimal)
    public static func make(spent: Decimal, budget: Decimal, roundedPercent: Int, direction: DisplayDirection) -> BudgetAmountLine
    public func text(amount: (Decimal) -> String, budget: String, period: String) -> String
}

public enum ThresholdDisplay {
    public static func shown(stored: Int, direction: DisplayDirection) -> Int
    public static func stored(entered: Int, direction: DisplayDirection) -> Int
    public static func hasInvalidStored(_ stored: [Int]) -> Bool
    public static func caption(stored: Int, direction: DisplayDirection) -> String?
    public static func placeholders(direction: DisplayDirection) -> (first: String, second: String)
    public static func fieldSuffix(direction: DisplayDirection) -> String
    public static func explanation(limitDescription: String, direction: DisplayDirection) -> String
    public static func furtherThresholds(_ stored: [Int], direction: DisplayDirection) -> String?
    public static func validationMessage(direction: DisplayDirection) -> String
}

public enum ThresholdNotificationText {
    public static func make(_ crossing: ThresholdCrossing, direction: DisplayDirection) -> (title: String, body: String)
    public static func logDescription(_ crossing: ThresholdCrossing) -> String
}
```

## Examples (unit test table)

| used | direction | text | accessibility (budget) | fill (from 70.4 / 115.0) |
|---|---|---|---|---|
| 70 | used | "70%" | "70%" | 0.704 |
| 70 | remaining | "30%" | "30% left" | 0.296 |
| 100 | remaining | "0%" | "0% left" | 0 |
| 115 | used | "115%" | "115%" | 1 |
| 115 | remaining | "−15%" | "15% over budget" | 0 |

| marker | used | remaining |
|---|---|---|
| run out | ↗ | ↘ |
| burns fast | ↑ | ↓ |

| spent / budget | rounded | used line | remaining line |
|---|---|---|---|
| 40 / 100 week | 40 | "$40 of $100/week" | "$60 left of $100/week" |
| 100.4 / 100 | 100 | "$100 of $100/week" | "$0 left of $100/week" |
| 115 / 100 | 115 | "$115 of $100/week" | "$15 over $100/week" |

Notification: crossing (Max, 7-day, T 80, P 83), remaining → "Max has 20% left", "7-day window at 17% left". Crossing (Vertex, weekly, T 100, P 115), remaining → "Vertex has 0% left", "weekly window at 15% over". Crossing T 120, remaining → title "Vertex is 20% over".

## Settings surface

- General tab, `Section("Display")` after "Refresh": segmented `Picker("Show usage as")` with "Used" and "Remaining", caption "Remaining counts down from 100% as you use a limit or budget. Thresholds and notifications follow."
- Menu Bar tab checkbox label: "Show ↗ or ↑ when an entry will run out before it resets" in used, "Show ↘ or ↓ …" in remaining.
