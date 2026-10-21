#!/bin/sh
set -e
cd "$(dirname "$0")"
Tools/install-hooks.sh
Tools/check-style.sh
Tools/swiftlint.sh
CONFIG=release
if [ "$1" = "--dev" ]; then CONFIG=debug; fi
if [ "$CONFIG" = "debug" ]; then
  swift build -c debug --build-system native
else
  swift build -c release
fi
pkill -x ouch 2>/dev/null || true
pkill -x Hyprthyst 2>/dev/null || true
APP=build/ouch.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp ".build/$CONFIG/ouch" "$APP/Contents/MacOS/"
xcrun vtool -set-build-version macos 14.0 "$(xcrun --show-sdk-version)" -replace \
  -output "$APP/Contents/MacOS/ouch" "$APP/Contents/MacOS/ouch"
cp Info.plist "$APP/Contents/"
PLIST="$APP/Contents/Info.plist"
BUILD=$(git rev-list --count HEAD)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"
if [ -n "$OUCH_CHANNEL" ]; then
  SHORT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SHORT-$OUCH_CHANNEL.$BUILD" "$PLIST"
  /usr/libexec/PlistBuddy -c "Add :OuchUpdateChannel string $OUCH_CHANNEL" "$PLIST"
fi
cp -R Resources/Fonts "$APP/Contents/Resources/"
cp Resources/Icon/AppIcon.icns "$APP/Contents/Resources/"
cp -R ".build/$CONFIG/MacKeys_MacKeysCore.bundle" "$APP/Contents/Resources/"
cp -R ".build/$CONFIG/PermissionFlow_PermissionFlow.bundle" "$APP/Contents/Resources/"
cp -R Resources/AgentDocs "$APP/Contents/Resources/"
cp Resources/ThirdPartyNotices.txt "$APP/Contents/Resources/"
SPARKLE=$(find .build/artifacts -type d -name Sparkle.framework -path '*macos-arm64_x86_64*' | head -1)
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --deep --sign - "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - -r='designated => identifier "local.ouch"' "$APP"
echo "Built $APP"
