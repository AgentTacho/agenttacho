# Contract: Credential Notification Texts and Identifiers

User-visible contract for spec 014 FR-009 to FR-011. `<account>` is the account's `displayName`. `<cmd>` is the command for the provider:

| Provider | Default directory | `<cmd>` with default | `<cmd>` with other directory `<dir>` (as configured) |
|---|---|---|---|
| Claude | `~/.claude` (compared after expansion) | `claude` | `CLAUDE_CONFIG_DIR=<dir> claude` |
| Codex | `~/.codex` (compared after expansion) | `codex` | `CODEX_HOME=<dir> codex` |

| Kind | Title | Body |
|---|---|---|
| rejected | `<account>: sign-in rejected` | `Run <cmd> to sign in again.` |
| notSignedIn | `<account>: no sign-in found` | `Run <cmd> to sign in.` |
| expired | `<account>: sign-in expired` | `Run <cmd> to refresh it.` |
| notReadable (Codex only) | `<account>: sign-in not readable` | `Codex keeps its sign-in in the keychain, which AgentMeter cannot read.` |

Examples:

- `Claude (Work): sign-in rejected` / `Run CLAUDE_CONFIG_DIR=~/.claude-work claude to sign in again.`
- `Codex: sign-in expired` / `Run codex to refresh it.`

## Identifier

`credential-<accountId>`. One per account; posting again replaces, withdrawing removes both the delivered and a not yet shown request.

## Sound and presentation

Default sound, like threshold notifications. Shown as banner and in the list also while AgentMeter is active (dropdown open).

## Click

Opens the dropdown (status item button click); an open dropdown stays open; if the button cannot be found, AgentMeter is brought to the front. Applies to threshold notifications as well.

## Diagnostic log (source `notifications`)

`CredentialAlertEvent.logMessage` (UsageCore) returns the subject, `<accountId> <kind>` for deliver and suppressed and `<accountId>` for withdraw; the presenter adds the prefix for the outcome. The full lines are:

- `credential sent: <accountId> <kind>`
- `credential failed: <accountId> <kind>: <error>` (the notification center refused the request)
- `credential not sent (switch off): <accountId> <kind>` (a `.suppressed` event)
- `credential not sent (no app bundle | authorization denied): <accountId> <kind>`
- `credential withdrawn: <accountId>` (only for a notification this run posted successfully)
- `credential leftovers removed: <count>` (at launch)
- `credential dropped from queue: <accountId>` (a `.withdraw` event for an alert still queued)
- `notification click: opened dropdown | dropdown already open (<window class>) | activated app`

No line contains a token, an account identifier from a credential, or a credential file's contents.
