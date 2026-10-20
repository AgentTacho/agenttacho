import Foundation
import Testing
@testable import UsageCore

/// Spec 012 SC-003: the decision table of `contracts/bar-rendering.md` for
/// every combination of level color and symbols, at every level, fresh and
/// stale, plus the accessibility text (FR-018).
@Suite struct BarPresentationTests {
    private static func item(level: BarLevel, value: String = "85%", stale: Bool = false,
                             name: String = "Vertex", id: String = "grp-vertex", overLimit: Bool = false) -> BarItem {
        BarItem(id: id, icon: "brands:google", name: name, value: value, level: level, stale: stale, overLimit: overLimit)
    }

    private static func present(_ item: BarItem, _ style: LevelColorStyle, symbols: Bool) -> BarEntryPresentation {
        let entries = BarPresentation.entries([item], settings: LevelDisplaySettings(levelColor: style, showSymbols: symbols))
        #expect(entries.count == 1)
        return entries[0]
    }

    /// One row of the decision table.
    struct Row: Sendable, CustomStringConvertible {
        let style: LevelColorStyle
        let symbols: Bool
        let level: BarLevel
        let iconTone: BarTone
        let glyph: String?
        let textTone: BarTone
        let pill: BarLevel?

        var description: String { "\(style) symbols:\(symbols) \(level)" }
    }

    static let rows: [Row] = [
        // Text
        Row(style: .text, symbols: false, level: .normal, iconTone: .neutral, glyph: nil, textTone: .neutral, pill: nil),
        Row(style: .text, symbols: false, level: .warning, iconTone: .neutral, glyph: nil, textTone: .warning, pill: nil),
        Row(style: .text, symbols: false, level: .critical, iconTone: .neutral, glyph: nil, textTone: .overLimit, pill: nil),
        Row(style: .text, symbols: true, level: .normal, iconTone: .neutral, glyph: nil, textTone: .neutral, pill: nil),
        Row(style: .text, symbols: true, level: .warning, iconTone: .neutral, glyph: "⚠", textTone: .warning, pill: nil),
        Row(style: .text, symbols: true, level: .critical, iconTone: .neutral, glyph: "‼", textTone: .overLimit, pill: nil),
        // Pill
        Row(style: .pill, symbols: false, level: .normal, iconTone: .neutral, glyph: nil, textTone: .neutral, pill: nil),
        Row(style: .pill, symbols: false, level: .warning, iconTone: .onPill(.warning), glyph: nil, textTone: .onPill(.warning), pill: .warning),
        Row(style: .pill, symbols: false, level: .critical, iconTone: .onPill(.critical), glyph: nil, textTone: .onPill(.critical), pill: .critical),
        Row(style: .pill, symbols: true, level: .normal, iconTone: .neutral, glyph: nil, textTone: .neutral, pill: nil),
        Row(style: .pill, symbols: true, level: .warning, iconTone: .onPill(.warning), glyph: "⚠", textTone: .onPill(.warning), pill: .warning),
        Row(style: .pill, symbols: true, level: .critical, iconTone: .onPill(.critical), glyph: "‼", textTone: .onPill(.critical), pill: .critical),
        // Off
        Row(style: .off, symbols: false, level: .normal, iconTone: .neutral, glyph: nil, textTone: .neutral, pill: nil),
        Row(style: .off, symbols: false, level: .warning, iconTone: .neutral, glyph: nil, textTone: .neutral, pill: nil),
        Row(style: .off, symbols: false, level: .critical, iconTone: .neutral, glyph: nil, textTone: .neutral, pill: nil),
        Row(style: .off, symbols: true, level: .normal, iconTone: .neutral, glyph: nil, textTone: .neutral, pill: nil),
        Row(style: .off, symbols: true, level: .warning, iconTone: .neutral, glyph: "⚠", textTone: .neutral, pill: nil),
        Row(style: .off, symbols: true, level: .critical, iconTone: .neutral, glyph: "‼", textTone: .neutral, pill: nil),
    ]

