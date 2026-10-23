#!/bin/sh
set -e
cd "$(dirname "$0")"
[ "${1:-}" = "--stable" ] || export OUCH_CHANNEL=beta
./build.sh
DEST=/Applications/CatWM.app
rm -rf /Applications/Ouch.app "$DEST"
ditto build/ouch.app "$DEST"
echo "Installed $DEST"
open "$DEST"
