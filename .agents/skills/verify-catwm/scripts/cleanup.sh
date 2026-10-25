#!/bin/sh
# Close the test windows, quit the verify instance and start the CatWM that ran before launch.sh.
# The evidence folder stays.
. "$(dirname "$0")/env.sh"
[ -f "$STATE" ] || { echo "cleanup: nothing to clean up"; exit 0; }
"$(dirname "$0")/desk.sh" stop
. "$STATE"
[ -n "$RUN" ] && tail -c +"$((${LOG_OFFSET:-0} + 1))" "$LOG" > "$RUN/catwm.log" 2>/dev/null

PREV_BUNDLE=""
[ -n "$PREV_EXE" ] && PREV_BUNDLE=${PREV_EXE%/Contents/MacOS/CatWM}
if [ -n "$PREV_EXE" ] && [ "$PREV_EXE" = "$EXE" ]; then
  echo "cleanup: the CatWM before this run was this build. It stays running."
elif [ -n "$PREV_EXE" ] && [ ! -x "$PREV_EXE" ]; then
  echo "cleanup: WARN the CatWM before this run ($PREV_BUNDLE) is gone from disk. This build stays running. Tell the user."
else
  if [ -n "$OURS_PID" ] && kill -0 "$OURS_PID" 2>/dev/null; then
    "$CLI" exit > /dev/null 2>&1 || kill "$OURS_PID"
    i=0
    while kill -0 "$OURS_PID" 2>/dev/null && [ $i -lt 50 ]; do i=$((i + 1)); sleep 0.2; done
    kill -0 "$OURS_PID" 2>/dev/null && kill "$OURS_PID"
  fi
  if [ -n "$PREV_BUNDLE" ]; then
    open -g "$PREV_BUNDLE" && echo "cleanup: started $PREV_BUNDLE again"
  else
    echo "cleanup: no CatWM ran before this run. None runs now."
  fi
fi
rm -f "$STATE"
[ -n "$RUN" ] && echo "cleanup: evidence kept in $RUN" && ls "$RUN"
