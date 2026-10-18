#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
for file in "$ROOT"/*.sh "$ROOT"/startup/*.sh; do bash -n "$file"; done
node --check "$ROOT/contents/code/main.js"
python3 -m json.tool "$ROOT/metadata.json" >/dev/null
node "$ROOT/tests/test.js"
bash "$ROOT/tests/test-startup.sh"
printf '%s\n' 'PASS: Shell and KWin JS syntax, metadata, 9 fullscreen simulations, startup and installer integration.'
