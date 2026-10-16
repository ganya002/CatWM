#!/bin/sh
# Builds ouch.app into ./build. Run it, then grant Accessibility when prompted.
# Usage: ./build.sh [--dev]   (--dev makes an unoptimized debug build: a few seconds per rebuild,
# not about a minute. Do not ship it; release.sh and install.sh use the default release build.)
set -e
cd "$(dirname "$0")"
CONFIG=release
if [ "$1" = "--dev" ]; then CONFIG=debug; fi
swift build -c "$CONFIG"
pkill -x ouch 2>/dev/null || true  # `open` would just re-activate an old running copy
pkill -x Hyprthyst 2>/dev/null || true # the app's old name; two tilers would fight over the same windows
APP=build/ouch.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp ".build/$CONFIG/ouch" "$APP/Contents/MacOS/"
# SwiftPM records the deployment target (14.0) as the SDK version, so macOS would treat the app as
# pre-26 and keep the old look for its sidebar, toolbar and controls. Stamp the real SDK in.
xcrun vtool -set-build-version macos 14.0 "$(xcrun --show-sdk-version)" -replace \
  -output "$APP/Contents/MacOS/ouch" "$APP/Contents/MacOS/ouch"
cp Info.plist "$APP/Contents/"
# Build number is the commit count, so it rises on its own and Sparkle always sees new builds as newer.
# OUCH_CHANNEL=beta (set by beta.sh) also marks the build so fresh installs follow the beta channel.
PLIST="$APP/Contents/Info.plist"
BUILD=$(git rev-list --count HEAD)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"
if [ -n "$OUCH_CHANNEL" ]; then
  SHORT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SHORT-$OUCH_CHANNEL.$BUILD" "$PLIST"
  /usr/libexec/PlistBuddy -c "Add :OuchUpdateChannel string $OUCH_CHANNEL" "$PLIST"
fi
cp -R Resources/Fonts "$APP/Contents/Resources/"  # Chillax (ITF), registered at launch
cp Resources/Icon/AppIcon.icns "$APP/Contents/Resources/"
# SwiftPM resource bundles of the MacKeys SDK (key data and click sounds); Bundle.module finds them here.
cp -R ".build/$CONFIG/MacKeys_MacKeysCore.bundle" "$APP/Contents/Resources/"
cp -R Resources/AgentDocs "$APP/Contents/Resources/"  # docs for AI agents; `ouch docs` prints the path
cp Resources/ThirdPartyNotices.txt "$APP/Contents/Resources/"
# Sparkle ships as a prebuilt framework inside the SwiftPM artifact bundle.
SPARKLE=$(find .build/artifacts -type d -name Sparkle.framework -path '*macos-arm64_x86_64*' | head -1)
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
# Local ad-hoc signature, Sparkle's helpers first. No hardened runtime here: it would reject Sparkle
# (library validation needs matching team IDs). `amore release` re-signs with your Developer ID.
codesign --force --deep --sign - "$APP/Contents/Frameworks/Sparkle.framework"
# The designated requirement is pinned to the bundle ID: a plain ad-hoc signature is tied to the exact
# binary, so every rebuild looked like a new app to macOS and the Accessibility / Input Monitoring
# grants went stale (toggled on in System Settings, but rejected).
codesign --force --sign - -r='designated => identifier "local.ouch"' "$APP"
echo "Built $APP"
