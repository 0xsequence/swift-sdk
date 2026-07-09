# OMS Wallet Swift SDK

Build non-custodial OMS Wallet experiences in Swift with email and OIDC auth, secure session restore, message signing, transaction submission, and token balance queries.

**Requirements:** iOS 15+ · macOS 12+

## Before You Start

- Use an OMS publishable key for your project. Use sandbox/dev keys for local development and testnet flows.
- Register any OIDC return URI you use, such as `yourapp://auth/callback`, as an app URL scheme or universal link before testing redirect auth.
- Start with sign-in, message signing, or balance reads. Transaction examples below use Polygon Amoy; mainnet transactions can move real funds.

## Installation

### Swift Package Manager

Add the package in Xcode with **File -> Add Package Dependencies** and enter the following git URL.

```
https://github.com/0xsequence/swift-sdk.git
```

Use the dependency rule **Up to Next Major Version** with version `0.2.0`.

### CocoaPods

Add the pod to your `Podfile`:

```ruby
pod 'oms-wallet-swift-sdk', '0.2.0'
```

## Quick Start

```swift
import OMSWallet

let omsWallet = try OMSWallet(
    publishableKey: "your-publishable-key"
)

try await omsWallet.wallet.startEmailAuth(email: "user@example.com")
let auth = try await omsWallet.wallet.completeEmailAuth(code: "123456")
if let wallet = auth.wallet {
    print("Wallet address:", wallet.address)

    let signature = try await omsWallet.wallet.signMessage(
        network: .polygonAmoy,
        message: "hello from OMS Wallet"
    )
    print("Signature:", signature)

    let balances = try await omsWallet.indexer.getBalances(
        GetBalancesParams(
            walletAddress: wallet.address,
            networks: [.polygon, .base, .arbitrum],
            includeMetadata: true
        )
    )
    print("Balances:", balances.nativeBalances)
}
```

## Overview

`OMSWallet` is the root object for the SDK. Create a single instance at app startup and keep it alive for the session. It constructs the SDK sub-clients and restores any saved secure session automatically.

Pass your OMS publishable key when creating the client. The SDK derives the wallet API URL and indexer URL from the publishable key prefix and project segment.

| Property | Type | Description |
|---|---|---|
| `wallet` | `WalletClient` | Authentication, session, signing, access management, and transaction helpers. |
| `indexer` | `IndexerClient` | Token balance and on-chain query helpers. |

## Security Model

Wallet API requests are signed with a non-extractable Keychain P-256 credential using the `webcrypto-secp256r1` key type. The credential remains Keychain-managed and is not serialized into SDK session storage.

Only completed wallet session metadata is restored automatically, including wallet address, expiry, and auth metadata such as email or OIDC issuer/provider details when available. The SDK checks the cached session expiry before restoring a session. Expired sessions are not activated, and invalid session metadata is cleared; expired session metadata remains in storage as a reauth hint until `signOut()` or a new auth flow clears or replaces it.

## Authentication Flow

OMS supports email-based OTP, OIDC ID-token auth, and OIDC redirect auth. The email two-step flow is:

1. **`startEmailAuth(email:)`** sends a one-time code to the user's inbox.
2. **`completeEmailAuth(code:walletSelection:walletType:sessionLifetimeSeconds:)`** verifies the code. In the default `.automatic` mode it selects the first matching wallet or creates one. The wallet address, wallet ID, and signer metadata are saved to the device keychain.

```swift
try await omsWallet.wallet.startEmailAuth(email: "user@example.com")

// Present your OTP entry UI.
let result = try await omsWallet.wallet.completeEmailAuth(code: "123456")

if let wallet = result.wallet {
    print(wallet.address)
}
let session = omsWallet.wallet.session
print(session.walletAddress ?? "signed out")
if let expiresAt = session.expiresAt { print(expiresAt) }
print(session.auth?.email ?? "unknown")
```

Auth completion methods accept `sessionLifetimeSeconds` when you need a shorter
or longer requested session; the default is one week. Custom values must be from
1 through 2,592,000 seconds (30 days). Use `addSessionExpiredObserver` when your
app needs to react to session expiry:

```swift
let sessionExpiredObservation = omsWallet.wallet.addSessionExpiredObserver { event in
    print("Session expired:", event.session.walletAddress ?? "unknown")
}

// Later, when the observer is no longer needed:
sessionExpiredObservation.cancel()
```

To opt out of automatic activation and drive wallet selection yourself:

