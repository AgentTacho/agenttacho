#!/usr/bin/env bash
# Cross-check for SC-003: sums the cost of Vertex (req_vrtx_) assistant records
# inside a window with the built-in price table, independently of the app.
#
# Usage: scripts/sum-vertex.sh <window-start-iso> <window-end-iso> [claude-dir ...]
#   e.g. scripts/sum-vertex.sh 2026-10-09T07:00:00Z 2026-10-16T07:00:00Z ~/.claude
#
# Rules mirrored from UsageCore: only type=assistant records with message.usage,
# dedupe by message.id keeping the last record, cache writes from
# cache_creation.ephemeral_5m/1h with fallback to cache_creation_input_tokens,
# model ids normalized by stripping a trailing -YYYYMMDD or @YYYYMMDD.
# Prefix fallback matching is not mirrored; such models are listed as unpriced.
set -euo pipefail

# Whole seconds, UTC: a fractional part is dropped so the shell date parsing
# and jq's fromdateiso8601 both accept the value.
START="$(printf '%s' "${1:?window start (ISO 8601 UTC)}" | sed -E 's/\.[0-9]+Z$/Z/')"
END="$(printf '%s' "${2:?window end (ISO 8601 UTC)}" | sed -E 's/\.[0-9]+Z$/Z/')"
shift 2
DIRS=("$@")
if [ ${#DIRS[@]} -eq 0 ]; then DIRS=("$HOME/.claude"); fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRICES="$SCRIPT_DIR/../Sources/UsageCore/Resources/prices.json"

# Only files modified after the window start can hold records inside it.
# BSD find reads -newermt in local time without a zone, so use one day before
# the window start: a superset of files, which the timestamp filter narrows.
# Each file is deduped on its own, like the app does, then all are summed.
NEWER_THAN="$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" -v-1d "$START" "+%Y-%m-%d %H:%M:%S")"
collect() {
  for dir in "${DIRS[@]}"; do
    [ -d "$dir/projects" ] || continue
    /usr/bin/find "$dir/projects" -name '*.jsonl' -newermt "$NEWER_THAN" -print0 2>/dev/null
  done | xargs -0 -n 50 jq -R -c --arg start "$START" --arg end "$END" '
      def epoch: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
      ($start | epoch) as $s | ($end | epoch) as $e
      | (fromjson? // empty)
      | select(.type == "assistant" and (.message.usage? != null)
             and ((.requestId // "") | startswith("req_vrtx_"))
             and ((.timestamp // "") | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}(\\.[0-9]+)?Z$")))
      | (.timestamp | epoch) as $t
      | select($t >= $s and $t < $e)
      | { id: (.message.id // .requestId), file: input_filename, model: .message.model,
          input: (.message.usage.input_tokens // 0),
          output: (.message.usage.output_tokens // 0),
          cw5m: (if (.message.usage.cache_creation // null) != null
                    and ((.message.usage.cache_creation.ephemeral_5m_input_tokens != null)
                         or (.message.usage.cache_creation.ephemeral_1h_input_tokens != null))
                 then (.message.usage.cache_creation.ephemeral_5m_input_tokens // 0)
                 else (.message.usage.cache_creation_input_tokens // 0) end),
          cw1h: (if (.message.usage.cache_creation // null) != null
                 then (.message.usage.cache_creation.ephemeral_1h_input_tokens // 0) else 0 end),
          cr: (.message.usage.cache_read_input_tokens // 0) }
      | select(.input + .output + .cw5m + .cw1h + .cr > 0)' 2>/dev/null
}

collect | jq -s --slurpfile prices "$PRICES" --arg start "$START" --arg end "$END" '
  def canonical: sub("[-@][0-9]{8}$"; "");
  ($prices[0] | map({key: .model, value: .}) | from_entries) as $table
  | (group_by(.file + "|" + .id) | map(last)) as $records
  | ($records | map(.model | canonical) | unique) as $models
  | {
      records: ($records | length),
      window: {start: $start, end: $end},
      perModel: ($models | map(. as $m
        | ($records | map(select((.model | canonical) == $m))) as $rs
        | ($table[$m]) as $p
        | { model: $m,
            records: ($rs | length),
            input: ($rs | map(.input) | add),
            output: ($rs | map(.output) | add),
            cw5m: ($rs | map(.cw5m) | add),
            cw1h: ($rs | map(.cw1h) | add),
            cr: ($rs | map(.cr) | add),
            cost: (if $p == null then null else
              (($rs | map(.input) | add) * $p.inputPerMTok
               + ($rs | map(.output) | add) * $p.outputPerMTok
               + ($rs | map(.cw5m) | add) * $p.cacheWrite5mPerMTok
               + ($rs | map(.cw1h) | add) * $p.cacheWrite1hPerMTok
               + ($rs | map(.cr) | add) * $p.cacheReadPerMTok) / 1000000 end) })),
    }
  | . + { totalUSD: (.perModel | map(.cost // 0) | add),
          unpriced: (.perModel | map(select(.cost == null) | .model)) }'
