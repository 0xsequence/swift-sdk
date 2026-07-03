# OMS Wallet (Swift)

A Swift SDK for the OMS (Open Money Stack) platform. Provides email, OIDC ID-token, and OIDC redirect wallet authentication, non-extractable Keychain request signing, keychain session persistence, wallet ID token retrieval with optional TTL and custom claims, on-chain transaction submission with fee selection, message and typed-data signing, signature verification, token balance queries, and base-unit formatting helpers.

**Requirements:** iOS 15+ · macOS 12+

## Installation

### Swift Package Manager

Add the package in Xcode with **File -> Add Package Dependencies** and enter the following git URL.

```
https://github.com/0xsequence/swift-sdk.git
```

### CocoaPods

Add the pod to your `Podfile`:

```ruby
pod 'oms-wallet-swift-sdk', '0.2.0'
```

## Quick Start

```swift
import OMSWallet

let oms = try OMSWallet(
    publishableKey: "pk_dev_sdbx_yourproject_yourkey"
)

try await oms.wallet.startEmailAuth(email: "user@example.com")
let auth = try await oms.wallet.completeEmailAuth(code: "123456")
guard case .walletSelected(_, let wallet, _, _) = auth else {
    fatalError("Expected automatic wallet selection")
}

print("Wallet address:", wallet.address)
print("Session email:", oms.wallet.session.auth?.email ?? "unknown")

let value = try parseUnits(value: "1", decimals: 18)
let txResult = try await oms.wallet.sendTransaction(
    network: .polygon,
    to: "0xRecipient",
    value: value
)
print("Transaction hash:", txResult.txnHash ?? "pending")
```

## Overview

`OMSWallet` is the root object for the SDK. Create a single instance at app startup and keep it alive for the session. It constructs the SDK sub-clients and restores any saved secure session automatically.

Pass your OMS publishable key when creating the client. The SDK derives the Wallet API URL, IndexerGateway URL, and project scope from the publishable key prefix and project segment. The derived project scope is used for signed Wallet API requests and persisted wallet/OIDC redirect state.

| Property | Type | Description |
|---|---|---|
| `wallet` | `WalletClient` | Authentication, session, signing, access management, and transaction helpers. |
| `indexer` | `IndexerClient` | Token balance and on-chain query helpers. |
| `supportedNetworks` | `[Network]` | Supported network list. |

Supported publishable key prefixes route to these API bases:

| Prefix | API base |
|---|---|
| `pk_dev_sdbx_` | `https://sandbox-api.dev.polygon-dev.technology` |
| `pk_dev_live_` | `https://api.dev.polygon-dev.technology` |
| `pk_stg_sdbx_` | `https://sandbox-api.stg.polygon-dev.technology` |
| `pk_stg_live_` | `https://api.stg.polygon-dev.technology` |
| `pk_sdbx_` | `https://sandbox-api.polygon.technology` |
| `pk_live_` | `https://api.polygon.technology` |

## Supported Networks

Use `Network.supportedNetworks` or the `OMSWallet` convenience helpers to bind numeric chain IDs and network names to SDK networks.

```swift
let networks = Network.supportedNetworks
let polygon = oms.findNetworkById(chainId: 137)
let amoy = oms.findNetworkById(chainId: 80002)
let base = oms.findNetworkByName(name: "base")
let katana = oms.findNetworkByName(name: "katana")
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

## Authentication Flow

OMS supports email-based OTP, OIDC ID-token auth, and OIDC redirect auth. The email two-step flow is:

1. **`startEmailAuth(email:)`** sends a one-time code to the user's inbox.
2. **`completeEmailAuth(code:walletSelection:walletType:sessionLifetimeSeconds:)`** verifies the code. In the default `.automatic` mode it selects the first matching wallet or creates one. The wallet address, wallet ID, and signer metadata are saved to the device keychain.

```swift
try await oms.wallet.startEmailAuth(email: "user@example.com")

// Present your OTP entry UI.
let result = try await oms.wallet.completeEmailAuth(code: "123456")

if case .walletSelected(_, let wallet, _, _) = result {
    print(wallet.address)
}
let session = oms.wallet.session
print(session.walletAddress ?? "signed out")
if let expiresAt = session.expiresAt { print(expiresAt) }
print(session.auth?.email ?? "unknown")

