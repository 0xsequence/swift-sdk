# OMS SDK (Swift) — API Reference

## Table of Contents

- [OMSClient](#omsclient)
- [WalletClient](#walletclient)
- [IndexerClient](#indexerclient)
- [Formatting Helpers](#formatting-helpers)
- [Types](#types)
  - [Network](#network)
  - [OMSClientIdentity](#omsclientidentity)
  - [SessionState](#sessionstate)
  - [SessionLoginType](#sessionlogintype)
  - [OMSClientEnvironment](#omsclientenvironment)
  - [FeeOptionSelector](#feeoptionselector)
  - [TransactionError](#transactionerror)
  - [UnitConversionError](#unitconversionerror)
  - [SendTransactionRequest](#sendtransactionrequest)
  - [TokenBalancesResult](#tokenbalancesresult)
  - [TokenBalancesPage](#tokenbalancespage)
  - [TokenBalance](#tokenbalance)
  - [CredentialInfo](#credentialinfo)
  - [WebRPCJSONValue](#webrpcjsonvalue)

---

## OMSClient

The top-level entry point for the SDK. Requires iOS 15+ or macOS 12+.

```swift
let oms = OMSClient(projectAccessKey: "your-key", projectId: "your-project-id")
```

### init

```swift
init(
    projectAccessKey: String,
    projectId: String,
    environment: OMSClientEnvironment = OMSClientEnvironment()
)
```

| Parameter | Type | Description |
|---|---|---|
| `projectAccessKey` | `String` | OMS project access key. |
| `projectId` | `String` | OMS project ID. Used as the signed Wallet API request scope and keychain namespace. |
| `environment` | `OMSClientEnvironment` | API endpoint configuration. |

### Properties

| Name | Type | Description |
|---|---|---|
| `wallet` | `WalletClient` | Authentication, signing, access, and transaction helper. |
| `indexer` | `IndexerClient` | Token balance query helper. |
| `supportedNetworks` | `[Network]` | Supported SDK network list. |

### network

```swift
func network(chainId: String) -> Network?
func network(chainId: Int) -> Network?
func network(name: String) -> Network?
```

Returns the supported `Network` for a numeric chain ID or canonical network name, or `nil` when the chain is not supported.

---

## WalletClient

Accessed via `oms.wallet`. Manages wallet authentication, non-extractable Keychain request signing, keychain session persistence, signing, signature verification, and transaction submission.

### init

```swift
init(
    projectAccessKey: String,
    projectId: String,
    environment: OMSClientEnvironment = OMSClientEnvironment()
)
```

Most apps create a wallet client through `OMSClient`. Use this initializer only when constructing `WalletClient` directly.

### walletAddress

```swift
var walletAddress: String
```

The on-chain address of the active wallet. Empty until a wallet is restored or activated by `completeEmailAuth`, `useWallet`, or `createWallet`.

### walletId

```swift
var walletId: String
```

The server-side wallet ID. Empty until a wallet is restored or activated by `completeEmailAuth`, `useWallet`, or `createWallet`.

### session

```swift
var session: SessionState
```

Snapshot of the currently completed wallet session for this wallet client.

### canResumeOidcRedirectAuth

```swift
var canResumeOidcRedirectAuth: Bool
```

Whether there is a persisted OIDC redirect flow waiting for its callback URL.

### startEmailAuth

```swift
func startEmailAuth(email: String) async throws
```

Sends a one-time passcode to the provided email address.

### completeEmailAuth

```swift
func completeEmailAuth(
    code: String,
    walletType: WalletType = .ethereum,
    walletSelection: WalletSelectionBehavior = .automatic
) async throws -> CompleteAuthResult
```

Verifies the OTP code. With `.automatic`, selects the first existing wallet
matching `walletType`, or creates and selects one when none exists. With
`.manual`, returns a pending wallet selection without selecting or creating a
wallet.

### WalletSelectionBehavior

```swift
enum WalletSelectionBehavior {
    case automatic
    case manual
}
```

### PendingWalletSelection

```swift
final class PendingWalletSelection {
    let walletType: WalletType
    let wallets: [Wallet]
    let credential: CredentialInfo

    func selectWallet(walletId: String) async throws -> WalletActivationResult
    func createAndSelectWallet(reference: String? = nil) async throws -> WalletActivationResult
}
```

`wallets` is filtered to `walletType`. `selectWallet(walletId:)` rejects wallet
IDs that are not in that filtered list.

In manual mode, apps should present `wallets` plus a create-new-wallet action,
then call `selectWallet(walletId:)` or `createAndSelectWallet(reference:)` from
that user choice. Automatic "first wallet" selection belongs to
`WalletSelectionBehavior.automatic`, not manual mode. A pending selection is
single-use and is invalidated by successful wallet selection, sign-out, or a
new auth completion; using an invalidated selection throws
`WalletAuthError.staleWalletSelection`.

### CompleteAuthResult

```swift
enum CompleteAuthResult {
    case walletSelected(
        walletAddress: String,
        wallet: Wallet,
        wallets: [Wallet],
        credential: CredentialInfo
    )
    case walletSelection(PendingWalletSelection)
}
```

### OIDC Redirect Auth

```swift
struct OidcProviderConfig {
    let issuer: String
    let clientId: String
    let authorizationUrl: String
    let scopes: [String]
    let relayRedirectUri: String?
    let authorizeParams: [String: String]
}
```

```swift
enum OidcProviders {
    static func google(
        clientId: String = OidcProviders.defaultGoogleClientId,
        relayRedirectUri: String? = OidcProviders.defaultRelayRedirectUri,
        scopes: [String] = ["openid", "email", "profile"],
        authorizeParams: [String: String] = [:]
    ) -> OidcProviderConfig
}
```

```swift
func startOidcRedirectAuth(
    provider: OidcProviderConfig,
    redirectUri: String,
    walletType: WalletType = .ethereum,
    authorizeParams: [String: String] = [:]
) async throws -> StartOidcRedirectAuthResult
```

```swift
func startOidcRedirectAuth(
    provider: OidcProviderConfig,
    redirectUri: String,
    walletType: WalletType = .ethereum,
    relayRedirectUri: String?,
    authorizeParams: [String: String] = [:]
) async throws -> StartOidcRedirectAuthResult
```

```swift
struct StartOidcRedirectAuthResult {
    let authorizationUrl: String
    let state: String
    let challenge: String
}
```

```swift
func handleOidcRedirectCallback(
    _ callbackUrl: String?,
    walletSelection: WalletSelectionBehavior = .automatic
) async throws -> OidcRedirectAuthResult
```

```swift
enum OidcRedirectAuthResult {
    case completed(wallet: Wallet)
    case walletSelection(PendingWalletSelection)
    case notOidcRedirectCallback
    case noPendingAuth
    case failed(Error)
}
```

OIDC redirect auth stores transient verifier/state data separately from completed
wallet sessions so apps can resume after the browser redirect. The callback
handler is safe to call for every incoming app link: unrelated links return
`.notOidcRedirectCallback`, stale links return `.noPendingAuth`, and provider or
completion failures return `.failed`. Invalid or unrelated callbacks do not clear
pending redirect auth. Valid callbacks clear pending redirect auth after success
or non-cancellation failure. Cancellation rethrows `CancellationError` without
clearing pending redirect auth.

### useWallet

```swift
func useWallet(walletId: String) async throws -> WalletActivationResult
```

Activates an existing wallet after auth completion.

### createWallet

```swift
func createWallet(
    walletType: WalletType = .ethereum,
    reference: String? = nil
) async throws -> WalletActivationResult
```

Creates and activates a new wallet after auth completion.

### listWallets

```swift
func listWallets() async throws -> [Wallet]
```

Lists all wallets available to the authenticated credential.

Wallet API requests are signed with a Keychain-backed P-256 credential using the `webcrypto-secp256r1` key type. Persisted sessions store wallet ID, wallet address, and signer metadata; private credential keys are not written into SDK session storage.

### signOut

```swift
func signOut() throws
```

Clears the keychain session, local wallet identifiers, verifier state, and session signer.

### signMessage

```swift
func signMessage(network: Network, message: String) async throws -> String
```

Signs an arbitrary message using the wallet's session key.

```swift
let signature = try await oms.wallet.signMessage(
    network: .polygon,
    message: "Hello from OMS"
)
```

### signTypedData

```swift
func signTypedData(network: Network, typedData: WebRPCJSONValue) async throws -> String
```

Signs an EIP-712 typed-data JSON payload using the wallet's session key.

### isValidMessageSignature

```swift
func isValidMessageSignature(
    network: Network,
    walletAddress: String,
    message: String,
    signature: String
) async throws -> Bool
```

Verifies a message signature against the provided wallet address and the active wallet ID.

### isValidTypedDataSignature

```swift
func isValidTypedDataSignature(
    network: Network,
    walletAddress: String,
    typedData: WebRPCJSONValue,
    signature: String
) async throws -> Bool
```

Verifies an EIP-712 typed-data signature against the provided wallet address and the active wallet ID.

### sendTransaction

```swift
func sendTransaction(
    network: Network,
    to: String,
    value: String,
    feeOptionSelector: FeeOptionSelector? = nil
) async throws -> String
```

Sends a native token transfer.

```swift
let value = try parseUnits(value: "1", decimals: 18)
let txHash = try await oms.wallet.sendTransaction(
    network: .polygon,
    to: "0xRecipient",
    value: value
)
```

Full-parameter overload:

```swift
func sendTransaction(
    network: Network,
    request: SendTransactionRequest,
    feeOptionSelector: FeeOptionSelector? = nil
) async throws -> String
```

### callContract

```swift
func callContract(
    network: Network,
    contract: String,
    method: String,
    args: [AbiArg]?,
    feeOptionSelector: FeeOptionSelector? = nil
) async throws -> String
```

Calls a state-changing smart contract function.

### getTransactionStatus

```swift
func getTransactionStatus(txnId: String) async throws -> TransactionStatusResponse
```

Returns the current execution status for a prepared or submitted transaction.

### listAccess

```swift
func listAccess() async throws -> [CredentialInfo]
```

Returns all credentials that currently have access to this wallet.

### getIdToken

```swift
func getIdToken(
    ttlSeconds: UInt32? = nil,
    customClaims: [String: WebRPCJSONValue]? = nil
) async throws -> String
```

Returns an ID token for the active wallet. `ttlSeconds` requests a token
lifetime in seconds, and `customClaims` adds app-defined claims encoded as
`WebRPCJSONValue`. Omit both parameters to use the server defaults.

### revokeAccess

```swift
func revokeAccess(targetCredentialId: String) async throws
```

Revokes a credential's access to this wallet.

---

## IndexerClient

Accessed via `oms.indexer`. Queries token balances through the OMS Indexer API.

### getTokenBalances

```swift
func getTokenBalances(
    network: Network,
    contractAddress: String,
    walletAddress: String,
    includeMetadata: Bool
) async throws -> TokenBalancesResult
```

Fetches token balances for a wallet on a supported network and contract.

```swift
let result = try await oms.indexer.getTokenBalances(
    network: .polygon,
    contractAddress: "0xTokenContract",
    walletAddress: oms.wallet.walletAddress,
    includeMetadata: true
)
```

### getNativeTokenBalance

```swift
func getNativeTokenBalance(
    network: Network,
    walletAddress: String
) async throws -> TokenBalance?
```

Fetches the native token balance for a wallet on a supported network. Returns `nil` when the indexer response does not include a balance object.

```swift
let balance = try await oms.indexer.getNativeTokenBalance(
    network: .polygon,
    walletAddress: oms.wallet.walletAddress
)
```

---

## Formatting Helpers

Top-level helpers convert between display amounts and base-unit integer strings without floating-point precision loss.

### parseUnits

```swift
func parseUnits(value: String, decimals: Int = 18) throws -> String
```

Converts a decimal amount into its base-unit integer string.

```swift
let raw = try parseUnits(value: "12.34", decimals: 6)
// "12340000"
```

### formatUnits

```swift
func formatUnits(
    value: String,
    decimals: Int = 18
) throws -> String
```

Converts a base-unit integer string into a human-readable decimal amount.

```swift
let amount = try formatUnits(value: "12340000", decimals: 6)
// "12.34"
```

---

## Types

### Network

```swift
enum Network: String, CaseIterable, Sendable, CustomStringConvertible {
    case mainnet
    case sepolia
    case polygon
    case polygonAmoy
    case arbitrum
    case arbitrumSepolia
    case optimism
    case optimismSepolia
    case base
    case baseSepolia
    case bsc
    case bscTestnet
    case arbitrumNova
    case avalanche
    case avalancheTestnet
    case katana

    var id: Int
    var chainId: String
    var name: String
    var nativeTokenSymbol: String
    var explorerUrl: String
    var explorerURL: URL?
    var displayName: String
    var description: String

    static var supportedNetworks: [Network]
    static func from(chainId: String) -> Network?
    static func from(chainId: Int) -> Network?
    static func from(name: String) -> Network?
    static func findNetworkById(_ chainId: Int) -> Network?
    static func findNetworkByName(_ name: String) -> Network?
}
```

| Case | Chain ID | Display name | Indexer value | Native token |
|---|---|---|---|---|
| `.mainnet` | `1` | Mainnet | `mainnet` | `ETH` |
| `.sepolia` | `11155111` | Sepolia | `sepolia` | `ETH` |
| `.polygon` | `137` | Polygon | `polygon` | `POL` |
| `.polygonAmoy` | `80002` | Polygon Amoy | `amoy` | `POL` |
| `.arbitrum` | `42161` | Arbitrum | `arbitrum` | `ETH` |
| `.arbitrumSepolia` | `421614` | Arbitrum Sepolia | `arbitrum-sepolia` | `ETH` |
| `.optimism` | `10` | Optimism | `optimism` | `ETH` |
| `.optimismSepolia` | `11155420` | Optimism Sepolia | `optimism-sepolia` | `ETH` |
| `.base` | `8453` | Base | `base` | `ETH` |
| `.baseSepolia` | `84532` | Base Sepolia | `base-sepolia` | `ETH` |
| `.bsc` | `56` | BSC | `bsc` | `BNB` |
| `.bscTestnet` | `97` | BSC Testnet | `bsc-testnet` | `BNB` |
| `.arbitrumNova` | `42170` | Arbitrum Nova | `arbitrum-nova` | `ETH` |
| `.avalanche` | `43114` | Avalanche | `avalanche` | `AVAX` |
| `.avalancheTestnet` | `43113` | Avalanche Testnet | `avalanche-testnet` | `AVAX` |
| `.katana` | `747474` | Katana | `katana` | `ETH` |

### OMSClientIdentity

```swift
final class OMSClientIdentity: Sendable {
    let type: IdentityType
    let issuer: String?
    let subject: String
    var sessionLoginType: SessionLoginType?
}
```

App-facing wrapper for wallet authentication identity details.

### SessionState

```swift
struct SessionState: Equatable, Sendable {
    let walletAddress: String?
    let expiresAt: Date?
    let loginType: SessionLoginType?
    let sessionEmail: String?
}
```

Current durable wallet-session snapshot. It intentionally excludes pending auth state and signer bookkeeping.

### SessionLoginType

```swift
enum SessionLoginType: String, Codable, Sendable {
    case email
    case googleAuth
    case oidc
}
```

Auth method that produced the completed wallet session.

### OMSClientEnvironment

```swift
struct OMSClientEnvironment: Equatable, Sendable {
    static let defaultWalletApiUrl: String
    static let defaultApiRpcUrl: String
    static let defaultIndexerUrlTemplate: String
    static let indexerURLTemplateDefault: String

    let walletApiUrl: String
    let apiRpcUrl: String
    let indexerUrlTemplate: String

    var indexerURLTemplate: String

    init(
        walletApiUrl: String = OMSClientEnvironment.defaultWalletApiUrl,
        apiRpcUrl: String = OMSClientEnvironment.defaultApiRpcUrl,
        indexerUrlTemplate: String = OMSClientEnvironment.defaultIndexerUrlTemplate
    )

    init(
        walletApiUrl: String = OMSClientEnvironment.defaultWalletApiUrl,
        apiRpcUrl: String = OMSClientEnvironment.defaultApiRpcUrl,
        indexerURLTemplate: String
    )

    func indexerURL(for network: Network) -> URL?
}
```

| Field | Type | Description |
|---|---|---|
| `walletApiUrl` | `String` | Base URL of the OMS Wallet API. |
| `apiRpcUrl` | `String` | Base URL of the OMS API RPC. |
| `indexerUrlTemplate` | `String` | URL template for the Indexer. `{value}` is replaced with the network indexer name. |

### FeeOptionSelector

```swift
struct FeeOptionSelector {
    typealias Select = @Sendable ([FeeOptionWithBalance]) async throws -> FeeOptionSelection?
    static let first: FeeOptionSelector
    static func custom(_ pick: @escaping Select) -> FeeOptionSelector
}
```

Chooses a fee option during the transaction prepare/execute flow.
When no selector is provided, the SDK uses the first required fee option, or no
fee option when the transaction is sponsored.

| Selector | Description |
|---|---|
| `.first` | Picks the first fee option returned by the server. |
| `.custom { options in ... }` | Calls your closure with the full `[FeeOptionWithBalance]` list and expects a `FeeOptionSelection?`. |

```swift
struct FeeOptionWithBalance {
    let feeOption: FeeOption
    let balance: TokenBalance?
    let available: String?
    let availableRaw: String?
    let decimals: Int?
    var selection: FeeOptionSelection
}
```

`balance` is the wallet's raw indexer balance for the fee token when available.
`available` is formatted with `decimals`, while `availableRaw` keeps the raw
integer balance. Use `selection` when returning a quoted option from a custom
selector; it preserves the option's `tokenID` when present and falls back to the
symbol for native fee options.

### TransactionError

```swift
enum TransactionError: Error {
    case noFeeOptionsAvailable
    case missingTransactionHash
    case transactionFailed(status: TransactionStatus)
    case pollingTimedOut
}
```

Transaction-flow errors surfaced by `sendTransaction` and `callContract`.
`noFeeOptionsAvailable` is retained for selector code that wants to reject an
empty fee-option list explicitly.

### UnitConversionError

```swift
enum UnitConversionError: Error, Equatable {
    case invalidDecimals(Int)
    case invalidValue(String)
    case fractionalComponentExceedsDecimals(value: String, decimals: Int)
}
```

Thrown by `parseUnits` and `formatUnits`.

### SendTransactionRequest

```swift
struct SendTransactionRequest {
    let to: String
    let value: String
    let data: String?
}
```

Used with the full `sendTransaction(network:request:feeOptionSelector:)` overload.

### TokenBalancesResult

```swift
struct TokenBalancesResult {
    let status: Int
    let page: TokenBalancesPage?
    let balances: [TokenBalance]
}
```

### TokenBalancesPage

```swift
struct TokenBalancesPage: Codable {
    let page: Int
    let pageSize: Int
    let more: Bool
}
```

### TokenBalance

```swift
struct TokenBalance: Codable {
    let contractType: String?
    let contractAddress: String?
    let accountAddress: String?
    let tokenId: String?
    let balance: String?
    let blockHash: String?
    let blockNumber: Int64?
    let chainId: Int64?
}
```

### CredentialInfo

```swift
struct CredentialInfo: Codable, Sendable {
    let credentialId: String
    let expiresAt: String
    let isCaller: Bool
}
```

### WebRPCJSONValue

```swift
enum WebRPCJSONValue: Codable, Sendable {
    case object([String: WebRPCJSONValue])
    case array([WebRPCJSONValue])
    case string(String)
    case integer(Int64)
    case unsignedInteger(UInt64)
    case number(Double)
    case bool(Bool)
    case null
}
```

Used for typed-data signing, typed-data signature verification, and ABI argument values.
