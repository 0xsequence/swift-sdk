#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ "$#" -gt 1 || ("$#" -eq 1 && "$1" != "--check") ]]; then
    echo "Usage: scripts/generate-api.sh [--check]" >&2
    exit 2
fi

if [[ -n "${OMSWALLET_SYMBOL_GRAPH:-}" ]]; then
    symbol_graph="$OMSWALLET_SYMBOL_GRAPH"
else
    swift package dump-symbol-graph --skip-synthesized-members --skip-inherited-docs >/dev/null
    symbol_graph="$(scripts/omswallet-symbol-graph-path.sh)"
fi

if [[ -z "$symbol_graph" || ! -f "$symbol_graph" ]]; then
    echo "OMSWallet symbol graph was not generated." >&2
    exit 1
fi

args=(
    --symbol-graph "$symbol_graph"
    --config scripts/api-presentation.json
    --output API.md
)
if [[ "$#" -eq 1 ]]; then
    args+=(--check)
fi

python3 scripts/generate-api.py "${args[@]}"
