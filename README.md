# Sequence SDK — Developer Documentation

## Overview

This SDK provides two public classes for integrating Sequence wallet functionality into your iOS or macOS application:

- **`SequenceConnector`** — Handles authentication (email OTP) and wallet creation/restoration.
- **`SequenceWallet`** — Represents an authenticated wallet session and exposes wallet operations like message signing, sending transactions, and sign-out.

### Platform Requirements

| Platform | Minimum Version |
|----------|----------------|
| iOS      | 15.0+          |
| macOS    | 12.0+          |

---

## SequenceConnector

`SequenceConnector` is a singleton-style class that manages the authentication lifecycle and wallet provisioning. It should be your entry point for all auth flows.

### Accessing the Shared Instance

```swift
let connector = SequenceConnector.shared
```

> **Note:** `shared` is a `@MainActor` property. Access it from the main thread or within a `@MainActor` context.

You can also instantiate the class directly if needed:

```swift
let connector = SequenceConnector()
```

---

### Methods

#### `restoreSession() -> SequenceWallet?`

Attempts to restore a previously authenticated wallet session from the device keychain. Returns `nil` if no session exists (e.g., first launch or after sign-out).

```swift
if let wallet = connector.restoreSession() {
    // User is already authenticated — proceed with wallet
} else {
    // No active session — prompt the user to sign in
}
```

Call this on app launch to check for an existing session before showing any auth UI.

---

#### `signInWithEmail(email: String) async`

Initiates email-based OTP authentication. This sends a one-time code to the provided email address and stores the verifier state internally.

```swift
await connector.signInWithEmail(email: "user@example.com")
// Now prompt the user to enter the OTP code they received
```

This method must be `await`ed. After it returns, present your OTP entry UI and call `confirmEmailSignIn` with the code.

---

#### `confirmEmailSignIn(code: String) async -> CompleteAuthResponse`

Completes the email OTP flow by submitting the verification code the user received. Returns a `CompleteAuthResponse` containing the authenticated identity and any wallets already associated with the account.

```swift
let authResult = await connector.confirmEmailSignIn(code: "123456")
// authResult.identity — the authenticated user's identity
// authResult.wallets  — existing wallets associated with this account
```

This must be called after `signInWithEmail`. The `code` parameter is the OTP string entered by the user.

---

#### `createWallet() async -> SequenceWallet`

Creates a new Ethereum wallet (Sequence V3) for the authenticated user. This is the recommended default for most applications.

```swift
let wallet = await connector.createWallet()
// `wallet` is ready to use
```

Internally calls `createWalletByType` with `WalletType.ethereumSequenceV3`.

---

#### `createWalletByType(walletType: WalletType) async -> SequenceWallet`

Creates a new wallet of the specified type for the authenticated user. The wallet address and session key are persisted to the device keychain automatically, so `restoreSession()` will return this wallet on future launches.

```swift
let wallet = await connector.createWalletByType(walletType: .ethereumSequenceV3)
```

---

#### `useWallet(walletType: WalletType) async -> SequenceWallet`

Fetches an existing wallet of the given type for the authenticated user, rather than creating a new one. The wallet address and session key are persisted to the keychain automatically.

```swift
let wallet = await connector.useWallet(walletType: .ethereumSequenceV3)
```

Use this when `confirmEmailSignIn` returns a wallet entry that matches your target type.

---

## SequenceWallet

`SequenceWallet` represents an active, authenticated wallet session. You receive instances of this class from `SequenceConnector` — either via session restoration or wallet creation. You do not instantiate this class directly.

---

### Properties

| Property | Type | Description |
|---|---|---|
| `walletAddress` | `String` | The on-chain address of this wallet. Use this to display the user's wallet address in your UI, pass it to smart contracts, or reference it in transaction requests. |

---

### Methods

#### `signOut()`

Clears the wallet session from the device keychain. After calling this, `restoreSession()` will return `nil` and the user must sign in again.

```swift
wallet.signOut()
// Navigate the user back to your sign-in screen
```

This is a synchronous operation.

---

#### `signMessage(network: String, message: String) async -> String`

Signs an arbitrary message with the wallet's session key and returns the signature as a hex string.

```swift
let signature = await wallet.signMessage(
    network: "mainnet",
    message: "Hello from my app!"
)
print(signature) // "0xabc123..."
```

| Parameter | Type | Description |
|---|---|---|
| `network` | `String` | The network identifier (e.g., `"mainnet"`, `"polygon"`) |
| `message` | `String` | The plaintext message to sign |

Returns a hex-encoded signature string.

---

#### `sendTransaction(network: String, to: String, value: String) async -> String`

