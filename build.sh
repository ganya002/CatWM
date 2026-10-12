#!/bin/sh
# Builds Hyprthyst.app into ./build. Run it, then grant Accessibility when prompted.
set -e
cd "$(dirname "$0")"
swift build -c release
pkill -x Hyprthyst 2>/dev/null || true  # `open` would just re-activate an old running copy
APP=build/Hyprthyst.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Hyprthyst "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
echo "Built $APP"
