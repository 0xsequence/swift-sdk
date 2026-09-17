#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_directory="$(swift build --package-path "$ROOT_DIR" --show-bin-path)"
symbol_graph_name="OMSWallet.symbols.json"
candidate_directories=(
    "$(dirname "$build_directory")/symbolgraph"
    "$(dirname "$(dirname "$build_directory")")/symbolgraph"
)

for candidate_directory in "${candidate_directories[@]}"; do
    symbol_graph="$candidate_directory/$symbol_graph_name"
    if [[ -f "$symbol_graph" ]]; then
        printf '%s\n' "$symbol_graph"
        exit 0
    fi
done

echo "OMSWallet symbol graph was not generated in any expected location:" >&2
for candidate_directory in "${candidate_directories[@]}"; do
    printf '  %s/%s\n' "$candidate_directory" "$symbol_graph_name" >&2
done
exit 1
