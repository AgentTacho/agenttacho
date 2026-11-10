import Foundation
import Testing
@testable import UsageCore

/// Spec 044 FR-016, FR-017, research R6: the group editor's draft, with an
/// optional amount, shown through spec 043's own budget form with its
/// enabling rules and help texts.
@Suite struct GroupBudgetFormTests {
    static let group = BudgetGroup(id: "grp-a", name: "Free models", icon: "solid:gift", period: .monthly, budgetUSD: 500,
                                   shownInBar: false, thresholds: [50, 90], timeFormat: .absolute,
                                   valueAs: "claude-opus-5-5", show: .money)

    @Test func formReadsTheGroup() {
        let form = GroupBudgetForm(Self.group)
        #expect(form.amount == 500)
        #expect(form.period == .monthly)
        #expect(form.thresholds == [50, 90])
        #expect(form.shownInBar == false)
        #expect(form.ownForm.hasAmount)
    }

    /// Clearing the amount keeps period, thresholds and shown-in-bar; an
    /// amount entered again gives the original group (FR-002, US4).
    @Test func clearingAndEnteringTheAmountKeepsTheSettings() {
        var form = GroupBudgetForm(Self.group)
        form.amount = nil
        let cleared = form.applied(to: Self.group)
        #expect(cleared.budgetUSD == nil)
        #expect(cleared.period == .monthly)
        #expect(cleared.thresholds == [50, 90])
        #expect(cleared.shownInBar == false)
        #expect(cleared.valueAs == "claude-opus-5-5")
        #expect(cleared.show == .money)
        var again = GroupBudgetForm(cleared)
        #expect(again.amount == nil)
        again.amount = 500
        #expect(again.applied(to: cleared) == Self.group)
    }

    /// An amount of 0 stays an amount, which saving refuses with today's
    /// message (spec 003 FR-019).
    @Test func zeroAmountRefusesSaving() {
        var form = GroupBudgetForm(Self.group)
        form.amount = 0
        #expect(form.ownForm.amountError == "The monthly budget must be greater than 0.")
        let config = Configuration(groups: [form.applied(to: Self.group)])
        #expect(throws: ConfigurationError(kind: .budget, message: "Monthly budget of group \"Free models\" must be greater than 0.")) {
            try config.validateForSaving()
        }
        form.amount = nil
        #expect(form.ownForm.amountError == nil)
        #expect((try? Configuration(groups: [form.applied(to: Self.group)]).validateForSaving()) != nil)
    }

    /// The editor reads its rules from `ownForm` (FR-016): without an
    /// amount the thresholds and "Show in menu bar" are disabled with the
    /// period's help text, the toggle shows unchecked, and the kept value
    /// stays.
    @Test func withoutAnAmountThresholdsAndMenuBarAreDisabled() {
        var form = GroupBudgetForm(Self.group)
        form.shownInBar = true
        #expect(form.ownForm.budgetControlsEnabled)
        #expect(form.ownForm.budgetControlsHelp == nil)
        #expect(form.ownForm.shownInBarDisplayed)
        form.amount = nil
        #expect(!form.ownForm.budgetControlsEnabled)
        #expect(!form.ownForm.shownInBarDisplayed)
        #expect(form.ownForm.shownInBar)
        #expect(form.ownForm.budgetControlsHelp == "Set a monthly budget to use thresholds and the menu bar.")
        form.period = .weekly
        #expect(form.ownForm.budgetControlsHelp == "Set a weekly budget to use thresholds and the menu bar.")
    }

    @Test func priceTokensAsOnlyWithoutAnAmount() {
        var form = GroupBudgetForm(Self.group)
        #expect(!form.ownForm.valueAsEnabled)
        #expect(form.ownForm.valueAsHelp == "Price tokens as applies only without a monthly budget.")
        form.amount = nil
        #expect(form.ownForm.valueAsEnabled)
        #expect(form.ownForm.valueAsHelp == nil)
    }

    /// Percent is disabled without an amount; a stored Percent stays
    /// selected with its help text (spec 043 FR-012, FR-018).
    @Test func percentNeedsAnAmount() {
        var group = Self.group
        group.show = .percent
        var form = GroupBudgetForm(group)
        #expect(DropdownShow.isEnabled(.percent, hasAmount: form.ownForm.hasAmount))
        form.amount = nil
        #expect(!DropdownShow.isEnabled(.percent, hasAmount: form.ownForm.hasAmount))
        #expect(form.applied(to: group).show == .percent)
        #expect(DropdownShow.help(.percent, hasAmount: form.ownForm.hasAmount, period: form.period)
                == "Percent needs a monthly budget. The headline follows Automatic.")
    }

    /// The group editor shows the own budget editor's fields through
    /// `ownForm`: it carries the group's values, and edits made in it reach
    /// the group, the other settings unchanged (FR-016, FR-002).
    @Test func ownFormCarriesTheGroupBudgetBothWays() {
        var form = GroupBudgetForm(Self.group)
        let own = form.ownForm
        #expect(own.period == .monthly)
        #expect(own.amount == 500)
        #expect(own.thresholds == [50, 90])
        #expect(own.shownInBar == false)
        #expect(own.hasAmount)
        var edited = own
        edited.amount = nil
        edited.period = .weekly
        edited.thresholds = [75]
        edited.shownInBar = true
        form.ownForm = edited
        // Only the four budget fields change; name, icon, Price tokens as,
        // Show and the time format stay.
        var expected = Self.group
        expected.budgetUSD = nil
        expected.period = .weekly
        expected.thresholds = [75]
        expected.shownInBar = true
        #expect(form.applied(to: Self.group) == expected)
        #expect(form.ownForm == edited)
    }
}
