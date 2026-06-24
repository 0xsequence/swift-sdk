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
  - [SessionExpiredEvent](#sessionexpiredevent)
  - [SessionLoginType](#sessionlogintype)
  - [OMSClientEnvironment](#omsclientenvironment)
  - [FeeOptionSelector](#feeoptionselector)
  - [OmsSdkError](#omssdkerror)
  - [OmsSdkErrorCode](#omssdkerrorcode)
  - [OmsSdkOperation](#omssdkoperation)
  - [TransactionError](#transactionerror)
  - [SendTransactionResponse](#sendtransactionresponse)
  - [TransactionMode](#transactionmode)
  - [UnitConversionError](#unitconversionerror)
  - [SendTransactionRequest](#sendtransactionrequest)
  - [IndexerNetworkType](#indexernetworktype)
  - [ContractVerificationStatus](#contractverificationstatus)
  - [MetadataOptions](#metadataoptions)
  - [GetBalancesParams](#getbalancesparams)
  - [BalancesResult](#balancesresult)
  - [GetTransactionHistoryParams](#gettransactionhistoryparams)
  - [TransactionHistoryResult](#transactionhistoryresult)
  - [Transaction](#transaction)
  - [TransactionTransfer](#transactiontransfer)
  - [SortBy](#sortby)
  - [TokenBalancesPage](#tokenbalancespage)
  - [TokenBalancesPageRequest](#tokenbalancespagerequest)
  - [TokenContractInfo](#tokencontractinfo)
  - [TokenMetadata](#tokenmetadata)
  - [TokenMetadataAsset](#tokenmetadataasset)
  - [TokenBalance](#tokenbalance)
  - [CredentialInfo](#credentialinfo)
  - [ListAccessPages](#listaccesspages)
  - [WebRPCJSONValue](#webrpcjsonvalue)

---

## OMSClient

The top-level entry point for the SDK. Requires iOS 15+ or macOS 12+.

```swift
let oms = try OMSClient(publishableKey: "pk_dev_sdbx_yourproject_yourkey")
```

### init

```swift
init(
    publishableKey: String,
    walletOrigin: String? = nil
) throws

init(
    publishableKey: String,
    environment: OMSClientEnvironment
) throws
```

| Parameter | Type | Description |
|---|---|---|
| `publishableKey` | `String` | OMS publishable key. The SDK derives the project scope and service URLs from this value. |
| `walletOrigin` | `String?` | Optional `Origin` header for OMS Wallet API requests when the publishable key is origin-scoped. |
| `environment` | `OMSClientEnvironment` | Explicit API endpoint override. The project scope is still derived from `publishableKey`. |

Publishable keys must use one of these prefixes and contain two suffix segments: a project segment and key segment. The project scope is `prj_<project segment>`.

| Prefix | API base |
|---|---|
| `pk_dev_sdbx_` | `https://sandbox-api.dev.polygon-dev.technology` |
| `pk_dev_live_` | `https://api.dev.polygon-dev.technology` |
| `pk_stg_sdbx_` | `https://sandbox-api.stg.polygon-dev.technology` |
| `pk_stg_live_` | `https://api.stg.polygon-dev.technology` |
| `pk_sdbx_` | `https://sandbox-api.polygon.technology` |
| `pk_live_` | `https://api.polygon.technology` |

### Properties

| Name | Type | Description |
|---|---|---|
| `wallet` | `WalletClient` | Authentication, signing, access, and transaction helper. |
| `indexer` | `IndexerClient` | Token balance query helper. |
| `supportedNetworks` | `[Network]` | Supported SDK network list. |

### Network Lookup

```swift
func findNetworkById(chainId: Int) -> Network?
func findNetworkByName(name: String) -> Network?
```

Returns the supported `Network` for a numeric chain ID or network name, or `nil`
when the chain is not supported. Names are trimmed and lowercased before lookup;
`polygonamoy` is accepted as a legacy alias for `.polygonAmoy`.

---

## WalletClient

Accessed via `oms.wallet`. Manages wallet authentication, non-extractable Keychain request signing, keychain session persistence, signing, signature verification, and transaction submission.

### init

```swift
init(
    publishableKey: String,
    walletOrigin: String? = nil
) throws

init(
    publishableKey: String,
    environment: OMSClientEnvironment
) throws
```

Most apps create a wallet client through `OMSClient`. Use these initializers only when constructing `WalletClient` directly. The project scope is derived from `publishableKey`.

### walletAddress

```swift
var walletAddress: String?
```

The read-only on-chain address of the active wallet, or `nil` until a wallet is restored or activated by `completeEmailAuth`, `useWallet`, or `createWallet`.

### walletId

```swift
var walletId: String
```

The read-only server-side wallet ID. Empty until a wallet is restored or activated by `completeEmailAuth`, `useWallet`, or `createWallet`.

### session

```swift
var session: SessionState
```

Snapshot of the currently completed wallet session for this wallet client.

### onSessionExpired

```swift
var onSessionExpired: ((SessionExpiredEvent) -> Void)?
```

Called when the active wallet session expires. The SDK clears active in-memory wallet state and the signer credential, but keeps expired session metadata in storage until `signOut()` or a new auth flow clears or replaces it. The event carries the expired session snapshot so apps can reuse `sessionEmail` for email OTP reauth or as a Google OIDC login hint.

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
    walletSelection: WalletSelectionBehavior = .automatic,
    walletType: WalletType = .ethereum,
    sessionLifetimeSeconds: UInt32 = 604_800
) async throws -> CompleteAuthResult
```

Verifies the OTP code. With `.automatic`, selects the first existing wallet
matching `walletType`, or creates and selects one when none exists. With
`.manual`, returns a pending wallet selection without selecting or creating a
wallet. `sessionLifetimeSeconds` controls the requested credential lifetime and
defaults to one week.

### signInWithOidcIdToken

```swift
func signInWithOidcIdToken(
    idToken: String,
    issuer: String,
    audience: String,
    walletType: WalletType = .ethereum,
    walletSelection: WalletSelectionBehavior = .automatic,
    sessionLifetimeSeconds: UInt32 = 604_800
) async throws -> CompleteAuthResult
```

Signs in with an OIDC ID token. The SDK commits an OIDC `id-token` verifier
using `issuer`, `audience`, the token `exp` claim, and a SHA-256 base64url hash
of the full token as the verifier handle, then completes auth with the original
token.

With `.automatic`, selects the first existing wallet matching `walletType`, or
creates and selects one when none exists. With `.manual`, returns a pending
wallet selection without selecting or creating a wallet. `sessionLifetimeSeconds`
controls the requested credential lifetime and defaults to one week.

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
`OmsSdkError` with `code == .walletSelectionStale`.

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
    loginHint: String? = nil,
    authorizeParams: [String: String] = [:]
) async throws -> StartOidcRedirectAuthResult
```

```swift
func startOidcRedirectAuth(
    provider: OidcProviderConfig,
    redirectUri: String,
    walletType: WalletType = .ethereum,
    relayRedirectUri: String?,
    loginHint: String? = nil,
    authorizeParams: [String: String] = [:]
) async throws -> StartOidcRedirectAuthResult
```

For Google OIDC providers, `loginHint` is sent as the OAuth `login_hint` parameter. If omitted, the SDK uses the previous session email when available. Non-Google providers do not receive `login_hint`.

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
    walletSelection: WalletSelectionBehavior = .automatic,
    sessionLifetimeSeconds: UInt32 = 604_800
) async throws -> OidcRedirectAuthResult
```

`sessionLifetimeSeconds` is used when completing the OIDC redirect callback and
defaults to one week.

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

Wallet API requests are signed with a Keychain-backed P-256 credential using the `webcrypto-secp256r1` key type. Persisted sessions store wallet ID, wallet address, expiry, and signer metadata; private credential keys are not written into SDK session storage. Restore checks the cached expiry first. Expired sessions are not activated, and the signer credential is cleared; expired metadata may remain in storage as a reauth hint until `signOut()` or a new auth flow clears or replaces it. Invalid persisted session metadata is cleared.

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
    selectFeeOption: FeeOptionSelector? = nil,
    mode: TransactionMode = .relayer,
    waitForStatus: Bool = true,
    statusPolling: TransactionStatusPollingOptions = TransactionStatusPollingOptions()
) async throws -> SendTransactionResponse
```

Sends a native token transfer.

```swift
let value = try parseUnits(value: "1", decimals: 18)
let txResult = try await oms.wallet.sendTransaction(
    network: .polygon,
    to: "0xRecipient",
    value: value
)
print(txResult.txnHash ?? "pending")
```

Full-parameter overload:

```swift
func sendTransaction(
    network: Network,
    request: SendTransactionRequest,
    selectFeeOption: FeeOptionSelector? = nil,
    waitForStatus: Bool = true,
    statusPolling: TransactionStatusPollingOptions = TransactionStatusPollingOptions()
) async throws -> SendTransactionResponse
```

### callContract

```swift
func callContract(
    network: Network,
    contract: String,
    method: String,
    args: [AbiArg]?,
    selectFeeOption: FeeOptionSelector? = nil,
    mode: TransactionMode = .relayer,
    waitForStatus: Bool = true,
    statusPolling: TransactionStatusPollingOptions = TransactionStatusPollingOptions()
) async throws -> SendTransactionResponse
```

Calls a state-changing smart contract function.

### getTransactionStatus

```swift
func getTransactionStatus(txnId: String) async throws -> TransactionStatusResponse
```

Returns the current execution status for a prepared or submitted transaction.

### listAccess

```swift
func listAccess(pageSize: UInt32? = nil) async throws -> [CredentialInfo]
```

Returns all credentials that currently have access to this wallet, following
WaaS cursors until every page has been loaded.

### listAccessPages

```swift
func listAccessPages(pageSize: UInt32? = nil) -> ListAccessPages
```

Returns credential-access pages for this wallet until WaaS stops returning a
cursor.

### listAccessPage

```swift
func listAccessPage(
    pageSize: UInt32? = nil,
    cursor: String? = nil
) async throws -> ListAccessResponse
```

Returns one credential-access page for this wallet.

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

Accessed via `oms.indexer`. Queries token balances and transaction history through the OMS IndexerGateway API.

### getBalances

```swift
func getBalances(_ params: GetBalancesParams) async throws -> BalancesResult
```

Fetches token balances for a wallet across explicit `networks` or an `IndexerNetworkType`. Results include native balances separately from token contract balances.

```swift
guard let walletAddress = oms.wallet.walletAddress else { return }

let result = try await oms.indexer.getBalances(
    GetBalancesParams(
        walletAddress: walletAddress,
        networks: [.polygon],
        contractAddresses: ["0xcontract"],
        includeMetadata: true,
        page: TokenBalancesPageRequest(page: 1, pageSize: 100)
    )
)
```

### getTransactionHistory

```swift
func getTransactionHistory(_ params: GetTransactionHistoryParams) async throws -> TransactionHistoryResult
```

Fetches transaction history for a wallet across explicit `networks` or an `IndexerNetworkType`.

```swift
guard let walletAddress = oms.wallet.walletAddress else { return }

let history = try await oms.indexer.getTransactionHistory(
    GetTransactionHistoryParams(
        walletAddress: walletAddress,
        networks: [.polygon],
        includeMetadata: true
    )
)
```

---

## Formatting Helpers

Top-level helpers convert between display amounts and base-unit integer strings without floating-point precision loss.

### parseUnits

```swift
func parseUnits(value: String, decimals: Int = 18) throws -> String
```

Converts a decimal amount into its base-unit integer string. Fractional precision beyond `decimals` is rounded to the nearest base unit.

```swift
let raw = try parseUnits(value: "12.34", decimals: 6)
// "12340000"

let rounded = try parseUnits(value: "1.235", decimals: 2)
// "124"
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
    case polygonAmoy = "amoy"
    case arbitrum
    case arbitrumSepolia = "arbitrum-sepolia"
    case optimism
    case optimismSepolia = "optimism-sepolia"
    case base
    case baseSepolia = "base-sepolia"
    case bsc
    case bscTestnet = "bsc-testnet"
    case arbitrumNova = "arbitrum-nova"
    case avalanche
    case avalancheTestnet = "avalanche-testnet"
    case katana

    static let amoy: Network

    var id: Int
    var chainId: String
    var name: String
    var nativeTokenSymbol: String
    var explorerUrl: String
    var explorerURL: URL?
    var displayName: String
    var description: String

    static var supportedNetworks: [Network]
}
```

| Case | Chain ID | Display name | Indexer value | Native token |
|---|---|---|---|---|
| `.mainnet` | `1` | Ethereum | `mainnet` | `ETH` |
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

`Network.amoy` is an alias for `.polygonAmoy`.

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

### SessionExpiredEvent

```swift
struct SessionExpiredEvent: Equatable, Sendable {
    let session: SessionState
    let expiredAt: Date
}
```

Event delivered to `wallet.onSessionExpired`. `session` is the expired session snapshot, including `sessionEmail` when available, and `expiredAt` is the parsed session expiry time.

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
    static let defaultIndexerGatewayUrl: String

    let walletApiUrl: String
    let apiRpcUrl: String
    let indexerGatewayUrl: String
    let walletOrigin: String?

    init(
        walletApiUrl: String = OMSClientEnvironment.defaultWalletApiUrl,
        apiRpcUrl: String = OMSClientEnvironment.defaultApiRpcUrl,
        indexerGatewayUrl: String = OMSClientEnvironment.defaultIndexerGatewayUrl,
        walletOrigin: String? = nil
    )
}
```

| Field | Type | Description |
|---|---|---|
| `walletApiUrl` | `String` | Base URL of the OMS Wallet API. |
| `apiRpcUrl` | `String` | Base URL of the OMS API RPC. |
| `indexerGatewayUrl` | `String` | Base URL of the IndexerGateway API. |
| `walletOrigin` | `String?` | Optional `Origin` header for OMS Wallet API requests when the publishable key is origin-scoped. |

### FeeOptionSelector

```swift
struct FeeOptionSelector {
    typealias Select = @Sendable ([FeeOptionWithBalance]) async throws -> FeeOptionSelection?
    init(_ select: @escaping Select)
    func callAsFunction(_ options: [FeeOptionWithBalance]) async throws -> FeeOptionSelection?
    func callAsFunction(_ options: [FeeOption]) async throws -> FeeOptionSelection?
    static let firstAvailable: FeeOptionSelector
    static func custom(_ pick: @escaping Select) -> FeeOptionSelector
}
```

Chooses a fee option during the transaction prepare/execute flow.
When no selector is provided, the SDK uses the first required fee option, or no
fee option when the transaction is sponsored.

| Selector | Description |
|---|---|
| `.firstAvailable` | Uses indexer balances to skip underfunded fee options and picks the first option the wallet can pay. Malformed balance or fee values are treated as not payable. |
| `.custom { options in ... }` | Calls your closure with the full `[FeeOptionWithBalance]` list and expects a `FeeOptionSelection?`. |

```swift
struct FeeOptionWithBalance {
    let feeOption: FeeOption
    let balance: TokenBalance?
    let available: String?
    let availableRaw: String?
    let decimals: Int?

    init(
        feeOption: FeeOption,
        balance: TokenBalance? = nil,
        available: String? = nil,
        availableRaw: String? = nil,
        decimals: Int? = nil
    )

    var selection: FeeOptionSelection
}
```

```swift
extension FeeOptionSelection {
    init(feeOption: FeeOption)
}
```

`balance` is the wallet's raw indexer balance for the fee token when available.
`available` is formatted with `decimals`, while `availableRaw` keeps the raw
integer balance. Use `selection` when returning a quoted option from a custom
selector; it preserves the option's `tokenID` when present and falls back to the
symbol for native fee options.

### OmsSdkError

```swift
struct OmsSdkError: Error, LocalizedError, Sendable {
    let code: OmsSdkErrorCode
    let operation: OmsSdkOperation?
    let status: Int?
    let txnId: String?
    let retryable: Bool
    let underlyingError: (any Error)?
}
```

Public `WalletClient` and `IndexerClient` methods normalize recoverable SDK
failures to `OmsSdkError`. Use `code` for stable app handling, `operation` for
logging and analytics, `status` for HTTP-backed failures, `txnId` for
transaction status lookup failures, and `retryable` for retry UI. The
`underlyingError` preserves lower-level details such as `WebRPCError`,
`TransactionError`, or decoding/transport errors.

`PendingWalletSelection` validation failures, such as stale selections or
unavailable wallet IDs, also throw `OmsSdkError`.

`CancellationError` is not wrapped.

```swift
do {
    _ = try await oms.wallet.signMessage(network: .polygon, message: "hello")
} catch let error as OmsSdkError {
    switch error.code {
    case .sessionMissing, .sessionExpired:
        // Prompt the user to sign in again.
        break
    case .httpError where error.retryable:
        // Show retry UI.
        break
    default:
        // Show a generic SDK error.
        break
    }
}
```

### OmsSdkErrorCode

```swift
enum OmsSdkErrorCode: String, Sendable {
    case httpError = "OMS_HTTP_ERROR"
    case invalidResponse = "OMS_INVALID_RESPONSE"
    case requestFailed = "OMS_REQUEST_FAILED"
    case authCommitmentConsumed = "OMS_AUTH_COMMITMENT_CONSUMED"
    case sessionMissing = "OMS_SESSION_MISSING"
    case sessionExpired = "OMS_SESSION_EXPIRED"
    case walletSelectionStale = "OMS_WALLET_SELECTION_STALE"
    case walletSelectionUnavailable = "OMS_WALLET_SELECTION_UNAVAILABLE"
    case walletSelectionInFlight = "OMS_WALLET_SELECTION_IN_FLIGHT"
    case transactionStatusLookupFailed = "OMS_TRANSACTION_STATUS_LOOKUP_FAILED"
    case validationError = "OMS_VALIDATION_ERROR"
}
```

### OmsSdkOperation

```swift
enum OmsSdkOperation: String, Sendable
```

Stable operation identifiers such as `wallet.sendTransaction`,
`wallet.completeEmailAuth`, `indexer.getBalances`, and
`indexer.getTransactionHistory`. Use
`operation.rawValue` when logging SDK failures.

### TransactionError

```swift
enum TransactionError: Error {
    case noFeeOptionsAvailable
    case noFeeOptionSelected
    case missingTransactionHash
    case transactionFailed(status: TransactionStatus)
    case pollingTimedOut
}
```

Transaction-flow detail cases preserved under `OmsSdkError.underlyingError`.
`noFeeOptionsAvailable` is used when an unsponsored transaction has no fee
options, and `noFeeOptionSelected` is used when a custom selector does not
return a selection for an unsponsored transaction. Terminal non-executed
statuses use `transactionFailed`. A normal pending polling timeout returns
`SendTransactionResponse(status: .pending, txnHash: nil)` instead of throwing.
`missingTransactionHash` and `pollingTimedOut` remain public compatibility cases.

### SendTransactionResponse

```swift
struct SendTransactionResponse {
    let txnId: String
    let status: TransactionStatus
    let txnHash: String?
}
```

Returned by `sendTransaction` and `callContract`. `txnId` and `status` are always
available; `txnHash` is present when the service has a chain transaction hash.
The transaction flow returns as soon as status is `.executed` or a non-empty
`txnHash` is available.
`TransactionResult` remains available as a compatibility alias.

### TransactionStatusPollingOptions

```swift
struct TransactionStatusPollingOptions {
    let timeoutMs: UInt64?
    let intervalMs: UInt64?
    let fastIntervalMs: UInt64?
    let fastPollCount: Int?
}
```

Controls how `sendTransaction` and `callContract` poll WaaS transaction status
after execute when `waitForStatus` is `true`. Defaults are a 60 second timeout,
400 ms fast polling for the first status checks, then 2 second polling.

### TransactionMode

```swift
enum TransactionMode {
    case native
    case relayer
    case unknown(String)
}
```

Used by transaction prepare requests. Public helpers default to `.relayer`.

### UnitConversionError

```swift
enum UnitConversionError: Error, Equatable {
    case invalidDecimals(Int)
    case invalidValue(String)
    case fractionalComponentExceedsDecimals(value: String, decimals: Int)
}
```

Thrown by `parseUnits` and `formatUnits`. The `fractionalComponentExceedsDecimals` case is retained for source compatibility; `parseUnits` rounds excess fractional precision to the nearest base unit.

### SendTransactionRequest

```swift
struct SendTransactionRequest {
    let to: String
    let value: String
    let data: String?
    let mode: TransactionMode
}
```

Used with the full `sendTransaction(network:request:selectFeeOption:waitForStatus:statusPolling:)` overload.
`mode` defaults to `.relayer`.

### IndexerNetworkType

```swift
enum IndexerNetworkType: String, Codable, Sendable {
    case mainnets
    case testnets
    case all
}
```

Gateway network scope used when `GetBalancesParams.networks` or `GetTransactionHistoryParams.networks` is omitted.

### ContractVerificationStatus

```swift
enum ContractVerificationStatus: String, Codable, Sendable {
    case verified
    case unverified
    case all
}
```

Optional token-contract verification filter for balance queries.

### MetadataOptions

```swift
struct MetadataOptions: Codable, Sendable {
    let verifiedOnly: Bool?
    let unverifiedOnly: Bool?
    let includeContracts: [String]?
}
```

Optional metadata filter for transaction-history queries.

### GetBalancesParams

```swift
struct GetBalancesParams: Sendable {
    let walletAddress: String
    let networks: [Network]?
    let networkType: IndexerNetworkType?
    let contractAddresses: [String]?
    let includeMetadata: Bool
    let omitPrices: Bool?
    let tokenIds: [String]?
    let contractStatus: ContractVerificationStatus?
    let page: TokenBalancesPageRequest?
}
```

Use `networks` for an explicit chain list. If omitted, `networkType` defaults to `.mainnets`.

### BalancesResult

```swift
struct BalancesResult: Sendable {
    let status: Int
    let page: TokenBalancesPage?
    let nativeBalances: [TokenBalance]
    let balances: [TokenBalance]
}
```

### GetTransactionHistoryParams

```swift
struct GetTransactionHistoryParams: Sendable {
    let walletAddress: String
    let networks: [Network]?
    let networkType: IndexerNetworkType?
    let contractAddresses: [String]?
    let transactionHashes: [String]?
    let metaTransactionIds: [String]?
    let fromBlock: Int?
    let toBlock: Int?
    let tokenId: String?
    let includeMetadata: Bool
    let omitPrices: Bool?
    let metadataOptions: MetadataOptions?
    let page: TokenBalancesPageRequest?
}
```

### TransactionHistoryResult

```swift
struct TransactionHistoryResult: Sendable {
    let status: Int
    let page: TokenBalancesPage?
    let transactions: [Transaction]
}
```

### Transaction

```swift
struct Transaction: Codable, Sendable {
    let txnHash: String
    let blockNumber: Int64
    let blockHash: String
    let chainId: Int64
    let metaTxnId: String?
    let transfers: [TransactionTransfer]?
    let timestamp: String
}
```

### TransactionTransfer

```swift
struct TransactionTransfer: Codable, Sendable {
    let transferType: String?
    let contractAddress: String?
    let contractType: String?
    let from: String?
    let to: String?
    let tokenIds: [String]?
    let amounts: [String]?
    let logIndex: Int?
    let amountsUSD: [String]?
    let pricesUSD: [String]?
    let contractInfo: TokenContractInfo?
    let tokenMetadata: [String: TokenMetadata]?
}
```

### SortBy

```swift
enum SortOrder: String, Codable, Sendable {
    case descending
    case ascending
}

struct SortBy: Codable, Sendable {
    let column: String
    let order: SortOrder
}
```

### TokenBalancesPage

```swift
struct TokenBalancesPage: Codable, Sendable {
    let page: Int?
    let column: String?
    let before: WebRPCJSONValue?
    let after: WebRPCJSONValue?
    let sort: [SortBy]?
    let pageSize: Int?
    let more: Bool?
}
```

### TokenBalancesPageRequest

```swift
struct TokenBalancesPageRequest: Codable, Sendable {
    let page: Int?
    let column: String?
    let before: WebRPCJSONValue?
    let after: WebRPCJSONValue?
    let sort: [SortBy]?
    let pageSize: Int?
}
```

`page` defaults to `0` and `pageSize` defaults to `40` when omitted.

### TokenBalance

```swift
struct TokenBalance: Codable, Sendable {
    let contractType: String?
    let contractAddress: String?
    let accountAddress: String?
    let tokenId: String?
    let name: String?
    let symbol: String?
    let balance: String?
    let balanceUSD: String?
    let priceUSD: String?
    let priceUpdatedAt: String?
    let blockHash: String?
    let blockNumber: Int64?
    let chainId: Int64?
    let uniqueCollectibles: String?
    let isSummary: Bool?
    let contractInfo: TokenContractInfo?
    let tokenMetadata: TokenMetadata?

    init(
        contractType: String?,
        contractAddress: String?,
        accountAddress: String?,
        tokenId: String?,
        name: String? = nil,
        symbol: String? = nil,
        balance: String?,
        balanceUSD: String? = nil,
        priceUSD: String? = nil,
        priceUpdatedAt: String? = nil,
        blockHash: String?,
        blockNumber: Int64?,
        chainId: Int64?,
        uniqueCollectibles: String? = nil,
        isSummary: Bool? = nil,
        contractInfo: TokenContractInfo? = nil,
        tokenMetadata: TokenMetadata? = nil
    )
}
```

### TokenContractInfo

```swift
struct TokenContractInfo: Codable, Sendable {
    let chainId: Int64?
    let address: String?
    let source: String?
    let name: String?
    let type: String?
    let symbol: String?
    let decimals: Int?
    let logoURI: String?
    let deployed: Bool?
    let bytecodeHash: String?
    let extensions: [String: WebRPCJSONValue]?
    let updatedAt: String?
    let queuedAt: String?
    let status: String?
}
```

### TokenMetadata

```swift
struct TokenMetadata: Codable, Sendable {
    let chainId: Int64?
    let contractAddress: String?
    let tokenId: String?
    let source: String?
    let name: String?
    let description: String?
    let image: String?
    let video: String?
    let audio: String?
    let properties: [String: WebRPCJSONValue]?
    let attributes: [[String: WebRPCJSONValue]]?
    let imageData: String?
    let externalUrl: String?
    let backgroundColor: String?
    let animationUrl: String?
    let decimals: Int?
    let updatedAt: String?
    let assets: [TokenMetadataAsset]?
    let status: String?
    let queuedAt: String?
    let lastFetched: String?
}
```

### TokenMetadataAsset

```swift
struct TokenMetadataAsset: Codable, Sendable {
    let id: Int64?
    let collectionId: Int64?
    let tokenId: String?
    let url: String?
    let metadataField: String?
    let name: String?
    let filesize: Int64?
    let mimeType: String?
    let width: Int?
    let height: Int?
    let updatedAt: String?
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

### ListAccessPages

```swift
struct ListAccessPages: AsyncSequence
```

Async sequence returned by `WalletClient.listAccessPages(pageSize:)`.

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
