#!/bin/sh
# Installs the latest Ouch to /Applications. Pass --beta for the beta channel.
# Usage: curl -fsSL https://ouch.perwko.com/install.sh | sh
#        curl -fsSL https://ouch.perwko.com/install.sh | sh -s -- --beta
set -e
CHANNEL=
case "${1:-}" in
  --beta) CHANNEL=beta ;;
  "") ;;
  *) echo "Unknown option: $1 (use --beta)" >&2; exit 1 ;;
esac
FEED=https://api.amore.computer/v1/apps/local.ouch/appcast.xml
DEST=/Applications/Ouch.app

[ "$(uname)" = Darwin ] || { echo "Ouch needs macOS." >&2; exit 1; }

# The appcast lists the newest release first. Take the newest one on the chosen channel
# (no channel tag means stable).
URL=$(curl -fsSL "$FEED" | awk -v want="$CHANNEL" '
  /<item>/ { chan = ""; url = "" }
  /<sparkle:channel>/ { chan = $0; sub(/.*<sparkle:channel>/, "", chan); sub(/<.*/, "", chan) }
  /<enclosure/ { url = $0; sub(/.*url="/, "", url); sub(/".*/, "", url) }
  /<\/item>/ { if (chan == want && url != "") { print url; exit } }
')
if [ -z "$URL" ]; then
  echo "No ${CHANNEL:-stable} release found." >&2
  [ -n "$CHANNEL" ] || echo "Try again with: sh -s -- --beta" >&2
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
echo "Downloading $URL"
curl -fL --progress-bar -o "$TMP/Ouch.zip" "$URL"
ditto -x -k "$TMP/Ouch.zip" "$TMP/out"
APP=$(find "$TMP/out" -maxdepth 2 -name '*.app' | head -1)
[ -n "$APP" ] || { echo "No app found in the download." >&2; exit 1; }

pkill -x ouch 2>/dev/null || true
rm -rf "$DEST"
ditto "$APP" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
echo "Installed $DEST"
open "$DEST"
