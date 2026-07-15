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

if ! command -v pod >/dev/null 2>&1; then
    echo "CocoaPods is required to verify the release podspec." >&2
    exit 1
fi

version="$(pod ipc spec oms-wallet-swift-sdk.podspec | ruby -rjson -e 'print JSON.parse(STDIN.read).fetch("version")')"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
    echo "The podspec version must be an exact SemVer version; found $version." >&2
    exit 1
fi

if ! grep -Fq "version \`$version\`" README.md; then
    echo "README.md must use podspec version $version in the Swift Package Manager instructions." >&2
    exit 1
fi
if ! grep -Fq "pod 'oms-wallet-swift-sdk', '$version'" README.md; then
    echo "README.md must use podspec version $version in the CocoaPods instructions." >&2
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
    "Lint local CocoaPod" \
    pod lib lint oms-wallet-swift-sdk.podspec --swift-version=6.0 --platforms=ios,macos
run \
    "Build SDK demo" \
    xcodebuild \
        -quiet \
        -project Examples/sdk-demo/oms-wallet-demo.xcodeproj \
        -scheme oms-wallet-demo \
        -destination "generic/platform=iOS Simulator" \
        build \
        CODE_SIGNING_ALLOWED=NO
run \
    "Build Trails Actions demo" \
    xcodebuild \
        -quiet \
        -project Examples/trails-actions/trails-actions.xcodeproj \
        -scheme trails-actions \
        -destination "generic/platform=iOS Simulator" \
        build \
        CODE_SIGNING_ALLOWED=NO

printf '\nVerified Swift SDK %s.\n' "$version"
