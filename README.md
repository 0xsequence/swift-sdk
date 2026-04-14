# Sequence SDK — Developer Documentation

## Overview

This SDK provides two public classes for integrating Sequence wallet functionality into your iOS or macOS application:

- **`SequenceSdk`** — The top-level entry point. Initialised once with your project credentials and exposes a `wallet` client for all wallet operations.
- **`SequenceWalletClient`** — Manages the full wallet lifecycle: authentication, wallet creation, signing, transactions, and access control.

### Platform Requirements

| Platform | Minimum Version |
|----------|----------------|
| iOS      | 15.0+          |
| macOS    | 12.0+          |

---

## SequenceSdk

`SequenceSdk` is the root object for the SDK. Create a single instance of it at app startup and keep it alive for the session.

### Initialisation

```swift
let sdk = SequenceSdk(
    projectAccessKey: "your-project-access-key",
    environment: .production
)
```

| Parameter | Type | Description |
|---|---|---|
| `projectAccessKey` | `String` | Your Sequence project access key from the Sequence Builder console |
| `environment` | `SequenceEnvironment` | The environment to connect to (e.g. `.production`) |

All wallet functionality is accessed through the `wallet` property:

```swift
sdk.wallet // SequenceWalletClient
```

---

## SequenceWalletClient

`SequenceWalletClient` handles everything from authentication through to on-chain operations. Access it via `sdk.wallet` — do not instantiate it directly.

On initialisation, the client automatically attempts to restore any existing keychain session. If one is found, `walletAddress` is populated immediately and the user does not need to sign in again.

---

### Properties

| Property | Type | Description |
|---|---|---|
| `walletAddress` | `String` | The on-chain address of this wallet. Use this to display the user's wallet address in your UI, pass it to smart contracts, or reference it in transaction requests. Empty string if no wallet has been created or restored yet. |

---

### Authentication

#### `signInWithEmail(email: String) async`

Initiates email-based OTP authentication. Sends a one-time code to the provided address and stores the verifier state internally.

```swift
await sdk.wallet.signInWithEmail(email: "user@example.com")
// Present your OTP entry UI
```

After this returns, show your OTP input and call `confirmEmailSignIn` with the code the user receives.

---

#### `completeEmailSignIn(code: String) async -> CompleteAuthResponse`

Completes the OTP flow by verifying the code the user received. Returns a `CompleteAuthResponse` containing the authenticated identity and any wallets already associated with the account.

```swift
let authResult = await sdk.wallet.completeEmailSignIn(code: "123456")
// authResult.identity — the authenticated user's identity
// authResult.wallets  — existing wallets associated with this account
```

---

#### `clearSession()`

Clears the wallet session from the device keychain. After calling this, the next app launch will start with an empty `walletAddress` and the user will need to sign in again.

```swift
sdk.wallet.clearSession()
// Navigate the user back to your sign-in screen
```

---

### Wallet Management

#### `createWallet() async`

Creates a new Ethereum wallet (Sequence V3) for the authenticated user and persists the address and session key to the keychain. This is the recommended default for most applications.

```swift
await sdk.wallet.createWallet()
print(sdk.wallet.walletAddress) // now populated
```

Internally calls `createWalletByType` with `WalletType.ethereumSequenceV3`.

---

#### `createWalletByType(walletType: WalletType) async`

Creates a new wallet of the specified type and persists the address and session key to the keychain.

```swift
await sdk.wallet.createWalletByType(walletType: .ethereumSequenceV3)
```

Use this instead of `createWallet()` when you need a specific wallet type.

---

#### `useWallet(walletType: WalletType) async`

Loads an existing wallet of the given type and persists the address and session key to the keychain.

```swift
await sdk.wallet.useWallet(walletType: .ethereumSequenceV3)
```

Use this when `completeEmailSignIn` returns a wallet entry that already matches your target type.

---

### Signing & Transactions

#### `signMessage(network: String, message: String) async -> String`

Signs an arbitrary message using the wallet's session key and returns the signature as a hex string.

```swift
let signature = await sdk.wallet.signMessage(
    network: "mainnet",
    message: "Hello from my app!"
)
print(signature) // "0xabc123..."
```

| Parameter | Type | Description |
|---|---|---|
| `network` | `String` | The network identifier (e.g., `"mainnet"`, `"polygon"`) |
| `message` | `String` | The plaintext message to sign |

---

#### `sendTransaction(network: String, to: String, value: String) async -> String`

