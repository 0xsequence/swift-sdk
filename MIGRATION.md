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
`CompleteAuthResult.walletSelected`, which is now
`.walletSelected(wallet:wallets:claimableWallets:credential:)` (see
[Claimable wallets](#claimable-wallets)). Use `result.wallet.address`:

```swift
// 0.3.x
case .walletSelected(let walletAddress, let wallet, let wallets, let credential):

// 0.4.0
case .walletSelected(let wallet, let wallets, let claimableWallets, let credential):
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

### `addSessionChangeObserver` replaces `addSessionExpiredObserver`

`addSessionExpiredObserver` and `OMSWalletSessionExpiredObservation` were removed.
`addSessionChangeObserver` reports every change of `activeWallet` or `session` as an
`OMSWalletSessionChangeEvent`: `.signedIn`, `.restored`, `.walletChanged`, `.expiryUpdated`,
`.signedOut`, or `.expired`. `.expired` carries an `OMSWalletExpiredSession`, which replaces
`OMSWalletSessionExpiredEvent`. It gained `wallet: Wallet?` (`nil` when the credential expired
during a pending manual wallet selection), and its `session` no longer carries `walletAddress`. The
method returns `OMSWalletSessionChangeObservation` and is no longer `@discardableResult`: keep the
observation, since delivery stops when it is released.

```swift
// 0.3.x
let observation = omsWallet.wallet.addSessionExpiredObserver { event in showSignIn(event.session.auth) }

// 0.4.0
let observation = omsWallet.wallet.addSessionChangeObserver { change in
    if case .expired(let expired) = change {
        showSignIn(expired.session.auth)
    }
}
```

The `.expired` replay to new observers is unchanged. A session whose keychain key another process
removed or replaced now reports its end on every path: `.expired` when its stored record is still
its own or its expiry passed, `.signedOut` when another sign-in replaced it. Previously only
background checks reported it, always as an expiry. An operation that finds a session ended this way
throws `.sessionExpired` when it reports `.expired`. A restore that waited for the device to unlock
now reports `.restored`.

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
of activating a wallet whose saved session would be discarded on the next launch. An auth response
whose credential `expiresAt` is not a valid ISO-8601 timestamp now fails with `.invalidResponse` and
leaves the user signed out. Previously the session was activated without an expiry.

### Exhaustive switches

`WalletType` gained `.tron`, and `WalletImportPrivateKey` gained `.tron(_:)` and `.tronBytes(_:)`.
`OMSWalletOperation` gained `.walletSignTronMessage`, `.walletSignTronTypedData`,
`.walletIsValidTronMessageSignature`, `.walletIsValidTronTypedDataSignature`,
`.walletSendTronTransaction`, `.walletCallTronContract`, `.indexerGetTronBalances`,
`.walletClaimWallet`, and `.pendingWalletSelectionClaimAndSelectWallet`. Update
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
- An empty or whitespace-only `walletAddress` now throws `.validationError` ("walletAddress must not
  be empty") before any request. It does not fall back to the active wallet. Previously the SDK sent
  it to the wallet API, which rejected it with a request error.

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

### Claimable wallets

Sign-in now reports wallets a project preallocated for the user's email:

- `CompleteAuthResult.walletSelected` gained a `claimableWallets: [Wallet]` value after
  `wallets`, so patterns that bind its values need a fourth binding (or `_`). The computed
  `CompleteAuthResult.claimableWallets` property reads it without a pattern.
- `PendingWalletSelection.claimableWallets` lists the claimable wallets of the pending wallet type,
  and `PendingWalletSelection.claimAndSelectWallet(walletId:)` claims one of them and completes the
  selection (operation `.pendingWalletSelectionClaimAndSelectWallet`).
- `WalletClient.claimWallet(walletId:)` claims one and activates it, like `useWallet(walletId:)`.
  Its errors use the new operation `.walletClaimWallet` (`"wallet.claimWallet"`).

Automatic wallet selection now claims a claimable wallet of the requested type when the user owns
none, instead of creating a new wallet. If the claim fails, sign-in fails.

```swift
// 0.4.0
let result = try await omsWallet.wallet.completeEmailAuth(code: "123456")
for wallet in result.claimableWallets {
    print("Claimable:", wallet.type, wallet.address)
}
```

### Session expiry timestamps

`OMSWalletSession.expiresAt` and `OMSWalletExpiredSession.expiredAt` are now ISO-8601
`String`s instead of `Date`s. `expiresAt` starts as the sign-in's `WalletCredential.expiresAt` and
follows the wallet API's sliding expiry as the SDK refreshes it (see Sliding session expiry);
`expiredAt` is the session's expiry, or the time the SDK found its keychain key replaced by another
process when that came first. `OMSWalletSession.init(expiresAt:auth:)` and `OMSWalletExpiredSession.init` take a
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

### Sliding session expiry

The wallet API now extends a session's expiry while it is used, up to the requested
`sessionLifetimeSeconds`, and ends idle sessions sooner. `OMSWalletSession.expiresAt` is the current
expiry, not a fixed value from sign-in: the SDK refreshes it after restoring a session and while the
session is in use. Read `omsWallet.wallet.session?.expiresAt` again instead of caching the sign-in
`WalletCredential.expiresAt`. A stored session whose expiry has passed may still be active on the wallet API, so unless its
requested lifetime has run out it is restored and the expiry refresh after the restore decides. A
session active in memory that reaches its local expiry ends at once if its lifetime has run out, and
is otherwise checked with the wallet API before it is treated as ended. The check (`GetCredential`)
counts as use, so on iOS it runs once the app is active (right away when it already is): a background
launch or an app extension does not extend an idle session.

An idle session ends about 10 days after its last use, and never after the requested lifetime. With
an accurate device clock and an app that keeps running, an ended session is noticed at its expiry.
When the check cannot reach the wallet API, the SDK keeps the session and retries the check while the
app is active, at most 15 minutes apart; until then `activeWallet` and `session` stay set, and a
wallet call checks with the wallet API first, as before.

When the wallet API reports the session's credential expired or gone (WaaS `KeyExpired` 7203 or
`KeyNotFound` 7202), the SDK ends the session as on local expiry, notifies session-expired observers
once, and throws `.sessionExpired` instead of `.requestFailed`. That includes a rejected
transaction `Execute`, which WaaS refuses before running it: it throws `.sessionExpired` instead of
`.transactionExecutionUnconfirmed`. Status polling after a submitted transaction keeps
`.transactionStatusLookupFailed` and its `txnId`. An `Execute` that WaaS answers with
`TransactionSimulationFailed` (7314, EVM only: the transaction would revert and was never sent) now
throws `.requestFailed` with that upstream error instead of `.transactionExecutionUnconfirmed`. If
the wallet API is unreachable when a session reaches its local expiry, operations throw the network
error (`.requestFailed`) and keep the session instead of throwing `.sessionExpired`.

Requests signed with the session credential now fail after 30 seconds in all, including the time
spent waiting behind other requests of the same credential and signing, with `.requestFailed`
(`retryable == true`, `upstreamError?.name == "WebrpcRequestFailed"`; the generated client wraps the
underlying `URLError.timedOut` in its transport error, so match on those fields rather than on
`URLError`). The call returns at the deadline even while the signer is still running, and
a request whose signing finishes later is never sent. Before, only `URLSession`'s timeout between
received bytes applied, and a request could wait behind a stalled refresh without limit. An
`Execute` that fails before its HTTP request starts (signing failed, or it timed out while waiting
or being signed) now throws `.requestFailed` without a `txnId` instead of
`.transactionExecutionUnconfirmed`, since nothing reached the wallet API; one that was sent and
then failed or timed out is still `.transactionExecutionUnconfirmed`.

When the wallet API answers the expiry check with `WebrpcBadRoute` (a version without
`GetCredential`), the SDK treats the local expiry as final for 15 minutes and then asks again,
instead of for the rest of the client's lifetime.

The SDK's expiry check (`GetCredential`) treats `Unauthorized` (7207) like 7202 and 7203: that
request involves no wallet, so a 7207 means the credential was revoked, and the session ends with
`.sessionExpired` and an `.expired` session change. A 7207 from any other wallet call still throws
`.requestFailed`; the SDK then checks the credential with `GetCredential` in the background, which
ends the session if the credential was revoked and otherwise keeps it.

A request that WaaS rejects for a stale nonce (`PreconditionFailed`, 7206, HTTP 412), for example
when concurrent calls reach it out of order, is now signed again with a fresh nonce and resent, at
most twice, instead of failing on the first rejection. WaaS rejects a stale nonce before running any
method, so a resent `Execute` cannot submit a transaction twice. A third rejection throws
`.requestFailed` (status 412), also from `sendTransaction`, where it is not reported as
`.transactionExecutionUnconfirmed`, because the transaction was never submitted. The same now holds
for an `Execute` refused with `InvalidSignature` (7201), `UsageLimitExceeded` (7205), or
`Unauthorized` (7207), and for a Tron `Execute` refused with `InvalidRequest` (7200) or
`InvalidFeeOption` (7310), which WaaS raises while pricing it again before broadcasting: WaaS
refuses these before submitting anything, so they throw `.requestFailed` with the upstream error and
no `txnId`.

The largest `sessionLifetimeSeconds` the SDK accepts rose from 2,592,000 seconds (30 days) to
15,552,000 (180 days), `WalletClient.maxSessionLifetimeSeconds`. The default rose from 604,800
seconds (7 days) to the same maximum, `WalletClient.defaultSessionLifetimeSeconds`: sign-in calls
that omit `sessionLifetimeSeconds` now request 180 days. A session still ends after 10 days without
use; pass a shorter `sessionLifetimeSeconds` if you need a hard limit. Wallet API versions without
sliding expiry clamp the requested lifetime to their 30-day maximum and have no idle timeout, so the
180-day default gives a fixed 30-day session there.

### One wallet per project in the process

Creating `OMSWallet` again for the same project and environment now returns the same `wallet` and
`indexer` instead of new ones, so instances share one session, active wallet, expiry timer, and set
of session-expired observers, and a stored session is restored once. Previously each instance kept
its own copy of the session, and they could disagree after a sign-out, sign-in, or wallet switch
through another instance. Observers registered through any instance receive every session-expired
event of that project. A publishable key with another key ID for the same project keeps the session
and is used for later requests; another project or environment remains a separate session.

Before each protected operation and expiry check, the SDK now also checks that the keychain still
holds the key the session signed in with. When another process sharing the keychain signed out or
signed in again, the operation fails with `.sessionMissing` without sending anything, and this
process's session ends without deleting the newer session's key or record; a background expiry
check that finds it notifies session-expired observers, with `expiredAt` the time it was found when
the session's expiry had not passed.

Signed wallet API requests are now sent one at a time per signing credential, in the order they are
made, so concurrent calls no longer reach the wallet API out of nonce order. Concurrent calls take
longer in total; each still has its 30-second deadline, which includes the wait. Requests of a new
sign-in, which uses a new key, do not wait for those of the previous credential.

### `WalletImportPrivateKey` string conversion

`WalletImportPrivateKey` now conforms to `CustomStringConvertible`,
`CustomDebugStringConvertible`, and `CustomReflectable`. `String(describing:)`,
`String(reflecting:)`, and string interpolation give the case name with the key redacted, for
example `WalletImportPrivateKey.ethereum(<redacted>)`, instead of the key, and `dump` and `Mirror`
show no children.

### Keychain items stay on the device

The SDK's keychain items (the session metadata, the request nonce, the OIDC redirect state, and the
P-256 signing key) are now stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`: readable only
while the device is unlocked, as before, and never moved to another device from a backup. Items
written by 0.3.x move to this class the next time the SDK writes them. A 0.3.x session is not
restored after upgrading: its record is discarded and its signing key deleted, and the key created
at the next sign-in uses the new class. Restoring a backup onto another device therefore does not carry the session
over; the user signs in again there. On macOS, where the SDK uses the file-based keychain, the
attribute is accepted but has no effect.

### Session keys are generated in the Secure Enclave

On an iOS device the P-256 key that signs wallet API requests is now generated in the Secure Enclave,
usable only to sign and only while the device is unlocked (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
with `privateKeyUsage`); the private key cannot be exported. There is no fallback: if the Secure
Enclave cannot create the key, sign-in fails with `.storageError`. A session restored with a software
key from an earlier build ends as `.expired`, with its wallet and authentication kept for signing in
again, and the next sign-in creates a Secure Enclave key. The iOS Simulator, which has no Secure
Enclave, and macOS keep using a non-extractable keychain key; nothing needs configuring.

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

`SolanaBalance` now exposes `network`, `accountAddress`, `name`, `symbol`,
`decimals`, `balance`, `formattedBalance`, `imageUrl`, `metadataUri`, `verificationStatus`,
`verificationSource`, `priceUSD`, and `balanceUSD` directly. `WalletImportPrivateKey.walletType`,
`WalletClient.defaultSessionLifetimeSeconds`, and
`WalletClient.maxSessionLifetimeSeconds` are now public. Remove app extensions that
declare members with these names on those types. (`TronBalance` is new in 0.4.0.)

### Empty Solana balance metadata

`SolanaBalance` now decodes an empty `imageUrl` or `metadataUri` as `nil`, as `TronBalance` does.

### Indexer model JSON keys

Indexer models now encode and decode only the indexer gateway keys: `TransactionTransfer` uses
`tokenIds`, `TokenMetadata` and `TokenMetadataAsset` use `tokenId`, `ContractTokenBalance` uses
`tokenID`, `Transaction` uses `metaTxnID`, and `NativeTokenBalance` uses `balance`.

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
