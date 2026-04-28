# OMS SDK (Swift)

A Swift SDK for the OMS (Open Mobile Stack) platform. Provides email-based wallet authentication, on-chain transaction submission with fee selection, message signing, and token balance queries — with automatic keychain session persistence.

**Requirements:** iOS 15+ · macOS 12+

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-org/oms-swift-sdk", from: "1.0.0")
]
```

Or add it via Xcode: **File → Add Package Dependencies**.

## Quick Start

```swift
import OMSClient

let oms = OMSClient(projectAccessKey: "your-project-access-key")

// 1. Send a one-time code to the user's email
await oms.wallet.startEmailAuth(email: "user@example.com")

// 2. User enters the code — verifies it and sets up the wallet automatically
await oms.wallet.completeEmailAuth(code: "123456")

// 3. The wallet is ready
print("Wallet address:", oms.wallet.walletAddress)

// 4. Send a transaction
let txHash = try await oms.wallet.sendTransaction(
    network: "polygon",
    to: "0xRecipient",
    value: "1000000000000000000"  // 1 MATIC in wei
)
```

## Overview

`OMSClient` exposes two sub-clients:

| Property | Type | Description |
|---|---|---|
| `oms.wallet` | `WalletClient` | Authentication, signing, and transaction submission. |
| `oms.indexer` | `IndexerClient` | Read token balances and on-chain state. |

## Authentication Flow

OMS uses email-based OTP. The two-step flow is:

1. **`startEmailAuth(email:)`** — sends a one-time code to the user's inbox.
2. **`completeEmailAuth(code:walletType:)`** — verifies the code, then automatically loads an existing wallet or creates a new one. The wallet address, wallet ID, and session key are saved to the device keychain.

On subsequent launches, the session is restored from the keychain automatically — no sign-in required.

To end the session, call `oms.wallet.signOut()`.

## Transaction Flow

`sendTransaction` and `callContract` use a two-step prepare/execute flow internally:

1. **Prepare** — the server calculates fee options for the transaction.
2. **Select fee** — your `FeeOptionSelector` picks which fee option to use.
3. **Execute** — the transaction is submitted.
4. **Poll** — the SDK polls until the transaction is confirmed on-chain.

The default selector is `.first`, which picks the first available fee option. Use `.cheapest` or provide a custom selector to give users control over gas costs:

```swift
// Use the cheapest available fee option
let txHash = try await oms.wallet.sendTransaction(
    network: "polygon",
    to: "0xRecipient",
    value: "1000000000000000000",
    feeOptionSelector: .cheapest
)

// Present fee options to the user
let txHash = try await oms.wallet.sendTransaction(
    network: "polygon",
    to: "0xRecipient",
    value: "1000000000000000000",
    feeOptionSelector: .custom { options in
        // options is [FeeOption] — return the one the user picked
        return options[selectedIndex]
    }
)
```

## Configuration

### Custom Environment

```swift
let env = OMSClientEnvironment(
    walletApiUrl: "https://staging-wallet.example.com",
    indexerUrlTemplate: "https://staging-indexer.example.com/{value}"
)

let oms = OMSClient(projectAccessKey: "your-key", environment: env)
```

## Examples

### Sign a Message

```swift
let signature = try await oms.wallet.signMessage(
    network: "polygon",
    message: "Hello from OMS"
)
```

### Send a Native Token Transfer

```swift
let txHash = try await oms.wallet.sendTransaction(
    network: "polygon",
    to: "0xRecipient",
    value: "1000000000000000000"  // 1 MATIC in wei
)
```

### Send a Transaction with Full Parameters

```swift
let txHash = try await oms.wallet.sendTransaction(
    network: "polygon",
    request: SendTransactionRequest(
        to: "0xContract",
        value: "0",
        data: "0xa9059cbb...",
        feeCeiling: nil,
        nonce: nil
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
    print("Transaction did not confirm in time — check the network")
} catch TransactionError.transactionFailed(let status) {
    print("Transaction failed with status:", status)
} catch TransactionError.missingTransactionHash {
    print("Transaction executed but no hash was returned")
}
```

### Query Token Balances

```swift
let result = try await oms.indexer.getTokenBalances(
    chainId: "137",
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
// List credentials with access to this wallet
let credentials = await oms.wallet.listAccess()

// Revoke one
await oms.wallet.revokeAccess(targetCredentialId: credentials[0].credentialId)
```

### Sign Out

```swift
oms.wallet.signOut()
// Navigate to sign-in screen
```

## API Reference

See [API.md](./API.md) for the full method and type reference.
