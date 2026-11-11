#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
PROBE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/catwm-fill-probe.XXXXXX")
trap 'rm -rf "$PROBE_DIR"' EXIT
swiftc -package-name CatWM -D CATWM_RESIZE_PROBE \
  Tools/WindowFillProbe.swift \
  Tools/WindowFillDemo.swift \
  Tools/WindowFillProbeChecks.swift \
  Tools/WindowFillProbeCapture.swift \
  Tools/WindowFillProbeFixture.swift \
  Sources/CatWMKit/Motion/Windows/WindowFillAppearance.swift \
  Sources/CatWMKit/Motion/Windows/WindowResizeFill.swift \
  Sources/CatWMKit/Motion/Windows/WindowSceneCapture.swift \
  Sources/CatWMKit/Motion/Windows/WindowFillObservation.swift \
  Sources/CatWMKit/Chrome/CatWMPanel.swift \
  Sources/CatWMKit/Tiling/Access/Screen.swift \
  Sources/CatWMKit/Tiling/Scan/WindowServerList.swift \
  Sources/CatWMKit/Tiling/Access/PrivateSymbols.swift \
  -o "$PROBE_DIR/probe"
if [ "${1:-}" = "--demo" ]; then
  "$PROBE_DIR/probe" "$@"
else
  .agents/skills/verify-catwm/scripts/with-lock.sh "$PROBE_DIR/probe" "$@"
fi
