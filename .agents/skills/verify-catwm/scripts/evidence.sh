#!/bin/sh
# evidence.sh <label>: save the state, the tiling dump, the log since launch and a screenshot to the evidence folder.
set -e
. "$(dirname "$0")/env.sh"
[ -n "$1" ] || { echo "usage: evidence.sh <label>" >&2; exit 2; }
[ -n "$RUN" ] || { echo "evidence: no run. Run launch.sh first." >&2; exit 1; }
"$CLI" status --json > "$RUN/$1.status.json"
"$CLI" windows --json > "$RUN/$1.windows.json"
"$CLI" workspaces --json > "$RUN/$1.workspaces.json"
"$CLI" dump > "$RUN/$1.dump.txt"
tail -c +"$((${LOG_OFFSET:-0} + 1))" "$LOG" > "$RUN/catwm.log" 2>/dev/null || true
screencapture -x "$RUN/$1.png" || echo "evidence: screencapture failed (Screen Recording permission?)" >&2
echo "$RUN/$1.*"
