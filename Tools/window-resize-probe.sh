#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
PROBE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/catwm-resize-probe.XXXXXX")
trap 'rm -rf "$PROBE_DIR"' EXIT
swiftc -D CATWM_RESIZE_PROBE \
  Tools/WindowResizeProbe.swift Tools/ResizeProbeAnimation.swift \
  Sources/CatWM/Motion/Windows/WindowSceneCapture.swift \
  Sources/CatWM/Motion/Windows/WindowScenePlacement.swift \
  Sources/CatWM/Motion/Windows/WindowResizeScene.swift \
  Sources/CatWM/Motion/Windows/WindowFrameClock.swift \
  Sources/CatWM/UI/Chrome/CatWMPanel.swift \
  Sources/CatWM/Tiling/Access/Screen.swift \
  Sources/CatWM/Tiling/Scan/WindowServerList.swift \
  Sources/CatWM/Tiling/Access/PrivateSymbols.swift \
  -o "$PROBE_DIR/probe"
.agents/skills/verify-catwm/scripts/with-lock.sh "$PROBE_DIR/probe"
