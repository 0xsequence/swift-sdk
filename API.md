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
  - [OmsUpstreamService](#omsupstreamservice)
  - [OmsUpstreamError](#omsupstreamerror)
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
    publishableKey: String
) throws

init(
    publishableKey: String,
    environment: OMSClientEnvironment
) throws
```

| Parameter | Type | Description |
|---|---|---|
| `publishableKey` | `String` | OMS publishable key. |
| `environment` | `OMSClientEnvironment` | Explicit API endpoint override. |

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
`polygonamoy` is also accepted for `.polygonAmoy`.

---

## WalletClient

Accessed via `oms.wallet`. Manages wallet authentication, session persistence,
signing, signature verification, and transaction submission.

### init

```swift
init(
    publishableKey: String
) throws

init(
    publishableKey: String,
    environment: OMSClientEnvironment
) throws
```

Most apps create a wallet client through `OMSClient`. Use these initializers only
when constructing `WalletClient` directly.

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

Called when the active wallet session expires. The event carries the expired
session snapshot so apps can reuse `sessionEmail` for email OTP reauth or as a
Google OIDC login hint.

### canResumeOidcRedirectAuth

```swift
var canResumeOidcRedirectAuth: Bool
```

Whether there is an OIDC redirect flow waiting for its callback URL.

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

Signs in with an OIDC ID token for the provided `issuer` and `audience`.

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

Convenience properties:

| Property | Type | Description |
|---|---|---|
| `wallets` | `[Wallet]` | Wallets available to the authenticated credential. |
| `credential` | `CredentialInfo` | Credential returned by the completed auth flow. |
| `walletAddress` | `String?` | Selected wallet address, or `nil` when manual wallet selection is pending. |
| `wallet` | `Wallet?` | Selected wallet, or `nil` when manual wallet selection is pending. |

### OIDC Redirect Auth

```swift
enum OidcAuthMode {
    case authCode
    case authCodePkce
}
```

```swift
struct OidcProviderConfig {
    let issuer: String
    let clientId: String
    let authorizationUrl: String
    let scopes: [String]
    let relayRedirectUri: String?
    let authorizeParams: [String: String]
    let authMode: OidcAuthMode
}
```

```swift
init(
    issuer: String,
    clientId: String,
    authorizationUrl: String,
    scopes: [String] = ["openid", "email", "profile"],
    relayRedirectUri: String? = nil,
    authorizeParams: [String: String] = [:],
    authMode: OidcAuthMode = .authCodePkce
)
```

`authMode` defaults to `.authCodePkce`. Use `.authCode` only for providers that
do not support PKCE for the redirect flow.

```swift
enum OidcProviders {
    static let defaultGoogleClientId: String
    static let defaultAppleClientId: String
    static let defaultRelayRedirectUri: String

    static func google(
        clientId: String = OidcProviders.defaultGoogleClientId,
        relayRedirectUri: String? = OidcProviders.defaultRelayRedirectUri,
        scopes: [String] = ["openid", "email", "profile"],
        authorizeParams: [String: String] = [:],
        authMode: OidcAuthMode = .authCodePkce
    ) -> OidcProviderConfig

    static func apple(
        clientId: String = OidcProviders.defaultAppleClientId,
        relayRedirectUri: String? = OidcProviders.defaultRelayRedirectUri,
        scopes: [String] = ["openid", "email"],
        authorizeParams: [String: String] = [:],
        authMode: OidcAuthMode = .authCodePkce
    ) -> OidcProviderConfig
}
```

Google defaults to issuer `https://accounts.google.com`, authorization URL
`https://accounts.google.com/o/oauth2/v2/auth`, scopes `openid email profile`,
the SDK default Google client ID, the SDK relay redirect URI,
`access_type=offline`, `prompt=consent`, and PKCE auth-code mode.

Apple defaults to issuer `https://appleid.apple.com`, authorization URL
`https://appleid.apple.com/auth/authorize`, scopes `openid email`, the SDK
default Apple Services ID, the SDK relay redirect URI, `response_mode=form_post`,
and PKCE auth-code mode. Apple `form_post` is intended to work through the
default relay before returning to your app callback.

Provider configs are the source of truth for authorization scopes. Empty
`scopes` omits the OAuth `scope` authorization parameter. `.authCodePkce` adds
`code_challenge` and `code_challenge_method=S256`; `.authCode` omits PKCE
authorization parameters.

```swift
func startOidcRedirectAuth(
    provider: OidcProviderConfig,
    redirectUri: String,
    walletType: WalletType = .ethereum,
    loginHint: String? = nil,
    authorizeParams: [String: String] = [:],
    walletSelection: WalletSelectionBehavior? = nil,
    sessionLifetimeSeconds: UInt32? = nil
) async throws -> StartOidcRedirectAuthResult
```

```swift
func startOidcRedirectAuth(
    provider: OidcProviderConfig,
    redirectUri: String,
    walletType: WalletType = .ethereum,
    relayRedirectUri: String?,
    loginHint: String? = nil,
    authorizeParams: [String: String] = [:],
    walletSelection: WalletSelectionBehavior? = nil,
    sessionLifetimeSeconds: UInt32? = nil
) async throws -> StartOidcRedirectAuthResult
```

For `OidcProviders.google()` or other providers using issuer `https://accounts.google.com`, `loginHint` is sent as the OAuth `login_hint` parameter. If omitted, the SDK uses the previous session email when available. Non-Google issuers do not receive `login_hint`.

`walletSelection` and `sessionLifetimeSeconds` passed at start are persisted in
pending redirect state and used when the callback is handled unless callback
arguments override them.

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
    walletSelection: WalletSelectionBehavior? = nil,
    sessionLifetimeSeconds: UInt32? = nil
) async throws -> OidcRedirectAuthResult
```

Callback `walletSelection` and `sessionLifetimeSeconds` override values stored
when starting the redirect. If neither start nor callback provides values, the
SDK uses automatic wallet selection and a one-week session lifetime.

```swift
enum OidcRedirectAuthResult {
    case completed(wallet: Wallet)
    case walletSelection(PendingWalletSelection)
    case notOidcRedirectCallback
    case noPendingAuth
    case failed(Error)
}
```

```swift
enum OidcRedirectAuthError {
    case invalidAuthorizationURL(String)
    case randomBytesUnavailable
    case invalidState
    case stateNonceMismatch
    case stateScopeMismatch
    case stateRedirectUriMismatch
    case providerError(String)
    case missingCode
    case signerMismatch
}
```

The callback handler is safe to call for every incoming app link: unrelated
links return `.notOidcRedirectCallback`, stale links return `.noPendingAuth`, and
provider or completion failures return `.failed`. Cancellation rethrows
`CancellationError`.

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

### signOut

```swift
func signOut() throws
```

Signs out and clears the active wallet session.

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
pagination until every page has been loaded.

### listAccessPages

```swift
func listAccessPages(pageSize: UInt32? = nil) -> ListAccessPages
```

Returns credential-access pages for this wallet until no further cursor is
returned.

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

| Case | Chain ID | Display name | Name | Native token |
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

Current wallet-session snapshot. It intentionally excludes pending auth state.

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
    static let defaultIndexerGatewayUrl: String

    let walletApiUrl: String
    let indexerGatewayUrl: String

    init(
        walletApiUrl: String = OMSClientEnvironment.defaultWalletApiUrl,
        indexerGatewayUrl: String = OMSClientEnvironment.defaultIndexerGatewayUrl
    )
}
```

