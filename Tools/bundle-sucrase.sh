#!/bin/sh
# Rebuilds Sources/CatWMKit/Config/Script/Sucrase.swift, the type stripper the TypeScript config uses.
set -e
cd "$(dirname "$0")/.."
VERSION=3.35.1
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
ROOT=$PWD
OUT="$WORK/sucrase.js"
cd "$WORK"
npm init -y >/dev/null
npm install --silent "sucrase@$VERSION"
cat > entry.js <<'JS'
import { transform } from "sucrase";
globalThis.strip = (source, path) => transform(source, {
  transforms: ["typescript", "imports"], filePath: path, production: true, disableESTransforms: true
}).code;
JS
bun build entry.js --minify --format=iife --target=browser --outfile="$OUT"
python3 "$ROOT/Tools/embed-sucrase.py" "$OUT" "$ROOT/Sources/CatWMKit/Config/Script/Sucrase.swift"