    /// FR-007 to FR-010, FR-016: every row, fresh and stale.
    @Test(arguments: rows, [false, true])
    func decisionTable(row: Row, stale: Bool) {
        let item = Self.item(level: row.level, value: "85%", stale: stale)
        let entry = present(item, row.style, symbols: row.symbols)
        #expect(entry.id == "grp-vertex")
        #expect(entry.icon == "brands:google")
        #expect(entry.glyph == row.glyph)
        #expect(entry.valueText == (stale ? "~85%" : "85%"))
        #expect(entry.iconTone == row.iconTone)
        #expect(entry.textTone == row.textTone)
        #expect(entry.pill == row.pill)
    }

    private func present(_ item: BarItem, _ style: LevelColorStyle, symbols: Bool) -> BarEntryPresentation {
        Self.present(item, style, symbols: symbols)
    }

    @Test func allSixCombinationsAreCovered() {
        let combinations = Set(Self.rows.map { "\($0.style.rawValue)|\($0.symbols)" })
        #expect(combinations.count == 6)
        #expect(Self.rows.count == 18)
    }

    /// Spec 007 FR-012: a Codex plan entry with a reached limit is over
    /// limit even when its percent is lower.
    @Test func criticalBelowHundredIsOverLimit() {
        let codex = Self.item(level: .critical, value: "60%", name: "Codex", id: "acc-codex", overLimit: true)
        let text = present(codex, .text, symbols: true)
        #expect(text.textTone == .overLimit)
        #expect(text.glyph == "‼")
        #expect(text.accessibilityText == "Codex over limit 60%")
        let pill = present(codex, .pill, symbols: false)
        #expect(pill.pill == .critical)
    }

    /// Entries without a percent never have a level.
    @Test(arguments: ["--", "…"])
    func entriesWithoutPercentAreNeutral(value: String) {
        let item = Self.item(level: .normal, value: value)
        for style in LevelColorStyle.allCases {
            for symbols in [false, true] {
                let entry = present(item, style, symbols: symbols)
                #expect(entry.glyph == nil)
                #expect(entry.valueText == value)
                #expect(entry.iconTone == .neutral)
                #expect(entry.textTone == .neutral)
                #expect(entry.pill == nil)
                #expect(entry.accessibilityText == "Vertex \(value)")
            }
        }
    }

    // MARK: usesColor (research R2)

    @Test func usesColorOnlyWhenALevelColorIsShown() {
        let normal = Self.item(level: .normal, value: "42%")
        let warning = Self.item(level: .warning, value: "85%", id: "w")
        let critical = Self.item(level: .critical, value: "104%", id: "c")
        for style in LevelColorStyle.allCases {
            for symbols in [false, true] {
                let settings = LevelDisplaySettings(levelColor: style, showSymbols: symbols)
                #expect(!BarPresentation.usesColor(BarPresentation.entries([normal], settings: settings)))
                #expect(!BarPresentation.usesColor(BarPresentation.entries([], settings: settings)))
                let mixed = BarPresentation.entries([normal, warning, critical], settings: settings)
                #expect(BarPresentation.usesColor(mixed) == (style != .off))
                let onlyWarning = BarPresentation.entries([warning], settings: settings)
                #expect(BarPresentation.usesColor(onlyWarning) == (style != .off))
            }
        }
    }

    // MARK: Accessibility text (FR-018)

