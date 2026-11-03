import Foundation
import Testing
@testable import UsageCore

/// Spec 043 FR-002, FR-003, FR-019, data-model.md "OwnBudgetForm", research
/// R7: the own budget editor's draft, whose amount flips the membership.
@Suite struct OwnBudgetFormTests {
    static let budget = BudgetSettings(period: .monthly, budgetUSD: 300, shownInBar: false, thresholds: [50, 90])

    /// The editor's texts as contracts/ui-strings.md words them (FR-018,
    /// story 1 scenario 2).
    @Test func editorTextsMatchTheContract() {
        #expect(OwnBudgetForm.amountPlaceholder == "No limit")
        // The tooltips name the period's budget, not "an amount", and the
        // pop-up is "Price tokens as" (walkthrough step 6).
        var form = OwnBudgetForm(.noLimit(NoLimitSettings(period: .monthly)))
        #expect(form.needsBudgetHelp == "Set a monthly budget to use thresholds and the menu bar.")
        #expect(form.valueAsDisabledHelp == "Price tokens as applies only without a monthly budget.")
        form.period = .weekly
        #expect(form.needsBudgetHelp == "Set a weekly budget to use thresholds and the menu bar.")
        #expect(form.valueAsDisabledHelp == "Price tokens as applies only without a weekly budget.")
        #expect(OwnBudgetForm.valueAsLabel == "Price tokens as")
        #expect(OwnBudgetForm.valueAsCaption == "Shows what the tokens of models without a price would cost at this model's prices.")
    }

    @Test func formFromAnOwnBudget() {
        let form = OwnBudgetForm(.ownBudget(Self.budget))
        #expect(form.amount == 300)
        #expect(form.period == .monthly)
        #expect(form.thresholds == [50, 90])
        #expect(form.shownInBar == false)
        #expect(form.membership == .ownBudget(Self.budget))
    }

    @Test func clearingTheAmountKeepsTheSettings() {
        var form = OwnBudgetForm(.ownBudget(Self.budget))
        form.amount = nil
        #expect(form.membership == .noLimit(NoLimitSettings(period: .monthly, thresholds: [50, 90], shownInBar: false)))
        form.amount = 300
        #expect(form.membership == .ownBudget(Self.budget))
    }

    @Test func formFromANewAccountWithoutAnAmount() {
        let form = OwnBudgetForm(.noLimit(NoLimitSettings()))
        #expect(form.amount == nil)
        #expect(form.period == .weekly)
        #expect(form.thresholds == [80, 100])
        #expect(form.shownInBar == true)
        #expect(form.membership == .noLimit(NoLimitSettings()))
    }

    /// Only nil means no amount; 0 or less stays an amount that saving
    /// refuses with today's message (FR-002).
    @Test(arguments: [Decimal(0), Decimal(-5)])
    func zeroOrLessIsAnAmountSavingRefuses(amount: Decimal) {
        var form = OwnBudgetForm(.noLimit(NoLimitSettings(period: .monthly)))
        form.amount = amount
        guard case .ownBudget(let budget) = form.membership else {
            Issue.record("expected an own budget")
            return
        }
        #expect(budget.budgetUSD == amount)
        let config = Configuration(accounts: [Account(id: "a", displayName: "Free", kind: .tokenBased(TokenBasedSettings(membership: form.membership)))])
        #expect(throws: ConfigurationError(kind: .budget, message: "Monthly budget of account \"Free\" must be greater than 0.")) {
            try config.validateForSaving()
        }
    }

    /// FR-018: without an amount the disabled "Show in menu bar" toggle shows
    /// unchecked, as the Menu Bar tab does (FR-020); the kept value stays
    /// stored and shows again once an amount is entered.
    @Test func shownInBarDisplaysOnlyWithAnAmount() {
        var form = OwnBudgetForm(.noLimit(NoLimitSettings(period: .monthly, thresholds: [80], shownInBar: true)))
        #expect(form.shownInBar == true)
        #expect(form.shownInBarDisplayed == false)
        form.amount = 50
        #expect(form.shownInBarDisplayed == true)
        form.shownInBar = false
        #expect(form.shownInBarDisplayed == false)
        form.amount = nil
        #expect(form.shownInBarDisplayed == false)
        #expect(form.membership == .noLimit(NoLimitSettings(period: .monthly, thresholds: [80], shownInBar: false)))
    }

    /// The inline error below the amount field of a group, an own budget
    /// and the new account sheet (spec 003 FR-019, spec 043 FR-002): an
    /// empty own budget amount is no limit, not an error.
    @Test func amountErrorNamesThePeriod() {
        #expect(BudgetPeriod.weekly.amountError(for: 0) == "The weekly budget must be greater than 0.")
        #expect(BudgetPeriod.monthly.amountError(for: -5) == "The monthly budget must be greater than 0.")
        #expect(BudgetPeriod.weekly.amountError(for: Decimal(string: "0.01")) == nil)
        #expect(BudgetPeriod.monthly.amountError(for: nil) == nil)
        var form = OwnBudgetForm(.noLimit(NoLimitSettings(period: .monthly)))
        #expect(form.amountError == nil)
        form.amount = 0
        #expect(form.amountError == "The monthly budget must be greater than 0.")
        form.amount = 300
        #expect(form.amountError == nil)
    }

    /// The new account sheet's caption below the budget pop-up
    /// (contracts/ui-strings.md "Settings: new account sheet").
    @Test func newAccountCaptionFollowsTheChoiceAndTheAmount() {
        #expect(OwnBudgetForm.newAccountCaption(ownBudget: nil)
                == "To share a budget with other accounts, create a budget group in the Groups tab first.")
        var form = OwnBudgetForm(.noLimit(NoLimitSettings()))
        #expect(OwnBudgetForm.newAccountCaption(ownBudget: form)
                == "Without a weekly budget the account has no limit and is not shown in the menu bar.")
        form.period = .monthly
        #expect(OwnBudgetForm.newAccountCaption(ownBudget: form)
                == "Without a monthly budget the account has no limit and is not shown in the menu bar.")
        form.amount = 100
        #expect(OwnBudgetForm.newAccountCaption(ownBudget: form)
                == "Shown in the menu bar, with notifications at 80% and 100%. To share a budget with other accounts, create a budget group in the Groups tab first.")
    }

    @Test func groupMembershipGivesADefaultForm() {
        let form = OwnBudgetForm(.group(id: "g", shownInBar: true))
        #expect(form.amount == nil)
        #expect(form.membership == .noLimit(NoLimitSettings()))
    }
}
