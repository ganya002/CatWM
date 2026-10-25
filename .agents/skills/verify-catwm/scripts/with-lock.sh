#!/bin/sh
# Run a command while this script holds the host lock. Only one agent on this Mac holds it.
# Use it for a test that needs global state: focus, Desktops or key presses.
# Usage: with-lock.sh <command> [args...]. LOCK_TIMEOUT (seconds, default 600) sets the longest wait.
LOCK="$HOME/Library/Caches/CatWM-verify/host.lock"
TIMEOUT=${LOCK_TIMEOUT:-600}
[ $# -ge 1 ] || { echo "usage: with-lock.sh <command> [args...]" >&2; exit 2; }
mkdir -p "$(dirname "$LOCK")"
START=$(date +%s)
WAITING=""
while ! mkdir "$LOCK" 2>/dev/null; do
  OWNER=$(cat "$LOCK/pid" 2>/dev/null)
  if [ -n "$OWNER" ] && ! kill -0 "$OWNER" 2>/dev/null; then
    echo "with-lock: pid $OWNER does not run. Removing its lock." >&2
    rm -rf "$LOCK"
    continue
  fi
  if [ -z "$WAITING" ]; then
    echo "with-lock: waiting for pid ${OWNER:-?}, which runs: $(cat "$LOCK/command" 2>/dev/null)" >&2
    WAITING=1
  fi
  if [ $(($(date +%s) - START)) -ge "$TIMEOUT" ]; then
    echo "with-lock: pid ${OWNER:-?} holds the lock after $TIMEOUT s. Ask the user before you remove $LOCK." >&2
    exit 75
  fi
  sleep 1
done
echo $$ > "$LOCK/pid"
echo "$*" > "$LOCK/command"
trap 'rm -rf "$LOCK"' EXIT
trap 'exit 130' INT TERM
"$@"
exit $?
