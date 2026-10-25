# Shared paths for the verify-catwm scripts. Source it, do not run it.
# $0 is the script when a script sources this file. In an interactive shell, the git root of the current folder is used.
ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || git rev-parse --show-toplevel)
# Each worktree runs its own CatWM instance. It has its own socket, config, log and pid file.
INSTANCE=${INSTANCE:-verify-$(basename "$ROOT" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9-\n' '-' | cut -c1-17)}
export CATWM_INSTANCE="$INSTANCE"
APP="$ROOT/build/CatWM.app"
EXE="$APP/Contents/MacOS/CatWM"
CLI="$EXE"
VERIFY_HOME="$HOME/Library/Caches/CatWM-verify/$INSTANCE"
STATE="$VERIFY_HOME/state.env"
LOG="$HOME/Library/Logs/CatWM-$INSTANCE.log"
PID_FILE="$HOME/.config/catwm/instances/$INSTANCE/catwm.pid"
CONF="$HOME/.config/catwm/instances/$INSTANCE/catwm.conf"
mkdir -p "$VERIFY_HOME/runs"
[ -f "$STATE" ] && . "$STATE"

# The pid of the running main process of this instance, from its pid file.
instance_pid() {
  p=$(cat "$PID_FILE" 2>/dev/null) || return 0
  [ "$(pid_exe "$p")" = "$EXE" ] && echo "$p"
  return 0
}

# One run for each instance id: a second run would stop the instance of the first run (build.sh, or the pid file).
# Take the flock(2) of this instance on fd 8, or stop with exit code 1. The lock stays until this shell and each
# child that has fd 8 stop. Give a child that must not hold the lock `8>&-`.
lock_instance() { # name of the script, for the message
  exec 8>>"$VERIFY_HOME/run.flock"
  if ! lockf -s -t 0 8; then
    echo "$1: another run uses instance $INSTANCE ($(cat "$VERIFY_HOME/run.owner" 2>/dev/null))." \
      "Wait for it, or set INSTANCE to another id." >&2
    exit 1
  fi
  echo "pid $$ ($1) since $(date +%s)" > "$VERIFY_HOME/run.owner"
}

pid_exe() { ps -o args= -p "$1" 2>/dev/null | awk '{ print $1 }'; }

save_state() { # key value
  touch "$STATE"
  grep -v "^$1=" "$STATE" > "$STATE.tmp" || true
  printf "%s='%s'\n" "$1" "$2" >> "$STATE.tmp"
  mv "$STATE.tmp" "$STATE"
}
