import Foundation
import Testing
@testable import UsageCore

/// spec 030 FR-016, FR-017, data-model.md ThresholdNotificationText: the
/// title and body of a threshold notification in the chosen direction,
/// and the log line that always stays in used percent.
@Suite struct ThresholdNotificationTextTests {
    static func crossing(_ name: String, _ kind: WindowKind, threshold: Int, percent: Int) -> ThresholdCrossing {
        ThresholdCrossing(entityId: name.lowercased(), entityName: name, windowKind: kind, threshold: threshold, percent: percent)
    }

    /// Direction used keeps today's texts.
    @Test func usedKeepsTodaysTexts() {
        let text = ThresholdNotificationText.make(Self.crossing("Max", .sevenDay, threshold: 80, percent: 83), direction: .used)
        #expect(text.title == "Max reached 80%")
        #expect(text.body == "7-day window at 83%")
        let over = ThresholdNotificationText.make(Self.crossing("Vertex", .weekly, threshold: 120, percent: 125), direction: .used)
        #expect(over.title == "Vertex reached 120%")
        #expect(over.body == "weekly window at 125%")
    }

    /// The contract examples and every row of the data-model table.
    @Test func remainingTexts() {
        let max = ThresholdNotificationText.make(Self.crossing("Max", .sevenDay, threshold: 80, percent: 83), direction: .remaining)
        #expect(max.title == "Max has 20% left")
        #expect(max.body == "7-day window at 17% left")
        let full = ThresholdNotificationText.make(Self.crossing("Vertex", .weekly, threshold: 100, percent: 115), direction: .remaining)
        #expect(full.title == "Vertex has 0% left")
        #expect(full.body == "weekly window at 15% over")
        let above = ThresholdNotificationText.make(Self.crossing("Vertex", .weekly, threshold: 120, percent: 125), direction: .remaining)
        #expect(above.title == "Vertex is 20% over")
        #expect(above.body == "weekly window at 25% over")
        let exact = ThresholdNotificationText.make(Self.crossing("Team", .monthly, threshold: 100, percent: 100), direction: .remaining)
        #expect(exact.title == "Team has 0% left")
        #expect(exact.body == "monthly window at 0% left")
    }

    /// A jump from 70% to 115% crosses 80 and 100; the body depends only on
    /// the current value.
    @Test func jumpPastSeveralThresholds() {
        let first = ThresholdNotificationText.make(Self.crossing("Plus", .weekly, threshold: 80, percent: 115), direction: .remaining)
        #expect(first.title == "Plus has 20% left")
        #expect(first.body == "weekly window at 15% over")
        let second = ThresholdNotificationText.make(Self.crossing("Plus", .weekly, threshold: 100, percent: 115), direction: .remaining)
        #expect(second.title == "Plus has 0% left")
        #expect(second.body == "weekly window at 15% over")
    }

    /// FR-017: the log line names the threshold and the percent in used
    /// percent, whatever the direction.
    @Test func logDescriptionStaysInUsedPercent() {
        let crossing = Self.crossing("Max", .sevenDay, threshold: 80, percent: 83)
        #expect(ThresholdNotificationText.logDescription(crossing) == "Max (max) 7-day crossed 80% at 83%")
    }
}