| Field | Type | Description |
|---|---|---|
| `walletApiUrl` | `String` | Base URL of the OMS Wallet API. |
| `indexerGatewayUrl` | `String` | Base URL of the IndexerGateway API. |

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
struct OmsSdkError: Error, LocalizedError, @unchecked Sendable {
    let code: OmsSdkErrorCode
    let operation: OmsSdkOperation?
    let status: Int?
    let txnId: String?
    let retryable: Bool?
    let upstreamError: OmsUpstreamError?
    let underlyingError: (any Error)?
}
```

Public `WalletClient` and `IndexerClient` methods normalize recoverable SDK
failures to `OmsSdkError`. Use `code` for stable app handling, `operation` for
logging and analytics, `status` for HTTP-backed failures, `txnId` for
transaction recovery, and `retryable == true` for retry UI. `retryable` is
nullable because not every error family has meaningful retry semantics.

`upstreamError` is normalized diagnostic detail from a remote OMS service
response, malformed remote response, or transport failure. It is present for
WaaS and Indexer failures that crossed a remote/transport boundary, and absent
for local session, selection, validation, OIDC state, and fee-selection errors.
Branch application behavior on SDK-level `code`; use `upstreamError` for logs
and service-specific troubleshooting.

`underlyingError` is Swift-local diagnostic context. It is present when the SDK
wraps a lower-level Swift error such as `WebRPCError`, `WebRPCTransportError`,
`TransactionError`, `HttpError`, `URLError`, or a decoding error. It can be
absent for deliberate local SDK errors such as missing session and stale wallet
selection, and for manually constructed `OmsSdkError` values unless the caller
supplies it. Do not serialize or depend on `underlyingError` for cross-SDK
behavior.

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
    case .httpError where error.retryable == true:
        // Show retry UI.
        break
    case .transactionExecutionUnconfirmed:
        // Preserve error.txnId and avoid blindly resending the write.
        break
    case .transactionStatusLookupFailed:
        // Retry getTransactionStatus with error.txnId.
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
    case transactionExecutionUnconfirmed = "OMS_TRANSACTION_EXECUTION_UNCONFIRMED"
    case transactionStatusLookupFailed = "OMS_TRANSACTION_STATUS_LOOKUP_FAILED"
    case validationError = "OMS_VALIDATION_ERROR"
}
```

