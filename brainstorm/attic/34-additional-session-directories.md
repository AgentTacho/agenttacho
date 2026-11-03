# Brainstorm: Additional Session Directories per Account

**Date:** 2026-10-22
**Status:** spec-created (specs/035-additional-session-directories)

## Problem Framing

Spec 034 gives every account exactly one agent directory (Claude Code directory or Codex home): its sessions are read there, and a subscription's login comes from it. Real setups already spread one account's sessions over several places. Tools such as review agents run `codex exec` with the default `~/.codex` while interactive work runs from a profile directory, and the walkthrough of spec 034 showed how easily one of them drops out of the count.

The coming OpenShell support makes this the normal case. OpenShell runs each harness in a sandbox whose home is `/sandbox` (`crates/openshell-sandbox/src/process.rs:198`) and keeps that storage per sandbox: a Podman volume inside the podman machine, a container layer, a MicroVM disk or a Kubernetes PVC (`docs/how-it-works/sandboxes/runtimes.mdx:365`). None of it is a host path AgentTacho could read. Host bind mounts exist but are off by default and discouraged. The supported way out is `openshell sandbox download` or `exec`. Credentials inside a sandbox are placeholders behind a provider proxy, so plan limits keep coming from the host login; sandboxes only add session usage. cc-deck destroys an OpenShell sandbox when its workspace stops (`cc-deck/internal/ws/openshell.go:568`), so its sessions are lost unless something copies them out first.

So one account needs one login directory plus any number of session locations, many of them created by other tools, one per sandbox.

## Approaches Considered

### A: Others deliver, AgentTacho reads a per-account list with wildcards
- Pros: AgentTacho stays read-only and tool-agnostic (constitution III); cc-deck, scripts or a later OpenShell export can all feed it; one wildcard entry covers every current and future sandbox folder.
- Cons: depends on a deliverer copying sessions out of sandboxes; until one exists, sandbox usage is invisible.

### B: AgentTacho pulls from OpenShell sandboxes
- Pros: works without cc-deck.
- Cons: AgentTacho starts running external tools, must know gateways and sandbox names, and grows its trust surface; sandboxes deleted before a refresh still lose their sessions.

### C: A fixed import folder per account
- Pros: nothing to configure in AgentTacho.
- Cons: deliverers must know AgentTacho's internal account identity; less transparent than a visible list.

### D: OTLP intake from OpenShell's planned observability relay (rfc-0012b)
- Pros: token usage straight from the gateway, no files.
- Cons: not available yet; a different data model than session logs. Noted as a possible later source.

## Decision

Approach A. Each account keeps its one main directory from spec 034 and gets an optional list of additional session directories with `*` wildcards; OpenCode's global list on the Sources page gets the same wildcard rule. Getting sessions out of sandboxes is the deliverer's job (cc-deck, scripts). Builds on spec 034, which lands first unchanged.

## Key Requirements

- **Additional session directories per account**: every Claude account (subscription, Vertex) and Codex account (subscription, OpenAI) has an optional list of additional session directories, edited in Settings > Accounts below the main directory, with add and remove. They are read for sessions only, never for a login, keychain item or `auth.json`.
- **Wildcards**: an entry may contain `*`, matching exactly one folder level (for example `~/agent-sessions/openshell/*/claude`). Matches are re-evaluated on every refresh, so new sandbox folders count without a Settings change.
- **Same attribution**: sessions from additional directories count by the existing rules (ChatGPT-plan sessions for the Codex subscription, API-key sessions for the OpenAI account, request ids and markers for Claude accounts). Listing a directory on an account does not force its sessions onto that account.
- **Read once**: a directory reached several ways (main directory, another entry, several wildcard matches, another account) is read once, by canonical path.
- **OpenCode**: the global OpenCode data directory list on General > Sources accepts the same `*` entries.
- **Invented examples**: captions and prompts use made-up paths (`~/agent-sessions/openshell/*/claude`, `~/.claude-lab`), no real tool paths.
- **Docs**: README (data sources, Security and privacy: what is read, read-only, no tool is run), `docs/configuration.md`; a short section on feeding sessions from sandboxes (copy the harness's `projects/` or `sessions/` tree, or `opencode.db`, into a host folder listed on the account).
- **Out of scope**: pulling from OpenShell or any remote host, OTLP intake, the export itself (a cc-deck idea: copy a workspace's session trees to a host folder before `ws stop` destroys the sandbox).

## Open Questions

- Wildcard limits: only `*` for one level, or also `**`? Maximum matches per entry before the scan is capped and logged?
- Do deleted or moved sandbox folders need any handling beyond disappearing from the next refresh (their usage then drops out of the week)?
- Should Settings show how many folders an entry currently matches?
- Configuration key name and shape for the per-account list.
- Recommended folder layout for deliverers, so cc-deck and others can agree on one convention.
- Whether the export idea goes to cc-deck's idea inbox now.
