#!/bin/sh
# Replace the running CatWM with a dev build of this worktree.
# Records the CatWM that ran before, so cleanup.sh can start it again.
set -e
. "$(dirname "$0")/env.sh"

if [ -n "$OURS_PID" ] && kill -0 "$OURS_PID" 2>/dev/null; then
  echo "launch: a verify instance already runs (pid $OURS_PID). Run doctor.sh, or cleanup.sh first." >&2
  exit 1
fi
rm -f "$STATE"

PREV_PID=$(catwm_main_pids | head -1)
PREV_EXE=""
PREV_WS=""
if [ -n "$PREV_PID" ]; then
  PREV_EXE=$(pid_exe "$PREV_PID")
  [ -x "$PREV_EXE" ] && PREV_WS=$("$PREV_EXE" status --json 2>/dev/null | jq -r '.screens[0].workspace // empty')
  [ -n "$PREV_WS" ] || PREV_WS=$("$CLI" status --json 2>/dev/null | jq -r '.screens[0].workspace // empty')
fi
save_state PREV_EXE "$PREV_EXE"
save_state PREV_WS "${PREV_WS##*/}"
echo "launch: CatWM before this run: ${PREV_EXE:-none}"

# build.sh quits every running CatWM (pkill -x CatWM).
(cd "$ROOT" && ./build.sh --dev) > "$VERIFY_HOME/build.log" 2>&1 || {
  tail -30 "$VERIFY_HOME/build.log" >&2; echo "launch: build failed, full log: $VERIFY_HOME/build.log" >&2; exit 1; }

RUN="$VERIFY_HOME/runs/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$RUN"
save_state RUN "$RUN"
save_state LOG_OFFSET "$(wc -c < "$LOG" 2>/dev/null | tr -d ' ' || echo 0)"
git -C "$ROOT" rev-parse HEAD > "$RUN/commit.txt"
git -C "$ROOT" status --short >> "$RUN/commit.txt"

open -g "$APP" --args --verbose
i=0
while [ $i -lt 100 ]; do
  PID=$("$CLI" ping --json 2>/dev/null | jq -r '.pid // empty' || true)
  if [ -n "$PID" ] && [ "$(pid_exe "$PID")" = "$EXE" ]; then break; fi
  PID=""; i=$((i + 1)); sleep 0.2
done
[ -n "$PID" ] || { echo "launch: $EXE did not answer ping in 20 s. Read $LOG." >&2; exit 1; }
save_state OURS_PID "$PID"

i=0
while [ $i -lt 50 ]; do
  [ "$("$CLI" status --json | jq -r '.trusted and .running')" = "true" ] && break
  i=$((i + 1)); sleep 0.2
done
"$CLI" status --json > "$RUN/launch.status.json"
if [ "$(jq -r '.trusted and .running' "$RUN/launch.status.json")" != "true" ]; then
  echo "launch: CatWM runs (pid $PID) but is not trusted or not tiling. Accessibility is missing for this build." >&2
  echo "launch: ask the user to allow CatWM in System Settings > Privacy & Security > Accessibility. Then run doctor.sh." >&2
  exit 1
fi
# A new instance can show another workspace than the old one did. Put the user back where they were.
[ -n "$PREV_WS" ] && "$CLI" workspace "${PREV_WS##*/}" > /dev/null
echo "launch: ready. pid $PID, workspace ${PREV_WS##*/}, evidence folder $RUN"
