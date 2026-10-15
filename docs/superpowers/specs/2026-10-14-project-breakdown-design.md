# Project Breakdown: Top 5 Projects in the Details View

Date: 2026-10-14
Status: approved in brainstorming, awaiting spec review

## Intent

**What the user asked for:** the expanded Details section of the dropdown should also show the usage of the top 5 projects, switchable with the current view (per-model table).

**Why:** the per-model table shows which models consume a subscription or budget, but not which work does. Seeing the projects that use the most tokens or money answers "where did my week go" directly.

**Success criteria:**
- Every expanded Details section (subscription, budget group, token account, Unassigned) can switch between a Models view and a Projects view.
- The Projects view lists the 5 projects with the highest usage in the current window, an "Other (n)" row for the rest, and each row's share of the section total.
- Subdirectories and git worktrees of a repository count toward that repository.
- The chosen view is shared by all sections and survives closing the dropdown and restarting the app.

## Decisions

| Topic | Decision |
|---|---|
| Project identity | Git repository root of the record's `cwd`; worktrees resolve to their main repository; submodules are their own project; no repository means the `cwd` folder itself |
| Project name | Last path component of the root; on a name collision between different roots, `name (parent)` |
| Row content | Project, total tokens, cost (priced sections only), share of the section total |
| Ranking | Priced sections by cost, ties by tokens; token-only sections by total tokens |
| Rows | Top 5 plus "Other (n)" when there are more; no Total row |
| Switch | Segmented `Models \| Projects`, one shared choice stored in UserDefaults |
| Day row | Unchanged, shown in both views |

## Data Pipeline

### Parser

`SessionRecordParser` decodes the top-level `cwd` of an assistant line into a new field `RawUsageRecord.cwd: String?`. A missing or empty `cwd` stays nil. The pre-filter and the dedupe logic are unchanged; the last record per message id keeps its `cwd` like every other field.

### ProjectResolver

A new type in `Sources/UsageCore/Logs/ProjectResolver.swift`:

```swift
public struct Project: Equatable, Hashable, Sendable {
    public var rootPath: String   // identity
    public var name: String       // last path component of rootPath
}

public final class ProjectResolver {
    public init(fileManager: FileManager = .default)
    public func project(forCwd cwd: String?) -> Project?
}
```

- `nil` or empty `cwd` returns nil (shown as "Unknown").
- Results are cached per `cwd` string for the lifetime of the resolver, so each directory is examined once.
- When `cwd` no longer exists (for example a removed worktree under `<repo>/.claude/worktrees`), resolution starts at its nearest existing ancestor, so the directory still counts toward the repository around it.
- Resolution walks from there toward `/` and stops at the first entry named `.git`:
  - `.git` is a directory: the root is the directory containing it.
  - `.git` is a file whose `gitdir:` path contains `/worktrees/`: read `commondir` inside that gitdir (relative paths resolve against the gitdir); the root is the parent of the common directory when its name starts with `.` (`.git`, `.bare`), otherwise the common directory itself (a bare clone such as `project.git`). If `commondir` is missing or unreadable, the root is the directory containing the `.git` file.
  - any other `.git` file (submodule): the root is the directory containing the `.git` file.
- No `.git` found: the root is `cwd` itself (standardized path). This is a normal case and is not logged.
- `cwd` missing on disk with no repository around it, or any read error (unreadable `.git` file, malformed `gitdir:` line): the root is `cwd` itself, and the resolver records one note for that `cwd` (for example `project fallback for /path: directory not found`).
- The resolver never throws. `func drainNotes() -> [String]` returns and clears the pending notes; `SessionLogSource` writes them to the diagnostic log under its own source name after each index update, as one summary line (count plus the first 5 notes, then "and N more"), because deleted scratch directories are common. Because results are cached, each `cwd` produces at most one note per resolver lifetime.

### Record model and index

`UsageRecord` gets `project: Project?`, set from the raw record's `cwd` in `LogIndex` where raw records become `UsageRecord`s (next to attribution and pricing). `LogIndex` owns one `ProjectResolver`. Cached records keep their project across incremental updates; a full re-attribution (price table or attribution change) resolves again through the same cache.

`Aggregator` stays free of filesystem access; it only reads `record.project`.