oms.wallet.onSessionExpired = { event in
    print("Session expired:", event.expiredAt)
    print("Reauth email:", event.session.auth?.email ?? "unknown")
}
```

Auth completion methods accept `sessionLifetimeSeconds` when you need a shorter
or longer requested session; the default is one week.

To opt out of automatic activation and drive wallet selection yourself:

```swift
enum WalletPickerChoice {
    case existing(Wallet)
    case createNew
}

func showWalletPicker(
    wallets: [Wallet],
    includeCreateNewWallet: Bool
) async -> WalletPickerChoice {
    // Present app UI and return the user's choice.
}

let result = try await oms.wallet.completeEmailAuth(
    code: "123456",
    walletSelection: .manual
)

switch result {
case .walletSelection(let pendingSelection):
    let choice = await showWalletPicker(
        wallets: pendingSelection.wallets,
        includeCreateNewWallet: true
    )

    switch choice {
    case .existing(let wallet):
        try await pendingSelection.selectWallet(walletId: wallet.id)
    case .createNew:
        try await pendingSelection.createAndSelectWallet()
    }
case .walletSelected:
    break
}
```

`PendingWalletSelection` values are single-use. They become invalid after a
wallet is selected or created, after sign-out, or after another auth completion.
Using an invalidated pending selection throws `OmsSdkError` with
`code == .walletSelectionStale`.

For OIDC ID-token flows such as Google Sign-In, pass the provider token plus
the issuer and audience used to mint it:

```swift
let result = try await oms.wallet.signInWithOidcIdToken(
    idToken: googleIdToken,
    issuer: "https://accounts.google.com",
    audience: "YOUR_WEB_CLIENT_ID"
)

if case .walletSelected(_, let wallet, _, _) = result {
    print(wallet.address)
}
```

Use `walletSelection: .manual` with `signInWithOidcIdToken` when you want the
same app-driven wallet picker shown in the email example.
Pass `provider` and `providerLabel` for custom ID-token providers when you want
those labels stored in `oms.wallet.session.auth`.

For OIDC authorization-code redirect flows, start the redirect, open the
returned URL with your browser UI, then safely handle incoming app links.
Google and Apple provider helpers include SDK defaults:

```swift
let started = try await oms.wallet.startOidcRedirectAuth(
    provider: OidcProviders.google(),
    redirectUri: "omsclientswiftdemo://auth/callback",
    walletSelection: .manual
)

// Open started.authorizationUrl.

