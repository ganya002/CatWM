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
".build/$CONFIG/CatWM" --write-schema
".build/$CONFIG/CatWM" --write-config-docs
python3 Tools/generate-clients.py
pkill -x CatWM 2>/dev/null || true
pkill -x Hyprthyst 2>/dev/null || true
APP=build/CatWM.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp ".build/$CONFIG/CatWM" "$APP/Contents/MacOS/"
xcrun vtool -set-build-version macos 14.0 "$(xcrun --show-sdk-version)" -replace \
  -output "$APP/Contents/MacOS/CatWM" "$APP/Contents/MacOS/CatWM"
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
