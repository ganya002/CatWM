#!/bin/sh
set -e
cd "$(dirname "$0")"
[ "${1:-}" = "--stable" ] || export CATWM_CHANNEL=beta
./build.sh
DEST=/Applications/CatWM.app
rm -rf /Applications/CatWM.app "$DEST"
ditto build/CatWM.app "$DEST"
echo "Installed $DEST"
open "$DEST"