Sends a native token transfer to the specified address. Submitted via the Sequence relayer, so the user does not need to hold gas tokens to cover fees.

```swift
let txHash = await sdk.wallet.sendTransaction(
    network: "polygon",
    to: "0xRecipientAddress",
    value: "1000000000000000000" // 1 MATIC in wei
)
print(txHash) // "0xabc123..."
```

| Parameter | Type | Description |
|---|---|---|
| `network` | `String` | The network to send the transaction on |
| `to` | `String` | The recipient's wallet address |
| `value` | `String` | The amount in the network's smallest denomination (e.g., wei) |

---

#### `callContract(params: CallContractRequest) async -> String`

Calls a smart contract function that writes state — token transfers, NFT mints, approvals, and so on. For read-only queries, call the contract directly without this method.

```swift
let txHash = await sdk.wallet.callContract(params: CallContractRequest(
    network: "polygon",
    wallet: sdk.wallet.walletAddress,
    // ... contract address, ABI, function, arguments
))
```

| Parameter | Type | Description |
|---|---|---|
| `params` | `CallContractRequest` | Describes the target contract, function selector, ABI-encoded arguments, network, and any value to attach |

---

### Access Control

#### `listAccess() async -> [CredentialInfo]`

Returns a list of credentials that currently have access to this wallet. Use this to display active sessions in your account management UI, or to identify credential IDs before revoking one.

```swift
let credentials = await sdk.wallet.listAccess()
for credential in credentials {
    print(credential.id)
}
```

---

#### `revokeAccess(targetCredentialId: String) async`

Revokes access for a specific credential. This action cannot be undone — the credential will need to be re-authorized to regain access.

```swift
await sdk.wallet.revokeAccess(targetCredentialId: "some-credential-id")
```

| Parameter | Type | Description |
|---|---|---|
| `targetCredentialId` | `String` | The unique identifier of the credential to revoke. Obtain this from `listAccess()`. |

---

## Full Usage Example

```swift
import Foundation

let sdk = SequenceSdk(
    projectAccessKey: "your-project-access-key",
    environment: .production
)

let targetWalletType = WalletType.ethereumSequenceV3

// 1. If a session was restored from the keychain, walletAddress is already set
if !sdk.wallet.walletAddress.isEmpty {
    print("Restored session: \(sdk.wallet.walletAddress)")
    // Proceed directly to your main app experience
} else {
    // 2. Initiate email sign-in
    await sdk.wallet.signInWithEmail(email: "user@example.com")

    // 3. Collect OTP from the user (via your UI)
    let otp = "123456"

    // 4. Confirm the OTP — response includes any wallets already on this account
    let authResult = await sdk.wallet.completeEmailSignIn(code: otp)

    // 5. Use an existing wallet if one matches, otherwise create a new one
    if authResult.wallets.contains(where: { $0.type == targetWalletType.rawValue }) {
        await sdk.wallet.useWallet(walletType: targetWalletType)
        print("Using existing wallet: \(sdk.wallet.walletAddress)")
    } else {
        await sdk.wallet.createWalletByType(walletType: targetWalletType)
        print("Created new wallet: \(sdk.wallet.walletAddress)")
    }

    // 6. Sign a message
    let signature = await sdk.wallet.signMessage(network: "mainnet", message: "Verify my identity")
    print("Signature: \(signature)")

    // 7. Send a transaction
    let txHash = await sdk.wallet.sendTransaction(
        network: "polygon",
        to: "0xRecipientAddress",
        value: "1000000000000000000"
    )
    print("Transaction hash: \(txHash)")

    // 8. Clear session when done
    sdk.wallet.clearSession()
}
```

---

## Session Persistence

The SDK automatically stores the wallet address and session private key in the device keychain when a wallet is created or loaded via `createWallet`, `createWalletByType`, or `useWallet`. On the next app launch, `SequenceWalletClient` restores this session during initialisation — no sign-in required.

Call `clearSession()` to explicitly clear the stored session from the keychain.

---

## Error Handling

The current public API uses `try!` internally for critical operations. It is expected that network connectivity and properly formatted server responses are available during auth and wallet flows. Future versions of the SDK may expose typed error handling. For now, ensure your app:

- Has network access before calling any `async` methods.
- Checks `walletAddress.isEmpty` to determine whether a session was restored before skipping the auth flow.
- Validates the OTP code format before passing it to `completeEmailSignIn`.
