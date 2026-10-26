#!/bin/bash
# Builds "Minimal Cat.app" into MinimalCat/build/. Pass --release for an optimized build.
set -euo pipefail
cd "$(dirname "$0")"
config=debug
[[ "${1:-}" == "--release" ]] && config=release
swift build -c "$config" --product MinimalCat
app="build/Minimal Cat.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp ".build/$config/MinimalCat" "$app/Contents/MacOS/Minimal Cat"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.minimalcat</string>
    <key>CFBundleName</key><string>Minimal Cat</string>
    <key>CFBundleDisplayName</key><string>Minimal Cat</string>
    <key>CFBundleExecutable</key><string>Minimal Cat</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$app"
echo "$app"
