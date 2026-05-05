# OMS SDK (Swift)

A Swift SDK for the OMS (Open Money Stack) platform. Provides email-based wallet authentication, keychain session persistence, on-chain transaction submission with fee selection, message signing, token balance queries, and base-unit formatting helpers.

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

let oms = OMSClient(projectAccessKey: "your-project-access-key")

// 1. Send a one-time code to the user's email
await oms.wallet.startEmailAuth(email: "user@example.com")

// 2. User enters the code; this loads or creates a wallet
await oms.wallet.completeEmailAuth(code: "123456")

// 3. The wallet is ready
print("Wallet address:", oms.wallet.walletAddress)

// 4. Send a transaction
let txHash = try await oms.wallet.sendTransaction(
    network: "polygon",
    to: "0xRecipient",
    value: "1000000000000000000"  // raw base-unit amount
)
```

## Overview

`OMSClient` is the root object for the SDK. Create a single instance at app startup and keep it alive for the session. It constructs the SDK sub-clients and restores any saved keychain session automatically.

| Property | Type | Description |
|---|---|---|
| `wallet` | `WalletClient` | Authentication, session, signing, access management, and transaction helpers. |
| `indexer` | `IndexerClient` | Token balance and on-chain query helpers. |
| `utils` | `OMSClientUtils` | Unit parser and formatter helpers. |
| `walletAddress` | `String` | Compatibility shortcut for `oms.wallet.walletAddress`. Empty if no wallet is active. |

`OmsWallet` remains available as a compatibility alias for `OMSClient`. `OmsEnvironment` remains available as a compatibility alias for `OMSClientEnvironment`.

## Authentication Flow

OMS uses email-based OTP. The two-step flow is:

1. **`startEmailAuth(email:)`** sends a one-time code to the user's inbox.
2. **`completeEmailAuth(code:walletType:)`** verifies the code, then automatically loads an existing wallet or creates a new one. The wallet address, wallet ID, and session key are saved to the device keychain.

On subsequent launches, the session is restored from the keychain automatically.

```swift
await oms.wallet.startEmailAuth(email: "user@example.com")

// Present your OTP entry UI
await oms.wallet.completeEmailAuth(code: "123456")

print(oms.wallet.walletAddress)
```

To end the session, call:

```swift
oms.wallet.signOut()
```

Compatibility methods are also available on `OMSClient` and `WalletClient`: `signInWithEmail`, `completeEmailSignIn`, and `clearSession`.

## Transaction Flow

`sendTransaction` and `callContract` use a prepare/execute flow internally:

1. **Prepare** - the server calculates fee options for the transaction.
2. **Select fee** - your `FeeOptionSelector` picks which fee option to use.
3. **Execute** - the transaction is submitted.
4. **Poll** - the SDK polls until the transaction is confirmed on-chain.

The default selector is `.first`, which picks the first available fee option.

```swift
let txHash = try await oms.wallet.sendTransaction(
    network: "polygon",
    to: "0xRecipient",
    value: "1000000000000000000"
)
```

Use `.cheapest` to choose the lowest numeric fee value:

```swift
let txHash = try await oms.wallet.sendTransaction(
    network: "polygon",
    to: "0xRecipient",
    value: "1000000000000000000",
    feeOptionSelector: .cheapest
)
```

Or provide a custom selector:

```swift
let txHash = try await oms.wallet.sendTransaction(
    network: "polygon",
    to: "0xRecipient",
    value: "1000000000000000000",
    feeOptionSelector: .custom { options in
        return options[selectedIndex]
    }
)
```

## Configuration

### Custom Environment

```swift
let env = OMSClientEnvironment(
    walletApiUrl: "https://staging-wallet.example.com",
    apiRpcUrl: "https://staging-api.example.com/rpc/API",
    indexerUrlTemplate: "https://staging-indexer.example.com/{value}",
    scope: "proj_staging"
)

let oms = OMSClient(projectAccessKey: "your-key", environment: env)
```

To keep the default endpoints and only change the signed-request scope:

```swift
let oms = OMSClient(
    projectAccessKey: "your-key",
    environment: OMSClientEnvironment(scope: "proj_staging")
)
```

### Unit Formatting

Use `utils` to convert between display amounts and base-unit integer strings without floating-point precision loss.

```swift
let usdcRaw = try oms.utils.parseUnits(value: "12.34", decimals: 6)
// "12340000"

let usdcDisplay = try oms.utils.formatUnits(value: usdcRaw, decimals: 6)
// "12.34"
```

## Examples

### Sign a Message

```swift
let signature = await oms.wallet.signMessage(
    network: "polygon",
    message: "Hello from OMS"
)
```

### Send a Transaction with Full Parameters

```swift
let txHash = try await oms.wallet.sendTransaction(
    network: "polygon",
    request: SendTransactionRequest(
        to: "0xContract",
        value: "0",
        data: "0xa9059cbb..."
    )
)
```

### Call a Smart Contract

```swift
let txHash = try await oms.wallet.callContract(
    network: "polygon",
    contract: "0xTokenContract",
    method: "transfer(address,uint256)",
    args: [
        AbiArg(type: "address", value: .string("0xRecipient")),
        AbiArg(type: "uint256", value: .string("1000000000000000000")),
    ]
)
```

### Handle Transaction Errors

```swift
do {
    let txHash = try await oms.wallet.sendTransaction(
        network: "polygon",
        to: "0xRecipient",
        value: "1000000000000000000"
    )
    print("Sent:", txHash)
} catch TransactionError.noFeeOptionsAvailable {
    print("No fee options returned from server")
} catch TransactionError.pollingTimedOut {
    print("Transaction did not confirm in time")
} catch TransactionError.transactionFailed(let status) {
    print("Transaction failed with status:", status)
} catch TransactionError.missingTransactionHash {
    print("Transaction executed but no hash was returned")
}
```

### Query Token Balances

```swift
let result = try await oms.indexer.getTokenBalances(
    chainId: "polygon",
    contractAddress: "0xTokenContract",
    walletAddress: oms.wallet.walletAddress,
    includeMetadata: true
)

for balance in result.balances {
    print(balance.contractAddress ?? "", balance.balance ?? "")
}
```

### Manage Wallet Access

```swift
let credentials = await oms.wallet.listAccess()

if let credential = credentials.first {
    await oms.wallet.revokeAccess(targetCredentialId: credential.credentialId)
}
```

## API Reference

See [API.md](./API.md) for the full method and type reference.
