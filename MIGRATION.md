# Migration Guide

This document records breaking changes and the steps to migrate between published
versions of `oms-wallet-swift-sdk`.

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

The public `revokeAccess` label changed from `targetCredentialId` to `credentialId`. Pass an
optional `sessionId` to revoke only one remote session for that credential:

```swift
// 0.2.0
try await omsWallet.wallet.revokeAccess(targetCredentialId: credentialId)

// 0.3.0
try await omsWallet.wallet.revokeAccess(credentialId: credentialId)
try await omsWallet.wallet.revokeAccess(
    credentialId: credentialId,
    sessionId: sessionId
)
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