Sends a native token transfer to the specified address. The transaction is submitted via the Sequence relayer, so the user does not need to hold gas tokens to cover fees.

```swift
let txHash = await wallet.sendTransaction(
    network: "polygon",
    to: "0xRecipientAddress",
    value: "1000000000000000000" // 1 MATIC in wei
)
print(txHash) // "0xabc123..."
```

| Parameter | Type | Description |
|---|---|---|
| `network` | `String` | The network to send the transaction on (e.g., `"mainnet"`, `"polygon"`) |
| `to` | `String` | The recipient's wallet address |
| `value` | `String` | The amount to send in the network's smallest denomination (e.g., wei for Ethereum) |

Returns the transaction hash of the submitted transaction.

---

#### `callContract(params: CallContractRequest) async -> String`

Calls a smart contract function that writes state — token transfers, NFT mints, approvals, and so on. For read-only calls that don't require a transaction, query the contract directly without this method.

```swift
let txHash = await wallet.callContract(params: CallContractRequest(
    network: "polygon",
    wallet: wallet.walletAddress,
    // ... contract address, ABI, function, arguments
))
print(txHash) // "0xabc123..."
```

| Parameter | Type | Description |
|---|---|---|
| `params` | `CallContractRequest` | Describes the target contract, function selector, ABI-encoded arguments, network, and any value to attach |

Returns the transaction hash of the submitted transaction.

---

#### `listAccess() async -> [CredentialInfo]`

Returns a list of credentials that currently have access to this wallet. Use this to display active sessions or integrations in your app's account management UI, or to audit what credentials exist before revoking one.

```swift
let credentials = await wallet.listAccess()
for credential in credentials {
    print(credential.id) // inspect each active credential
}
```

Returns an array of `CredentialInfo` values, one per credential with access to the wallet.

---

#### `revokeAccess(targetCredentialId: String) async`

Revokes access for a specific credential, preventing it from interacting with this wallet going forward. This action cannot be undone — the credential will need to be re-authorized to regain access.

```swift
let credentials = await wallet.listAccess()
if let toRevoke = credentials.first(where: { $0.id == "some-credential-id" }) {
    await wallet.revokeAccess(targetCredentialId: toRevoke.id)
}
```

| Parameter | Type | Description |
|---|---|---|
| `targetCredentialId` | `String` | The unique identifier of the credential to revoke. Obtain this from `listAccess()`. |

---

## Full Usage Example

Below is a complete example showing a typical authentication and wallet creation flow:

```swift
import Foundation

let connector = SequenceConnector.shared
let targetWalletType = WalletType.ethereumSequenceV3

// 1. Check for an existing session on app launch
if let wallet = connector.restoreSession() {
    print("Restored session for wallet: \(wallet.walletAddress)")
    // Proceed directly to your main app experience
} else {
    // 2. Initiate email sign-in
    await connector.signInWithEmail(email: "user@example.com")

    // 3. Collect OTP from the user (via your UI)
    let otp = "123456"

    // 4. Confirm the OTP — response includes any wallets already associated with this identity
    let authResult = await connector.confirmEmailSignIn(code: otp)

    // 5. Use an existing wallet if one matches the target type, otherwise create a new one
    let wallet: SequenceWallet
    if authResult.wallets.contains(where: { $0.type == targetWalletType.rawValue }) {
        wallet = await connector.useWallet(walletType: targetWalletType)
        print("Using existing wallet: \(wallet.walletAddress)")
    } else {
        wallet = await connector.createWalletByType(walletType: targetWalletType)
        print("Created new wallet: \(wallet.walletAddress)")
    }

    // 6. Sign a message
    let signature = await wallet.signMessage(network: "mainnet", message: "Verify my identity")
    print("Signature: \(signature)")

    // 7. Send a transaction
    let txHash = await wallet.sendTransaction(
        network: "polygon",
        to: "0xRecipientAddress",
        value: "1000000000000000000"
    )
    print("Transaction hash: \(txHash)")

    // 8. Sign out when done
    wallet.signOut()
}
```

---

## Session Persistence

The SDK automatically stores the wallet address and session private key in the device keychain when a wallet is created via `createWallet`, `createWalletByType`, or `useWallet`. This allows `restoreSession()` to rehydrate the session without requiring the user to re-authenticate.

Call `signOut()` on the `SequenceWallet` to explicitly clear this stored session.

---

## Error Handling

The current public API uses `try!` internally for critical operations. It is expected that network connectivity and properly formatted server responses are available during auth and wallet flows. Future versions of the SDK may expose typed error handling. For now, ensure your app:

- Has network access before calling any `async` methods.
- Handles the `nil` return from `restoreSession()` gracefully.
- Validates the OTP code format before passing it to `confirmEmailSignIn`.
