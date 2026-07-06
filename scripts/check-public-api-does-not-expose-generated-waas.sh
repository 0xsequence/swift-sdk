#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift package dump-symbol-graph --skip-synthesized-members >/dev/null

symbol_graph="$(find .build -path '*/symbolgraph/OMSWallet.symbols.json' -type f | head -n 1)"
if [[ -z "$symbol_graph" ]]; then
    echo "OMSWallet symbol graph was not generated." >&2
    exit 1
fi

forbidden_symbol_pattern='OMSWalletWaas|WebRPC[A-Za-z0-9_]*|Waas(API|PublicAPI|Client|PublicClient)|SigningAlgorithm|IdentityType|(^|[^A-Za-z0-9_])AuthMode([^A-Za-z0-9_]|$)|StartEmailAuthRequest|CompleteEmailAuthRequest|FederateAccountRequest|ListWalletsRequest|CreateWalletRequest|SignMessageRequest|SignTypedDataRequest|ExecuteRequest|PrepareTransactionRequest|PrepareCallContractRequest|GetIdTokenRequest|RevokeAccessRequest|ListAccessRequest|IntentRegistrationRequest|GetTransactionStatusRequest'
matches="$(grep -Eoh "$forbidden_symbol_pattern" "$symbol_graph" | sort -u || true)"
if [[ -n "$matches" ]]; then
    echo "Generated WaaS symbols leaked into the public OMSWallet symbol graph:" >&2
    echo "$matches" >&2
    exit 1
fi

tmpdir="$(mktemp -d /tmp/oms-wallet-public-api.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

package_identity="$(basename "$ROOT_DIR")"
cat > "$tmpdir/Package.swift" <<EOF
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OMSWalletPublicApiCheck",
    platforms: [.macOS(.v12)],
    products: [.executable(name: "OMSWalletPublicApiCheck", targets: ["OMSWalletPublicApiCheck"])],
    dependencies: [
        .package(path: "$ROOT_DIR")
    ],
    targets: [
        .executableTarget(
            name: "OMSWalletPublicApiCheck",
            dependencies: [.product(name: "OMSWallet", package: "$package_identity")]
        )
    ]
)
EOF

mkdir -p "$tmpdir/Sources/OMSWalletPublicApiCheck"
cat > "$tmpdir/Sources/OMSWalletPublicApiCheck/main.swift" <<'EOF'
import OMSWallet

let _: JSONValue = .object(["ok": .bool(true)])
EOF

swift build --package-path "$tmpdir" >/dev/null

cat > "$tmpdir/Sources/OMSWalletPublicApiCheck/main.swift" <<'EOF'
import OMSWallet
import OMSWalletWaas

let _: JSONValue = .null
let _ = WEBRPC_HEADER_VALUE
let _ = WebRPCJSONValue.null
let _ = WaasClient.self
EOF

set +e
negative_output="$(swift build --package-path "$tmpdir" 2>&1)"
negative_status=$?
set -e

if [[ "$negative_status" -eq 0 ]]; then
    echo "External consumer unexpectedly accessed generated OMSWalletWaas symbols." >&2
    exit 1
fi

for expected in "WEBRPC_HEADER_VALUE" "WebRPCJSONValue" "WaasClient"; do
    if [[ "$negative_output" != *"cannot find '$expected' in scope"* ]]; then
        echo "External generated-symbol check failed for an unexpected reason." >&2
        echo "$negative_output" >&2
        exit 1
    fi
done

echo "Public OMSWallet API does not expose generated WaaS declarations."
