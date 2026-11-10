#!/bin/sh
# Rebuilds Sources/CatWM/Config/Script/sucrase.js, the type stripper the TypeScript config uses.
set -e
cd "$(dirname "$0")/.."
VERSION=3.35.1
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
OUT="$PWD/Sources/CatWM/Config/Script/sucrase.js"
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
