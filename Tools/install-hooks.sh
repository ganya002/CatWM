#!/bin/sh
set -e
cd "$(dirname "$0")/.."
hooks=$(git rev-parse --git-path hooks)
mkdir -p "$hooks"
dest="$hooks/pre-commit"
if [ -e "$dest" ] && ! grep -q 'Tools/check-style.sh' "$dest"; then
  echo "install-hooks: $dest exists and is not the style check. Left it in place." >&2
  exit 0
fi
cp .githooks/pre-commit "$dest"
chmod +x "$dest" .githooks/pre-commit
