#!/bin/sh
# Builds Hyprthyst.app into ./build. Run it, then grant Accessibility when prompted.
set -e
cd "$(dirname "$0")"
swift build -c release
pkill -x Hyprthyst 2>/dev/null || true  # `open` would just re-activate an old running copy
APP=build/Hyprthyst.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks"
cp .build/release/Hyprthyst "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
# Sparkle ships as a prebuilt framework inside the SwiftPM artifact bundle.
SPARKLE=$(find .build/artifacts -type d -name Sparkle.framework -path '*macos-arm64_x86_64*' | head -1)
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
# Local ad-hoc signature, Sparkle's helpers first. No hardened runtime here: it would reject Sparkle
# (library validation needs matching team IDs). `amore release` re-signs with your Developer ID.
codesign --force --deep --sign - "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - "$APP"
echo "Built $APP"
