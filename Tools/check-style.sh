#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

allow='^Sources/ouch/(UI/|Keys/Keyboard/)'

patterns=(
    '\.system\(size:'
    'Color\(red:'
    'cornerRadius: *[0-9]'
    '\.(easeOut|easeInOut|easeIn|linear)\(duration: *[0-9]'
    '\.spring\('
    '\.shadow\('
)

hits=$(grep -rnE --include='*.swift' "$(IFS='|'; echo "${patterns[*]}")" Sources/ouch \
    | grep -vE "$allow" | grep -v '// style-ok' || true)

if [[ -n "$hits" ]]; then
    echo "$hits"
    echo
    echo "check-style: $(wc -l <<<"$hits" | tr -d ' ') hard-coded styles. Use a Theme token, or mark a deliberate one-off with // style-ok."
    exit 1
fi
echo "check-style: OK"