`OMS_AUTH_COMMITMENT_CONSUMED` means the OTP/OIDC auth commitment has already
been used. Restart the auth flow before retrying.

`OMS_TRANSACTION_EXECUTION_UNCONFIRMED` means transaction preparation succeeded
and produced a `txnId`, but the execute request failed before the SDK could
confirm whether the transaction was submitted. Do not blindly resend the same
write solely because the upstream failure looked temporary.

`OMS_TRANSACTION_STATUS_LOOKUP_FAILED` means the transaction was submitted, but
post-submit status polling failed. The error includes `txnId` when available and
is retryable by checking status again with `getTransactionStatus(txnId:)`.

### OmsSdkOperation

```swift
enum OmsSdkOperation: String, Sendable {
    case pendingWalletSelection = "wallet.pendingWalletSelection"
    case pendingWalletSelectionSelectWallet = "wallet.pendingWalletSelection.selectWallet"
    case pendingWalletSelectionCreateAndSelectWallet = "wallet.pendingWalletSelection.createAndSelectWallet"
    case walletStartEmailAuth = "wallet.startEmailAuth"
    case walletCompleteEmailAuth = "wallet.completeEmailAuth"
    case walletSignInWithOidcIdToken = "wallet.signInWithOidcIdToken"
    case walletStartOidcRedirectAuth = "wallet.startOidcRedirectAuth"
    case walletHandleOidcRedirectCallback = "wallet.handleOidcRedirectCallback"
    case walletUseWallet = "wallet.useWallet"
    case walletCreateWallet = "wallet.createWallet"
    case walletListWallets = "wallet.listWallets"
    case walletSignOut = "wallet.signOut"
    case walletListAccess = "wallet.listAccess"
    case walletListAccessPage = "wallet.listAccessPage"
    case walletListAccessPages = "wallet.listAccessPages"
    case walletGetIdToken = "wallet.getIdToken"
    case walletRevokeAccess = "wallet.revokeAccess"
    case walletSignMessage = "wallet.signMessage"
    case walletSignTypedData = "wallet.signTypedData"
    case walletIsValidMessageSignature = "wallet.isValidMessageSignature"
    case walletIsValidTypedDataSignature = "wallet.isValidTypedDataSignature"
    case walletSendTransaction = "wallet.sendTransaction"
    case walletCallContract = "wallet.callContract"
    case walletExecute = "wallet.execute"
    case walletGetTransactionStatus = "wallet.getTransactionStatus"
    case walletTransactionStatus = "wallet.transactionStatus"
    case indexerGetBalances = "indexer.getBalances"
    case indexerGetTransactionHistory = "indexer.getTransactionHistory"
}
```

Use `operation.rawValue` when logging SDK failures.

### OmsUpstreamService

```swift
enum OmsUpstreamService: String, Sendable {
    case waas = "Waas"
    case indexer = "Indexer"
}
```

### OmsUpstreamError

```swift
struct OmsUpstreamError: Equatable, Sendable {
    let service: OmsUpstreamService
    let name: String?
    let code: String?
    let message: String?
    let status: Int?
}
```

`name` and `code` are service-specific. Indexer non-JSON HTTP failures use a
sanitized fallback message instead of exposing raw HTML or text response bodies.
WaaS non-JSON failures are normalized as `WebrpcBadResponse`.

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

Transaction-flow detail cases may be preserved under
`OmsSdkError.underlyingError`. `noFeeOptionsAvailable` is used when an
unsponsored transaction has no fee options, and `noFeeOptionSelected` is used
when a custom selector does not return a selection for an unsponsored
transaction. Terminal non-executed statuses use `transactionFailed`. A normal
pending polling timeout returns
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

Controls how `sendTransaction` and `callContract` poll transaction status
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
