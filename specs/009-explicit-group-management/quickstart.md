# Quickstart: Explicit Group Management

## Automated checks

```bash
make test        # GroupLifecycleTests, ConfigurationTests, ArrangementReconcileTests, ThresholdTrackerTests
make app
```

## Manual validation (with a config backup)

1. **Group survives (US1).** Settings > Accounts: switch the only member of a group to "Own budget". The group stays in the Groups tab, keeps its settings and its place in the Menu Bar tab; the bar shows it at 0%, and its dropdown section says "No accounts in this group yet". Switch the account back: it is a member again.
2. **Add (US2).** Groups tab > Add: "Budget group" appears selected (weekly, 60 USD, shown in bar, 80%/100%); it is last in the Menu Bar tab and offered in an account's Budget picker.
3. **Remove with members (US3).** Remove a group with two members choosing "Own budgets": both get their own budget with the group's values and take the group's place in the bar, in member order. Undo restores the group. Remove again choosing another group: the members join it, last, in member order.
4. **Remove empty group.** A plain confirmation, then the group is gone.
5. **Account removal text.** Remove the last member of a group: the message says the group stays.
