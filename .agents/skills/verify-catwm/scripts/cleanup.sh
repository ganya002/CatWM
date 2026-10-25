#!/bin/sh
# Close the test windows and quit the verify instance. The user's CatWM is not touched.
# The evidence folder stays.
. "$(dirname "$0")/env.sh"
[ -f "$STATE" ] || { echo "cleanup: nothing to clean up"; exit 0; }
"$(dirname "$0")/desk.sh" stop
. "$STATE"
[ -n "$RUN" ] && tail -c +"$((${LOG_OFFSET:-0} + 1))" "$LOG" > "$RUN/catwm.log" 2>/dev/null

if [ -n "$OURS_PID" ] && [ "$(pid_exe "$OURS_PID")" = "$EXE" ]; then
  "$CLI" exit > /dev/null 2>&1 || kill "$OURS_PID"
  i=0
  while kill -0 "$OURS_PID" 2>/dev/null && [ $i -lt 50 ]; do i=$((i + 1)); sleep 0.2; done
  kill -0 "$OURS_PID" 2>/dev/null && kill "$OURS_PID"
  echo "cleanup: stopped instance $INSTANCE (pid $OURS_PID)"
fi
rm -f "$STATE"
[ -n "$RUN" ] && echo "cleanup: evidence kept in $RUN" && ls "$RUN"
