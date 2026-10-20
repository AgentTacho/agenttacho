import Foundation
import Testing
@testable import UsageCore

/// spec 030 FR-001 to FR-003, FR-005, `contracts/level-rule.md`: one level
/// rule from an owner's thresholds, with real limits always critical.
@Suite struct LevelThresholdsTests {
    struct Row: Sendable, CustomTestStringConvertible {
        let thresholds: [Int]
        let warning: Int
        let critical: Int
        /// Levels at 79, 85, 91 and 100.
        let levels: [BarLevel]
        var testDescription: String { "\(thresholds)" }
    }

    /// The table of `contracts/level-rule.md`. Its `[50, 75, 90]` row once
    /// listed 79 as warning, which contradicted FR-002 (79 is at or above
    /// the critical threshold 75); the contract and this row follow the spec.
    static let table: [Row] = [
        Row(thresholds: [], warning: 80, critical: 100, levels: [.normal, .warning, .warning, .critical]),
        Row(thresholds: [80, 90], warning: 80, critical: 90, levels: [.normal, .warning, .critical, .critical]),
        Row(thresholds: [90, 80], warning: 80, critical: 90, levels: [.normal, .warning, .critical, .critical]),
        Row(thresholds: [90, 90], warning: 90, critical: 90, levels: [.normal, .normal, .critical, .critical]),
        Row(thresholds: [80], warning: 80, critical: 100, levels: [.normal, .warning, .warning, .critical]),
        Row(thresholds: [100], warning: 100, critical: 100, levels: [.normal, .normal, .normal, .critical]),
        Row(thresholds: [80, 120], warning: 80, critical: 120, levels: [.normal, .warning, .warning, .critical]),
        Row(thresholds: [50, 75, 90], warning: 50, critical: 75, levels: [.critical, .critical, .critical, .critical]),
        Row(thresholds: [0, -5, 80], warning: 80, critical: 100, levels: [.normal, .warning, .warning, .critical]),
    ]

    @Test(arguments: table)
    func contractTable(row: Row) {
        let levels = LevelThresholds(row.thresholds)
        #expect(levels.warning == row.warning)
        #expect(levels.critical == row.critical)
        #expect([79, 85, 91, 100].map { levels.level(usedPercent: $0) } == row.levels)
    }

    /// FR-003: a real limit is critical below every threshold.
    @Test func realLimitIsAlwaysCritical() {
        for thresholds in [[], [80, 90], [90, 90], [100], [80, 120]] {
            #expect(LevelThresholds(thresholds).level(usedPercent: 10, atRealLimit: true) == .critical)
            #expect(LevelThresholds(thresholds).level(usedPercent: 0, atRealLimit: true) == .critical)
        }
    }

    /// FR-003: 100% and above is critical whatever the critical threshold.
    @Test func atOrAboveHundredIsCritical() {
        let levels = LevelThresholds([80, 120])
        #expect(levels.level(usedPercent: 100) == .critical)
        #expect(levels.level(usedPercent: 115) == .critical)
        #expect(levels.level(usedPercent: 99) == .warning)
    }

    /// No value is normal, unless a real limit is reached elsewhere (a
    /// reached Codex limit, a full 7-day window), which is never hidden
    /// (FR-003).
    @Test func noValueIsNormalUnlessAtARealLimit() {
        #expect(LevelThresholds([80, 90]).level(usedPercent: nil) == .normal)
        #expect(LevelThresholds([]).level(usedPercent: nil, atRealLimit: true) == .critical)
    }

    /// FR-003, FR-004: the level and whether it comes from a real limit
    /// are decided together, so "over limit" and "critical" cannot drift
    /// apart from the level.
    @Test func decisionCarriesTheRealLimit() {
        let levels = LevelThresholds([80, 90])
        #expect(levels.decide(usedPercent: 91) == LevelDecision(level: .critical, overLimit: false))
        #expect(levels.decide(usedPercent: 100) == LevelDecision(level: .critical, overLimit: true))
        #expect(levels.decide(usedPercent: 115) == LevelDecision(level: .critical, overLimit: true))
        #expect(levels.decide(usedPercent: 85) == LevelDecision(level: .warning, overLimit: false))
        #expect(levels.decide(usedPercent: 10, atRealLimit: true) == LevelDecision(level: .critical, overLimit: true))
        #expect(levels.decide(usedPercent: nil, atRealLimit: true) == LevelDecision(level: .critical, overLimit: true))
        #expect(levels.decide(usedPercent: nil) == LevelDecision(level: .normal, overLimit: false))
        for value in [nil, 0, 50, 85, 91, 100, 130] as [Int?] {
            for atRealLimit in [false, true] {
                #expect(levels.decide(usedPercent: value, atRealLimit: atRealLimit).level
                        == levels.level(usedPercent: value, atRealLimit: atRealLimit))
            }
        }
    }

    /// FR-005: the dropdown percent tone of each level.
    @Test func percentToneFollowsTheLevel() {
        #expect(PercentTone(.normal) == .primary)
        #expect(PercentTone(.warning) == .warning)
        #expect(PercentTone(.critical) == .critical)
    }
}