## Aggregation

### Types (UsageSnapshot.swift)

```swift
public struct ProjectUsage: Equatable, Sendable, Identifiable {
    public var project: Project?     // nil = Unknown
    public var displayName: String   // name, or "name (parent)" on collision, or "Unknown"
    public var totalTokens: Int
    public var costUSD: Decimal?     // nil when unpriced or not applicable
    public var pricedCostUSD: Decimal // sum of the priced records; ranks and shares priced sections
    public var priced: Bool
    public var id: String            // rootPath, or "" for Unknown
}

public struct ProjectRanking: Equatable, Sendable {
    public var top: [ProjectRanked]          // at most `limit`
    public var other: OtherProjects?         // nil when nothing beyond the top
}

public struct ProjectRanked: Equatable, Sendable, Identifiable {
    public var usage: ProjectUsage
    public var sharePercent: Int?            // nil when the section total is 0
    public var id: String { usage.id }
}

public struct OtherProjects: Equatable, Sendable {
    public var count: Int
    public var totalTokens: Int
    public var costUSD: Decimal?
    public var sharePercent: Int?
}
```

`UsageBreakdown` gets `perProject: [ProjectUsage]` (all projects, already sorted by rank) and `func topProjects(limit: Int = 5, byCost: Bool) -> ProjectRanking`. A breakdown does not know whether it is priced, so the caller passes `byCost` (the view's `showsCost`).

### Rules

- `Aggregator.breakdown(of:priced:window:calendar:)` fills `perProject` in the same pass as `perModel`.
- Priced sections: a project's cost is the sum of its priced records; one unpriced record sets `priced = false` and `costUSD = nil`, like `ModelUsage`. Ranking uses the sum of the priced records only, so an unpriced project still ranks by what is known.
- Sort: priced sections by priced cost descending, then total tokens descending, then display name; token-only sections by total tokens descending, then display name.
- Collision naming: when two or more distinct roots in the same breakdown share a `name`, each gets `name (parent folder)`.
- Share: priced sections use cost, token-only sections use tokens. The top rows and "Other" get whole percents by largest-remainder rounding, so the column always adds up to exactly 100, also without an Other row. A section total of 0 sets every share to nil (column hidden).

## UI

In `Sources/AgentMeter/BreakdownView.swift`:

- A segmented `Picker` with `Models` and `Projects` at the top of the expanded content, `.controlSize(.mini)`, bound to `@AppStorage("detailsMode")` (default `Models`).
- Models mode shows today's table unchanged.
- Projects mode shows a `Grid` with the columns `Project`, `Tokens`, `Cost` (only when `showsCost`), `Share` (only when shares are non-nil). Project names truncate in the middle; `.help(rootPath)` shows the full path. The "Other (n)" row uses secondary style. "Unknown" has no hover path.
- The day row stays below the table in both modes.
- The (i) legend follows the mode. The Projects legend explains: project = git repository of the session's working directory, worktrees count toward their repository, folders outside a repository count on their own, "Unknown" = log lines without a working directory, share = part of the section total by cost (or tokens).
- No changes to `DropdownView`: its existing height tracking resizes the panel when the mode switch changes the content height.

## Error Handling

No new user-visible errors. Resolver failures fall back to the `cwd` folder and are written to the diagnostic log once per `cwd` (see ProjectResolver).

## Testing

Swift Testing, written test first.

- `SessionRecordParserTests`: `cwd` extracted when present; nil when absent or empty.
- `ProjectResolverTests` (temporary directories): plain repository; `cwd` in a subdirectory; worktree resolving to the main repository via `commondir`; worktree with missing `commondir`; submodule; directory without a repository; `cwd` that does not exist; nil `cwd`; cache hit does not touch the filesystem (counting `FileManager` stub or a removed directory after the first lookup).
- `AggregatorTests`: `perProject` totals; ranking by cost and by tokens; tie breaks; unpriced project; collision naming; `topProjects` with 0, 3, 5 and 8 projects (Other row count and totals, shares adding up to 100); zero total gives nil shares.
- `LogIndexTests`: records keep their project across an incremental update.

## Out of Scope

- Per-project model split or per-project day trend.
- Configurable top-N or project aliases.
- Project-level budgets or thresholds.
