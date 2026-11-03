# Brainstorm: Account Matching by Profile and Match Rules

**Date:** 2026-10-27
**Status:** spec-created (specs/037-profile-account-matching)

## Problem Framing

cc-deck gives each Claude Code profile its own configuration directory (`~/.local/share/cc-deck/profiles/<name>/claude`), but every profile's `projects/` is a symlink to the same `~/.claude/projects`. The maintainer runs three such profiles: `private` (Claude Max subscription), `work` (Claude Code via Vertex) and `enmaas` (Claude Code against an intranet gateway with models such as `rits/zai-org/glm-5-3` and `rits/deepseek-ai/DeepSeek-V4.1-Flash-1017`).

Adding EnMaaS as a second token-based account with provider "Vertex" sent all Vertex usage to Unassigned (23.2M tokens on 2026-10-27), and Vertex dropped to 0%:

- A token-based account matches only through its provider's built-in rule (`Attribution.swift:35`, `req_vrtx_` for Claude Code). Its Claude Code directory plays no part in attribution (`Attribution.swift:120`, `directory: nil`).
- Two token-based accounts with the same rule both match every `req_vrtx_` record, and a tie between token-based accounts is Unassigned (`Attribution.swift:191`).
- EnMaaS records have none of the markers AgentTacho knows: no `requestId`, a message id `chatcmpl-…`, and a `rits/…` model. They match no account.
- Even the directory tie-breaker for subscriptions cannot help: `Attributor.canonical` resolves symlinks, so all three profiles look like `~/.claude/projects`.

The "Provider" picker adds to the confusion. For Claude Code, "Vertex" means only "the request id starts with `req_vrtx_`". The same choice also decides the harness behind the scenes (Vertex means Claude Code, OpenAI means Codex), the directory key in `config.json` and the default icon. The maintainer's first thought was to rename "Vertex" to "Claude", but the harness, not the provider, decides the log format.

## Research: Which Profile Wrote a Session

Checked on the maintainer's machine on 2026-10-27:

- Since Claude Code 2.1.300, session files contain `api-request-shape` lines with the full request shape, including the system prompt. With auto-memory on, that prompt names the memory directory: `…/cc-deck/profiles/<name>/claude/projects/<project>/memory/`. Everything before `/projects/` is the configuration directory the session ran under.
- Of 42 main session files from the last three days, 39 name exactly one profile, and the other 3 contain no usage. None names two profiles. All 156 subagent files have their own shape lines.
- Two sessions are odd: one `private` session also contains `req_vrtx_` records, and one `work` session contains `req_011` records. Each names only one profile. Profile switching or `--resume` from another profile might explain it, but that is not confirmed.
- One `enmaas` session made Vertex calls (`req_vrtx_`), so the EnMaaS profile does not always use the gateway.
- `.claude.json` is the only per-profile file with session ids, and it keeps only the last session per project, so it cannot separate history.
- Codex is not affected: the cc-deck profiles' `codex/sessions` are real directories, not shared.

## Approaches Considered

### A: Profile signal from the session file, match rules as fallback
- Pros: matches the maintainer's intent ("an account counts everything its profile did"). Works for every account kind, including two subscriptions that share `projects/`. Needs nothing from cc-deck.
- Cons: reads an internal, undocumented Claude Code format that may change in any release. Absent before 2.1.300, and probably absent with auto-memory off.

### B: Match rules on the record shape only (request id, message id, model)
- Pros: fields that are part of the record itself, so they are more stable. Simple to explain.
- Cons: counts by gateway, not by profile, which the maintainer explicitly rejected (a Vertex call inside an EnMaaS session would count toward Vertex). Cannot separate two subscriptions of the same kind.

### C: cc-deck stops sharing `projects/` between profiles
- Pros: the existing directory tie-breaker would work as is.
- Cons: outside AgentTacho. Loses resuming one profile's sessions from another. Does not help non-cc-deck setups.

## Decision

Approach A, with the rule editor of B as the fallback. An account counts everything its profile did. When a session file names no profile, the account's match rule decides. The "Provider" picker is replaced by a visible harness choice plus a match rule, which also settles the rename question.

## Key Requirements

- **Attribution order** for a Claude Code record:
  1. **Profile.** If the session file names a configuration directory, the record belongs to the account (of any kind) whose Claude Code directory, or one of its additional session directories (spec 035), is that directory. Compare paths after `~` expansion and standardization but without resolving symlinks, since resolving is what makes the profiles look the same. Main directories rank above additional ones, as in spec 035 FR-012: exactly one main claim wins, else exactly one additional claim, wildcard matches included.
  2. **Match rule.** If no profile is named, or the named directory belongs to no account or to several, the match rules decide, as today's built-in rules and markers do. A shared directory is the normal setup without cc-deck (one `~/.claude` for a subscription and Vertex, also when the directory field is empty and falls back to `~/.claude`), so it must fall through to the rules, never to Unassigned.
  3. **Unassigned** when neither step decides.
