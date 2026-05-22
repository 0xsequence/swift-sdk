# OMS SDK (Swift)

A Swift SDK for the OMS (Open Money Stack) platform. Provides email, OIDC ID-token, and OIDC redirect wallet authentication, non-extractable Keychain request signing, keychain session persistence, wallet ID token retrieval with optional TTL and custom claims, on-chain transaction submission with fee selection, message and typed-data signing, signature verification, token balance queries, and base-unit formatting helpers.

**Requirements:** iOS 15+ · macOS 12+

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-org/oms-swift-sdk", from: "1.0.0")
]
```

Or add it via Xcode: **File -> Add Package Dependencies**.

## Quick Start

```swift
import OMS_SDK

let oms = OMSClient(
    projectAccessKey: "your-project-access-key",
    projectId: "your-project-id"
)

try await oms.wallet.startEmailAuth(email: "user@example.com")
let auth = try await oms.wallet.completeEmailAuth(code: "123456")
guard case .walletSelected(_, let wallet, _, _) = auth else {
    fatalError("Expected automatic wallet selection")
}

print("Wallet address:", wallet.address)
print("Session email:", oms.wallet.session.sessionEmail ?? "unknown")

let value = try parseUnits(value: "1", decimals: 18)
let txResult = try await oms.wallet.sendTransaction(
    network: .polygon,
    to: "0xRecipient",
    value: value
)
print("Transaction hash:", txResult.txnHash ?? "pending")
```

## Overview

`OMSClient` is the root object for the SDK. Create a single instance at app startup and keep it alive for the session. It constructs the SDK sub-clients and restores any saved keychain session automatically.

Pass both your project access key and project ID when creating the client. The SDK uses `projectId` as the signed Wallet API request scope and as part of the keychain namespace for persisted wallet sessions and OIDC redirect state.

| Property | Type | Description |
|---|---|---|
| `wallet` | `WalletClient` | Authentication, session, signing, access management, and transaction helpers. |
| `indexer` | `IndexerClient` | Token balance and on-chain query helpers. |
| `supportedNetworks` | `[Network]` | Supported network list. |

## Supported Networks

Use `Network.supportedNetworks` or the `OMSClient` convenience helpers to bind numeric chain IDs and network names to SDK networks.

```swift
let networks = Network.supportedNetworks
let polygon = oms.findNetworkById(chainId: 137)
let amoy = oms.findNetworkById(chainId: 80002)
let base = oms.findNetworkByName(name: "base")
let katana = oms.findNetworkByName(name: "katana")
```

| Chain ID | Network | Swift case | Indexer value | Native token |
|---|---|---|---|---|
| `1` | Ethereum | `.mainnet` | `mainnet` | `ETH` |
| `11155111` | Sepolia | `.sepolia` | `sepolia` | `ETH` |
| `137` | Polygon | `.polygon` | `polygon` | `POL` |
| `80002` | Polygon Amoy | `.polygonAmoy` | `amoy` | `POL` |
| `42161` | Arbitrum | `.arbitrum` | `arbitrum` | `ETH` |
| `421614` | Arbitrum Sepolia | `.arbitrumSepolia` | `arbitrum-sepolia` | `ETH` |
| `10` | Optimism | `.optimism` | `optimism` | `ETH` |
| `11155420` | Optimism Sepolia | `.optimismSepolia` | `optimism-sepolia` | `ETH` |
| `8453` | Base | `.base` | `base` | `ETH` |
| `84532` | Base Sepolia | `.baseSepolia` | `base-sepolia` | `ETH` |
| `56` | BSC | `.bsc` | `bsc` | `BNB` |
| `97` | BSC Testnet | `.bscTestnet` | `bsc-testnet` | `BNB` |
| `42170` | Arbitrum Nova | `.arbitrumNova` | `arbitrum-nova` | `ETH` |
| `43114` | Avalanche | `.avalanche` | `avalanche` | `AVAX` |
| `43113` | Avalanche Testnet | `.avalancheTestnet` | `avalanche-testnet` | `AVAX` |
| `747474` | Katana | `.katana` | `katana` | `ETH` |

## Authentication Flow

OMS supports email-based OTP, OIDC ID-token auth, and OIDC redirect auth. The email two-step flow is:

1. **`startEmailAuth(email:)`** sends a one-time code to the user's inbox.
2. **`completeEmailAuth(code:walletSelection:walletType:)`** verifies the code. In the default `.automatic` mode it selects the first matching wallet or creates one. The wallet address, wallet ID, and signer metadata are saved to the device keychain.

```swift
try await oms.wallet.startEmailAuth(email: "user@example.com")

// Present your OTP entry UI.
let result = try await oms.wallet.completeEmailAuth(code: "123456")

