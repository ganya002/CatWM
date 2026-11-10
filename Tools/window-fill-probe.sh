#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
PROBE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/catwm-fill-probe.XXXXXX")
trap 'rm -rf "$PROBE_DIR"' EXIT
swiftc -D CATWM_RESIZE_PROBE \
  Tools/WindowFillProbe.swift \
  Tools/WindowFillDemo.swift \
  Tools/WindowFillProbeChecks.swift \
  Tools/WindowFillProbeCapture.swift \
  Tools/WindowFillProbeFixture.swift \
  Sources/CatWM/Motion/Windows/WindowFillAppearance.swift \
  Sources/CatWM/Motion/Windows/WindowResizeFill.swift \
  Sources/CatWM/Motion/Windows/WindowSceneCapture.swift \
  Sources/CatWM/UI/Chrome/CatWMPanel.swift \
  Sources/CatWM/Tiling/Access/Screen.swift \
  Sources/CatWM/Tiling/Scan/WindowServerList.swift \
  Sources/CatWM/Tiling/Access/PrivateSymbols.swift \
  -o "$PROBE_DIR/probe"
if [ "${1:-}" = "--demo" ]; then
  "$PROBE_DIR/probe" "$@"
else
  .agents/skills/verify-catwm/scripts/with-lock.sh "$PROBE_DIR/probe" "$@"
fi
