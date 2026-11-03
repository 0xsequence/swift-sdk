#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

run() {
    local label="$1"
    shift
    printf '\n==> %s\n' "$label"
    "$@"
}

version="$(sed -n 's/.*with version `\([^`]*\)`.*/\1/p' README.md | head -n 1)"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
    echo "README.md must give an exact SemVer version in the Swift Package Manager instructions; found '$version'." >&2
    exit 1
fi
if ! grep -Fq "from: \"$version\"" README.md; then
    echo "README.md must use version $version in the Package.swift example." >&2
    exit 1
fi

run "Build Swift package" swift build
run "Test Swift package" swift test
run "Test API generator" python3 scripts/test-generate-api.py
run \
    "Dump OMSWallet symbol graph" \
    swift package dump-symbol-graph --skip-synthesized-members --skip-inherited-docs
symbol_graph="$(scripts/omswallet-symbol-graph-path.sh)"
run \
    "Check public API" \
    env OMSWALLET_SYMBOL_GRAPH="$symbol_graph" scripts/check-public-api-does-not-expose-generated-waas.sh
run \
    "Check API.md" \
    env OMSWALLET_SYMBOL_GRAPH="$symbol_graph" scripts/generate-api.sh --check
run \
    "Build SDK demo" \
    xcodebuild \
        -quiet \
        -project Examples/sdk-demo/oms-wallet-demo.xcodeproj \
        -scheme oms-wallet-demo \
        -destination "generic/platform=iOS Simulator" \
        build
run \
    "Build Trails Actions demo" \
    xcodebuild \
        -quiet \
        -project Examples/trails-actions/trails-actions.xcodeproj \
        -scheme trails-actions \
        -destination "generic/platform=iOS Simulator" \
        build

run \
    "Build device tests" \
    xcodebuild \
        -quiet \
        -project Tests/DeviceTests/OMSWalletDeviceTests.xcodeproj \
        -scheme OMSWalletDeviceTests \
        -destination "generic/platform=iOS Simulator" \
        build-for-testing

printf '\nVerified Swift SDK %s.\n' "$version"