```swift
let result = try await omsWallet.wallet.completeEmailAuth(
    code: "123456",
    walletSelection: .manual
)

if case .walletSelection(let pendingSelection) = result {
    // Show pendingSelection.wallets in your app UI.
    try await pendingSelection.selectWallet(walletId: "wallet-id")
    // or:
    // try await pendingSelection.createAndSelectWallet()
}
```

`PendingWalletSelection` values are single-use. They become invalid after a
wallet is selected or created, after sign-out, or after another auth completion.
Using an invalidated pending selection throws `OMSWalletError` with
`code == .walletSelectionStale`.

For OIDC authorization-code redirect flows, start the redirect, open the
returned URL with your browser UI, then safely handle incoming app links.
Google and Apple provider helpers include SDK defaults:

```swift
let started = try await omsWallet.wallet.startOidcRedirectAuth(
    provider: OidcProviders.google(),
    omsRelayReturnUri: "yourapp://auth/callback",
    walletSelection: .manual
)

// Open started.authorizationUrl.

let result = try await omsWallet.wallet.handleOidcRedirectCallback(
    callbackURLString
)
switch result {
case .completed(let wallet):
    print(wallet.address)
case .walletSelection(let pendingSelection):
    // Show pendingSelection.wallets in your app UI.
    try await pendingSelection.selectWallet(walletId: "wallet-id")
    // or:
    // try await pendingSelection.createAndSelectWallet()
case .notOidcRedirectCallback:
    break
case .noPendingAuth:
    break
case .failed(let error):
    print(error.localizedDescription)
}
```

`OidcProviders.google()` uses the SDK default Google client ID, `openid email
profile` scopes, Google offline/consent authorization parameters, and PKCE
auth-code mode. `OidcProviders.apple()` uses the SDK default Apple Services ID,
`openid email` scopes, `response_mode=form_post`, and PKCE auth-code mode. These
helpers are the SDK default OMS-relayed providers:
`startOidcRedirectAuth(provider:omsRelayReturnUri:...)` derives the OMS relay URL
from the publishable-key environment and stores `omsRelayReturnUri` in the OAuth
state so the relay can return to your app callback. Apple `form_post` works
through that relay before returning to your app callback.

To use Google or Apple without the SDK relay, configure that provider as a custom
`OidcProviderConfig` with `providerRedirectUri`; custom providers do not use
`omsRelayReturnUri`.

| Flow | Provider config | App return URL | Provider OAuth callback |
|---|---|---|---|
| SDK default Google/Apple | `OidcProviders.google()` / `OidcProviders.apple()` | `omsRelayReturnUri` | OMS relay callback derived as `{walletApiUrl}/auth/waas/callback/{google|apple}` |
| Custom OIDC provider | Custom `OidcProviderConfig` | `providerRedirectUri` | `providerRedirectUri` |
| Google/Apple without SDK relay | Custom `OidcProviderConfig` for Google or Apple | `providerRedirectUri` | `providerRedirectUri` |

For custom providers, create `OidcProviderConfig` with a required
`providerRedirectUri` and call `startOidcRedirectAuth(provider:...)` without
`omsRelayReturnUri`. The SDK sends `providerRedirectUri` as OAuth `redirect_uri`
and expects the callback URL to match that same URI.

```swift
let acmeProvider = OidcProviderConfig(
    issuer: "https://login.acme.example",
    clientId: "acme-client-id",
    authorizationUrl: "https://login.acme.example/oauth/authorize",
    providerRedirectUri: "yourapp://auth/callback",
    provider: "acme",
    providerLabel: "Acme",
    scopes: ["openid", "email"]
)

let started = try await omsWallet.wallet.startOidcRedirectAuth(provider: acmeProvider)
```

Pass `walletSelection` or `sessionLifetimeSeconds` to `startOidcRedirectAuth`
to store completion preferences with the pending redirect state. Values passed
to `handleOidcRedirectCallback` override pending values; otherwise the SDK uses
automatic wallet selection and a one-week session lifetime. Custom session
lifetime values must be from 1 through 2,592,000 seconds (30 days). Provider
configs can use `.authCode` to omit PKCE parameters or `.authCodePkce` for PKCE.
Providers with omitted or empty `scopes` omit the OAuth `scope` authorization
parameter.

For OIDC ID-token flows such as Google Sign-In, pass the provider token plus
the issuer and audience used to mint it:

