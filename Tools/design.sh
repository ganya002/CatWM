#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../design"
python3 build.py
echo "Open http://localhost:4173"
exec python3 -m http.server 4173
