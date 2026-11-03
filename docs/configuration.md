# Configuration

Everything lives in one JSON file, `~/.config/agenttacho/config.json`. The settings window (the Settings icon at the bottom of the dropdown, or ⌘,) writes it, and you can edit it by hand. The app picks up changes at the next refresh. If the file is invalid, the dropdown says so and the last valid configuration stays active.

```json
{
  "version": 1,
  "refreshIntervalSeconds": 300,
  "adaptiveRefresh": true,
  "openCodeDirectories": [],
  "accounts": [
    { "id": "acc-max", "type": "subscription", "icon": "brands:claude",
      "displayName": "Claude Max", "credentialDirectory": "~/.claude",
      "additionalSessionDirectories": ["~/.claude-lab", "~/agent-sessions/openshell/*/claude"],
      "shownInBar": true, "thresholds": [80, 100], "headlineWindow": "model:Fable" },
    { "id": "acc-vertex", "type": "tokenBased", "icon": "brands:google",
      "displayName": "Claude Code via Vertex", "harness": "claudeCode",
      "sessionKind": "vertex",
      "claudeCodeDirectory": "~/agent-profiles/work/claude",
      "groupId": "grp-vertex", "shownInBar": false },
    { "id": "acc-vertex-oc", "type": "tokenBased", "icon": "brands:google",
      "displayName": "OpenCode via Vertex", "harness": "openCode",
      "sessionKind": "vertex",
      "groupId": "grp-vertex", "shownInBar": false },
    { "id": "acc-lab", "type": "tokenBased", "icon": "brands:claude",
      "displayName": "Lab gateway", "harness": "claudeCode",
      "sessionKind": "otherProvider",
      "condition": { "field": "model", "operator": "contains", "text": "glm" },
      "claudeCodeDirectory": "~/.claude-gateway",
      "budget": { "period": "monthly", "budgetUSD": 100, "shownInBar": true, "thresholds": [80, 100] } },
    { "id": "acc-oai", "type": "tokenBased", "icon": "brands:openai",
      "displayName": "Codex API key", "harness": "codex",
      "sessionKind": "apiKey", "codexHome": "~/.codex-lab",
      "budget": { "period": "monthly", "budgetUSD": 50, "shownInBar": true, "thresholds": [80, 100] } },
    { "id": "acc-codex", "type": "codexSubscription", "icon": "brands:openai",
      "displayName": "ChatGPT Plus", "codexHome": "~/.codex",
      "additionalSessionDirectories": ["~/agent-sessions/openshell/*/codex"],
      "shownInBar": true, "thresholds": [80, 95], "liveLimits": true }
  ],
  "groups": [
    { "id": "grp-vertex", "name": "Vertex", "icon": "solid:wallet",
      "period": "monthly", "budgetUSD": 400, "shownInBar": true, "thresholds": [80, 100] }
  ]
}
```

Each account names the agent directory it runs from. A Claude subscription's `credentialDirectory` is its Claude Code directory: its sessions and its login come from there. A Codex subscription's `codexHome` is where its sessions and, with live limits on, its sign-in come from. Left empty, they mean `~/.claude` and `~/.codex`. Settings does not let you empty one while another account already uses the default; a file saved that way by an older version still loads, both accounts read the same login, and the log notes it. A token-based Claude Code account takes an optional `claudeCodeDirectory` and a token-based Codex account an optional `codexHome`, for an agent that runs from a profile directory such as `~/agent-profiles/work/claude` or `~/.codex-lab`; an OpenCode account has neither. From these AgentTacho reads session files only (the `projects` or `sessions` folder), never a login or `auth.json`. Left empty, they mean `~/.claude` and `~/.codex` too. AgentTacho reads exactly the directories the accounts name: `~/.claude` and `~/.codex` are read only when an account resolves to them, an agent without an account has none of its sessions read, and a directory named by more than one account is read once. OpenCode is different: its default data directory is always read, plus the ones added on the Sources page. The key follows the harness: a `codexHome` on a Claude Code account, a `claudeCodeDirectory` on a Codex account, or either on an OpenCode account, is ignored and noted in the log, and the next save drops it.

