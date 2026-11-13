# Contract: Claude Code Auto-mode decision log (input)

Claude Code writes this file when `AUTOMODE_DECISION_LOG=1` is set. It is an internal, undocumented diagnostic; this contract records what AgentTacho relies on, as observed in Claude Code 2.1.319.

**Location**: `<session working directory>/.automode_decisions.jsonl`

**Encoding**: UTF-8 JSON Lines, one object per line, appended; lines end with `\n`.

## Fields AgentTacho reads

| Field | JSON type | Required | Use |
|---|---|---|---|
| `ts` | number | yes | Decision time, epoch milliseconds |
| `classifierModel` | string | yes | Model of the classifier call; a trailing `[...]` is removed |
| `inputTokens` | integer >= 0 | no | Uncached input |
| `cacheReadInputTokens` | integer >= 0 | no | Cache read |
| `cacheCreationInputTokens` | integer >= 0 | no | Cache write, counted as 5-minute tier |
| `outputTokens` | integer >= 0 | no | Output |

At least one counter must be above zero for the row to count.

## Fields AgentTacho ignores

Everything else, for example `tool`, `decision`, `durationMs`, `costUSD`, `stage`, `originalDecisionReasonType`, `classifierSource`, `serverClassifierRole`, `serverClassifierOffReason`, `classifierSite`, `serverClassifierConnection`, `totalWaitMs`. They are not decoded and not kept.

## Sanitized example lines (fixtures)

```json
{"ts":1794505114575,"tool":"Bash","decision":"allowed","classifierModel":"rits/zai-org/glm-5-3[1m]","inputTokens":484,"outputTokens":23,"cacheReadInputTokens":34304,"cacheCreationInputTokens":0,"durationMs":1800,"costUSD":0,"stage":"fast"}
{"ts":1794505124339,"tool":"Bash","decision":"allowed","classifierModel":"rits/zai-org/glm-5-3[1m]","inputTokens":485,"outputTokens":24,"cacheReadInputTokens":34304,"cacheCreationInputTokens":0,"durationMs":1700,"costUSD":0,"stage":"fast"}
```

Together: 969 input, 68,608 cache read, 47 output, 69,624 tokens (the probe's totals). Per-row splits in fixtures are illustrative.
