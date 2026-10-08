# Migration Guide

This document records breaking changes and the steps to migrate between published
versions of `oms-wallet-swift-sdk`.

## 0.4.0

### Active wallet replaces `walletAddress`

`omsWallet.wallet.walletAddress` was removed. Read the active wallet from
`omsWallet.wallet.activeWallet`, a `Wallet` (`id`, `type`, `address`, `reference`, `keyOrigin`) or
`nil` when signed out. Check `type` before passing the address to family-specific code:

```swift
// 0.3.x
let address = omsWallet.wallet.walletAddress

// 0.4.0
if let activeWallet = omsWallet.wallet.activeWallet, activeWallet.type == .ethereum {
    let ethereumAddress = activeWallet.address
}
```

`walletAddress` was also removed from `WalletSelectionResult` and from
`CompleteAuthResult.walletSelected`, which is now `.walletSelected(wallet:wallets:credential:)`.
Use `result.wallet.address`:

```swift
// 0.3.x
case .walletSelected(let walletAddress, let wallet, let wallets, let credential):

// 0.4.0
case .walletSelected(let wallet, let wallets, let credential):
    let walletAddress = wallet.address
```

### `session` is `nil` when signed out

`OMSWalletSessionState` was renamed to `OMSWalletSession`, and `omsWallet.wallet.session` is now
`OMSWalletSession?`. Previously it returned a value whose fields were all `nil`. The
`walletAddress` field was removed, and `expiresAt` and `auth` are no longer optional. `session` is
non-`nil` exactly when `activeWallet` is.

```swift
// 0.3.x
let email = omsWallet.wallet.session.auth?.email

// 0.4.0
let email = omsWallet.wallet.session?.auth.email
```

`OMSWalletSessionExpiredEvent` gained `wallet: Wallet?`, and its `session` no longer carries
`walletAddress`. `wallet` is `nil` when the credential expired while a manual wallet selection was
still pending.

```swift
// 0.3.x
print(event.session.walletAddress ?? "unknown")

// 0.4.0
print(event.wallet?.address ?? "no wallet selected")
```

### One-time sign-in after upgrading

Saved sessions now record the full wallet, including its type. Sessions saved by 0.3.x do not, so
0.4.0 discards them on launch and users sign in once after upgrading.

### Contract method names

`callContract` (and the new `callTronContract`) now reject a `method` that is not a bare function
name, such as `"transfer(address,uint256)"`, with `.validationError` before sending a request. The
wallet service builds the signature from the argument types, so pass only the name:

```swift
// 0.3.x
method: "transfer(address,uint256)"

// 0.4.0
method: "transfer"
```

### Wallet responses

Ethereum wallets whose address is not `0x` followed by 40 hexadecimal digits are now rejected with
`.invalidResponse`. Checksum casing is not enforced.

### Exhaustive switches

`WalletType` gained `.tron`, and `WalletImportPrivateKey` gained `.tron(_:)` and `.tronBytes(_:)`.
`OMSWalletOperation` gained `.walletSignTronMessage`, `.walletSignTronTypedData`,
`.walletIsValidTronMessageSignature`, `.walletIsValidTronTypedDataSignature`,
`.walletSendTronTransaction`, `.walletCallTronContract`, and `.indexerGetTronBalances`. Update
exhaustive switches over these enums.

## 0.3.0

### Wallet types and key origin

`WalletType` now includes `solana`. Update exhaustive switches to handle Solana wallets before
passing wallet addresses or messages to Ethereum-only code.

Every `Wallet` now has a required `keyOrigin`. Wallets returned by the SDK already include it.
Tests, mocks, or adapters that construct `Wallet` values directly must pass `.enclave` or
`.imported`:

```swift
let wallet = Wallet(
    id: "wallet-id",
    type: .ethereum,
    address: "0x1111111111111111111111111111111111111111",
    keyOrigin: .enclave
)
```

### Error enum cases

`OMSWalletErrorCode` now includes `.attestationVerificationFailed`. `OMSWalletOperation` now
includes these operation identifiers:

- `.walletImportWallet`, `.walletGetImportRecipientKey`, and `.walletImportEncryptedWallet`
- `.walletInspectRemoteCredential`, `.walletAuthorizeRemoteAccess`,
  `.walletGetRemoteAccessSession`, and `.walletGetRemoteAccessSessionUsage`
- `.walletSignSolanaMessage`, `.walletIsValidSolanaMessageSignature`, and
  `.walletSendSolanaTransfer`
- `.indexerGetSolanaBalances`

Update exhaustive switches over either public enum to handle the new cases.

### Access grants and revocation

`CredentialInfo` was renamed to `WalletCredential`. Access listing now distinguishes direct
credentials from remote smart sessions:

- `listAccess()` returns `[AccessGrant]` instead of `[CredentialInfo]`.
- `ListAccessResponse` was replaced by `AccessGrantPage`.
- `listAccessPage()` and `listAccessPages()` return access-grant pages.

Narrow on each grant before reading remote-session fields:

```swift
for grant in try await omsWallet.wallet.listAccess() {
    switch grant {
    case .direct(let credential):
        print(credential.credentialId)
    case .remote(let remote):
        // Display the remote app/session and its authorized permissions.
        print(remote.sessionId, remote.metadata, remote.grants)
    }
}
```

The public `revokeAccess` label changed from `targetCredentialId` to `credentialId`. For a direct
grant, omit `sessionId`. For a remote grant, its `sessionId` is required and revokes exactly that
session; revoke each session separately when a remote credential has more than one:

```swift
// 0.2.0
try await omsWallet.wallet.revokeAccess(targetCredentialId: credentialId)

// 0.3.0
let grants = try await omsWallet.wallet.listAccess()
if let grant = grants.first(where: { !$0.credential.isCaller }) {
    switch grant {
    case .direct(let credential):
        try await omsWallet.wallet.revokeAccess(credentialId: credential.credentialId)
    case .remote(let remote):
        try await omsWallet.wallet.revokeAccess(
            credentialId: remote.credential.credentialId,
            sessionId: remote.sessionId
        )
    }
}
```

Authentication results and pending wallet selections expose `WalletCredential` through their
existing `credential` property.

### Sponsored fee selectors

Fee selections can now include the quoted option index. Custom selectors should return the
provided option's `selection` value instead of reconstructing a selection from its token:

```swift
let selector = FeeOptionSelector { options in
    options.first?.selection
}
```

Sponsored transactions invoke the selector with an empty array. Return `nil` to acknowledge the
free fee, or throw to stop execution. `FeeOptionSelector.firstAvailable` already handles both
sponsored and non-sponsored transactions.
