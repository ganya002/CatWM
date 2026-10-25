#!/bin/sh
# Read-only: is the instance $INSTANCE the dev build of this worktree, and is it usable?
. "$(dirname "$0")/env.sh"
fail=0
bad() { echo "doctor: FAIL $*"; fail=1; }

PIDS=$(instance_pid)
[ -n "$PIDS" ] || { echo "doctor: FAIL instance $INSTANCE does not run. Run launch.sh."; exit 1; }
echo "doctor: instance $INSTANCE, pid $PIDS: $(pid_exe "$PIDS")"

[ -x "$CLI" ] || { echo "doctor: FAIL $CLI is missing. Run launch.sh."; exit 1; }
PID=$("$CLI" ping --json 2>/dev/null | jq -r '.pid // empty')
[ -n "$PID" ] || { echo "doctor: FAIL the socket does not answer"; exit 1; }
[ "$PID" = "$PIDS" ] || bad "the socket answers from pid $PID, which is not the pid in $PID_FILE"
[ -z "$OURS_PID" ] || [ "$OURS_PID" = "$PID" ] || bad "launch.sh started pid $OURS_PID, but pid $PID answers"

BUILT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist" 2>/dev/null)
[ "$BUILT" = "$(git -C "$ROOT" rev-list --count HEAD)" ] || bad "build $BUILT is not HEAD ($(git -C "$ROOT" rev-list --count HEAD)). Run cleanup.sh, then launch.sh."
[ "$EXE" -nt "$ROOT/Sources" ] || echo "doctor: WARN a file in Sources/ may be newer than the build. Rebuild if you changed code."

"$CLI" status --json | jq -c '{trusted, running, tilingEnabled, keybindsActive, workspaces, mode, tiled, floating}'
"$CLI" status --json | jq -e '.trusted and .running and .tilingEnabled' > /dev/null || bad "not trusted, not running or tiling is off"
[ -z "$DESK_PID" ] || echo "doctor: test desk (TextEdit) pid $DESK_PID on workspace $SCRATCH_WS (alive: $(kill -0 "$DESK_PID" 2>/dev/null && echo yes || echo no))"
[ -z "$RUN" ] || echo "doctor: evidence folder $RUN"
[ $fail = 0 ] && echo "doctor: OK"
exit $fail