let result = try await oms.wallet.handleOidcRedirectCallback(
    callbackURLString
)
switch result {
case .completed(let wallet):
    print(wallet.address)
case .walletSelection(let pendingSelection):
    let choice = await showWalletPicker(
        wallets: pendingSelection.wallets,
        includeCreateNewWallet: true
    )

    switch choice {
    case .existing(let wallet):
        try await pendingSelection.selectWallet(walletId: wallet.id)
    case .createNew:
        try await pendingSelection.createAndSelectWallet()
    }
case .notOidcRedirectCallback:
    break
case .noPendingAuth:
    break
case .failed(let error):
    print(error.localizedDescription)
}
```

`OidcProviders.google()` uses the SDK default Google client ID, relay redirect
URI, `openid email profile` scopes, Google offline/consent authorization
parameters, and PKCE auth-code mode. `OidcProviders.apple()` uses the SDK
default Apple Services ID, relay redirect URI, `openid email` scopes,
`response_mode=form_post`, and PKCE auth-code mode. Apple `form_post` works
through the default relay before returning to your app callback; do not bypass
the relay unless your provider response mode can call your app callback
directly.

Pass `walletSelection` or `sessionLifetimeSeconds` to `startOidcRedirectAuth`
to store completion preferences with the pending redirect state. Values passed
to `handleOidcRedirectCallback` override pending values; otherwise the SDK uses
automatic wallet selection and a one-week session lifetime. Provider configs
can use `.authCode` to omit PKCE parameters or `.authCodePkce` for PKCE.
Providers with omitted or empty `scopes` omit the OAuth `scope` authorization
parameter.

Wallet API requests are signed with a non-extractable Keychain P-256 credential using the `webcrypto-secp256r1` key type. Only completed wallet session metadata is restored automatically, including wallet address, expiry, and auth metadata such as email or OIDC issuer/provider details when available. The SDK checks the cached session expiry before restoring a session. Expired sessions are not activated, and invalid session metadata is cleared; expired metadata may remain in storage as a reauth hint until `signOut()` or a new auth flow clears or replaces it. The private credential key remains owned by the Keychain and is not written into SDK session storage.

On subsequent launches, an unexpired completed session is restored from secure storage automatically. To end the session:

```swift
try oms.wallet.signOut()
```

## Transaction Flow

`sendTransaction` and `callContract` use a prepare/execute flow internally:

1. **Prepare** - the server calculates fee options for the transaction.
2. **Select fee** - the SDK picks the default fee option, or your `FeeOptionSelector` picks one.
3. **Execute** - the transaction is submitted.
4. **Poll** - the SDK polls for about 60 seconds and returns once the status is `.executed` or a transaction hash is available.

By default, the SDK uses the first required fee option, or no fee option when the
transaction is sponsored. Transaction mode defaults to `.relayer`; pass
`.native` when you want native mode.

```swift
let value = try parseUnits(value: "1", decimals: 18)
let txResult = try await oms.wallet.sendTransaction(
    network: .polygon,
    to: "0xRecipient",
    value: value
)
print("Transaction ID:", txResult.txnId)
print("Transaction status:", txResult.status)
print("Transaction hash:", txResult.txnHash ?? "pending")
```

To return immediately after execute without status polling, pass
`waitForStatus: false`. You can then call `getTransactionStatus` with the
returned `txnId`.

```swift
let value = try parseUnits(value: "1", decimals: 18)
let txResult = try await oms.wallet.sendTransaction(
    network: .polygon,
    to: "0xRecipient",
    value: value,
    waitForStatus: false
)

