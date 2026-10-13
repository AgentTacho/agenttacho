# Contract: LiteLLM Price List Mapping

Source: `https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json`, fetched only when the user picks a provider import. GET, no credentials, ephemeral session without cache, 30 s total timeout (`timeoutIntervalForResource`), at most 20 MB, HTTP 200 required.

## Selection per import kind

Only object values whose `mode` is `chat` are considered, plus `responses` for the OpenAI kind.

| Kind | `litellm_provider` | Key transformation |
|---|---|---|
| `anthropic` | `anthropic` | none |
| `openai` | `openai`, `vertex_ai-openai_models` | strip a leading `vertex_ai/` |
| `gemini` | `gemini` | strip a leading `gemini/` |

Then `PriceTable.canonicalModel` removes `-YYYYMMDD` and `@YYYYMMDD` suffixes.

Skipped as malformed: a key (after prefix stripping) that contains whitespace or control characters, is longer than 200 characters, or starts with `=`, `+`, `-` or `@` (`PriceTable.isAcceptableImportedModelId`).

## Field mapping

All values are dollars per token in the source, converted to dollars per million tokens and rounded to 6 decimal places.

| Source field | Target | When missing |
|---|---|---|
| `input_cost_per_token` | `inputPerMTok` | entry skipped |
| `output_cost_per_token` | `outputPerMTok` | entry skipped |
| `cache_creation_input_token_cost` | `cacheWrite5mPerMTok` | input price |
| `cache_creation_input_token_cost_above_1hr` | `cacheWrite1hPerMTok` | input price |
| `cache_read_input_token_cost` | `cacheReadPerMTok` | input price |

A value that is not a number (string, null, object) counts as missing. Negative values cause the entry to be skipped.

## Merging variants

When several keys map to the same canonical id: if their prices are all equal, one entry results. Otherwise the undated key wins when present; without an undated key, the key with the latest date suffix wins (FR-011).

## Errors

| Situation | Error |
|---|---|
| Transport failure | `network(reason)` |
| No response within 30 s | `timeout` |
| Status other than 200 | `httpStatus(code)` |
| More than 20 MB | `tooLarge` |
| Body is not a JSON object | `notJSON` |
| No usable entry for the kind | `noUsableEntries(kind)` |