    @Test func accessibilityTextNamesLevelsInEverySetting() {
        let items = [
            Self.item(level: .warning, value: "85%", name: "Vertex", id: "a"),
            Self.item(level: .critical, value: "104%", name: "Vertex", id: "b", overLimit: true),
            Self.item(level: .warning, value: "85%", stale: true, name: "Vertex", id: "c"),
            Self.item(level: .normal, value: "42%", name: "Vertex", id: "d"),
        ]
        for style in LevelColorStyle.allCases {
            for symbols in [false, true] {
                let entries = BarPresentation.entries(items, settings: LevelDisplaySettings(levelColor: style, showSymbols: symbols))
                #expect(entries.map(\.accessibilityText) == [
                    "Vertex warning 85%", "Vertex over limit 104%", "Vertex warning ~85%", "Vertex 42%",
                ])
                let text = BarPresentation.accessibilityText(entries)
                #expect(text == "Vertex warning 85%  Vertex over limit 104%  Vertex warning ~85%  Vertex 42%")
                #expect(!text.contains("⚠"))
                #expect(!text.contains("‼"))
            }
        }
    }

    @Test func staleNormalEntryKeepsItsMarker() {
        let entry = present(Self.item(level: .normal, value: "42%", stale: true), .text, symbols: true)
        #expect(entry.accessibilityText == "Vertex ~42%")
        #expect(entry.valueText == "~42%")
    }

    @Test func emptyBarReadsAsPlaceholder() {
        #expect(BarPresentation.placeholder == "AgentTacho")
        #expect(BarPresentation.accessibilityText([]) == "AgentTacho")
    }

    @Test func entriesKeepTheBarOrder() {
        let items = [Self.item(level: .normal, id: "x"), Self.item(level: .warning, id: "y"), Self.item(level: .critical, id: "z")]
        let entries = BarPresentation.entries(items, settings: .default)
        #expect(entries.map(\.id) == ["x", "y", "z"])
    }

    /// Spec 011 FR-012, FR-015 combined with spec 012: the run-out marker
    /// follows the value in every style, keeps the bar neutral, and is
    /// spelled out in the accessibility text.
    @Test(arguments: LevelColorStyle.allCases, [false, true])
    func runOutMarkerStaysNeutralAndIsSpelledOut(style: LevelColorStyle, symbols: Bool) {
        let item = BarItem(id: "acc", icon: "brands:claude", name: "Claude", value: "42%", level: .normal, stale: false,
                           runOutMarker: true)
        let entry = present(item, style, symbols: symbols)
        #expect(entry.runOutMarker == "↗")
        #expect(entry.valueText == "42%")
        #expect(entry.glyph == nil)
        #expect(entry.pill == nil)
        #expect(!BarPresentation.usesColor([entry]))
        #expect(entry.accessibilityText == "Claude 42%, projected to run out before reset")
        #expect(!entry.accessibilityText.contains("↗"))
    }

    @Test func noRunOutMarkerByDefault() {
        let entry = present(Self.item(level: .warning), .text, symbols: false)
        #expect(entry.runOutMarker == nil)
    }

    /// Spec 017 FR-008, FR-011: a fast entry shows "↑" instead of "↗", stays
    /// neutral, and names the fast burn in the accessibility text.
    @Test(arguments: LevelColorStyle.allCases, [false, true])
    func fastEntryShowsUpArrowAndNamesTheFastBurn(style: LevelColorStyle, symbols: Bool) {
        let item = BarItem(id: "acc", icon: "brands:claude", name: "Claude", value: "36%", level: .normal, stale: false,
                           runOutMarker: true, burnsFast: true)
        let entry = present(item, style, symbols: symbols)
        #expect(entry.runOutMarker == "↑")
        #expect(entry.valueText == "36%")
        #expect(!BarPresentation.usesColor([entry]))
        #expect(entry.accessibilityText == "Claude 36%, burning fast, projected to run out well before reset")
        #expect(!entry.accessibilityText.contains("↑"))
    }

    /// Spec 017 FR-008: without the fast burn the spec 011 marker and text
    /// stay; without the marker there is neither glyph nor suffix.
    @Test func markerChoiceFollowsBurnsFast() {
        let slow = BarItem(id: "a", icon: "brands:claude", name: "Claude", value: "55%", level: .normal, stale: false,
                           runOutMarker: true, burnsFast: false)
        let slowEntry = present(slow, .text, symbols: true)
        #expect(slowEntry.runOutMarker == "↗")
        #expect(slowEntry.accessibilityText.hasSuffix(", projected to run out before reset"))
        #expect(!slowEntry.accessibilityText.contains("burning fast"))
        let none = BarItem(id: "a", icon: "brands:claude", name: "Claude", value: "55%", level: .normal, stale: false)
        let noneEntry = present(none, .text, symbols: true)
        #expect(noneEntry.runOutMarker == nil)
        #expect(noneEntry.accessibilityText == "Claude 55%")
        #expect(none.burnsFast == false)
    }

    // MARK: Headline window tag (spec 027 FR-009)

    /// The tag passes through; the accessibility text names the window
    /// after the entry's name and before the level word and the value.
    @Test func tagAndWindowNameInTheAccessibilityText() {
        func tagged(_ value: String, level: BarLevel = .normal, stale: Bool = false, overLimit: Bool = false) -> BarItem {
            BarItem(id: "acc-max", icon: "brands:claude", name: "Claude Max", value: value, level: level, stale: stale,
                    overLimit: overLimit, tag: "5h", windowName: "5-hour window")
        }
        let plain = present(tagged("58%"), .text, symbols: false)
        #expect(plain.tag == "5h")
        #expect(plain.valueText == "58%")
        #expect(plain.accessibilityText == "Claude Max 5-hour window 58%")
        let warning = present(tagged("85%", level: .warning, stale: true), .text, symbols: true)
        #expect(warning.tag == "5h")
        #expect(warning.glyph == "⚠")
        #expect(warning.accessibilityText == "Claude Max 5-hour window warning ~85%")
        #expect(present(tagged("--"), .text, symbols: false).accessibilityText == "Claude Max 5-hour window --")
        let critical = present(tagged("40%", level: .critical, overLimit: true), .pill, symbols: false)
        #expect(critical.accessibilityText == "Claude Max 5-hour window over limit 40%")
        let fable = BarItem(id: "acc-max", icon: "brands:claude", name: "Claude Max", value: "31%", level: .normal, stale: false,
                            tag: "Fable", windowName: "Fable weekly limit")
        #expect(present(fable, .text, symbols: false).accessibilityText == "Claude Max Fable weekly limit 31%")
        let marked = BarItem(id: "c", icon: "brands:openai", name: "ChatGPT Plus", value: "40%", level: .normal, stale: false,
                             runOutMarker: true, tag: "5h", windowName: "5-hour window")
        #expect(present(marked, .text, symbols: false).accessibilityText
                == "ChatGPT Plus 5-hour window 40%, projected to run out before reset")
    }

    /// spec 030 FR-004: a critical level below a real limit reads
    /// "critical", a real limit "over limit"; warning stays "warning". The
    /// tone and the pill are the same for both.
    @Test func criticalWordsTellThresholdFromRealLimit() {
        let threshold = present(Self.item(level: .critical, value: "91%", name: "Claude Max"), .text, symbols: false)
        #expect(threshold.accessibilityText == "Claude Max critical 91%")
        #expect(threshold.textTone == .overLimit)
        let real = present(Self.item(level: .critical, value: "100%", name: "Claude Max", overLimit: true), .text, symbols: false)
        #expect(real.accessibilityText == "Claude Max over limit 100%")
        #expect(real.textTone == .overLimit)
        let warning = present(Self.item(level: .warning, value: "85%", name: "Claude Max"), .pill, symbols: true)
        #expect(warning.accessibilityText == "Claude Max warning 85%")
    }

    /// spec 030 FR-009, FR-011: an item in direction remaining shows the
    /// downward markers and reads its value in words.
    @Test func remainingEntryUsesDownwardMarkersAndWords() {
        let slow = BarItem(id: "acc", icon: "brands:claude", name: "Claude", value: "30%", level: .normal, stale: false,
                           runOutMarker: true, accessibilityValue: "30% left", direction: .remaining)
        let slowEntry = present(slow, .text, symbols: false)
        #expect(slowEntry.runOutMarker == "↘")
        #expect(slowEntry.valueText == "30%")
        #expect(slowEntry.accessibilityText == "Claude 30% left, projected to run out before reset")
        let fast = BarItem(id: "acc", icon: "brands:claude", name: "Claude", value: "30%", level: .normal, stale: false,
                           runOutMarker: true, burnsFast: true, accessibilityValue: "30% left", direction: .remaining)
        #expect(present(fast, .text, symbols: false).runOutMarker == "↓")
        let none = BarItem(id: "acc", icon: "brands:claude", name: "Claude", value: "30%", level: .normal, stale: false,
                           accessibilityValue: "30% left", direction: .remaining)
        #expect(present(none, .text, symbols: false).runOutMarker == nil)
    }

    /// Without a tag the entry and its text stay as today.
    @Test func noTagWithoutWindowName() {
        let entry = present(Self.item(level: .normal, value: "70%", name: "Claude Max"), .text, symbols: false)
        #expect(entry.tag == nil)
        #expect(entry.accessibilityText == "Claude Max 70%")
    }
}
