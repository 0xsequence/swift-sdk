#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_directory="$(swift build --package-path "$ROOT_DIR" --show-bin-path)"
symbol_graph="$(dirname "$build_directory")/symbolgraph/OMSWallet.symbols.json"

if [[ ! -f "$symbol_graph" ]]; then
    echo "OMSWallet symbol graph was not generated at $symbol_graph." >&2
    exit 1
fi

printf '%s\n' "$symbol_graph"
