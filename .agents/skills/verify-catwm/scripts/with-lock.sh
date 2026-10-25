#!/bin/sh
# Run a command while this script holds the host lock. Only one agent on this Mac holds it.
# Use it for a test that needs global state: focus, Desktops or key presses.
# Usage: with-lock.sh <command> [args...]. LOCK_TIMEOUT (seconds, default 600) sets the longest wait.
# The lock is a flock(2) on $LOCK (lockf). The kernel releases it when this shell stops, also on kill -9.
# So a lock of a stopped agent cannot stay, and no waiter removes a lock. Do not delete $LOCK.
LOCK="$HOME/Library/Caches/CatWM-verify/host.flock"
OWNER="$LOCK.owner"
TIMEOUT=${LOCK_TIMEOUT:-600}
[ $# -ge 1 ] || { echo "usage: with-lock.sh <command> [args...]" >&2; exit 2; }
mkdir -p "$(dirname "$LOCK")"
exec 9>>"$LOCK"
if ! lockf -s -t 0 9; then
  echo "with-lock: waiting for $(tr '\n' ' ' < "$OWNER" 2>/dev/null || echo "another agent")" >&2
  if ! lockf -s -t "$TIMEOUT" 9; then
    echo "with-lock: $(tr '\n' ' ' < "$OWNER" 2>/dev/null) holds the lock after $TIMEOUT s. Ask the user." >&2
    exit 75
  fi
fi
TOKEN="pid $$ since $(date +%s)"
printf '%s\nruns: %s\n' "$TOKEN" "$*" > "$OWNER"
trap '[ "$(head -1 "$OWNER" 2>/dev/null)" = "$TOKEN" ] && rm -f "$OWNER"' EXIT
trap 'exit 130' INT TERM
"$@" 9>&-
exit $?
