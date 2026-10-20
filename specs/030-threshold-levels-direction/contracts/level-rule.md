# Contract: Level Rule

UsageCore API that every level in the menu bar and the dropdown goes through (FR-001 to FR-006).

```swift
public struct LevelThresholds: Equatable, Sendable {
    public let warning: Int
    public let critical: Int
    public init(_ thresholds: [Int])
    public func level(usedPercent: Int?, atRealLimit: Bool = false) -> BarLevel
}

public enum PercentTone: Equatable, Sendable {
    case primary, warning, critical
    public init(_ level: BarLevel)
}
```

## Examples (unit test table)

| thresholds | warning | critical | 79 | 85 | 91 | 100 |
|---|---|---|---|---|---|---|
| [] | 80 | 100 | normal | warning | warning | critical |
| [80, 90] | 80 | 90 | normal | warning | critical | critical |
| [90, 80] | 80 | 90 | normal | warning | critical | critical |
| [90, 90] | 90 | 90 | normal | normal | critical | critical |
| [80] | 80 | 100 | normal | warning | warning | critical |
| [100] | 100 | 100 | normal | normal | normal | critical |
| [80, 120] | 80 | 120 | normal | warning | warning | critical (real limit) |
| [50, 75, 90] | 50 | 75 | critical | critical | critical | critical |
| [0, -5, 80] | 80 | 100 | normal | warning | warning | critical |

## Call sites

| Surface | Value | atRealLimit |
|---|---|---|
| Menu bar subscription entry | headline percent | Claude 7-day ≥ 100 |
| Menu bar Codex entry | headline percent | any window limit reached |
| Menu bar budget entry | budget rounded percent | false (≥ 100 covered by the rule) |
| Menu bar member entry | member share, group thresholds | false |
| Subscription section header | same as its menu bar entry | same |
| Budget section header percent | budget rounded percent | false |
| Window row percent and bar | the row's rounded percent | the row's own `limitReached` only |
| Budget bar and amount line | budget rounded percent | false |

Member percent lines in the dropdown take no level (uncolored).

## Accessibility words (FR-004)

- normal: "<name> <value>"
- warning: "<name> warning <value>"
- critical without a real limit: "<name> critical <value>"
- critical at a real limit: "<name> over limit <value>"
