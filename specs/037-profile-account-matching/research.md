# Research: Account Matching by Profile and Match Rules

## R1: Where the profile is in a session file

- **Decision**: Read `api-request-shape` lines and look for each configured Claude Code directory followed by `/projects/`.
- **Rationale**: Since Claude Code 2.1.300, these lines carry the request's system prompt, which names the auto-memory folder `<configuration directory>/projects/<project>/memory/`. On the maintainer's machine (2026-10-27) 39 of 42 main session files from three days named exactly one directory; the other 3 held no usage; all 156 subagent files had their own shape lines. Looking for configured paths instead of parsing the memory sentence survives rewording of the prompt as long as the path stays in it. Claude Code writes JSON without escaping `/`, so the path appears literally.
- **Alternatives considered**: parsing the memory paragraph by wording (breaks on rewording); `.claude.json` `lastSessionId` (only the last session per project); the file's scan directory (all profiles share one `projects` folder, and the scanner credits each file to the first target that reaches it, `LogDirectoryScanner.swift:100-132`); asking cc-deck to stop sharing `projects` (outside AgentTacho, loses cross-profile resume).

## R2: Cost and privacy of shape lines

- **Decision**: Recognize a shape line by a byte search for `"type":"api-request-shape"`, then byte-search the candidate strings; never JSON-decode it, never keep any of it but the matched canonical directory.
- **Rationale**: Shape lines hold tens of KB. The parser already rejects non-assistant lines by a byte search (`SessionRecordParser.swift:13-20`) and the reader already holds the unread region in memory (`LogIndex.swift:253`), so the added cost is a few `range(of:)` calls per shape line on lines that are read anyway. Keeping only the directory satisfies FR-004.
- **Alternatives considered**: decoding the line as JSON (slow, keeps prompt text in memory longer); one detection per file only (misses the rare file that names two profiles).

## R3: Incremental reads and re-attribution

- **Decision**: Store `profile` and `sawShapeLine` per file in `FileIndexEntry`. Evict and re-read a file when its first profile appears in a later read. Store the candidate key; when it changes, evict only files that saw a shape line but have no profile, and files whose profile left the candidates.
- **Rationale**: Records are merged by key and re-attributed when re-read (`LogIndex.swift:212-224`); raw lines are not cached, so a full re-read is the only way to re-attribute with custom "anywhere" rules. Spec 035 keeps additional directories out of the fingerprint so a new sandbox folder does not re-read every file (`Attribution.swift:133-139`); evicting only files whose result can change keeps that property. A file without shape lines can never gain a profile from a candidate change.
- **Alternatives considered**: putting the candidates into the fingerprint (re-reads everything on every wildcard change); caching every distinct path seen before `/projects/` (would need generic path extraction, which the spec avoids).

## R4: Rule step and precedence

- **Decision**: Keep today's precedence: custom rules (token `custom`, subscription `customMarker`) before presets and subscription rules, then the subscription directory tie-breaker. Token candidates are filtered to their harness. When the profile has several claimants at the deciding rank, only they enter the rule step.
- **Rationale**: Custom markers exist to tell apart two accounts of one kind (`Attribution.swift:59-61`). Filtering by harness implements FR-008 (one harness per account). Restricting to the claimants keeps a `~/.claude` session's Vertex record with the Vertex account on `~/.claude` instead of tying with a Vertex account of another profile (spec review finding 1).
- **Alternatives considered**: presets and custom rules at one level (reintroduces the ties markers exist to break).

## R5: Configuration shape and migration

- **Decision**: Token-based accounts store `harness` (now meaningful for them) and `matchRule` (`{"type":"preset","preset":...}`, `{"type":"custom","field":...,"text":...}` or `{"type":"none"}`). A token account without `matchRule` is migrated from `provider`. `Account.harness` becomes computed from the kind. `Provider` is removed.
- **Rationale**: `Account.harness` is written for every account but read nowhere and says `claudeCode` even for OpenAI accounts (`Configuration.swift:490`, `631`), so it cannot drive migration, but the key name fits the new meaning. The presence of `matchRule` cleanly separates old and new files. Backward compatibility is not a goal (maintainer, 2026-10-27), so no downgrade path is kept.
- **Alternatives considered**: keeping `provider` and adding `harness` (two overlapping choices again); a configuration version number (heavier than the key test).

## R6: Demo scenario

- **Decision**: Split `acc-vertex` into `acc-vertex` (Claude Code, Vertex preset, its 2 Claude Code usage entries) and `acc-vertex-opencode` (OpenCode, Vertex preset, the 5 OpenCode entries), both in `grp-company`; add a coverage check that every usage entry's harness equals its account's harness.
- **Rationale**: Demo usage bypasses the attributor (`DemoSources.swift:113-124`), so nothing fails today, but the scenario should show the model the app now enforces, and `shotBudgetHasAllHarnesses` (DefaultScenarioTests.swift:258) needs the company group to keep all three harnesses. The group gains one member line, so the `budget` and `harnesses` shots change.
- **Alternatives considered**: keeping the mixed account (contradicts FR-008 in the shots); moving OpenCode usage to `acc-side` (changes more sections).

## R7: Overlap warnings

- **Decision**: `Configuration.matchOverlaps(paths:)` groups token-based accounts by harness, rule and (Claude Code only) canonical main directory; every group of two or more yields a warning per member naming the others.
- **Rationale**: These are exactly the pairs neither step separates (FR-013). Pairs that differ only in directory get no warning, though records without a profile signal can still tie (spec edge case).
- **Alternatives considered**: also warning on directory-only overlaps (would warn on the normal non-cc-deck setup).
