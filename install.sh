#!/bin/sh
# Builds the beta app and installs it to /Applications/Ouch.app, then opens it.
# Beta builds follow the beta update channel, so Sparkle keeps this copy current.
# Usage: ./install.sh [--stable]   (--stable builds without the beta channel marker)
set -e
cd "$(dirname "$0")"
[ "${1:-}" = "--stable" ] || export OUCH_CHANNEL=beta
./build.sh
DEST=/Applications/Ouch.app
rm -rf "$DEST"
ditto build/ouch.app "$DEST"
echo "Installed $DEST"
open "$DEST"
