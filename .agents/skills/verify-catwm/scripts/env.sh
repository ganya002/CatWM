# Shared paths for the verify-catwm scripts. Source it, do not run it.
# $0 is the script when a script sources this file. In an interactive shell, the git root of the current folder is used.
ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || git rev-parse --show-toplevel)
APP="$ROOT/build/CatWM.app"
EXE="$APP/Contents/MacOS/CatWM"
CLI="$EXE"
VERIFY_HOME="$HOME/Library/Caches/CatWM-verify"
STATE="$VERIFY_HOME/state.env"
LOG="$HOME/Library/Logs/CatWM.log"
mkdir -p "$VERIFY_HOME/runs"
[ -f "$STATE" ] && . "$STATE"

# The pid of each main CatWM process (not the desktop guard, not the practice windows).
catwm_main_pids() {
  ps -axo pid=,args= | awk '$2 ~ /\/Contents\/MacOS\/CatWM$/ && $3 != "--native-desktop-guard" && $3 != "practice" { print $1 }'
}

pid_exe() { ps -o args= -p "$1" 2>/dev/null | awk '{ print $1 }'; }

save_state() { # key value
  touch "$STATE"
  grep -v "^$1=" "$STATE" > "$STATE.tmp" || true
  printf "%s='%s'\n" "$1" "$2" >> "$STATE.tmp"
  mv "$STATE.tmp" "$STATE"
}
