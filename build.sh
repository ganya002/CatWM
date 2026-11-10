#!/bin/sh
set -e
cd "$(dirname "$0")"
if [ -n "${CATWM_INSTANCE+set}" ]; then
  case "$CATWM_INSTANCE" in
    "" | *[!a-z0-9-]*) BAD_INSTANCE=1 ;;
    *) [ ${#CATWM_INSTANCE} -le 24 ] || BAD_INSTANCE=1 ;;
  esac
  if [ -n "$BAD_INSTANCE" ]; then
    echo "build: CATWM_INSTANCE must be 1 to 24 characters of a-z, 0-9 and -" >&2
    exit 2
  fi
fi
CONFIG=release
REPLACE=
for ARG in "$@"; do
  case "$ARG" in
    --dev) CONFIG=debug ;;
    --replace) REPLACE=1 ;;
  esac
done
INSTANCES="$HOME/.config/catwm/instances"
DEFAULT_PIDS=
if [ -z "${CATWM_INSTANCE+set}" ]; then
  NAMED=" "
  for FILE in "$INSTANCES"/*/catwm.pid; do
    if [ -f "$FILE" ]; then NAMED="$NAMED$(tr -d ' \n' < "$FILE") "; fi
  done
  for PID in $(pgrep -x CatWM || true); do
    PARENT=$(ps -o ppid= -p "$PID" 2>/dev/null | tr -d ' ')
    case "$NAMED" in *" $PID "* | *" ${PARENT:-0} "*) ;; *) DEFAULT_PIDS="$DEFAULT_PIDS $PID" ;; esac
  done
  if [ -n "$DEFAULT_PIDS" ] && [ -z "$REPLACE" ]; then
    echo "build: CatWM is running (pid$DEFAULT_PIDS) and this build would stop it." >&2
    echo "build: pass --replace to stop it, or set CATWM_INSTANCE=<id> to build an instance next to it." >&2
    exit 3
  fi
fi
Tools/install-hooks.sh
Tools/check-style.sh
Tools/swiftlint.sh
if [ "$CONFIG" = "debug" ]; then
  swift build -c debug --build-system native
else
  swift build -c release
fi
".build/$CONFIG/CatWM" --write-schema
".build/$CONFIG/CatWM" --write-config-docs
python3 Tools/generate-clients.py
stop_catwm() {
  case "$(ps -o comm= -p "$1" 2>/dev/null)" in */CatWM) ;; *) return 0 ;; esac
  kill "$1" 2>/dev/null || return 0
  i=0
  while kill -0 "$1" 2>/dev/null && [ $i -lt 50 ]; do i=$((i + 1)); sleep 0.1; done
}
if [ -n "${CATWM_INSTANCE+set}" ]; then
  PID=$(cat "$INSTANCES/$CATWM_INSTANCE/catwm.pid" 2>/dev/null || true)
  if [ -n "$PID" ]; then stop_catwm "$PID"; fi
else
  for PID in $DEFAULT_PIDS; do kill "$PID" 2>/dev/null || true; done
  pkill -x Hyprthyst 2>/dev/null || true
fi
APP=build/CatWM.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp ".build/$CONFIG/CatWM" "$APP/Contents/MacOS/"
SDK_VERSION=$(xcrun --sdk macosx --show-sdk-version)
if [ -z "$SDK_VERSION" ]; then
  echo "build: cannot read the macOS SDK version; macOS would draw the app with the old pre-26 look" >&2
  exit 1
fi
xcrun vtool -set-build-version macos 14.0 "$SDK_VERSION" -replace \
  -output "$APP/Contents/MacOS/CatWM" "$APP/Contents/MacOS/CatWM"
STAMPED=$(xcrun vtool -show-build "$APP/Contents/MacOS/CatWM" | awk '$1 == "sdk" { print $2 }')
if [ "$STAMPED" != "$SDK_VERSION" ]; then
  echo "build: the app is stamped with SDK '$STAMPED', not $SDK_VERSION; macOS would draw it with the old pre-26 look" >&2
  exit 1
fi
cp Info.plist "$APP/Contents/"
PLIST="$APP/Contents/Info.plist"
BUILD=$(git rev-list --count HEAD)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"
if [ -n "$CATWM_CHANNEL" ]; then
  SHORT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SHORT-$CATWM_CHANNEL.$BUILD" "$PLIST"
  /usr/libexec/PlistBuddy -c "Add :CatWMUpdateChannel string $CATWM_CHANNEL" "$PLIST"
fi
cp -R Resources/Fonts "$APP/Contents/Resources/"
cp Resources/Icon/AppIcon.icns "$APP/Contents/Resources/"
cp -R ".build/$CONFIG/MacKeys_MacKeysCore.bundle" "$APP/Contents/Resources/"
cp -R ".build/$CONFIG/PermissionFlow_PermissionFlow.bundle" "$APP/Contents/Resources/"
cp -R ".build/$CONFIG/CatWM_CatWM.bundle" "$APP/Contents/Resources/"
cp -R Resources/AgentDocs "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/AgentDocs/python"
cp -R Clients/python/catwm "$APP/Contents/Resources/AgentDocs/python/"
find "$APP/Contents/Resources/AgentDocs/python" -name __pycache__ -prune -exec rm -rf {} +
cp Resources/ThirdPartyNotices.txt "$APP/Contents/Resources/"
SPARKLE=$(find .build/artifacts -type d -name Sparkle.framework -path '*macos-arm64_x86_64*' | head -1)
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --deep --sign - "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - -r='designated => identifier "local.catwm"' "$APP"
echo "Built $APP"
