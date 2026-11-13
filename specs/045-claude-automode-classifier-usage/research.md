# Research: Claude Code Auto-mode Classifier Usage

## R1: Where the classifier step plugs in

- **Decision**: A separate `ClassifierLogIndex` called from `SessionLogSource.collect` after `LogIndex.update`, inside the same offloaded closure.
- **Rationale**: Decision logs are found from records, not from the directory scan, keyed by byte offset, not by message id, and attributed from spans, not rules. Folding them into `LogIndex` would touch its re-read rules (spec 035, 037, 038) for no gain. Running in the same offload keeps spec 039 FR-018 (actor never held).
- **Alternatives considered**: Feeding decision logs to `LogIndex` as extra `ScannedFile`s (rejected: its dedupe key and rule attribution are wrong for these rows); a separate `UsageSource` (rejected: it would need the session records of another source, and sources are independent).

## R2: Session spans need session id and cwd on records

- **Decision**: Add `sessionKey: String?`, `cwd: String?` and `origin: RecordOrigin` (`.session` default, `.classifier`) to `UsageRecord`, all defaulted in the initializers. `LogIndex` sets `sessionKey = raw.sessionId ?? file.canonicalPath` and `cwd = raw.cwd`.
- **Rationale**: `RawUsageRecord` already has both values, `UsageRecord` drops them. Keeping them on the record lets spans be rebuilt each refresh from `index.records` with no second data structure that could drift. Defaulted fields keep the nine existing construction sites compiling.
- **Memory**: Two more strings per record would cost roughly 100 bytes each on a month-long index. `LogIndex.readAndMerge` therefore reuses one `String` instance per distinct `sessionKey` and `cwd` value within a file's merge (a small dictionary per job), so records of one file share their storage (plan review decision 2026-11-13).
- **Alternatives considered**: Per-file span tables inside `FileIndexEntry` (rejected: duplicates state and must follow every re-read rule).

## R3: Model name normalization

- **Decision**: Strip one trailing bracketed suffix (`[...]`, such as `[1m]`) from `classifierModel` in the parser, before `PriceTable.canonicalModel`.
- **Rationale**: In the 2026-11-12 probe the session records say `rits/zai-org/glm-5-3`, the decision log `rits/zai-org/glm-5-3[1m]`. `canonicalModel` strips `@...` and date suffixes, not brackets. Changing `canonicalModel` globally would also change session records, which is out of scope.
- **Alternatives considered**: Changing `PriceTable.canonicalModel` (rejected: wider effect, other harnesses).

## R4: Probing directories without blocking

- **Decision**: `DecisionLogProbe` runs each directory's check (canonicalize, `lstat` of the log path) on a concurrent dispatch queue and waits on a `DispatchGroup` with a 2-second deadline for the whole batch, started together, so each directory gets 2 seconds. Unfinished checks are reported `.timedOut`; their paths stay in a lock-protected in-flight set until the thread returns; a later refresh reports `.busy` for them without starting another check. A timed-out directory is logged once, and again only after a check of it finished.
- **Rationale**: `stat` on a hung network mount cannot be cancelled; the in-flight set bounds stuck threads to one per directory (FR-012). Canonicalization resolves symlinks and touches the file system, so it belongs inside the check.
- **Alternatives considered**: Async/await with task cancellation (rejected: cancellation does not interrupt a blocking syscall); checking on the merge thread (rejected: blocks the refresh).
- **Implementation note (T024)**: Each check runs on its own `Thread` instead of a concurrent dispatch queue. A concurrent queue draws on the width-limited global pool: checks that hang there (and, in the test run, the many other parallel jobs) starved the remaining checks until they timed out as well. A dedicated thread per check cannot be starved; the in-flight set still bounds hung threads to one per directory.

## R5: Reading the file safely and incrementally

- **Where**: The read of new bytes runs inside the probe's timed check, right after the `lstat`, so nothing that touches a working directory runs on the refresh thread (plan review decision 2026-11-13). The probe receives a snapshot of the index's per-file state (`size`, `modificationDate`, `parsedOffset`, keyed by canonical log path) and returns the unread bytes; `ClassifierLogIndex` only parses and applies them. A read that does not finish in time makes the directory `.timedOut` like a hung `lstat`.
- **Decision**: Open with `O_RDONLY | O_NOFOLLOW | O_NONBLOCK`, `fstat` for regular file and size (as `RegularFile.read` does), seek to the parsed offset, read the rest. Size above 64 MB → skip and log once per file. Complete lines only; the offset advances to the end of the last complete line. File shorter than the parsed offset → read from 0 and drop old rows.
- **Rationale**: Same rules as `LogIndex` (FR-003), with the hostile-file guards of `RegularFile` (FR-001). The lstat in the probe already rejects symlinks; `O_NOFOLLOW` closes the race.
- **Alternatives considered**: Reusing `LogIndex.readUnreadBytes` (rejected: follows symlinks and opens FIFOs blocking).

## R6: Row identity

- **Decision**: A row's id is `"<canonical log path>#<byte offset of the line start>"`, which also becomes the record's `messageId`, with `requestId` empty.
- **Rationale**: FR-008a. The id is stable across incremental reads; identical lines at different offsets stay distinct; a replaced file starts from offset 0 and its old rows are dropped first.

## R7: Parsing only what is needed

- **Decision**: Decode a minimal `Decodable` struct with `ts` (`Double`, epoch ms), `classifierModel` (`String`) and the four counters (`Int?` read through a tolerant wrapper that distinguishes absent from invalid). Every other field is ignored by the decoder. A cheap byte pre-check for `"classifierModel"` skips decoding lines that cannot qualify.
- **Rationale**: FR-004, FR-015 (no tool name, decision or routing fields kept). Distinguishing "absent" from "invalid" separates "without usage" from "malformed" (FR-013).

## R8: Measuring SC-004

- **Decision**: A test builds 50 directories with 100 KB decision logs, runs the classifier step once (cold), then measures a second run with unchanged files and asserts under 50 ms; the scan bench is not extended.
- **Rationale**: The second run is the steady state the criterion describes (logs already read). The scan bench runs over real directories and is not part of `make test`.
