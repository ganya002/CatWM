#!/bin/sh
set -e
cd "$(dirname "$0")/.."
if ! command -v swiftlint >/dev/null 2>&1; then
  echo "swiftlint: not installed, skipped. Install it with 'brew install swiftlint'." >&2
  exit 0
fi
clt=/Library/Developer/CommandLineTools
if [ -z "$TOOLCHAIN_DIR" ] && [ "$(xcode-select -p 2>/dev/null)" = "$clt" ]; then
  export TOOLCHAIN_DIR=$clt
fi
exec swiftlint --quiet "$@"
