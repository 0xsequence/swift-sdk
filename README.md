# OMS Wallet Swift SDK

Build non-custodial OMS Wallet experiences in Swift with email and OIDC auth, secure session restore, message signing, transaction submission, and token balance queries.

[API reference](https://docs.polygon.technology/wallets/sdk/swift/api-reference)

**Requirements:** Swift 6.2+ · iOS 15+ · macOS 12+

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

Use the dependency rule **Up to Next Minor Version** with version `0.3.1`. While the SDK is
pre-1.0, minor releases can contain breaking changes (see [MIGRATION.md](MIGRATION.md)).

To add the package from a `Package.swift` manifest instead:

```swift
dependencies: [
    .package(url: "https://github.com/0xsequence/swift-sdk.git", .upToNextMinor(from: "0.3.1"))
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "OMSWallet", package: "swift-sdk")
        ]
    )
]
```

### CocoaPods

Add the pod to your `Podfile`:

```ruby
pod 'oms-wallet-swift-sdk', '0.3.1'
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
        network: .amoy,
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

`OMSWallet` is the only public composition root. Access `WalletClient` and
`IndexerClient` through `omsWallet.wallet` and `omsWallet.indexer`; their
initialization and endpoint environment are SDK-managed.

Pass your OMS publishable key when creating the client. The SDK derives the wallet API URL and indexer URL from the publishable key prefix and project segment.

| Property | Type | Description |
|---|---|---|
| `wallet` | `WalletClient` | Authentication, session, signing, access management, and transaction helpers. |
| `indexer` | `IndexerClient` | Token balance and on-chain query helpers. |

## Security Model

Wallet API requests are signed with a non-extractable Keychain P-256 credential using the `ecdsa-p256-sha256` signing algorithm. The credential remains Keychain-managed and is not serialized into SDK session storage.

Only completed wallet session metadata is restored automatically, including the active wallet (ID, type, address, reference, and key origin), expiry, and auth metadata such as email or OIDC issuer/provider details when available. The SDK checks the cached session expiry before restoring a session. Expired sessions are not activated, and invalid session metadata is cleared; expired session metadata remains in storage as a reauth hint until `signOut()` or a new auth flow clears or replaces it.

## Authentication Flow

OMS supports email-based OTP, OIDC ID-token auth, and OIDC redirect auth. The email two-step flow is:

1. **`startEmailAuth(email:sessionLifetimeSeconds:)`** validates the requested session lifetime and sends a one-time code to the user's inbox.
2. **`completeEmailAuth(code:walletSelection:walletType:)`** verifies the code using the session lifetime chosen when the flow started. In the default `.automatic` mode it selects the first matching wallet or creates one. The active wallet and signer metadata are saved to the device keychain.

```swift
try await omsWallet.wallet.startEmailAuth(email: "user@example.com")

// Present your OTP entry UI.
let result = try await omsWallet.wallet.completeEmailAuth(code: "123456")

if let wallet = result.wallet {
    print(wallet.address)
}
if let activeWallet = omsWallet.wallet.activeWallet,
   let session = omsWallet.wallet.session {
    print(activeWallet.type, activeWallet.address)
    print(session.expiresAt)
    print(session.auth.email ?? "unknown")
} else {
    print("signed out")
}
```

`activeWallet` is a `Wallet`, the same type `listWallets()` returns, or `nil` when signed out.
`session` holds the expiry and auth metadata and is non-`nil` exactly when `activeWallet` is. Its
`expiresAt` is the ISO-8601 timestamp returned by the wallet API, the same value as
`WalletCredential.expiresAt`.

Pass `sessionLifetimeSeconds` to `startEmailAuth` when you need a shorter or
longer email session. The default is `WalletClient.defaultSessionLifetimeSeconds` (one week), and
custom values must be from 1 through `WalletClient.maxSessionLifetimeSeconds` (2,592,000 seconds,
30 days). The SDK validates the value before sending
the one-time code. Use `addSessionExpiredObserver` when your app needs to react
to session expiry:

```swift
let sessionExpiredObservation = omsWallet.wallet.addSessionExpiredObserver { event in
    // `wallet` is nil when the credential expired during a pending manual wallet selection.
    print("Session expired:", event.wallet?.address ?? "no wallet selected", event.expiredAt)
}

// Later, when the observer is no longer needed:
sessionExpiredObservation.cancel()
```

Session-expiry observers are `@Sendable` and always run on `MainActor`.

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

For native iOS sign-in, prefer an OIDC ID-token flow when the provider SDK can
supply a token. For example, pass a Google Sign-In ID token to OMS with the
issuer and audience used to mint it:

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

Use `walletSelection: .manual` when the app should present its own wallet
picker. Pass `provider` and `providerLabel` for custom ID-token providers when
those labels should be stored in `omsWallet.wallet.session?.auth`.

For OIDC authorization-code redirect flows, start the redirect, open the
returned URL with your browser UI, then safely handle incoming app links.
Google and Apple use fixed SDK-owned relay provider values:

```swift
let started = try await omsWallet.wallet.startOIDCRedirectAuth(
    provider: OMSRelayOIDCProviders.google,
    omsRelayReturnURI: "yourapp://auth/callback",
    walletSelection: .manual
)

// Open started.authorizationURL.

do {
    let result = try await omsWallet.wallet.handleOIDCRedirectCallback(
        callbackURLString
    )
    switch result {
    case .completed(.walletSelected(let wallet, let wallets, let credential)):
        print(wallet.address, wallets.count, credential.credentialId)
    case .completed(.walletSelection(let pendingSelection)):
        // Show pendingSelection.wallets in your app UI.
        try await pendingSelection.selectWallet(walletId: "wallet-id")
    case .notOIDCRedirectCallback, .noPendingAuth:
        break
    }
} catch let error as OMSWalletError {
    print(error.code, error.localizedDescription)
}
```

`OMSRelayOIDCProviders.google` uses the fixed SDK default Google client ID, `openid email
profile` scopes, Google offline/consent authorization parameters, and PKCE
auth-code mode. `OMSRelayOIDCProviders.apple` uses the fixed SDK default Apple Services ID,
`openid email` scopes, `response_mode=form_post`, and PKCE auth-code mode. These
values contain no caller-editable client ID or provider configuration.
`startOIDCRedirectAuth(provider:omsRelayReturnURI:...)` derives the OMS relay URL
from the publishable-key environment and stores `omsRelayReturnURI` in the OAuth
state so the relay can return to your app callback. Apple `form_post` works
through that relay before returning to your app callback.

To use Google or Apple without the SDK relay, configure that provider as a custom
`CustomOIDCProviderConfiguration` with `providerRedirectURI`; custom providers do
not accept `omsRelayReturnURI`.

| Flow | Provider config | App return URL | Provider OAuth callback |
|---|---|---|---|
| SDK default Google/Apple | `OMSRelayOIDCProviders.google` / `.apple` | `omsRelayReturnURI` | OMS relay callback derived from the wallet API base URL as `/auth/waas/callback/{google|apple}` |
| Custom OIDC provider | `CustomOIDCProviderConfiguration` | `providerRedirectURI` | `providerRedirectURI` |
| Google/Apple without SDK relay | Custom configuration for Google or Apple | `providerRedirectURI` | `providerRedirectURI` |

For custom providers, create `CustomOIDCProviderConfiguration` with a required
`providerRedirectURI` and call `startOIDCRedirectAuth(provider:...)`. The SDK
sends `providerRedirectURI` as OAuth `redirect_uri`
and expects the callback URL to match that same URI.

```swift
let acmeProvider = CustomOIDCProviderConfiguration(
    issuer: "https://login.acme.example",
    clientID: "acme-client-id",
    authorizationURL: "https://login.acme.example/oauth/authorize",
    providerRedirectURI: "yourapp://auth/callback",
    provider: "acme",
    providerLabel: "Acme",
    scopes: ["openid", "email"]
)

let started = try await omsWallet.wallet.startOIDCRedirectAuth(provider: acmeProvider)
```

Pass `walletSelection` or `sessionLifetimeSeconds` to `startOIDCRedirectAuth`
to store completion preferences with the pending redirect state. Values passed
to `handleOIDCRedirectCallback` override pending values; otherwise the SDK uses
automatic wallet selection and a one-week session lifetime. Custom session
lifetime values must be from 1 through 2,592,000 seconds (30 days). Provider
configs can use `.authCode` to omit PKCE parameters or `.authCodePKCE` for PKCE.
Providers with omitted or empty `scopes` omit the OAuth `scope` authorization
parameter.

The SDK demo app in `Examples/sdk-demo` includes separate buttons for Google
ID-token auth and Google redirect auth. The ID-token button uses
GoogleSignIn-iOS to mint an ID token for the configured web client ID, then
passes that token to `signInWithOidcIdToken`. To run that path, configure a
Google iOS OAuth client for the demo bundle ID
`technology.polygon.omswallet.demo`, add its reversed client ID as an app URL
scheme, and set `GIDServerClientID` to the web client ID that OMS accepts as the
ID-token audience.

On iOS, prefer `signInWithOidcIdToken` over defining a custom Google or Apple
redirect configuration when the native provider SDK can supply an ID token.
Use custom redirect auth for caller-owned or browser-only provider flows.

On subsequent launches, an unexpired completed session is restored from secure storage automatically. To end the session:

```swift
try omsWallet.wallet.signOut()
```

### Import a Wallet

Wallet import verifies AWS Nitro enclave attestations against measurements managed by each OMS
environment. Development uses Nitro debug mode, whose all-zero PCR0 does not identify a specific
enclave image; use only disposable test keys there. Staging and Production accept only the release
measurements shipped by the SDK.

```swift
let omsWallet = try OMSWallet(publishableKey: "your-publishable-key")

let imported = try await omsWallet.wallet.importWallet(
    privateKey: .ethereum("0x..."),
    reference: "Imported wallet"
)
print(imported.wallet.keyOrigin == .imported)
```

Ethereum and Tron imports (both secp256k1) accept a 32-byte raw scalar or 64 hexadecimal digits,
optionally prefixed with `0x`, through `.ethereum`/`.ethereumBytes` or `.tron`/`.tronBytes`. Solana imports accept a 32-byte seed or 64-byte keypair as raw bytes, or the base58 encoding
of either. The SDK does not persist plaintext imported keys. For
caller-managed HPKE flows, use `getWalletImportRecipientKey(cipherSuite:)` and then
`importEncryptedWallet(walletType:keyMaterial:reference:)`; both responses remain attestation
verified.

## Core Workflows

### Sign and Verify Messages

```swift
let signature = try await omsWallet.wallet.signMessage(
    network: .amoy,
    message: "hello from OMS Wallet"
)

// Omit `walletAddress` to verify against the active wallet, or pass any address to verify
// without a session.
let isValid = try await omsWallet.wallet.isValidMessageSignature(
    network: .amoy,
    message: "hello from OMS Wallet",
    signature: signature
)
```

Every `isValid…Signature` method takes an optional `walletAddress`. With an address it needs no
session and ignores the active wallet. Without one it uses the active wallet's address: it throws
`.sessionMissing` when signed out and `.validationError` when the active wallet belongs to another
chain family (for example an Ethereum wallet passed to `isValidSolanaMessageSignature`).

For a selected Solana wallet, use the Solana-specific message methods; off-chain messages do not
require a cluster:

```swift
let signature = try await omsWallet.wallet.signSolanaMessage(message: "hello from Solana")
let valid = try await omsWallet.wallet.isValidSolanaMessageSignature(
    message: "hello from Solana",
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
    network: .amoy,
    typedData: typedData
)

let typedDataValid = try await omsWallet.wallet.isValidTypedDataSignature(
    network: .amoy,
    typedData: typedData,
    signature: signature
)
```

### Query Balances

```swift
guard let activeWallet = omsWallet.wallet.activeWallet, activeWallet.type == .ethereum else { return }
let walletAddress = activeWallet.address

let result = try await omsWallet.indexer.getBalances(
    GetBalancesParams(
        walletAddress: walletAddress,
        networks: [.polygon, .base, .arbitrum],
        includeMetadata: true,
        page: TokenBalancesPageRequest(page: 0, pageSize: 100)
    )
)

for balance in result.balances {
    print(balance.contractAddress, balance.balance)
    print(balance.contractInfo?.symbol ?? "", balance.contractInfo?.decimals ?? 0)
}
```

Query native SOL and fungible token balances through the Solana indexer gateway:

```swift
let result = try await omsWallet.indexer.getSolanaBalances(
    GetSolanaBalancesParams(
        walletAddress: "solana-wallet-address",
        networks: [.mainnet, .devnet]
    )
)
for balance in result.balances {
    print(balance)
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
guard let activeWallet = omsWallet.wallet.activeWallet, activeWallet.type == .ethereum else { return }
let walletAddress = activeWallet.address

let history = try await omsWallet.indexer.getTransactionHistory(
    GetTransactionHistoryParams(
        walletAddress: walletAddress,
        networks: [.amoy],
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
4. **Poll** - by default, the SDK polls for about 60 seconds and returns when it sees a terminal status, a transaction hash, or the polling deadline.

By default, the SDK uses the first required fee option, or no fee option when the
transaction is sponsored. Transaction mode defaults to `.relayer`; pass
`.native` when you want native mode.

#### First Testnet Transaction

```swift
let value = try parseUnits(value: "0.001", decimals: 18)
let txResult = try await omsWallet.wallet.sendTransaction(
    network: .amoy,
    to: "0x1111111111111111111111111111111111111111",
    value: value
)
print("Transaction ID:", txResult.txnId)
print("Transaction status:", txResult.status)
print("Transaction hash:", txResult.txnHash ?? "pending")
print("Status resolution:", txResult.statusResolution)
```

`statusResolution` is `.resolved` when polling observes a terminal status or
transaction hash, `.timedOut` when the polling deadline expires first, and
`.notRequested` when `waitForStatus` is `false`.

#### Send a Transaction with Full Parameters

```swift
let value = try parseUnits(value: "0.001", decimals: 18)
let txResult = try await omsWallet.wallet.sendTransaction(
    network: .amoy,
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
    network: .amoy,
    contractAddress: "0x3333333333333333333333333333333333333333",
    method: "transfer",
    args: [
        AbiArg(type: "address", value: .string("0x1111111111111111111111111111111111111111")),
        AbiArg(type: "uint256", value: .string(amount)),
    ]
)
```

Pass the bare function name, such as `"transfer"`, not a signature such as
`"transfer(address,uint256)"`. The wallet service builds the signature from the argument types, and
the SDK rejects any other value with `.validationError` before sending a request.

To return immediately after execute without status polling, pass
`waitForStatus: false`. You can then call `getTransactionStatus` with the
returned `txnId`. The immediate response has `statusResolution == .notRequested`.

```swift
let value = try parseUnits(value: "0.001", decimals: 18)
let txResult = try await omsWallet.wallet.sendTransaction(
    network: .amoy,
    to: "0x1111111111111111111111111111111111111111",
    value: value,
    waitForStatus: false
)

let status = try await omsWallet.wallet.getTransactionStatus(txnId: txResult.txnId)
```

For a selected Solana wallet, amounts are smallest units (lamports for SOL and base units for SPL
tokens):

```swift
let result = try await omsWallet.wallet.sendSolanaTransfer(
    network: .devnet,
    asset: "SOL",
    to: "solana-recipient-address",
    amount: "1000000"
)
```

To tune polling, pass `statusPolling`:

```swift
let value = try parseUnits(value: "0.001", decimals: 18)
let txResult = try await omsWallet.wallet.sendTransaction(
    network: .amoy,
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
    network: .amoy,
    to: "0x1111111111111111111111111111111111111111",
    value: value,
    selectFeeOption: .custom { options in
        if options.isEmpty {
            // Present the sponsored transaction for confirmation here.
            return nil
        }
        guard let selected = options.first else { return nil }
        return selected.selection
    }
)
```

Custom selectors receive `FeeOptionWithBalance` values. For Ethereum fees, `balance`
contains the matching `TokenBalance` when available. For Ethereum, Solana, and Tron fees,
`available` is formatted with the token decimals, `availableRaw` is the raw integer
balance, and `decimals` is the token decimal count used for formatting. This lets
`.firstAvailable` select the first affordable option on any network family. Unsponsored
transactions require the selector to return a fee selection. Sponsored transactions
invoke the selector with an empty array; return `nil` after acknowledging the free fee,
or throw to stop execution. `.firstAvailable` returns `nil` for that empty array and
continues execution as before.

### Tron Wallets

Tron wallets are EOAs and always execute in native mode, so the Tron methods take no `mode`
parameter. Create one with `createWallet(walletType: .tron)`, sign in with `walletType: .tron`, or
import a secp256k1 private key with `.tron(_:)`. Tron addresses are Base58Check strings (`T…`).
Supported networks are `TronNetwork.mainnet` and `TronNetwork.nile`. TRC-10 tokens are not
supported.

```swift
let created = try await omsWallet.wallet.createWallet(walletType: .tron)

let signature = try await omsWallet.wallet.signTronMessage(message: "some message to sign")
let isValid = try await omsWallet.wallet.isValidTronMessageSignature(
    walletAddress: created.wallet.address,
    message: "some message to sign",
    signature: signature
)

// Replace with the Base58Check (`T…`) address that should receive the funds.
let recipient = "<recipient T… address>"

// TRX transfer. Values are in sun (1 TRX = 1,000,000 sun).
let trxTransfer = try await omsWallet.wallet.sendTronTransaction(
    network: .nile,
    to: recipient,
    value: try parseUnits(value: "1", decimals: 6)
)

// TRC-20 transfer. The wallet service ABI-encodes the call; address arguments accept `T…`.
let trc20Transfer = try await omsWallet.wallet.callTronContract(
    network: .nile,
    contractAddress: "TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf",
    method: "transfer",
    args: [
        AbiArg(type: "address", value: .string(recipient)),
        AbiArg(type: "uint256", value: .string("1000000")),
    ]
)
```

`signTronTypedData(typedData:)` and `isValidTronTypedDataSignature(walletAddress:typedData:signature:)`
sign and verify TIP-712 typed data, whose address values may be Base58Check.

Omitting `data` from `sendTronTransaction` sends a plain TRX transfer. Passing `data`, even `"0x"`,
makes the transaction a contract call: `"0x"` calls the recipient contract's payable fallback.

Tron transactions report `.pending` with a `txnHash` until the block is solidified (about a
minute), so status polling returns as soon as the hash is available.

Every Tron account gets a daily free bandwidth allowance (600 points, about two TRX transfers), so
prepared Tron transactions are often sponsored even without a relayer. When the allowance is spent,
WaaS quotes the TRX to burn as a single native fee option, which a fee selector receives like any
other fee option.

Use `getTronBalances` for TRX and TRC-20 balances. Omit `networks` to query both Tron Mainnet and
Nile, or pass either network explicitly. Results have the same structure as `getSolanaBalances`:
precision-safe raw and formatted balance strings, with TRC-20 entries identified by
`tokenStandard` and `contractAddress` where Solana token entries use `tokenProgram` and
`mintAddress`. `TronBalance` and `SolanaBalance` expose the fields shared by both cases (`network`,
`accountAddress`, `symbol`, `decimals`, `balance`, `formattedBalance`, and so on) directly, so you
only need to switch for the token-specific fields. Pass `contractAddresses` or `excludedContractAddresses` to filter tokens.
Individual network failures are reported in `errors` without discarding balances returned by the
other requested network.

```swift
let balances = try await omsWallet.indexer.getTronBalances(
    GetTronBalancesParams(walletAddress: created.wallet.address, networks: [.nile])
)

for balance in balances.balances {
    switch balance {
    case .native(let trx):
        print(trx.network, trx.symbol, trx.formattedBalance)
    case .fungibleToken(let token):
        print(token.network, token.contractAddress, token.symbol, token.formattedBalance)
    }
}
```

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
networks. `findByName(_:)` matches the indexer value in the table below, ignoring case and
surrounding whitespace.

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
| `80002` | Polygon Amoy | `.amoy` | `amoy` | `POL` |
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

Solana uses the separate `SolanaNetwork` type, not `Network`:

| Swift case | Raw value |
|---|---|
| `SolanaNetwork.devnet` | `solana:devnet` |
| `SolanaNetwork.mainnet` | `solana:mainnet` |

`SolanaNetwork.mainnet` is distinct from `Network.mainnet`, which is Ethereum mainnet.

Tron uses the separate `TronNetwork` type:

| Swift case | Raw value |
|---|---|
| `TronNetwork.mainnet` | `tron:mainnet` |
| `TronNetwork.nile` | `tron:nile` |

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
polling failed, so retry status lookup with the returned `txnId`.
`.walletSelectionInFlight` means another action on the same `PendingWalletSelection`
is still running; wait for it to finish before starting another. `retryable`
describes the failed SDK operation, not the whole user intent.

`upstreamError.service` is `.waas` or `.indexer` (raw values `"waas"` and `"indexer"`), and
`upstreamError.code` is a string; numeric WebRPC codes are stringified (for example `"7313"`).
Wallet import reports an address that is already managed as `.walletAddressAlreadyImported`
(status `409`, `retryable == false`); select the existing wallet or use a different key.

```swift
let value = try parseUnits(value: "0.001", decimals: 18)
do {
    let txResult = try await omsWallet.wallet.sendTransaction(
        network: .amoy,
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
let grants = try await omsWallet.wallet.listAccess()

for try await page in omsWallet.wallet.listAccessPages(pageSize: 25) {
    print(page.grants)
}

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

For an owner-approved smart session, inspect the remote credential before showing consent, then
authorize bounded EVM transfer grants. The returned wallet and session IDs can be shared with the
remote backend; backend credential registration and execution stay outside this SDK surface. WaaS
caps the requested session expiry at the remote credential's expiry.

```swift
import Foundation

let credentialId = "remote-credential-id"
let metadata = try await omsWallet.wallet.inspectRemoteCredential(credentialId: credentialId)
// Render these returned public fields in your app's consent UI before authorizing access.
print(metadata.appName, metadata.appUrl)

let requestedExpiry = ISO8601DateFormatter().string(
    from: Date().addingTimeInterval(3_600)
)

let session = try await omsWallet.wallet.authorizeRemoteAccess(
    credentialId: credentialId,
    network: .polygon,
    grants: [
        .nativeTransfer(
            to: "0x1111111111111111111111111111111111111111",
            limit: "1000000000000000"
        )
    ],
    expiresAt: requestedExpiry
)

let details = try await omsWallet.wallet.getRemoteAccessSession(sessionId: session.sessionId)
let usage = try await omsWallet.wallet.getRemoteAccessSessionUsage(
    sessionId: session.sessionId,
    network: .polygon
)
try await omsWallet.wallet.revokeAccess(
    credentialId: credentialId,
    sessionId: session.sessionId
)
```

## API Reference

See [API.md](./API.md) for the full method and type reference.

When upgrading from `0.3.x`, see [MIGRATION.md](./MIGRATION.md) for the breaking changes in
`0.4.0`.

## Publishing

See [publishing.md](./publishing.md) for release PR, tag, Swift Package Manager, and CocoaPods publishing steps.

## License

Apache-2.0. See [LICENSE](./LICENSE).