```swift
let result = try await omsWallet.wallet.signInWithOidcIdToken(
    idToken: googleIdToken,
    issuer: "https://accounts.google.com",
    audience: "YOUR_WEB_CLIENT_ID"
)

if let wallet = result.wallet {
    print(wallet.address)
}
```

The SDK demo app in `Examples/sdk-demo` includes separate buttons for Google
ID-token auth and Google redirect auth. The ID-token button uses
GoogleSignIn-iOS to mint an ID token for the configured web client ID, then
passes that token to `signInWithOidcIdToken`. To run that path, configure a
Google iOS OAuth client for the demo bundle ID
`technology.polygon.omswallet.demo`, add its reversed client ID as an app URL
scheme, and set `GIDServerClientID` to the web client ID that OMS accepts as the
ID-token audience.

Use `walletSelection: .manual` with `signInWithOidcIdToken` when you want the
same app-driven wallet picker shown in the email example.
Pass `provider` and `providerLabel` for custom ID-token providers when you want
those labels stored in `omsWallet.wallet.session.auth`.

On subsequent launches, an unexpired completed session is restored from secure storage automatically. To end the session:

```swift
try omsWallet.wallet.signOut()
```

## Core Workflows

### Sign and Verify Messages

```swift
let signature = try await omsWallet.wallet.signMessage(
    network: .polygonAmoy,
    message: "hello from OMS Wallet"
)

guard let walletAddress = omsWallet.wallet.walletAddress else { return }

let isValid = try await omsWallet.wallet.isValidMessageSignature(
    network: .polygonAmoy,
    walletAddress: walletAddress,
    message: "hello from OMS Wallet",
    signature: signature
)
```

### Sign Typed Data

```swift
let typedData: JSONValue = .object([
    "domain": .object([
        "name": .string("Example"),
        "version": .string("1"),
        "chainId": .integer(80002)
    ]),
    "message": .object([
        "contents": .string("hello from OMS Wallet")
    ]),
    "primaryType": .string("Message"),
    "types": .object([
        "Message": .array([
            .object([
                "name": .string("contents"),
                "type": .string("string")
            ])
        ])
    ])
])

let signature = try await omsWallet.wallet.signTypedData(
    network: .polygonAmoy,
    typedData: typedData
)

guard let walletAddress = omsWallet.wallet.walletAddress else { return }

let typedDataValid = try await omsWallet.wallet.isValidTypedDataSignature(
    network: .polygonAmoy,
    walletAddress: walletAddress,
    typedData: typedData,
    signature: signature
)
```

### Query Balances

```swift
guard let walletAddress = omsWallet.wallet.walletAddress else { return }

let result = try await omsWallet.indexer.getBalances(
    GetBalancesParams(
        walletAddress: walletAddress,
        networks: [.polygon, .base, .arbitrum],
        includeMetadata: true,
        page: TokenBalancesPageRequest(page: 0, pageSize: 100)
    )
)

for balance in result.balances {
    print(balance.contractAddress ?? "", balance.balance ?? "")
    print(balance.contractInfo?.symbol ?? "", balance.contractInfo?.decimals ?? 0)
}
```

```swift
let nativeBalances = try await omsWallet.indexer.getBalances(
    GetBalancesParams(
        walletAddress: walletAddress,
        networks: [.polygon, .base, .arbitrum],
        includeMetadata: false
    )
)

let balance = nativeBalances.nativeBalances.first { $0.chainId == Int64(Network.polygon.id) }
print(balance?.balance ?? "0")
```

### Query Transaction History

```swift
guard let walletAddress = omsWallet.wallet.walletAddress else { return }

let history = try await omsWallet.indexer.getTransactionHistory(
    GetTransactionHistoryParams(
        walletAddress: walletAddress,
        networks: [.polygonAmoy],
        includeMetadata: true
    )
)

for transaction in history.transactions {
    print(transaction.txnHash, transaction.timestamp)
}
```

### Sending Transactions

Transactions can move real funds on mainnet. Start on a testnet such as Polygon
Amoy, fund the wallet from a faucet, and use a small value before switching to a
production network.

`sendTransaction` and `callContract` use a prepare/execute flow internally:

1. **Prepare** - the server calculates fee options for the transaction.
2. **Select fee** - the SDK picks the default fee option, or your `FeeOptionSelector` picks one.
3. **Execute** - the transaction is submitted.
4. **Poll** - the SDK polls for about 60 seconds and returns once the status is `.executed` or a transaction hash is available.

By default, the SDK uses the first required fee option, or no fee option when the
transaction is sponsored. Transaction mode defaults to `.relayer`; pass
`.native` when you want native mode.

