#!/bin/sh
# Builds, then signs, notarizes and publishes through Amore. One-time: amore login && amore setup build/ouch.app
# Usage: ./release.sh "release notes" [extra amore flags, e.g. --channel beta | --critical | --phased-rollout | --draft]
set -e
cd "$(dirname "$0")"
NOTES=${1:-}
[ $# -gt 0 ] && shift
./build.sh
if [ -n "$NOTES" ]; then
  exec amore release build/ouch.app --release-notes "$NOTES" "$@"
fi
exec amore release build/ouch.app "$@"
