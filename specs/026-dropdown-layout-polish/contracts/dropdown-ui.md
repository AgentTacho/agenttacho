# Contract delta: Dropdown (spec 026 over spec 025's contracts/dropdown-ui.md)

## Budget section

```
[icon] Company budget                       86%
430 of $500/month                resets in 12d 17h
█████████████████│████████░░░░░░░░░
27% ahead · runs out in 2d 23h
G  Claude via Vertex                $181 (36%)
֍  OpenAI API                       $249 (50%)
⌄ Details
  [Models | Projects | Harnesses]
  ...group table...
  T   F   S   S   M   T   W   T    Σ
  12  40  31  55  42  0   0   0   180
  Show account details
  G Claude via Vertex
  ...table... + day row with Σ
  ֍ OpenAI API
  ...table... + day row with Σ
```

- Member lines: no Details of their own.
- Button text toggles "Show account details" / "Hide account details"; shown only when `MemberDisplay.showsAccountsButton`.

## Details of subscriptions and Unassigned

- First element is the view picker (no "This week" line); the day row ends with Σ.

## Footer (pinned)

```
  … sections scroll above …
<footer band, full width, no divider above it (amended by spec 028 FR-001, FR-007)>
<up to 3 error lines, one line each; "+N more">
<update line when present>
[↻] Last refreshed 7:23 AM   stale      [⚙] [⏻]
```

- Status text: one line, truncated; tooltip per `FooterText.statusTooltip`; accessibility value is the pace text.
- Identifiers unchanged: `agenttacho.refreshButton`, `agenttacho.settingsButton`, `agenttacho.quitButton`, `agenttacho.details`, `agenttacho.budgetRow`.
