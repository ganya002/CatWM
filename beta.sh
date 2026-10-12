#!/bin/sh
# Publishes a beta to Amore's "beta" channel for early-access users. Version and build number are
# stamped automatically (0.1-beta.<commit count>), so there's nothing to bump.
# Without a Developer ID certificate it ships an unsigned ZIP; testers then need to allow it once in
# System Settings → Privacy & Security → Open Anyway.
# Usage: ./beta.sh "release notes" [extra amore flags, e.g. --draft]
set -e
cd "$(dirname "$0")"
export OUCH_CHANNEL=beta
NOTES=${1:-}
[ $# -gt 0 ] && shift
if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  exec ./release.sh "$NOTES" "$@" --channel beta
fi
echo "No Developer ID certificate found: publishing an unsigned, un-notarized ZIP."
exec ./release.sh "$NOTES" "$@" --channel beta --no-dmg --skip-notarization