- **Profile beats rule.** A `req_vrtx_` record inside an EnMaaS session counts toward EnMaaS. A `req_vrtx_` record inside a subscription profile's session counts toward that subscription.
- **Exactly one harness per account.** Every token-based account shows its harness (Claude Code, Codex, OpenCode) as its own setting. It decides which logs are read, which directory key is stored and which presets and custom fields are offered, the jobs `Provider` does implicitly today. An account matches records of its own harness only.
- **Cross-harness spend through budget groups, not special rules.** Today a Vertex account also counts OpenCode `google-vertex` records, and an OpenAI account also counts OpenCode `openai` records. That special treatment goes away. Someone who uses Vertex from Claude Code and OpenCode creates two accounts (Claude Code with the Vertex preset, OpenCode with the Vertex preset) and puts both into one budget group, which already adds up its members against a shared budget. An OpenCode account has no directory of its own: OpenCode data directories stay global on General > Sources, and the profile step does not apply to OpenCode records.
- **Match rule per account**, a popup with:
  - **Presets** per harness, each matching records of that harness only, with the rule they check shown as read-only text: Claude Code "Vertex" (request id starts with `req_vrtx_`); OpenCode "Vertex" (`providerHint` is `google-vertex` or `google-vertex-anthropic`) and "OpenAI" (`providerHint` is `openai`); Codex "API key" (auth mode `apikey`).
  - **Custom**: a field plus a prefix, for example "Model starts with `rits/`". The fields are model, request id and message id.
  - Precedence stays as today (`Attribution.swift:59-61`): a custom rule replaces the account's preset and is more specific than any preset, so when a custom rule matches, only custom-rule accounts are considered. Telling apart two Vertex projects keeps working.
  - Subscription accounts keep their implicit rules (direct request id for Claude, ChatGPT plan for Codex) and get no rule picker. Their existing marker field stays as it is.
- **Overlap warnings in Settings**, inline on the account: two accounts whose rules (preset or custom) claim the same records and share a directory, so neither step can separate them. Two accounts sharing a directory but separated by their rules (the default `~/.claude` with a subscription and Vertex) get no warning. Today such overlaps silently go to Unassigned.
- **Diagnostics.** The diagnostic log notes per refresh how many Claude Code session files named a profile and how many fell back to the rules, so a change in Claude Code's format shows up quickly.
- **Migration, kept simple.** Backward compatibility is not a goal yet (maintainer, 2026-10-27). Existing `config.json` files load without user action: `provider: vertex` becomes harness Claude Code with the Vertex preset, `provider: openai` becomes harness Codex with the API key preset, and an existing `customMarker` becomes a custom rule with the field "anywhere in the line" (see "Calls made"). OpenCode usage that a Vertex or OpenAI account counted before stops counting there until the user adds an OpenCode account.
- **Release notes** say so: the "Provider" picker is replaced by harness and match rule, an account now counts one harness, OpenCode usage needs its own account (in a budget group for a shared budget), and cc-deck style profiles that share `projects/` are now told apart.
- **Docs and privacy.** AgentTacho now reads `api-request-shape` lines, which hold the system prompt and with it CLAUDE.md content. It takes only the configuration directory from them and keeps nothing else. The README's "Security and privacy" section, the website's privacy section and `docs/configuration.md` say so (constitution III).
- **Screenshots and website.** Settings > Accounts changes visibly (harness, match rule, warnings). The plan's "Screenshots and website" section needs the shots that change and the demo scenario (constitution V).
- **Out of scope:**
  - Prices for models without one, and token budgets: idea inbox `unpriced-model-accounts`.
  - Changes to cc-deck.
  - Profile detection for Codex and OpenCode (Codex profiles already have separate folders).

## Calls Made in This Brainstorm (not discussed, check while reading)

- One prefix per custom rule. More prefixes or other operators can come later if a gateway needs them.
- The old free-text marker survives only as the custom field "anywhere in the line", so migration loses nothing. It is offered last, with a caption that it also searches tool inputs and outputs.
- Profile detection looks for each configured account directory, followed by `/projects/`, in the shape lines, instead of parsing the wording of the memory paragraph. This survives rewording of the system prompt as long as the path is present.
- One profile per session file. If a file ever names two, the most recent shape line before a record decides.
- Subscription accounts get profile matching too, but no rule picker.

- A directory claimed by several accounts falls through to the rules (builder check, question 1).
- Spec 035's main-before-additional ranking carries over to the profile step (builder check, question 4).
- Custom rules keep today's precedence over presets, and subscriptions keep their marker field (builder check, question 3).
- `Account.harness` is stored for every account today but unused, and says `claudeCode` even for OpenAI accounts, so migration derives the harness from `provider`, not from the stored value.

## Open Questions

- Does the memory path also appear with auto-memory off, or under `CLAUDE_CONFIG_DIR` setups outside cc-deck? Is there a steadier field (for example a future `configDir` on the record) worth asking Claude Code for?
- What explains the two mixed sessions (`private` with `req_vrtx_`, `work` with `req_011`)?
- Cost of reading the shape lines, which carry the whole system prompt: is one hit per file enough, cached in the log index next to the attribution fingerprint?
- Wording and placement of the overlap warnings under the HIG (inline caption or a warning symbol in the sidebar row).
- Should the Unassigned section's info popover explain why records stayed unassigned (no profile, no rule, overlap)?
