# Quickstart: Unified Token Accounts

Validation scenarios. Build and test only through the Makefile.

1. `make test`: the suites named in tasks.md pass, including the legacy `noLimit` fixture (story 4) and the demo coverage for `acc-free` (Tokens headline, value line) and `acc-api` (Money headline), neither in the menu bar.
2. `make app-demo`, open the dropdown:
   - "Free models" shows `48.2M`-style tokens and `≈ $… at claude-opus-5-5 prices` as before.
   - "API key" shows a whole-dollar headline, tooltip `$… spent this month`, line `spent this month`, Details with cost per model.
   - The menu bar has no entry for either.
3. Settings > Accounts > "API key": budget picker offers `Own budget` and groups only; Amount empty with placeholder `No limit`; thresholds and "Show in menu bar" disabled with help; `Dropdown shows` has Percent disabled. Enter `300`: controls enable, headline becomes percent, a menu bar entry appears after saving. Clear the amount: back to the Money headline, entry gone.
4. Set `Dropdown shows` to Tokens on a budgeted account: the headline shows tokens; amount line, bar and pace unchanged.
5. Remaining mode on (Menu Bar tab): a budgeted account with `Dropdown shows` Money shows the amount left, or `−$…` when over.
6. Load a configuration file with a spec 041 `noLimit` account: it loads without error, looks as before, and the next save writes `budget` without `budgetUSD`.
