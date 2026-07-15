#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

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

public_api_baseline="$ROOT_DIR/scripts/public-api-baseline.txt"
public_api_actual="$(mktemp /tmp/oms-wallet-public-api-baseline.XXXXXX)"
jq -r '
    (.symbols | map({ key: .identifier.precise, value: (.pathComponents | join(".")) }) | from_entries) as $names
    | (
        [.symbols[]
            | select(.accessLevel == "public")
            | "symbol\t\(.kind.identifier)\t\(.pathComponents | join("."))\t\([.declarationFragments[].spelling] | join(""))"
        ]
        + [.relationships[]
            | select(.kind == "conformsTo")
            | select(.targetFallback != "Swift.SendableMetatype")
            | select($names[.source] != null)
            | "conformance\t\($names[.source])\t\(.targetFallback // .target)"
        ]
    )[]
' "$symbol_graph" | LC_ALL=C sort -u > "$public_api_actual"

if [[ "${UPDATE_PUBLIC_API_BASELINE:-0}" == "1" ]]; then
    cp "$public_api_actual" "$public_api_baseline"
elif ! diff -u "$public_api_baseline" "$public_api_actual"; then
    echo "Public OMSWallet API differs from scripts/public-api-baseline.txt." >&2
    echo "Review the diff, then regenerate intentionally with:" >&2
    echo "UPDATE_PUBLIC_API_BASELINE=1 scripts/check-public-api-does-not-expose-generated-waas.sh" >&2
    exit 1
fi

forbidden_symbol_pattern='WaasGenerated|OMSWalletWaas|WebRPC[A-Za-z0-9_]*|Waas(API|PublicAPI|Client|PublicClient)|SigningAlgorithm|IdentityType|(^|[^A-Za-z0-9_])AuthMode([^A-Za-z0-9_]|$)|StartEmailAuthRequest|CompleteEmailAuthRequest|FederateAccountRequest|ListWalletsRequest|CreateWalletRequest|SignMessageRequest|SignTypedDataRequest|ExecuteRequest|PrepareTransactionRequest|PrepareCallContractRequest|GetIdTokenRequest|RevokeAccessRequest|ListAccessRequest|IntentRegistrationRequest|GetTransactionStatusRequest'
matches="$(grep -Eoh "$forbidden_symbol_pattern" "$symbol_graph" | sort -u || true)"
if [[ -n "$matches" ]]; then
    echo "Generated WaaS symbols leaked into the public OMSWallet symbol graph:" >&2
    echo "$matches" >&2
    exit 1
fi

tmpdir="$(mktemp -d /tmp/oms-wallet-public-api.XXXXXX)"
trap 'rm -rf "$tmpdir" "$public_api_actual"' EXIT

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

func checkPublicAPI(omsWallet: OMSWallet) async throws {
    let customProvider = CustomOIDCProviderConfiguration(
        issuer: "https://issuer.example",
        clientID: "client-id",
        authorizationURL: "https://issuer.example/authorize",
        providerRedirectURI: "example-app://auth/callback"
    )
    let _: StartOIDCRedirectAuthResult = try await omsWallet.wallet.startOIDCRedirectAuth(
        provider: customProvider
    )
    let _: StartOIDCRedirectAuthResult = try await omsWallet.wallet.startOIDCRedirectAuth(
        provider: OMSRelayOIDCProviders.google,
        omsRelayReturnURI: "example-app://auth/callback"
    )
    let _: OIDCRedirectAuthResult = try await omsWallet.wallet.handleOIDCRedirectCallback(nil)
    let _: TransactionStatusResolution = .notRequested
    let _: any Sendable = omsWallet
    let _: any Sendable = omsWallet.indexer
    _ = omsWallet.wallet.addSessionExpiredObserver { _ in }
    let _: String = try await omsWallet.wallet.getIdToken()
}
EOF

swift build --package-path "$tmpdir" >/dev/null

cat > "$tmpdir/Sources/OMSWalletPublicApiCheck/main.swift" <<'EOF'
import OMSWallet

let _: JSONValue = .null
let _ = WaasGenerated.WEBRPC_HEADER_VALUE
let _ = WaasGenerated.WebRPCJSONValue.null
let _ = WaasGenerated.WaasClient.self
EOF

set +e
negative_output="$(swift build --package-path "$tmpdir" 2>&1)"
negative_status=$?
set -e

if [[ "$negative_status" -eq 0 ]]; then
    echo "External consumer unexpectedly accessed generated WaaS symbols." >&2
    exit 1
fi

for expected in "WaasGenerated"; do
    if [[ "$negative_output" != *"cannot find '$expected' in scope"* ]]; then
        echo "External generated-symbol check failed for an unexpected reason." >&2
        echo "$negative_output" >&2
        exit 1
    fi
done

expect_external_build_failure() {
    local label="$1"
    local expected="$2"
    local source="$3"

    printf '%s\n' "$source" > "$tmpdir/Sources/OMSWalletPublicApiCheck/main.swift"
    set +e
    local output
    output="$(swift build --package-path "$tmpdir" 2>&1)"
    local status=$?
    set -e

    if [[ "$status" -eq 0 ]]; then
        echo "External public API check unexpectedly compiled: $label" >&2
        exit 1
    fi
    if [[ "$output" != *"$expected"* ]]; then
        echo "External public API check failed for an unexpected reason: $label" >&2
        echo "$output" >&2
        exit 1
    fi
}

expect_external_build_failure \
    "custom OIDC provider with OMS relay return URI" \
    "OMSRelayOIDCProvider" \
    $'import OMSWallet\n\nfunc invalid(omsWallet: OMSWallet, provider: CustomOIDCProviderConfiguration) async throws {\n    _ = try await omsWallet.wallet.startOIDCRedirectAuth(provider: provider, omsRelayReturnURI: "example-app://auth/callback")\n}'

expect_external_build_failure \
    "OMS relay provider without OMS relay return URI" \
    "CustomOIDCProviderConfiguration" \
    $'import OMSWallet\n\nfunc invalid(omsWallet: OMSWallet) async throws {\n    _ = try await omsWallet.wallet.startOIDCRedirectAuth(provider: OMSRelayOIDCProviders.google)\n}'

expect_external_build_failure \
    "OMS relay provider authorization parameter override" \
    "extra argument 'authorizeParams'" \
    $'import OMSWallet\n\nfunc invalid(omsWallet: OMSWallet) async throws {\n    _ = try await omsWallet.wallet.startOIDCRedirectAuth(provider: OMSRelayOIDCProviders.google, omsRelayReturnURI: "example-app://auth/callback", authorizeParams: ["prompt": "select_account"])\n}'

expect_external_build_failure \
    "direct WalletClient construction" \
    "WalletClient" \
    $'import OMSWallet\n\nlet _ = try WalletClient(publishableKey: "pk_sdbx_project_key")'

expect_external_build_failure \
    "public OMSWalletEnvironment construction" \
    "OMSWalletEnvironment" \
    $'import OMSWallet\n\nlet _ = OMSWalletEnvironment(walletApiUrl: "https://wallet.example", indexerGatewayUrl: "https://indexer.example")'

expect_external_build_failure \
    "public OMSWalletError construction" \
    "OMSWalletError" \
    $'import OMSWallet\n\nlet _ = OMSWalletError(code: .validationError, message: "invalid")'

echo "Public OMSWallet API matches its baseline and does not expose generated WaaS declarations."
