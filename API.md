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
let oms = OMSClient(projectAccessKey: "your-key")
```

### init

```swift
init(projectAccessKey: String, environment: OMSClientEnvironment = OMSClientEnvironment())
```

| Parameter | Type | Description |
|---|---|---|
| `projectAccessKey` | `String` | OMS project access key. |
| `environment` | `OMSClientEnvironment` | API endpoint and authorization-scope configuration. |

### Properties

| Name | Type | Description |
|---|---|---|
| `wallet` | `WalletClient` | Authentication, signing, access, and transaction helper. |
| `indexer` | `IndexerClient` | Token balance query helper. |
| `supportedNetworks` | `[Network]` | Supported SDK network list. |

### network

```swift
func network(chainId: String) -> Network?
```

Returns the supported `Network` for a numeric chain ID, or `nil` when the chain is not supported.

---

## WalletClient

Accessed via `oms.wallet`. Manages wallet authentication, non-extractable Keychain request signing, keychain session persistence, signing, signature verification, and transaction submission.

### walletAddress

```swift
var walletAddress: String
```

The on-chain address of the active wallet. Empty until a wallet is restored or activated by `completeEmailAuth`.

### walletId

```swift
var walletId: String
```

The server-side wallet ID. Empty until a wallet is restored or activated by `completeEmailAuth`.

### session

```swift
var session: SessionState
```

Snapshot of the currently completed wallet session for this wallet client.

### startEmailAuth

```swift
func startEmailAuth(email: String) async throws
```

Sends a one-time passcode to the provided email address.

### completeEmailAuth

```swift
func completeEmailAuth(code: String, walletType: WalletType = .ethereum) async throws
```

Verifies the OTP code and activates an existing or newly created wallet.

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
    feeOptionSelector: FeeOptionSelector = .first
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
    feeOptionSelector: FeeOptionSelector = .first
) async throws -> String
```

### callContract

```swift
func callContract(
    network: Network,
    contract: String,
    method: String,
    args: [AbiArg]?,
    feeOptionSelector: FeeOptionSelector = .first
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
    case polygon
    case polygonAmoy

    var chainId: String
    var displayName: String
    var description: String

    static var supportedNetworks: [Network]
    static func from(chainId: String) -> Network?
}
```

| Case | Chain ID | Display name | Indexer value |
|---|---|---|---|
| `.polygon` | `137` | Polygon | `polygon` |
| `.polygonAmoy` | `80002` | Polygon Amoy | `amoy` |

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
    static let defaultScope: String

    let walletApiUrl: String
    let apiRpcUrl: String
    let indexerUrlTemplate: String
    let scope: String

    var indexerURLTemplate: String

    init(
        walletApiUrl: String = OMSClientEnvironment.defaultWalletApiUrl,
        apiRpcUrl: String = OMSClientEnvironment.defaultApiRpcUrl,
        indexerUrlTemplate: String = OMSClientEnvironment.defaultIndexerUrlTemplate,
        scope: String = OMSClientEnvironment.defaultScope
    )

    init(
        walletApiUrl: String = OMSClientEnvironment.defaultWalletApiUrl,
        apiRpcUrl: String = OMSClientEnvironment.defaultApiRpcUrl,
        indexerURLTemplate: String,
        scope: String = OMSClientEnvironment.defaultScope
    )

    func indexerURL(for network: Network) -> URL?
}
```

| Field | Type | Description |
|---|---|---|
| `walletApiUrl` | `String` | Base URL of the OMS Wallet API. |
| `apiRpcUrl` | `String` | Base URL of the OMS API RPC. |
| `indexerUrlTemplate` | `String` | URL template for the Indexer. `{value}` is replaced with the network indexer name. |
| `scope` | `String` | Authorization scope used for signed wallet requests. |

### FeeOptionSelector

```swift
struct FeeOptionSelector {
    static let first: FeeOptionSelector
    static let cheapest: FeeOptionSelector
    static func custom(_ pick: @escaping Select) -> FeeOptionSelector
}
```

Chooses a fee option during the transaction prepare/execute flow.

| Selector | Description |
|---|---|
| `.first` | Picks the first fee option returned by the server. |
| `.cheapest` | Picks the option with the lowest numeric fee value. |
| `.custom { options in ... }` | Calls your closure with the full `[FeeOption]` list. |

### TransactionError

```swift
enum TransactionError: Error {
    case noFeeOptionsAvailable
    case missingTransactionHash
    case transactionFailed(status: TransactionStatus)
    case pollingTimedOut
}
```

Thrown by `sendTransaction` and `callContract`.

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
