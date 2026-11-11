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
# Sucrase's start-up work runs on every config load, so trim it. A pattern that stops matching fails the build
# instead of leaving the slow code in.
# - A 65,536-step loop fills a table, and JavaScriptCore compiles a 9,000-number array literal one element at a time.
# - The option checker (ts-interface-checker) builds its checkers at import and walks the options on each call,
#   and CatWM's options are constants.
cat > startup.js <<'JS'
import { readFileSync, writeFileSync } from "node:fs";
import { READ_WORD_TREE } from "./node_modules/sucrase/dist/esm/parser/tokenizer/readWordTree";

const dist = "node_modules/sucrase/dist/esm";
function patch(file, from, to) {
  const text = readFileSync(`${dist}/${file}`, "utf8");
  const next = text.replace(from, to);
  if (next === text) throw new Error(`Sucrase ${file} changed, so its start-up patch no longer applies`);
  writeFileSync(`${dist}/${file}`, next);
}

patch("parser/util/identifier.js", /for \(let i = 128; i < 65536; i\+\+\) \{\n  IS_IDENTIFIER_CHAR\[i\] = 1;\n\}/,
  "IS_IDENTIFIER_CHAR.fill(1, 128);");
patch("parser/tokenizer/readWordTree.js", /new Int32Array\(\[[^\]]*\]\)/,
  `new Int32Array(JSON.parse(${JSON.stringify(JSON.stringify([...READ_WORD_TREE]))}))`);
patch("Options.js", /import \{createCheckers\}[^]*?\n\}\n/, "export function validateOptions() {}\n");
JS
bun startup.js
cat > entry.js <<'JS'
import { transform } from "sucrase";
globalThis.strip = (source, path) => transform(source, {
  transforms: ["typescript", "imports"], filePath: path, production: true, disableESTransforms: true
}).code;
JS
bun build entry.js --minify --format=iife --target=browser --outfile="$OUT"
python3 "$ROOT/Tools/embed-sucrase.py" "$OUT" "$ROOT/Sources/CatWMKit/Config/Script/Sucrase.swift"