if case .walletSelected(_, let wallet, _, _) = result {
    print(wallet.address)
}
let session = oms.wallet.session
print(session.walletAddress ?? "signed out")
if let expiresAt = session.expiresAt { print(expiresAt) }
if let loginType = session.loginType { print(loginType) }
print(session.sessionEmail ?? "unknown")
```

To opt out of automatic activation and drive wallet selection yourself:

```swift
enum WalletPickerChoice {
    case existing(Wallet)
    case createNew
}

func showWalletPicker(
    wallets: [Wallet],
    includeCreateNewWallet: Bool
) async -> WalletPickerChoice {
    // Present app UI and return the user's choice.
}

let result = try await oms.wallet.completeEmailAuth(
    code: "123456",
    walletSelection: .manual
)

switch result {
case .walletSelection(let pendingSelection):
    let choice = await showWalletPicker(
        wallets: pendingSelection.wallets,
        includeCreateNewWallet: true
    )

    switch choice {
    case .existing(let wallet):
        try await pendingSelection.selectWallet(walletId: wallet.id)
    case .createNew:
        try await pendingSelection.createAndSelectWallet()
    }
case .walletSelected:
    break
}
```

`PendingWalletSelection` values are single-use. They become invalid after a
wallet is selected or created, after sign-out, or after another auth completion.
Using an invalidated pending selection throws `WalletAuthError.staleWalletSelection`.

For OIDC ID-token flows such as Google Sign-In, pass the provider token plus
the issuer and audience used to mint it:

```swift
let result = try await oms.wallet.signInWithOidcToken(
    idToken: googleIdToken,
    issuer: "https://accounts.google.com",
    audience: "YOUR_WEB_CLIENT_ID"
)

if case .walletSelected(_, let wallet, _, _) = result {
    print(wallet.address)
}
```

Use `walletSelection: .manual` with `signInWithOidcToken` when you want the
same app-driven wallet picker shown in the email example.

For OIDC authorization-code PKCE redirect flows, start the redirect, open the
returned URL with your browser UI, then safely handle incoming app links:

```swift
let started = try await oms.wallet.startOidcRedirectAuth(
    provider: OidcProviders.google(clientId: "YOUR_WEB_CLIENT_ID"),
    redirectUri: "omssdkdemo://auth/callback"
)

// Open started.authorizationUrl.

let result = try await oms.wallet.handleOidcRedirectCallback(
    callbackURLString,
    walletSelection: .manual
)
switch result {
case .completed(let wallet):
    print(wallet.address)
case .walletSelection(let pendingSelection):
    let choice = await showWalletPicker(
        wallets: pendingSelection.wallets,
        includeCreateNewWallet: true
    )

    switch choice {
    case .existing(let wallet):
        try await pendingSelection.selectWallet(walletId: wallet.id)
    case .createNew:
        try await pendingSelection.createAndSelectWallet()
    }
case .notOidcRedirectCallback:
    break
case .noPendingAuth:
    break
case .failed(let error):
    print(error.localizedDescription)
}
```

Wallet API requests are signed with a non-extractable Keychain P-256 credential using the `webcrypto-secp256r1` key type. Only completed wallet session metadata is restored automatically, including wallet address, expiry, login type, and session email when available. The private credential key remains owned by the Keychain and is not written into SDK session storage.

On subsequent launches, the completed session is restored from the keychain automatically. To end the session:

```swift
try oms.wallet.signOut()
```

## Transaction Flow

`sendTransaction` and `callContract` use a prepare/execute flow internally:

1. **Prepare** - the server calculates fee options for the transaction.
2. **Select fee** - the SDK picks the default fee option, or your `FeeOptionSelector` picks one.
3. **Execute** - the transaction is submitted.
4. **Poll** - the SDK polls for about 60 seconds and returns once the status is `.executed` or a transaction hash is available.

By default, the SDK uses the first required fee option, or no fee option when the
transaction is sponsored. Transaction mode defaults to `.relayer`; pass
`.native` when you want native mode.

```swift
let value = try parseUnits(value: "1", decimals: 18)
let txResult = try await oms.wallet.sendTransaction(
    network: .polygon,
    to: "0xRecipient",
    value: value
)
print("Transaction ID:", txResult.txnId)
print("Transaction status:", txResult.status)
print("Transaction hash:", txResult.txnHash ?? "pending")
```

Provide `selectFeeOption` on `sendTransaction` or `callContract` to choose
from the returned fee options:

```swift
let value = try parseUnits(value: "1", decimals: 18)
let txResult = try await oms.wallet.sendTransaction(
    network: .polygon,
    to: "0xRecipient",
    value: value,
    selectFeeOption: .custom { options in
        let selected = options[selectedIndex]
        return selected.selection
    }
)
```

Custom selectors receive `FeeOptionWithBalance` values. `balance` is the wallet's
raw indexer balance for that fee token when available, `available` is formatted
with the token decimals, `availableRaw` is the raw integer balance, and
`decimals` is the token decimal count used for formatting. Unsponsored
transactions require the selector to return a fee selection.

## Configuration

### Custom Environment

```swift
let env = OMSClientEnvironment(
    walletApiUrl: "https://staging-wallet.example.com",
    apiRpcUrl: "https://staging-api.example.com/rpc/API",
    indexerUrlTemplate: "https://staging-{value}-indexer.example.com/rpc/Indexer/"
)

