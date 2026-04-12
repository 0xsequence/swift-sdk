# Sequence SDK — Developer Documentation

## Overview

This SDK provides two public classes for integrating Sequence wallet functionality into your iOS or macOS application:

- **`SequenceConnector`** — Handles authentication (email OTP) and wallet creation/restoration.
- **`SequenceWallet`** — Represents an authenticated wallet session and exposes wallet operations like message signing and sign-out.

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

#### `RestoreSession() -> SequenceWallet?`

Attempts to restore a previously authenticated wallet session from the device keychain. Returns `nil` if no session exists (e.g., first launch or after sign-out).

```swift
if let wallet = connector.RestoreSession() {
    // User is already authenticated — proceed with wallet
} else {
    // No active session — prompt the user to sign in
}
```

Call this on app launch to check for an existing session before showing any auth UI.

---

#### `SignInWithEmail(email: String) async`

Initiates email-based OTP authentication. This sends a one-time code to the provided email address and stores the verifier state internally.

```swift
await connector.SignInWithEmail(email: "user@example.com")
// Now prompt the user to enter the OTP code they received
```

This method must be `await`ed. After it returns, present your OTP entry UI and call `ConfirmEmailSignIn` with the code.

---

#### `ConfirmEmailSignIn(code: String) async -> CompleteAuthReturn`

Completes the email OTP flow by submitting the verification code the user received. Returns a `CompleteAuthReturn` value containing the result of the authentication.

```swift
let result = await connector.ConfirmEmailSignIn(code: "123456")
// Inspect `result` to confirm successful auth before creating a wallet
```

This must be called after `SignInWithEmail`. The `code` parameter is the OTP string entered by the user.

---

#### `CreateWallet() async -> SequenceWallet`

Creates a new Ethereum wallet (Sequence V3) for the authenticated user. This is the recommended default for most applications.

```swift
let wallet = await connector.CreateWallet()
// `wallet` is ready to use
```

Internally calls `CreateWalletByType` with `"Ethereum_SequenceV3"`.

---

#### `CreateWalletByType(walletType: String) async -> SequenceWallet`

Creates a new wallet of a specific type. Use this if you need a wallet type other than the default.

```swift
let wallet = await connector.CreateWalletByType(walletType: "Ethereum_SequenceV3")
```

The wallet address and session key are persisted to the device keychain automatically, so `RestoreSession()` will return this wallet on future launches.

---

#### `UseWallet(walletType: String) async -> SequenceWallet`

Fetches an existing wallet of the given type for the authenticated user, rather than creating a new one.

```swift
let wallet = await connector.UseWallet(walletType: "Ethereum_SequenceV3")
```

Use this when the user has already created a wallet in a previous session and you want to load it by type rather than restoring from the keychain.

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

#### `SignOut()`

Clears the wallet session from the device keychain. After calling this, `RestoreSession()` will return `nil` and the user must sign in again.

```swift
wallet.SignOut()
// Navigate the user back to your sign-in screen
```

This is a synchronous operation.

---

#### `SignMessage(network: String, message: String) async -> String`

Signs an arbitrary message with the wallet's session key and returns the signature as a hex string.

```swift
let signature = await wallet.SignMessage(
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

## Full Usage Example

Below is a complete example showing a typical authentication and wallet creation flow:

```swift
import Foundation

let connector = SequenceConnector.shared

// 1. Check for an existing session on app launch
if let wallet = connector.RestoreSession() {
    print("Restored session for wallet: \(wallet.walletAddress)")
    // Proceed directly to your main app experience
} else {
    // 2. Initiate email sign-in
    await connector.SignInWithEmail(email: "user@example.com")

    // 3. Collect OTP from the user (via your UI)
    let otp = "123456"

    // 4. Confirm the OTP
    let authResult = await connector.ConfirmEmailSignIn(code: otp)
    print("Auth complete: \(authResult)")

    // 5. Create a wallet for the authenticated user
    let wallet = await connector.CreateWallet()
    print("Wallet address: \(wallet.walletAddress)")

    // 6. Sign a message
    let signature = await wallet.SignMessage(network: "mainnet", message: "Verify my identity")
    print("Signature: \(signature)")

    // 7. Sign out when done
    wallet.SignOut()
}
```

---

## Session Persistence

The SDK automatically stores the wallet address and session private key in the device keychain when a wallet is created via `CreateWallet`, `CreateWalletByType`, or `UseWallet`. This allows `RestoreSession()` to rehydrate the session without requiring the user to re-authenticate.

Call `SignOut()` on the `SequenceWallet` to explicitly clear this stored session.

---

## Error Handling

The current public API uses `try!` internally for critical operations. It is expected that network connectivity and properly formatted server responses are available during auth and wallet flows. Future versions of the SDK may expose typed error handling. For now, ensure your app:

- Has network access before calling any `async` methods.
- Handles the `nil` return from `RestoreSession()` gracefully.
- Validates the OTP code format before passing it to `ConfirmEmailSignIn`.
