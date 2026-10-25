#!/bin/sh
set -e
cd "$(dirname "$0")"
export CATWM_CHANNEL=beta
NOTES=
case "${1:-}" in -*) ;; *) NOTES=${1:-}; [ $# -gt 0 ] && shift ;; esac
if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  exec ./release.sh "$NOTES" "$@" --channel beta
fi
echo "No Developer ID certificate found: publishing an unsigned, un-notarized ZIP."
exec ./release.sh "$NOTES" "$@" --channel beta --no-dmg --skip-notarization