let oms = OMSClient(
    projectAccessKey: "your-key",
    projectId: "proj_staging",
    environment: env
)
```

To keep the default endpoints and use a different project:

```swift
let oms = OMSClient(
    projectAccessKey: "your-key",
    projectId: "proj_staging"
)
```

## Unit Formatting

Use the top-level helpers to convert between display amounts and base-unit integer strings without floating-point precision loss.

```swift
let usdcRaw = try parseUnits(value: "12.34", decimals: 6)
// "12340000"

let usdcDisplay = try formatUnits(value: usdcRaw, decimals: 6)
// "12.34"
```

## Examples

### Sign a Message

```swift
let signature = try await oms.wallet.signMessage(
    network: .polygon,
    message: "Hello from OMS"
)
```

### Verify a Message Signature

```swift
let isValid = try await oms.wallet.isValidMessageSignature(
    network: .polygon,
    walletAddress: oms.wallet.walletAddress,
    message: "Hello from OMS",
    signature: signature
)
```

### Sign Typed Data

```swift
let typedData: WebRPCJSONValue = .object([
    "domain": .object([
        "name": .string("Example"),
        "version": .string("1"),
        "chainId": .integer(137)
    ]),
    "message": .object([
        "contents": .string("Hello from OMS")
    ]),
    "primaryType": .string("Message"),
    "types": .object([
        "Message": .array([
            .object([
                "name": .string("contents"),
                "type": .string("string")
            ])
        ])
    ])
])

let signature = try await oms.wallet.signTypedData(
    network: .polygon,
    typedData: typedData
)

let isValid = try await oms.wallet.isValidTypedDataSignature(
    network: .polygon,
    walletAddress: oms.wallet.walletAddress,
    typedData: typedData,
    signature: signature
)
```

### Send a Transaction with Full Parameters

```swift
let value = try parseUnits(value: "1", decimals: 18)
let txResult = try await oms.wallet.sendTransaction(
    network: .polygon,
    request: SendTransactionRequest(
        to: "0xRecipient",
        value: value,
        data: nil,
        mode: .relayer
    )
)
```

### Call a Smart Contract

```swift
let amount = try parseUnits(value: "1", decimals: 18)
let txResult = try await oms.wallet.callContract(
    network: .polygon,
    contract: "0xTokenContract",
    method: "transfer(address,uint256)",
    args: [
        AbiArg(type: "address", value: .string("0xRecipient")),
        AbiArg(type: "uint256", value: .string(amount)),
    ]
)
```

### Handle Transaction Errors

```swift
let value = try parseUnits(value: "1", decimals: 18)
do {
    let txResult = try await oms.wallet.sendTransaction(
        network: .polygon,
        to: "0xRecipient",
        value: value
    )
    if txResult.status == .pending {
        print("Submitted:", txResult.txnId)
    } else {
        print("Sent:", txResult.txnHash ?? "no hash")
    }
} catch TransactionError.transactionFailed(let status) {
    print("Transaction failed with status:", status)
}
```

### Query Token Balances

```swift
let result = try await oms.indexer.getTokenBalances(
    network: .polygon,
    contractAddress: "0xTokenContract",
    walletAddress: oms.wallet.walletAddress,
    includeMetadata: true
)

for balance in result.balances {
    print(balance.contractAddress ?? "", balance.balance ?? "")
}
```

### Query Native Token Balance

```swift
let balance = try await oms.indexer.getNativeTokenBalance(
    network: .polygon,
    walletAddress: oms.wallet.walletAddress
)

print(balance?.balance ?? "0")
```

### Get a Wallet ID Token

```swift
let idToken = try await oms.wallet.getIdToken()

let scopedIdToken = try await oms.wallet.getIdToken(
    ttlSeconds: 3_600,
    customClaims: [
        "role": .string("member"),
        "features": .array([.string("trading")])
    ]
)
```

### Manage Wallet Access

```swift
let credentials = try await oms.wallet.listAccess()

for try await page in oms.wallet.listAccessPages(pageSize: 25) {
    print(page.credentials)
}

if let credential = credentials.first {
    try await oms.wallet.revokeAccess(targetCredentialId: credential.credentialId)
}
```

## API Reference

See [API.md](./API.md) for the full method and type reference.
