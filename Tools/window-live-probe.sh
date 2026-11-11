#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
PROBE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/catwm-live-probe.XXXXXX")
trap 'rm -rf "$PROBE_DIR"' EXIT
swiftc -O -package-name CatWM -D CATWM_RESIZE_PROBE \
  Tools/WindowLiveProbe.swift Tools/ProbeLog.swift \
  Sources/CatWMKit/Motion/Windows/NativeBufferGeometry.swift \
  Sources/CatWMKit/Motion/Windows/NativeWindowStream.swift \
  Sources/CatWMKit/Motion/Windows/NativeWindowBufferLayer.swift \
  Sources/CatWMKit/Motion/Windows/WindowFrameClock.swift \
  Sources/CatWMKit/Motion/Engine/AnimationCurve.swift \
  Sources/CatWMKit/Motion/Windows/WindowSceneCapture.swift \
  Sources/CatWMKit/Chrome/CatWMPanel.swift \
  Sources/CatWMKit/Tiling/Access/Screen.swift \
  Sources/CatWMKit/Tiling/Scan/WindowServerList.swift \
  Sources/CatWMKit/Tiling/Access/PrivateSymbols.swift \
  -o "$PROBE_DIR/probe"
if [ "${1:-}" = "--fixture" ]; then
  "$PROBE_DIR/probe" --child --tile-fixture
else
  .agents/skills/verify-catwm/scripts/with-lock.sh "$PROBE_DIR/probe"
fi