#### First Testnet Transaction

```swift
let value = try parseUnits(value: "0.001", decimals: 18)
let txResult = try await omsWallet.wallet.sendTransaction(
    network: .polygonAmoy,
    to: "0x1111111111111111111111111111111111111111",
    value: value
)
print("Transaction ID:", txResult.txnId)
print("Transaction status:", txResult.status)
print("Transaction hash:", txResult.txnHash ?? "pending")
```

#### Send a Transaction with Full Parameters

```swift
let value = try parseUnits(value: "0.001", decimals: 18)
let txResult = try await omsWallet.wallet.sendTransaction(
    network: .polygonAmoy,
    request: SendTransactionRequest(
        to: "0x1111111111111111111111111111111111111111",
        value: value,
        data: nil,
        mode: .relayer
    )
)
```

#### Call a Smart Contract

```swift
let amount = try parseUnits(value: "0.001", decimals: 18)
let txResult = try await omsWallet.wallet.callContract(
    network: .polygonAmoy,
    contract: "0x3333333333333333333333333333333333333333",
    method: "transfer(address,uint256)",
    args: [
        AbiArg(type: "address", value: .string("0x1111111111111111111111111111111111111111")),
        AbiArg(type: "uint256", value: .string(amount)),
    ]
)
```

To return immediately after execute without status polling, pass
`waitForStatus: false`. You can then call `getTransactionStatus` with the
returned `txnId`.

```swift
let value = try parseUnits(value: "0.001", decimals: 18)
let txResult = try await omsWallet.wallet.sendTransaction(
    network: .polygonAmoy,
    to: "0x1111111111111111111111111111111111111111",
    value: value,
    waitForStatus: false
)

let status = try await omsWallet.wallet.getTransactionStatus(txnId: txResult.txnId)
```

To tune polling, pass `statusPolling`:

```swift
let value = try parseUnits(value: "0.001", decimals: 18)
let txResult = try await omsWallet.wallet.sendTransaction(
    network: .polygonAmoy,
    to: "0x1111111111111111111111111111111111111111",
    value: value,
    statusPolling: TransactionStatusPollingOptions(
        timeoutMs: 30_000,
        intervalMs: 1_000
    )
)
```

Provide `selectFeeOption` on `sendTransaction` or `callContract` to choose
from the returned fee options:

```swift
let value = try parseUnits(value: "0.001", decimals: 18)
let txResult = try await omsWallet.wallet.sendTransaction(
    network: .polygonAmoy,
    to: "0x1111111111111111111111111111111111111111",
    value: value,
    selectFeeOption: .custom { options in
        guard let selected = options.first else { return nil }
        return selected.selection
    }
)
```

Custom selectors receive `FeeOptionWithBalance` values. `balance` is the wallet's
raw indexer balance for that fee token when available, `available` is formatted
with the token decimals, `availableRaw` is the raw integer balance, and
`decimals` is the token decimal count used for formatting. Unsponsored
transactions require the selector to return a fee selection.

## Advanced Configuration

The SDK derives API endpoints from the publishable key. Use the key prefix for
the target environment rather than passing custom endpoint defaults in app code.

| Prefix | API base |
|---|---|
| `pk_dev_sdbx_` | `https://sandbox-api.dev.polygon-dev.technology` |
| `pk_dev_live_` | `https://api.dev.polygon-dev.technology` |
| `pk_stg_sdbx_` | `https://sandbox-api.stg.polygon-dev.technology` |
| `pk_stg_live_` | `https://api.stg.polygon-dev.technology` |
| `pk_sdbx_` | `https://sandbox-api.polygon.technology` |
| `pk_live_` | `https://api.polygon.technology` |

## Supported Networks

Use `Network.supportedNetworks`, `Network.findById(_:)`, and
`Network.findByName(_:)` to bind numeric chain IDs and network names to SDK
networks. `polygonamoy` is also accepted as a lookup alias for `.polygonAmoy`.

```swift
let networks = Network.supportedNetworks
let polygon = Network.findById(137)
let amoy = Network.findById(80002)
let base = Network.findByName("base")
let katana = Network.findByName("katana")
```

