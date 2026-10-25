#!/bin/sh
# Build this worktree, start it as a scoped instance for the given pids, run a command, then stop the instance.
# The instance is a child process of this script, so it gets the macOS permissions of this shell.
# Usage: run-scoped.sh [--no-build] <pid>[,<pid>...] <command> [args...]
. "$(dirname "$0")/env.sh"
BUILD=1
[ "$1" = "--no-build" ] && { BUILD=""; shift; }
[ $# -ge 2 ] || { echo "usage: run-scoped.sh [--no-build] <pid>[,<pid>...] <command> [args...]" >&2; exit 2; }
PIDS=$1
shift
# The instance gets fd 8, so the lock stays until this shell and the instance stop. The build and the command do not.
lock_instance run-scoped
RUNNING=$(cat "$PID_FILE" 2>/dev/null)
case "$(ps -o comm= -p "${RUNNING:-0}" 2>/dev/null)" in
  */CatWM)
    echo "run-scoped: instance $INSTANCE already runs (pid $RUNNING). Run cleanup.sh first, or set INSTANCE to another id." >&2
    exit 1 ;;
esac
if [ -n "$BUILD" ]; then
  (cd "$ROOT" && ./build.sh --dev) 8>&- > "$VERIFY_HOME/build.log" 2>&1 || {
    tail -30 "$VERIFY_HOME/build.log" >&2; echo "run-scoped: build failed, full log: $VERIFY_HOME/build.log" >&2; exit 1; }
fi

OURS=""
cleanup() {
  [ -n "$OURS" ] || return
  if [ "$(cat "$PID_FILE" 2>/dev/null)" = "$OURS" ]; then "$CLI" exit > /dev/null 2>&1; fi
  i=0
  while kill -0 "$OURS" 2>/dev/null && [ $i -lt 50 ]; do i=$((i + 1)); sleep 0.2; done
  kill -0 "$OURS" 2>/dev/null && kill "$OURS"
  echo "run-scoped: stopped instance $INSTANCE (pid $OURS)" >&2
}
trap cleanup EXIT
trap 'exit 130' INT TERM

CATWM_SCOPE="pids:$PIDS" "$EXE" --verbose > "$VERIFY_HOME/instance.out" 2>&1 &
OURS=$!
i=0
while [ "$("$CLI" ping --json 2>/dev/null | jq -r '.pid // empty')" != "$OURS" ]; do
  kill -0 "$OURS" 2>/dev/null && [ $i -lt 100 ] || {
    tail -3 "$VERIFY_HOME/instance.out" >&2
    echo "run-scoped: instance $INSTANCE did not answer ping. Read $LOG and $VERIFY_HOME/instance.out." >&2; exit 1; }
  i=$((i + 1)); sleep 0.2
done
if [ "$("$CLI" status --json | jq -r '.trusted')" != "true" ]; then
  echo "run-scoped: instance $INSTANCE has no Accessibility permission. Start this script from a trusted app." >&2
  exit 1
fi
echo "run-scoped: instance $INSTANCE (pid $OURS) manages pids $PIDS" >&2
"$@" 8>&-
exit $?
