#!/bin/bash
# Fails when a view outside Sources/ouch/UI/ hard-codes a style that has a Theme token.
# Use the tokens in UI/Theme.swift and the components in UI/Components.swift and UI/Popups.swift.
# For a deliberate one-off (real hardware colours, the intro timing), add `// style-ok` to the line.
set -euo pipefail
cd "$(dirname "$0")/.."

# Drawings of real Apple keyboards: their sizes and colours are measured, not design tokens.
allow='^Sources/ouch/(UI/|Keys/KeyHintKeyboard\.swift|Keys/MacKeyboard\.swift)'

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