Every account can also take `additionalSessionDirectories`, a list of further directories whose sessions count for it: Claude Code directories for a Claude subscription or token-based Claude Code account, Codex homes for a Codex subscription or token-based Codex account; OpenCode accounts have none. From these AgentTacho reads only the `projects` or `sessions` folder, read-only, never a login, keychain item, `auth.json` or limit snapshot; plan limits always come from the account's main directory. For Claude Code, a session file that names a listed directory as its profile counts for the account when no account has it as its main directory (see below); otherwise a listed directory never forces its sessions onto the account. When two subscription accounts of the same kind both match a session, the account whose main directory holds it wins, then the one account that lists the directory; otherwise the session stays Unassigned. An entry may use `*` for any folder name at one level (`~/agent-sessions/openshell/*/claude`, `~/.claude-*`); a `*` at the start of a name skips names that begin with `.`, only folders match, and no other character is special. The matching folders are looked up again at every refresh, at most 100 per entry in name order; the log says when an entry matches more, and each refresh's log line names how many directories were read. Entries must start with `~/` or `/`; an entry with `**`, a bare `*` directly under the home folder or `/` (such as `~/*/claude`), or the home folder or `/` itself is refused in Settings with "Not applied", and in a hand-edited file it is dropped with a note in the log. A value that is not a list of strings is ignored with a note too, and the next save writes neither. A directory reached several ways, as a main directory, an entry, a match or on several accounts, is read once. The same `*` rule applies to `openCodeDirectories`, where a matched folder counts when it holds an `opencode.db`; there a relative entry is refused only when it contains `*`.

Older versions had global lists of extra directories, `logDirectories` (Claude Code) and `codexHomes` (Codex). They are no longer read, and the next save drops them. On load, each entry leaves a note in the log (Settings > Log): set it as the Claude Code directory or Codex home of an account, or, when an account already names it or it is the default, nothing is left to do.

`checksForUpdates` (default `true`) turns the automatic update check on or off, like the toggle in Settings > General > Startup.

The optional `arrangement` key holds the order of the bar and the dropdown: `entries` lists the top-level entries as `{ "kind": "account" | "group", "id": "..." }`, and `members` maps each group id to its member account ids in order. The key is absent until you first change the order (or add, move or remove an account or group in a way that affects it); until then the bar shows accounts first, then groups. Unknown or misplaced ids are ignored and missing entries are added at the end, so a hand edit never makes the file invalid.

Every account and group takes an optional `timeFormat` for its section in the dropdown: `"relative"` (the default) reads reset and run-out times as "resets in 2h 26m" or "runs out in 2d 13h", `"absolute"` as "resets 17:20" today, "resets Fri 09:00" within the next six days, and with the date further out. Hovering a time shows the other form. It changes only the dropdown, not the bar or notifications. A token-based account in a group uses its group's format and keeps its own value for when it gets its own budget again. An unknown `timeFormat` value reads as `"relative"` and is noted in the log.

Claude and Codex subscription accounts take an optional `headlineWindow`: the window the bar and the account's section header follow, set by clicking a window row in the dropdown. For a Claude subscription it names the window as AgentTacho identifies it: `"sevenDay"` for the 7-day window, `"fiveHour"` for a 5-hour window, `"model:<model name>"` for a model limit (for example `"model:Fable"`, matched exactly, including case), `"model:<model name>:<kind>"` for a further limit of the same model, and `"limit:<kind>"` for any other plan window, with the kind as Anthropic reports it (for example `"limit:daily_all"`). For a Codex plan it is `"window:<name>"` with the window's name from the dropdown, such as `"window:5-hour"`, `"window:weekly"` or `"window:30-day"`. Without it the bar shows the 7-day window (without one, the longest plan window Anthropic reports) or the plan's longest window. A window the provider does not report falls back to that default until it is back, and the stored value stays. An unknown value, or one for the other account type, is ignored and noted in the log; the next save drops it.

The optional `levelColor` key sets how the bar shows levels: `"text"` (the default) colors the value orange at the first threshold and red at the second one or at a real limit, such as 100% or a reached Codex limit, `"pill"` draws the entry on an orange or red background, and `"off"` uses no color. `showLevelSymbols` (default `false`) adds the `⚠` and `‼` symbols. An unknown `levelColor` value falls back to `"text"` and is noted in the log.

