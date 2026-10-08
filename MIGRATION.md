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

`walletAddress` was also removed from `WalletSelectionResult` (now `WalletActivationResult`, see
below) and from
`CompleteAuthResult.walletSelected`, which is now `.walletSelected(wallet:wallets:credential:)`.
Use `result.wallet.address`:

```swift
// 0.3.x
case .walletSelected(let walletAddress, let wallet, let wallets, let credential):

// 0.4.0
case .walletSelected(let wallet, let wallets, let credential):
    let walletAddress = wallet.address
```

The computed `CompleteAuthResult.walletAddress` property was removed too; use
`result.wallet?.address`:

```swift
// 0.3.x
let walletAddress = result.walletAddress

// 0.4.0
let walletAddress = result.wallet?.address
```

### `session` is `nil` when signed out

`OMSWalletSessionState` was renamed to `OMSWalletSession`, and `omsWallet.wallet.session` is now
`OMSWalletSession?`. Previously it returned a value whose fields were all `nil`. The
`walletAddress` field was removed, and `expiresAt` and `auth` are no longer optional (`expiresAt` is
now an ISO-8601 `String`; see [Session expiry timestamps](#session-expiry-timestamps)). `session` is
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
`.invalidResponse`. Checksum casing is not enforced. Sign-in and wallet selection also reject, with
`.invalidResponse`, a wallet whose network family or key origin the SDK does not recognize, instead
of activating a wallet whose saved session would be discarded on the next launch.

### Exhaustive switches

`WalletType` gained `.tron`, and `WalletImportPrivateKey` gained `.tron(_:)` and `.tronBytes(_:)`.
`OMSWalletOperation` gained `.walletSignTronMessage`, `.walletSignTronTypedData`,
`.walletIsValidTronMessageSignature`, `.walletIsValidTronTypedDataSignature`,
`.walletSendTronTransaction`, `.walletCallTronContract`, and `.indexerGetTronBalances`. Update
exhaustive switches over these enums.

### Signature verification

Every `isValid…Signature` method (`isValidMessageSignature`, `isValidTypedDataSignature`,
`isValidSolanaMessageSignature`, `isValidTronMessageSignature`, `isValidTronTypedDataSignature`)
now takes an optional `walletAddress`, and verification requests never send a wallet ID:

- With `walletAddress`, no session is required. Previously the EVM methods threw `.sessionMissing`
  when signed out even though an address was passed.
- Without `walletAddress`, the active wallet's address is used. Signed out, the call throws
  `.sessionMissing`; if the active wallet belongs to another family (for example an Ethereum wallet
  and `isValidSolanaMessageSignature`), it throws `.validationError` before any request.

```swift
// 0.3.x
let isValid = try await omsWallet.wallet.isValidMessageSignature(
    network: .amoy,
    walletAddress: walletAddress,
    message: message,
    signature: signature
)

// 0.4.0: verify against the active wallet
let isValid = try await omsWallet.wallet.isValidMessageSignature(
    network: .amoy,
    message: message,
    signature: signature
)
```

### Contract call parameters

`callContract` and `callTronContract` label the contract `contractAddress:` instead of
`contract:`. `callContract`'s `args` now defaults to `nil`, so a call without arguments can omit it.

```swift
// 0.3.x
try await omsWallet.wallet.callContract(network: .amoy, contract: token, method: "mint", args: nil)

// 0.4.0
try await omsWallet.wallet.callContract(network: .amoy, contractAddress: token, method: "mint")
```

### `WalletActivationResult`

`WalletSelectionResult` was renamed to `WalletActivationResult`. It is returned by `useWallet`,
`createWallet`, `importWallet`, `importEncryptedWallet`, and `PendingWalletSelection`'s
`selectWallet` and `createAndSelectWallet`. Its `wallet` property is unchanged.

```swift
// 0.3.x
let result: WalletSelectionResult = try await omsWallet.wallet.createWallet()

// 0.4.0
let result: WalletActivationResult = try await omsWallet.wallet.createWallet()
```

### `walletId` removed from `WalletClient`

`omsWallet.wallet.walletId` is no longer public. Read the ID from the active wallet:

```swift
// 0.3.x
let walletId = omsWallet.wallet.walletId

// 0.4.0
let walletId = omsWallet.wallet.activeWallet?.id
```

### Session expiry timestamps

`OMSWalletSession.expiresAt` and `OMSWalletSessionExpiredEvent.expiredAt` are now the ISO-8601
`String` returned by the wallet API (the same value as `WalletCredential.expiresAt`) instead of a
`Date`. `OMSWalletSession.init(expiresAt:auth:)` and `OMSWalletSessionExpiredEvent.init` take a
`String`. Parse the value when you need a `Date`; the wallet API may include fractional seconds:

```swift
// 0.3.x
let expiry: Date? = omsWallet.wallet.session.expiresAt

// 0.4.0
guard let session = omsWallet.wallet.session else { return }
let formatter = ISO8601DateFormatter()
formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
let expiry = formatter.date(from: session.expiresAt)
    ?? ISO8601DateFormatter().date(from: session.expiresAt)
```

### Networks

`Network.polygonAmoy` was renamed to `Network.amoy` (raw value `"amoy"`, chain ID `80002`), and the
duplicate `Network.amoy` static alias was removed. `Network.findByName(_:)` no longer accepts the
`"polygonamoy"` alias; pass `"amoy"`. `Network.chainId` (the chain ID as a `String`) was removed;
use `id`.

```swift
// 0.3.x
let network = Network.polygonAmoy
let chainId = network.chainId

// 0.4.0
let network = Network.amoy
let chainId = String(network.id)
```

### Unit helpers require `decimals`

`parseUnits(value:decimals:)` and `formatUnits(value:decimals:)` no longer default `decimals` to
`18`. Pass the token's decimals explicitly:

```swift
// 0.3.x
let wei = try parseUnits(value: "0.001")

// 0.4.0
let wei = try parseUnits(value: "0.001", decimals: 18)
```

### OIDC redirect parameter order

`startOIDCRedirectAuth` parameters now follow the order used by the other OMS Wallet SDKs. Defaults
are unchanged. Calls that pass `loginHint` or `authorizeParams` together with `walletSelection` or
`sessionLifetimeSeconds` must reorder those arguments:

```swift
// 0.3.x
startOIDCRedirectAuth(provider:walletType:loginHint:authorizeParams:walletSelection:sessionLifetimeSeconds:)
startOIDCRedirectAuth(provider:omsRelayReturnURI:walletType:loginHint:walletSelection:sessionLifetimeSeconds:)

// 0.4.0
startOIDCRedirectAuth(provider:walletType:walletSelection:sessionLifetimeSeconds:loginHint:authorizeParams:)
startOIDCRedirectAuth(provider:omsRelayReturnURI:walletType:walletSelection:sessionLifetimeSeconds:loginHint:)
```

### Error and operation strings

These changes compile without edits, so check code that stores, logs, or compares raw values:

- `OMSWalletOperation.walletStartOIDCRedirectAuth.rawValue` is now `"wallet.startOidcRedirectAuth"`
  (was `"wallet.startOIDCRedirectAuth"`), and `.walletHandleOIDCRedirectCallback.rawValue` is now
  `"wallet.handleOidcRedirectCallback"` (was `"wallet.handleOIDCRedirectCallback"`). Case names are
  unchanged.
- `OMSWalletUpstreamService` raw values are now `"waas"` and `"indexer"` (were `"Waas"` and
  `"Indexer"`).
- `OMSWalletErrorCode` gained `.walletAddressAlreadyImported` (`OMS_WALLET_ADDRESS_ALREADY_IMPORTED`).
  Importing a key whose address is already managed now throws it with `status` `409` and
  `retryable == false`; it previously surfaced as `.requestFailed`. Update exhaustive switches over
  `OMSWalletErrorCode`.

```swift
// 0.3.x
if error.code == .requestFailed, error.upstreamError?.code == "7313" { /* already imported */ }

// 0.4.0
if error.code == .walletAddressAlreadyImported { /* already imported */ }
```

### New members that may shadow app extensions

`TronBalance` and `SolanaBalance` now expose `network`, `accountAddress`, `name`, `symbol`,
`decimals`, `balance`, `formattedBalance`, `imageUrl`, `metadataUri`, `verificationStatus`,
`verificationSource`, `priceUSD`, and `balanceUSD` directly. `WalletImportPrivateKey.walletType`,
`WalletClient.defaultSessionLifetimeSeconds` (604,800), and
`WalletClient.maxSessionLifetimeSeconds` (2,592,000) are now public. Remove app extensions that
declare members with these names on those types.

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
