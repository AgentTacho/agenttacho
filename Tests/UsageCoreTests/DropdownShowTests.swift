import Testing
@testable import UsageCore

/// Spec 043 FR-011, FR-012, FR-018, data-model.md "DropdownShow", research
/// R3: the resolver of the dropdown headline and the pop-up rules.
@Suite struct DropdownShowTests {
    /// Every row of the table in data-model.md.
    @Test(arguments: [
        (DropdownShow.automatic, true, false, HeadlineMeasure.percent),
        (.automatic, true, true, .percent),
        (.automatic, false, true, .money),
        (.automatic, false, false, .tokens),
        (.percent, true, false, .percent),
        (.percent, true, true, .percent),
        (.percent, false, true, .money),
        (.percent, false, false, .tokens),
        (.tokens, true, true, .tokens),
        (.tokens, true, false, .tokens),
        (.tokens, false, true, .tokens),
        (.tokens, false, false, .tokens),
        (.money, true, true, .money),
        (.money, true, false, .money),
        (.money, false, true, .money),
        (.money, false, false, .money),
    ])
    func resolve(show: DropdownShow, hasAmount: Bool, hasPricedUsage: Bool, expected: HeadlineMeasure) {
        #expect(show.resolve(hasAmount: hasAmount, hasPricedUsage: hasPricedUsage) == expected)
    }

    @Test func percentIsDisabledWithoutAnAmount() {
        #expect(DropdownShow.isEnabled(.percent, hasAmount: false) == false)
        #expect(DropdownShow.help(.percent, hasAmount: false, period: .monthly) == "Percent needs a monthly budget. The headline follows Automatic.")
        #expect(DropdownShow.help(.percent, hasAmount: false, period: .weekly) == "Percent needs a weekly budget. The headline follows Automatic.")
        for choice in DropdownShow.allCases {
            #expect(DropdownShow.isEnabled(choice, hasAmount: true))
            #expect(DropdownShow.help(choice, hasAmount: true, period: .monthly) == nil)
        }
        for choice in [DropdownShow.automatic, .tokens, .money] {
            #expect(DropdownShow.isEnabled(choice, hasAmount: false))
            #expect(DropdownShow.help(choice, hasAmount: false, period: .monthly) == nil)
        }
    }

    /// A stored Percent stays selected (and disabled) without an amount; the
    /// stored setting is never rewritten (FR-012, FR-018).
    @Test func storedPercentStaysSelectedWithoutAnAmount() {
        var settings = TokenBasedSettings(membership: .noLimit(NoLimitSettings()))
        settings.show = .percent
        #expect(settings.show == .percent)
        #expect(settings.show.resolve(hasAmount: false, hasPricedUsage: false) == .tokens)
        #expect(!DropdownShow.isEnabled(settings.show, hasAmount: false))
    }

    @Test func titles() {
        #expect(DropdownShow.allCases.map(\.title) == ["Automatic", "Percent", "Tokens", "Money"])
        #expect(DropdownShow.popUpLabel == "Dropdown shows")
    }
}
