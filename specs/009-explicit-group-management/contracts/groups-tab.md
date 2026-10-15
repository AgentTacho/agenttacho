# Contract: Settings > Groups tab

List (left): groups in groups-list order, each with icon, name and "<amount> <per period>, <n> member(s)". Below the list:

- Buttons: **Add** (always enabled) and **Remove...** (enabled with a selection).
- Caption: "Add and remove groups here. A group stays when its last account leaves; membership is set in each account's Budget picker."

Add: appends "Budget group" (default icon, weekly, 60 USD, shown in bar, thresholds 80% and 100%) and selects it.

Remove... opens a sheet:

| Group has members | Sheet content | Buttons |
|---|---|---|
| no | "Remove "<name>"?" | Remove (destructive), Cancel |
| yes | "Remove "<name>"?", the member names, picker "Move its accounts to": "Own budgets" (default), then each other group in Groups tab order | Remove (destructive), Cancel |

After Remove no group is selected; Edit > Undo restores the group and the members' previous membership.

Group editor (right): unchanged fields; the Members section lists the members, or "No accounts in this group yet".

Accounts tab, Remove... message: no longer says the group is removed; for the last member of a group it adds: The group "<name>" stays, without accounts.
