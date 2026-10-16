#!/bin/sh
set -e
cd "$(dirname "$0")"
NOTES=
case "${1:-}" in -*) ;; *) NOTES=${1:-}; [ $# -gt 0 ] && shift ;; esac
./build.sh
if [ -n "$NOTES" ]; then
  exec amore release build/ouch.app --release-notes "$NOTES" "$@"
fi
exec amore release build/ouch.app "$@"
