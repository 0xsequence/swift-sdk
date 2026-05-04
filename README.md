# OMS Wallet SDK — Developer Documentation

## Overview

This SDK provides a single public class for integrating OMS wallet functionality into your iOS or macOS application:

- **`OMSClient`** — The entry point. Initialised once with your project credentials and exposes wallet, indexer, and utility helpers.

`OmsWallet` remains available as a compatibility alias for existing integrations.

### Platform Requirements

| Platform | Minimum Version |
|----------|----------------|
| iOS      | 15.0+          |
| macOS    | 12.0+          |

---

## OMSClient

`OMSClient` is the root object for the SDK. Create a single instance of it at app startup and keep it alive for the session. It handles everything from authentication through to on-chain operations.

On initialisation, the wallet automatically attempts to restore any existing keychain session. If one is found, `walletAddress` is populated immediately and the user does not need to sign in again.

### Initialisation

```swift
let oms = OMSClient(
    projectAccessKey: "your-project-access-key",
    environment: OmsEnvironment()
)
```

| Parameter | Type | Description |
|---|---|---|
| `projectAccessKey` | `String` | Your project access key |
| `environment` | `OmsEnvironment` | The environment to connect to. Defaults to `OmsEnvironment()`. |

---

### Properties

| Property | Type | Description |
|---|---|---|
| `wallet` | `WalletClient` | Authentication, session, signing, and transaction helpers. Constructed by `OMSClient`; developers cannot create it directly. |
| `indexer` | `IndexerClient` | Token balance and on-chain query helpers. Constructed by `OMSClient`; developers cannot create it directly. |
| `utils` | `OMSClientUtils` | Unit parser and formatter helpers. Constructed by `OMSClient`; developers cannot create it directly. |
| `walletAddress` | `String` | The on-chain address of this wallet. Empty string if no wallet has been created or restored yet. |

---

### Authentication

#### `signInWithEmail(email: String) async`

Initiates email-based OTP authentication. Sends a one-time code to the provided address and stores the verifier state internally.

```swift
await oms.signInWithEmail(email: "user@example.com")
// Present your OTP entry UI
```

After this returns, show your OTP input and call `completeEmailSignIn` with the code the user receives.

---

#### `completeEmailSignIn(code: String, walletType: WalletType = .ethereumEoa) async`

Completes the OTP flow by verifying the code the user received. On success, this method also provisions a wallet of `walletType` for the authenticated user: if one already exists on the account it is loaded, otherwise a new one is created. In both cases the wallet address and session key are persisted to the keychain, and `walletAddress` is populated once this call returns.

```swift
await oms.completeEmailSignIn(code: "123456")
print(oms.walletAddress) // now populated
```

You can pass a specific wallet type if you don't want the default:

```swift
await oms.completeEmailSignIn(code: "123456", walletType: .ethereumEoa)
```

| Parameter | Type | Description |
|---|---|---|
| `code` | `String` | The one-time passcode entered by the user |
| `walletType` | `WalletType` | The wallet type to load or create. Defaults to `.ethereumEoa`. |

---

#### `clearSession()`

Clears the wallet session from the device keychain. After calling this, the next app launch will start with an empty `walletAddress` and the user will need to sign in again via `signInWithEmail(email:)`.

```swift
oms.clearSession()
// Navigate the user back to your sign-in screen
```

---

### Signing & Transactions

#### `signMessage(network: String, message: String) async -> String`

Signs an arbitrary message using the wallet's session key and returns the signature as a hex string.

```swift
let signature = await oms.signMessage(
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
let txHash = await oms.sendTransaction(
    network: "polygon",
    to: "0xRecipientAddress",
    value: try oms.utils.parseEther(value: "1")
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
let txHash = await oms.callContract(params: CallContractRequest(
    network: "polygon",
    wallet: oms.walletAddress,
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
let credentials = await oms.listAccess()
for credential in credentials {
    print(credential.id)
}
```

---

#### `revokeAccess(targetCredentialId: String) async`

Revokes access for a specific credential. This action cannot be undone — the credential will need to be re-authorized to regain access.

```swift
await oms.revokeAccess(targetCredentialId: "some-credential-id")
```

| Parameter | Type | Description |
|---|---|---|
| `targetCredentialId` | `String` | The unique identifier of the credential to revoke. Obtain this from `listAccess()`. |

---

### Unit Formatting

Use `utils` to convert between display amounts and base-unit integer strings without floating-point precision loss.

```swift
let usdcRaw = try oms.utils.parseUnits(value: "12.34", decimals: 6)
// "12340000"

let usdcDisplay = try oms.utils.formatUnits(value: usdcRaw, decimals: 6)
// "12.34"

let wei = try oms.utils.parseEther(value: "1")
let eth = try oms.utils.formatEther(value: wei)
```

---

## Full Usage Example

```swift
import Foundation

let oms = OMSClient(
    projectAccessKey: "your-project-access-key",
    environment: OmsEnvironment()
)

// 1. If a session was restored from the keychain, walletAddress is already set
if !oms.walletAddress.isEmpty {
    print("Restored session: \(oms.walletAddress)")
    // Proceed directly to your main app experience
} else {
    // 2. Initiate email sign-in
    await oms.signInWithEmail(email: "user@example.com")

    // 3. Collect OTP from the user (via your UI)
    let otp = "123456"

    // 4. Complete sign-in — this also provisions the wallet
    //    (loads existing or creates new) and populates walletAddress.
    await oms.completeEmailSignIn(code: otp)
    print("Wallet ready: \(oms.walletAddress)")

    // 5. Sign a message
    let signature = await oms.signMessage(network: "mainnet", message: "Verify my identity")
    print("Signature: \(signature)")

    // 6. Send a transaction
    let txHash = await oms.sendTransaction(
        network: "polygon",
        to: "0xRecipientAddress",
        value: try oms.utils.parseEther(value: "1")
    )
    print("Transaction hash: \(txHash)")

    // 7. Clear session when done
    oms.clearSession()
}
```

---

## Session Persistence

The SDK automatically stores the wallet address and session private key in the device keychain when `completeEmailSignIn` provisions a wallet. On the next app launch, `OMSClient` restores this session during initialisation — no sign-in required.

Call `clearSession()` to explicitly clear the stored session from the keychain.

---

## Error Handling

The current public API uses `try!` internally for critical operations. It is expected that network connectivity and properly formatted server responses are available during auth and wallet flows. Future versions of the SDK may expose typed error handling. For now, ensure your app:

- Has network access before calling any `async` methods.
- Checks `walletAddress.isEmpty` to determine whether a session was restored before skipping the auth flow.
- Validates the OTP code format before passing it to `completeEmailSignIn`.