The optional `displayDirection` key sets how limits and budgets read, like **Show usage as** in Settings > General > Appearance: `"used"` (the default) counts up from 0% to 100%, `"remaining"` counts down from 100%. Thresholds are stored in used percent either way, so a first notification shown as "20% left" is stored as 80, and switching never changes when a notification fires. An unknown value reads as `"used"` and is noted in the log.

The optional `dropdownTheme` key sets the dropdown's look, like **Dropdown theme** in Settings > General > Appearance: `"auto"` (the default) follows the system appearance, `"dark"` and `"light"` keep the dropdown dark or light whatever the system does. AgentTacho writes the key only for `"dark"` and `"light"`; with Auto the file has no `dropdownTheme` entry. It changes only the dropdown, not the menu bar item or the Settings window. An unknown value reads as `"auto"` and is noted in the log.

## Matching usage to accounts

Every token-based account has exactly one `harness`, `claudeCode`, `codex` or `openCode`: it decides which sessions feed the account, which directory field it has (a Claude Code directory, a Codex home, or none for OpenCode, whose data directories are set for all accounts on General > Sources) and which session kinds it offers. A token-based account sees only usage of its own harness.

**The Claude Code directory decides first.** Workspace managers can give each Claude Code profile its own configuration directory, such as `~/agent-profiles/work/claude`, while linking every profile's `projects` folder to one shared folder. Since Claude Code 2.1.300, each session file holds request shape lines whose system prompt names the configuration directory's memory folder, `<configuration directory>/projects/<project>/memory/`. AgentTacho searches these lines for the Claude Code directories of your accounts (main and additional, `~` expanded, a symlinked configuration directory resolved, the `projects` folder never resolved) and takes only the directory it finds; nothing else of the line is kept, logged or shown. A record counts for the one account, a Claude subscription or a token-based Claude Code account, whose main directory it names, whatever the account's session kind and condition say; without one, for the one account that lists it as an additional session directory. A record takes the directory of the latest shape line before it, records before the first take the first one, and a line that names two directories is skipped. When several accounts share the directory (for example a Claude subscription and a Vertex account on `~/.claude`), the session kinds decide among them only. Each refresh's log line says how many files named a configured directory and how many named none, so a change of Claude Code's file format shows up.

**Which sessions count (`sessionKind`).** For records without that directory information (older sessions, auto-memory off, Codex and OpenCode), a token-based account counts the records of its session kind. Every check is exact and case-sensitive:

| Harness | `sessionKind` | In Settings | Counts a record when |
|---|---|---|---|
| Claude Code | `directoryOnly` | Directory only | never: only sessions from the account's Claude Code directories count |
| Claude Code | `vertex` | Vertex | the request id starts with `req_vrtx_` |
| Claude Code | `otherProvider` | Other provider | the record has no request id starting with `req_`, such as the records of a company gateway |
| Codex | `apiKey` | (no choice) | the session signed in with an API key |
| OpenCode | `vertex` | Vertex | the provider is `google-vertex` or `google-vertex-anthropic` |
| OpenCode | `openai` | OpenAI | the provider is `openai` |
| OpenCode | `anthropic` | Anthropic | the provider is `anthropic`; OpenCode reports it for an Anthropic API key and for a Claude plan sign-in alike, so such plan usage counts here too, at API prices |
| OpenCode | `otherProvider` | Other provider | a provider is set and is none of these four; this kind needs a condition that says which |

A new Claude Code account starts as Directory only, an OpenCode account as Vertex. Claude subscriptions count direct Anthropic records (a request id `req_` with no further `_`), Codex subscriptions ChatGPT-plan sessions. The kinds of one harness never overlap, so a record is of at most one kind; a record of a kind no account has, such as a direct record without a Claude subscription, or a message without a provider, is Unassigned.

Directory only is the setup for an Anthropic API key billed per token: its records look like a Claude subscription's, so no kind can tell them apart. Give such an account its own Claude Code directory, such as `~/.claude-gateway`, and run Claude Code from there. Settings warns when a Directory only account shares its main directory with another account (an empty field is `~/.claude`), since that account would then count the sessions. Other provider relies on gateways sending no Anthropic request id; Amazon Bedrock and other proxies have not been checked. A proxy whose request ids start with `req_` but carry another infix matches no Claude Code kind and stays Unassigned.

