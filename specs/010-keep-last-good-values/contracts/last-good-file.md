# Contract: last-good.json

The file AgentMeter writes to remember the last good plan limits across launches (spec 010 FR-013 to FR-018).

## Location and permissions

- Path: `~/Library/Application Support/agentmeter/last-good.json`
- Directory created with permissions 0700, file written with 0600 (owner read/write only).
- Written atomically (temporary file in the same directory, then rename); never appended.
- Written only by AgentMeter, after a collect whose saved map changed. Never read or written by any agent.

## Format (version 1)

```json
{
  "version": 1,
  "claude": {
    "<account id>": {
      "credentialDirectory": "/Users/me/.claude",
      "fetchedAt": "2026-10-15T09:12:03.120Z",
      "fiveHour": { "utilizationPercent": 41.0, "resetsAt": "2026-10-15T11:00:00.000Z" },
      "sevenDay": { "utilizationPercent": 63.5, "resetsAt": "2026-10-18T07:00:00.000Z" },
      "modelLimits": [
        { "modelName": "Fable", "utilizationPercent": 12.0, "resetsAt": "2026-10-18T07:00:00.000Z", "allowancePercentOfWeekly": 50 }
      ]
    }
  },
  "codex": {
    "<account id>": {
      "codexHome": "/Users/me/.codex",
      "observedAt": "2026-10-15T09:12:04.500Z",
      "planType": "plus",
      "windows": [
        { "lengthMinutes": 300, "usedPercent": 20.0, "resetsAt": "2026-10-15T12:00:00.000Z", "limitReached": false },
        { "lengthMinutes": 10080, "usedPercent": 55.0, "resetsAt": "2026-10-20T08:00:00.000Z", "limitReached": false }
      ]
    }
  }
}
```

- Dates: ISO 8601 with fractional seconds, UTC.
- `fiveHour`, `sevenDay` and `resetsAt` may be absent (window not reported or not started).
- `allowancePercentOfWeekly` and `planType` may be absent.
- Directories are stored canonical (expanded `~`, symlinks resolved), the form the sources compare against (FR-015).

## Never in the file

Access tokens, refresh tokens, ID tokens, ChatGPT account ids, email addresses, the Claude plan type, or any text from a usage service answer other than the numbers and model names above (FR-014, spec 001 FR-011a, spec 007 FR-018).

## Reading rules

- Missing file, unreadable file, invalid JSON, or `version` other than 1: ignored, one diagnostic log line per launch, rewritten after the next successful request (FR-018).
- An entry whose account id is not configured, or whose directory differs from the account's current canonical directory, is not shown and is dropped at the next write (FR-015).
- A Codex entry is ignored for an account with live limits off (FR-017).