| Chain ID | Network | Swift case | Indexer value | Native token |
|---|---|---|---|---|
| `1` | Ethereum | `.mainnet` | `mainnet` | `ETH` |
| `11155111` | Sepolia | `.sepolia` | `sepolia` | `ETH` |
| `137` | Polygon | `.polygon` | `polygon` | `POL` |
| `80002` | Polygon Amoy | `.polygonAmoy` | `amoy` | `POL` |
| `42161` | Arbitrum | `.arbitrum` | `arbitrum` | `ETH` |
| `421614` | Arbitrum Sepolia | `.arbitrumSepolia` | `arbitrum-sepolia` | `ETH` |
| `10` | Optimism | `.optimism` | `optimism` | `ETH` |
| `11155420` | Optimism Sepolia | `.optimismSepolia` | `optimism-sepolia` | `ETH` |
| `8453` | Base | `.base` | `base` | `ETH` |
| `84532` | Base Sepolia | `.baseSepolia` | `base-sepolia` | `ETH` |
| `56` | BSC | `.bsc` | `bsc` | `BNB` |
| `97` | BSC Testnet | `.bscTestnet` | `bsc-testnet` | `BNB` |
| `42170` | Arbitrum Nova | `.arbitrumNova` | `arbitrum-nova` | `ETH` |
| `43114` | Avalanche | `.avalanche` | `avalanche` | `AVAX` |
| `43113` | Avalanche Testnet | `.avalancheTestnet` | `avalanche-testnet` | `AVAX` |
| `747474` | Katana | `.katana` | `katana` | `ETH` |

## Unit Formatting

Use the top-level helpers to convert between display amounts and base-unit integer strings without floating-point precision loss. Fractional precision beyond `decimals` is rounded to the nearest base unit.

```swift
let usdcRaw = try parseUnits(value: "12.34", decimals: 6)
// "12340000"

let rounded = try parseUnits(value: "1.235", decimals: 2)
// "124"

let usdcDisplay = try formatUnits(value: usdcRaw, decimals: 6)
// "12.34"
```

## Reference

### Handle SDK Errors

Public methods throw `OMSWalletError` with stable fields such as `code`,
`operation`, `status`, nullable `retryable`, and `txnId`. When a failure comes
from a remote OMS service response or transport failure, `upstreamError`
contains normalized wallet API or indexer detail for logging. For `OMSWalletError`
values, branch application logic on `code`.

For transaction writes, `.transactionExecutionUnconfirmed` means the SDK has a
`txnId` from preparation, but execute failed before the SDK could confirm
whether the transaction was submitted; do not blindly resend the same write.
`.transactionStatusLookupFailed` means the transaction was submitted, but status
polling failed, so retry status lookup with the returned `txnId`. `retryable`
describes the failed SDK operation, not the whole user intent.

```swift
let value = try parseUnits(value: "0.001", decimals: 18)
do {
    let txResult = try await omsWallet.wallet.sendTransaction(
        network: .polygonAmoy,
        to: "0x1111111111111111111111111111111111111111",
        value: value
    )
    if txResult.status == .pending {
        print("Submitted:", txResult.txnId)
    } else {
        print("Sent:", txResult.txnHash ?? "no hash")
    }
} catch let error as OMSWalletError {
    switch error.code {
    case .sessionMissing, .sessionExpired:
        print("Sign in again")
    case .httpError where error.retryable == true:
        print("Retry:", error.localizedDescription)
    case .transactionExecutionUnconfirmed:
        print("Execution unconfirmed:", error.txnId ?? "unknown")
    case .transactionStatusLookupFailed:
        print("Transaction status lookup failed:", error.txnId ?? "unknown")
    default:
        print("OMS Wallet error:", error.localizedDescription, error.upstreamError as Any)
    }
}
```

See [Public Error Contracts](docs/error-contracts.md) for the full SDK matrix.

### Get a Wallet ID Token

```swift
let idToken = try await omsWallet.wallet.getIdToken()

let scopedIdToken = try await omsWallet.wallet.getIdToken(
    ttlSeconds: 3_600,
    customClaims: [
        "role": .string("member"),
        "features": .array([.string("trading")])
    ]
)
```

### Manage Wallet Access

```swift
let credentials = try await omsWallet.wallet.listAccess()

for try await page in omsWallet.wallet.listAccessPages(pageSize: 25) {
    print(page.credentials)
}

if let credential = credentials.first {
    try await omsWallet.wallet.revokeAccess(targetCredentialId: credential.credentialId)
}
```

## API Reference

See [API.md](./API.md) for the full method and type reference.

## Publishing

See [publishing.md](./publishing.md) for release PR, tag, Swift Package Manager, and CocoaPods publishing steps.

## License

Apache-2.0. See [LICENSE](./LICENSE).