**Conditions (`condition`).** "Only when" narrows a kind with one condition: a field, an operator and a text, for example Model contains `glm`. A record counts only when it is of the account's kind and matches the condition; a condition never makes a record of another kind count, so it cannot take a subscription's records. Among the accounts of one kind, accounts whose condition matches win over accounts without a condition; one winner takes the record, anything else is Unassigned. Directory only offers no condition; OpenCode Other provider always has one.

| `field` | Compares | `operator` values |
|---|---|---|
| `model` | the record's model (all harnesses) | `startsWith`, `contains`, `regex` |
| `requestId` | the request id (Claude Code) | `startsWith`, `contains`, `regex` |
| `messageId` | the message id (Claude Code) | `startsWith`, `contains`, `regex` |
| `anywhere` | the raw record line, including tool inputs and outputs, so a session that only mentions the text matches too | `contains`, `regex` |

| `operator` | In Settings | Matches when |
|---|---|---|
| `startsWith` | starts with | the field begins with the text |
| `contains` | contains | the field contains the text anywhere |
| `regex` | matches regex | the regular expression is found anywhere in the field; `^` and `$` anchor it, as in `^gateway-(a\|b)/` |

Conditions ignore case, including Unicode case (`GLM` matches `glm`, `Ä` matches `ä`), but not diacritics (`a` does not match `ä`). Starts with and contains compare the text literally, so contains `a.b` matches only a literal `a.b`. A regular expression uses the ICU syntax that macOS provides ([ICU regular expressions](https://unicode-org.github.io/icu/userguide/strings/regexp.html)); `(?-i)` at its start turns case sensitivity back on. A field that is empty never matches, so a pattern such as `x*` matches every record of the kind that has the field. Session kinds keep their exact, case-sensitive checks, and so does a subscription's `customMarker`.

Matching one record with a regular expression stops after 50 ms and counts as no match. The condition then sits out the rest of that refresh: the records it would have checked go through the other accounts, or stay Unassigned, and the log names the account once per refresh. The next refresh tries the condition again and attributes those records once more; the record the condition ran out of time on counts as no match without running again. If the condition runs out of time on another record during that second attribution, it is slow on more than one record: from then on, until you change a setting that decides which sessions count, records it sat out on keep their attribution. A pattern that runs out of time on every record therefore costs about 50 ms per refresh and does not keep reading session files again. The limit applies to each record on its own: a pattern that takes a few milliseconds on every long record line never runs out of time and slows every refresh, so keep patterns simple, especially on Anywhere. A condition runs only on records of its kind. A session file that grew in the meantime counts as tried again, including its new lines. After a time-out early in the first scan, the next refresh reads the affected Claude Code session files once more from the start.

Settings refuses a regular expression that is not valid, a blank text, and OpenCode Other provider without a condition: the change is not saved, the "Not applied" line names the account, and the notes below the controls say what is wrong. A hand-edited file with such a setting still loads; the condition matches no record until you correct it in Settings, and the log names the account once per load.

**Subscription markers.** A Claude or Codex subscription can take a `customMarker`, text that must appear in the record line exactly as written. It only decides among the subscription's own kind of records (direct Anthropic records, ChatGPT-plan sessions): a marked subscription takes such a record when the line contains the marker, and wins over a subscription of the same kind without one. It never takes the records of a token-based account.

**Stored form.** A token-based account stores `sessionKind` always and `condition` (`field`, `operator`, `text`) only when "Only when" is on and the kind offers one. A condition turned off, or kept while Directory only is chosen, is not written.

**Overlap warning.** Two token-based accounts of the same harness and kind with the same condition (both without one, or the same field, operator and text), and for Claude Code the same main directory, cannot be told apart. Settings shows a warning on each that records matching both stay Unassigned. Directory only accounts are separated by their directory alone and get the shared directory warning instead. The warning compares conditions as written: texts are equal ignoring case for starts with and contains, and exactly as written for a regular expression (`\d` and `\D` are different patterns). Two different texts or patterns that happen to match the same records get no warning.

**Spend across harnesses.** One account reads one harness. For one Vertex budget across Claude Code and OpenCode, add a Claude Code account and an OpenCode account, both of kind Vertex, and put them into one budget group; the group shows the sum and its harness breakdown lists both.

**Migration from older files.** Files of earlier versions load without action; the log names each migrated account once, and the next save writes `sessionKind` and `condition`, never `matchRule`, `provider` or a token-based `customMarker`.

- Version 0.8.0 and earlier: a token-based account has a `provider`. `"provider": "vertex"` (or none) becomes a Claude Code account of kind Vertex, `"provider": "openai"` a Codex account (API key), both keeping their directories; the stored `harness` of such a file is ignored. A token-based `customMarker` becomes the condition Anywhere contains that text, which now ignores case. Such a marker used to match any record that contained it; as a condition of the Vertex kind it no longer matches the records of a company gateway, and the log says so. For a gateway, choose kind Other provider. A Vertex or OpenAI account no longer counts OpenCode usage: add an OpenCode account of kind Vertex or OpenAI for it, in the same budget group if it should share the budget.
- Development builds with `matchRule`: a preset becomes its kind; `{ "type": "none" }` becomes Directory only (Claude Code) or API key (Codex); a custom rule becomes kind Other provider (Claude Code, OpenCode) or API key (Codex) with the rule's field, operator and text as the condition, where a missing operator is `startsWith`, or `contains` on `anywhere`.
- A setting AgentTacho cannot read (an unknown kind, a kind of another harness, an unreadable condition, `none` on OpenCode) gives the account Directory only (Claude Code), API key (Codex) or OpenCode Other provider without a condition, so it never counts more than before; the log says so, and Settings shows the choice to correct. A `condition` next to Directory only is ignored with a note. For a Codex account with an unreadable condition this means every API-key session counts for it until you set the condition again in Settings.

## Accounts without a limit

A token-based account with its own budget can leave the amount empty. It then has no limit: it counts its period (input, output, cache write and cache read tokens) and shows it in its dropdown section, but it has no percent, bar, thresholds, notifications or pace, and no menu bar entry. Use it for models that cost nothing, such as the open-weight models a company gateway offers for free, or for an API key billed per token without a monthly cap.

```json
{ "id": "acc-free", "type": "tokenBased", "icon": "solid:gift",
  "displayName": "Free models", "harness": "claudeCode",
  "sessionKind": "otherProvider",
  "condition": { "field": "model", "operator": "startsWith", "text": "gateway-a/" },
  "claudeCodeDirectory": "~/.claude-gateway",
  "budget": { "period": "monthly", "shownInBar": true, "thresholds": [80, 100] },
  "valueAs": "claude-opus-5-5" }
```

| Key | Type | Meaning |
|---|---|---|
| `budget.budgetUSD` | number | optional for an account's own budget; absent or `null` means no amount and no limit. When present it must be greater than 0. A budget group always needs it |
| `budget.period` | `"weekly"` or `"monthly"` | the window the account counts over, with or without an amount; absent means weekly |
| `budget.shownInBar`, `budget.thresholds` | | kept without an amount, without effect; they apply again once an amount is entered |
| `valueAs` | model id | optional; the model whose prices value the tokens of models without a price, on an account without an amount |
| `show` | `"automatic"`, `"percent"`, `"tokens"` or `"money"` | optional; what the headline of the account's dropdown section shows; absent means Automatic |

**What the section shows.** The models of an account without an amount are priced from the price table like any other record. Automatic picks the headline: the percent with an amount; without one, the real spend of the period ("$37", tooltip "$37.42 spent this month", with "spent this month" next to the reset time) as soon as one record has a price, and otherwise the token count ("48.2M", with "this month"). Details show the cost per model under a spend headline and tokens under a token headline. Under a spend headline, models without a price add the usual "incomplete, unpriced" note, unless a `valueAs` model values them.

**Price tokens as.** With `valueAs` (in Settings: **Price tokens as**), the section shows a line such as "≈ $412 at claude-opus-5-5 prices" next to the reset time: what the records of models without a price would have cost if they had used that model, priced with every rate it has in the price table (including the separate 5-minute and 1-hour cache write rates). Records that have a price are real spend and are never valued again. The amount is rounded to whole dollars, "≈ <$1" below one dollar and "≈ $0" when every record has a price. It is an estimate; nothing was spent, and it never counts toward a budget. The model is looked up like a record's model, so an id with an `@` suffix or a date suffix finds its price, and the value follows a price import or override at once. A `valueAs` model that has no price is still valid: the section then says "Price tokens as: <model id> has no price", and under a spend headline also notes the unpriced models. `valueAs` may stay on an account with an amount or in a group, where it has no effect.

**Show.** The `show` key (Settings: **Dropdown shows**) changes only the headline of the account's section, never the menu bar or a refresh. With an amount, Tokens shows the token count and Money the spend (in remaining mode what is left, "$63", or over, "−$12"), while the amount line, bar and pace stay as they are. Without an amount, Percent shows what Automatic would. The setting is kept while the account is in a group and applies again when it returns to its own budget. Automatic is not written to the file.

**Earlier files.** Files of earlier builds with `"noLimit": { "period": "monthly" }` still load: the account becomes an own budget without an amount with that period, thresholds 80% and 100% and shown in the menu bar, the log names each converted account once, and the next save writes `budget` without `budgetUSD`. `noLimit` is never written again. An account whose records all lack a price looks as before; one with priced records now shows its real spend and values only its unpriced records. The rules of the old form stay: the file is invalid when a token-based account has none or more than one of `groupId`, `budget` and `noLimit`, when `noLimit` holds `budgetUSD`, `thresholds` or `shownInBar`, or when the account has `shownInBar` or `thresholds` next to `noLimit`.

In Settings, choose **Own budget** in the account's Budget pop-up and leave **Amount** empty; it shows "No limit". Thresholds and "Show in menu bar" stay visible but disabled until a budget amount is entered. **Price tokens as** lists None, the built-in and manually priced models, and a **More** submenu with imported models; it is disabled while an amount is set. Entering an amount turns thresholds and the menu bar entry on with their kept settings, and the first refresh after that sets a baseline without notifying for thresholds already passed. Switching from a group to an own budget fills in the group's period, amount, thresholds and menu bar setting. A group the account leaves stays, also without members.

**Free and paid models of one gateway.** When one gateway directory serves free models and paid ones that count against a monthly allowance, add two Claude Code accounts of kind Other provider with the same Claude Code directory. One has an own budget without an amount and the condition Model starts with `gateway-a/`; the other has its own monthly budget, for example 300 USD, with the condition Model matches regex `^(claude|gpt)`. Each gateway record matches one of the two conditions and counts for that account only.

## Sessions from sandboxes

Agents that run in a sandbox, for example under OpenShell, keep their sessions inside the sandbox, where AgentTacho cannot see them, and a workspace tool may delete a sandbox when its workspace stops. AgentTacho never reaches into a sandbox: it runs no tool and pulls nothing. Instead, a deliverer (a workspace manager, a script or a later OpenShell export) copies the agent's session tree to a folder on this Mac:

- Claude Code: the `projects` tree, into `~/agent-sessions/<tool>/<sandbox>/claude/projects`
- Codex: the `sessions` tree, into `~/agent-sessions/<tool>/<sandbox>/codex/sessions`
- OpenCode: the `opencode.db` file, into `~/agent-sessions/<tool>/<sandbox>/opencode/opencode.db`

Then list `~/agent-sessions/openshell/*/claude` or `~/agent-sessions/openshell/*/codex` once under **Additional session directories** of the account the sessions belong to, or `~/agent-sessions/openshell/*/opencode` on General > Sources. Every sandbox folder that exists now or appears later counts from the next refresh on. Keep each copy at least as long as the budget period it should count for: a deleted folder stops counting at the next refresh. Credentials inside a sandbox are placeholders, so plan limits keep coming from the login on this Mac. A `projects`, `sessions` or `opencode.db` link inside a copied folder that leads outside it is not followed, and `*` never lists the home folder or `/` themselves, whatever their spelling.

## Settings tabs

The settings window has seven tabs:

- **General**: a sidebar with six pages. **Appearance**: whether usage reads as used or remaining (**Show usage as**) and the dropdown's theme (**Dropdown theme**: Auto, Dark or Light). **Weekly window**: which subscription account sets the weekly window, and the fallback weekday and hour (both apply to weekly budgets, of groups or of accounts with their own budget, and to Unassigned only). **Notifications**: whether a sign-in that stops working and a free limit reset about to expire are notified. **Refresh**: the refresh interval (default 5 minutes, minimum 1 minute) and **Adapt refresh**. **Sources**: extra OpenCode data directories, where `*` stands for any folder name at one level; Claude Code directories and Codex homes, with any additional session directories, are set per account in Accounts, and an account without one uses `~/.claude` or `~/.codex`. **Startup**: start at login and the automatic update check. With **Adapt refresh** on (the default), opening the menu refreshes values that are more than a minute old, plan limits are checked less often while no agent writes new usage, and the whole refresh slows down while you are away, in Low Power Mode or when the Mac runs hot. Plan limits are still checked at least every 30 minutes (or at the refresh interval, if that is longer), and hovering "Last refreshed" in the dropdown says why and when the next check is due. Turn it off to go back to the fixed interval.
- **Menu Bar**: the order of the bar entries, which the dropdown sections follow too, with a live preview of the bar. Drag a row, or select it and use Move Up and Move Down (Option-Command-Up and Option-Command-Down Arrow). A group's members are listed under it and move with it; they can be reordered only within their group. Each row has a "Show in bar" checkbox, the same setting as the toggle in the account or group editor; the row of an account without an amount reads "No limit" and its checkbox is disabled until an amount is entered. "Level color" (Text, Pill or Off) and "Mark levels with ⚠ / ‼" set how warning and over-limit levels look; with Off and no symbols, levels no longer appear in the bar. "Show ↗ or ↑ when an entry will run out before it resets" turns both markers on or off; the dropdown's bars and notes stay.
- **Accounts**: display name, icon, the **Claude Code directory** of a Claude subscription account, the **Codex home** of a Codex subscription account, **Additional session directories** below the main directory on every Claude subscription, Codex subscription and token-based Claude Code or Codex account, whether the account shows in the bar, notification thresholds (checked for every plan window) and live limits for Codex subscription accounts, an optional custom marker for telling apart two subscriptions of the same kind, and "Times" (Relative or Absolute) for how the account's section in the dropdown reads its reset and run-out times. A token-based account has a **Harness** (Claude Code, Codex or OpenCode) and a budget: either its own (period, an optional amount, whether it shows in the bar, Price tokens as, **Dropdown shows**, Times, notification thresholds; an empty amount means no limit, see [Accounts without a limit](#accounts-without-a-limit)) or a budget group. A group member can show its share of the group budget in the bar. Its **Usage source** section holds an optional Claude Code directory or Codex home whose sessions count for it (an OpenCode account points to General > Sources instead), and its **Which sessions count** section the **Sessions** pop-up with the kinds of its harness (a Codex account shows a sentence instead), the **Only when** checkbox and, when it is ticked, one **Condition** row with a field, an operator (starts with, contains, matches regex) and a text. What the kind counts, an invalid pattern, and the warnings when another account cannot be told apart from it or shares a Directory only account's directory appear below the controls. Changing the harness clears the directories, sets the kind to the harness's default and keeps the condition.
- **Groups**: name, icon, period (weekly or monthly) and budget, whether the group shows in the bar, notification thresholds, and Times (Relative or Absolute) for the group's section in the dropdown. Add creates a group called "Budget group" (weekly, 60 USD, shown in the bar, thresholds at 80% and 100%) that you then edit. Remove asks first; if the group still has accounts, you pick where they go: each to its own budget with the group's settings, or all into another group. Membership itself is set in each account's Budget picker.
- **Prices**: prices in USD per million tokens, with their source, your own overrides and extra models, and an Import menu (see [Prices](prices.md)).
- **Log**: the newest 500 lines of the diagnostic log, refreshed after every refresh, with buttons to reload it, show it in Finder or open it in Console. The log stays within 5 MB: at 2.5 MB it moves to `usage.log.1` and a new file starts.
- **About**: the running build (version and build number, the commit it was built from and build date), the update status with "Check for Updates…", what changed since the previous release with a link to the release notes, and links to the GitHub repository, the issue tracker and the [sponsor page](https://github.com/sponsors/rhuss). "Your credentials" opens a short summary of the credentials AgentTacho reads (details in [Security and privacy](../README.md#security-and-privacy)).

## Icons

Every account and group has one [Font Awesome Free](https://fontawesome.com) icon, chosen from a searchable picker. New entries start with a default: the Claude icon for subscriptions, the Google icon for token-based accounts of kind Vertex, the OpenAI icon for Codex API key and OpenCode OpenAI accounts and for Codex subscription accounts, the Claude icon for a Claude Code account of kind Directory only or Other provider, the code icon for OpenCode Other provider, and a wallet for groups. Several entries may share an icon; the dropdown and settings show each icon next to its name. Older configuration files with text labels still load: the labels are ignored and entries without an icon get the default.