let status = try await oms.wallet.getTransactionStatus(txnId: txResult.txnId)
```

To tune polling, pass `statusPolling`:

```swift
let value = try parseUnits(value: "1", decimals: 18)
let txResult = try await oms.wallet.sendTransaction(
    network: .polygon,
    to: "0xRecipient",
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
let value = try parseUnits(value: "1", decimals: 18)
let txResult = try await oms.wallet.sendTransaction(
    network: .polygon,
    to: "0xRecipient",
    value: value,
    selectFeeOption: .custom { options in
        let selected = options[selectedIndex]
        return selected.selection
    }
)
```

Custom selectors receive `FeeOptionWithBalance` values. `balance` is the wallet's
raw indexer balance for that fee token when available, `available` is formatted
with the token decimals, `availableRaw` is the raw integer balance, and
`decimals` is the token decimal count used for formatting. Unsponsored
transactions require the selector to return a fee selection.

## Configuration

### Custom Environment

```swift
let env = OMSWalletEnvironment(
    walletApiUrl: "https://staging-wallet.example.com",
    indexerGatewayUrl: "https://staging-api.example.com/v1/IndexerGateway/"
)

let oms = try OMSWallet(
    publishableKey: "pk_dev_sdbx_yourproject_yourkey",
    environment: env
)
```

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

## Examples

### Sign a Message

```swift
let signature = try await oms.wallet.signMessage(
    network: .polygon,
    message: "Hello from OMS"
)
```

### Verify a Message Signature

```swift
guard let walletAddress = oms.wallet.walletAddress else { return }

let isValid = try await oms.wallet.isValidMessageSignature(
    network: .polygon,
    walletAddress: walletAddress,
    message: "Hello from OMS",
    signature: signature
)
```

### Sign Typed Data

```swift
let typedData: WebRPCJSONValue = .object([
    "domain": .object([
        "name": .string("Example"),
        "version": .string("1"),
        "chainId": .integer(137)
    ]),
    "message": .object([
        "contents": .string("Hello from OMS")
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

let signature = try await oms.wallet.signTypedData(
    network: .polygon,
    typedData: typedData
)
guard let walletAddress = oms.wallet.walletAddress else { return }

let isValid = try await oms.wallet.isValidTypedDataSignature(
    network: .polygon,
    walletAddress: walletAddress,
    typedData: typedData,
    signature: signature
)
```

### Send a Transaction with Full Parameters

```swift
let value = try parseUnits(value: "1", decimals: 18)
let txResult = try await oms.wallet.sendTransaction(
    network: .polygon,
    request: SendTransactionRequest(
        to: "0xRecipient",
        value: value,
        data: nil,
        mode: .relayer
    )
)
```

### Call a Smart Contract

```swift
let amount = try parseUnits(value: "1", decimals: 18)
let txResult = try await oms.wallet.callContract(
    network: .polygon,
    contract: "0xTokenContract",
    method: "transfer(address,uint256)",
    args: [
        AbiArg(type: "address", value: .string("0xRecipient")),
        AbiArg(type: "uint256", value: .string(amount)),
    ]
)
```

### Handle SDK Errors

Public methods throw `OmsSdkError` with stable fields such as `code`,
`operation`, `status`, nullable `retryable`, and `txnId`. When a failure comes
from a remote OMS service response or transport failure, `upstreamError`
contains normalized WaaS or Indexer detail for logging. Application logic should
usually branch on `code`.

For transaction writes, `.transactionExecutionUnconfirmed` means the SDK has a
`txnId` from preparation, but execute failed before the SDK could confirm
whether the transaction was submitted; do not blindly resend the same write.
`.transactionStatusLookupFailed` means the transaction was submitted, but status
polling failed, so retry status lookup with the returned `txnId`. `retryable`
describes the failed SDK operation, not the whole user intent.

```swift
let value = try parseUnits(value: "1", decimals: 18)
do {
    let txResult = try await oms.wallet.sendTransaction(
        network: .polygon,
        to: "0xRecipient",
        value: value
    )
    if txResult.status == .pending {
        print("Submitted:", txResult.txnId)
    } else {
        print("Sent:", txResult.txnHash ?? "no hash")
    }
} catch let error as OmsSdkError {
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

### Query Token Balances

```swift
guard let walletAddress = oms.wallet.walletAddress else { return }

let result = try await oms.indexer.getBalances(
    GetBalancesParams(
        walletAddress: walletAddress,
        networks: [.polygon],
        includeMetadata: true,
        page: TokenBalancesPageRequest(page: 0, pageSize: 100)
    )
)

for balance in result.balances {
    print(balance.contractAddress ?? "", balance.balance ?? "")
    print(balance.contractInfo?.symbol ?? "", balance.contractInfo?.decimals ?? 0)
}
```

### Query Native Token Balance

```swift
guard let walletAddress = oms.wallet.walletAddress else { return }

let result = try await oms.indexer.getBalances(
    GetBalancesParams(
        walletAddress: walletAddress,
        networks: [.polygon],
        includeMetadata: false
    )
)

let balance = result.nativeBalances.first { $0.chainId == Int64(Network.polygon.id) }
print(balance?.balance ?? "0")
```

### Query Transaction History

```swift
guard let walletAddress = oms.wallet.walletAddress else { return }

let history = try await oms.indexer.getTransactionHistory(
    GetTransactionHistoryParams(
        walletAddress: walletAddress,
        networks: [.polygon],
        includeMetadata: true
    )
)

for transaction in history.transactions {
    print(transaction.txnHash, transaction.timestamp)
}
```

### Get a Wallet ID Token

```swift
let idToken = try await oms.wallet.getIdToken()

let scopedIdToken = try await oms.wallet.getIdToken(
    ttlSeconds: 3_600,
    customClaims: [
        "role": .string("member"),
        "features": .array([.string("trading")])
    ]
)
```

### Manage Wallet Access

```swift
let credentials = try await oms.wallet.listAccess()

for try await page in oms.wallet.listAccessPages(pageSize: 25) {
    print(page.credentials)
}

if let credential = credentials.first {
    try await oms.wallet.revokeAccess(targetCredentialId: credential.credentialId)
}
```

## API Reference

See [API.md](./API.md) for the full method and type reference.

## Publishing

See [publishing.md](./publishing.md) for release PR, tag, Swift Package Manager, and CocoaPods publishing steps.
