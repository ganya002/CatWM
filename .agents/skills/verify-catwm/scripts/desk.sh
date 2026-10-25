#!/bin/sh
# desk.sh start [count]: go to an empty workspace and open test windows there (default 4).
# desk.sh stop:          close them and go back to the workspace you came from.
# The test windows are scratch files in a new TextEdit process (DESK_PID). A new process does not touch
# the user's own TextEdit. CatWM floats its own windows, so the onboarding practice windows cannot test tiling.
set -e
. "$(dirname "$0")/env.sh"

case "$1" in
start)
  if [ -n "$DESK_PID" ] && kill -0 "$DESK_PID" 2>/dev/null; then echo "desk: already open, pid $DESK_PID"; exit 0; fi
  COUNT=${2:-4}
  FOCUSED_WS=$("$CLI" status --json | jq -r '.screens[0].workspace')
  DISPLAY_ID=${FOCUSED_WS%/*}
  # Each workspace is a macOS Desktop. Use the number after the last one, so CatWM makes only one new Desktop.
  LAST=$("$CLI" workspaces --json | jq --arg d "$DISPLAY_ID/" '[.[] | select(.name | startswith($d)) | .name | ltrimstr($d) | tonumber? ] | max // 0')
  SCRATCH=$((LAST + 1))
  [ "$SCRATCH" -le 10 ] || { echo "desk: workspaces 1..10 are all in use" >&2; exit 1; }
  save_state ORIG_WS "${FOCUSED_WS##*/}"
  save_state SCRATCH_WS "$SCRATCH"
  "$CLI" workspace "$SCRATCH" > /dev/null

  DESK_DIR="$VERIFY_HOME/desk"
  rm -rf "$DESK_DIR"; mkdir -p "$DESK_DIR"
  FILES=""
  i=1
  while [ $i -le "$COUNT" ]; do
    echo "CatWM verify window $i" > "$DESK_DIR/verify-$i.txt"; FILES="$FILES $DESK_DIR/verify-$i.txt"; i=$((i + 1))
  done
  BEFORE=$(pgrep -x TextEdit || true)
  # shellcheck disable=SC2086
  open -n -a TextEdit $FILES --args -ApplePersistenceIgnoreState YES
  DESK=""
  i=0
  while [ -z "$DESK" ] && [ $i -lt 50 ]; do
    for p in $(pgrep -x TextEdit); do echo "$BEFORE" | grep -qx "$p" || DESK=$p; done
    i=$((i + 1)); sleep 0.2
  done
  [ -n "$DESK" ] || { echo "desk: TextEdit did not start" >&2; exit 1; }
  save_state DESK_PID "$DESK"
  i=0
  while [ $i -lt 50 ]; do
    [ "$("$CLI" windows --json | jq --argjson p "$DESK" '[.[] | select(.pid == $p and (.floating | not))] | length')" -ge "$COUNT" ] && break
    i=$((i + 1)); sleep 0.2
  done
  sleep 1  # let the open animations settle
  # TextEdit opens in the background of the CatWM focus model. Give a test window the focus.
  focused_test() { "$CLI" windows --json | jq --argjson p "$DESK" '[.[] | select(.pid == $p and .focused)] | length'; }
  [ "$(focused_test)" -ge 1 ] || { "$CLI" cyclenext > /dev/null; sleep 0.5; }
  [ "$(focused_test)" -ge 1 ] || echo "desk: WARN no test window has the focus. Run \$CLI cyclenext." >&2
  "$CLI" windows --json | jq -c --argjson p "$DESK" '.[] | select(.pid == $p) | {id, title, workspace, floating, focused, frame}'
  echo "desk: TextEdit pid $DESK, workspace $SCRATCH, came from workspace ${FOCUSED_WS##*/}"
  ;;
stop)
  if [ -n "$DESK_PID" ] && kill -0 "$DESK_PID" 2>/dev/null; then
    kill "$DESK_PID"
    i=0
    while kill -0 "$DESK_PID" 2>/dev/null && [ $i -lt 25 ]; do i=$((i + 1)); sleep 0.2; done
    kill -0 "$DESK_PID" 2>/dev/null && kill -9 "$DESK_PID"
  fi
  [ -n "$ORIG_WS" ] && "$CLI" workspace "$ORIG_WS" > /dev/null 2>&1 || true
  rm -rf "$VERIFY_HOME/desk"
  save_state DESK_PID ""
  echo "desk: closed, back on workspace ${ORIG_WS:-?}"
  ;;
*) echo "usage: desk.sh start [count] | stop" >&2; exit 2 ;;
esac
