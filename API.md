# OMS SDK (Swift) — API Reference

## Table of Contents

- [OMSClient](#omsclient)
  - [init](#init)
- [WalletClient](#walletclient)
  - [walletAddress](#walletaddress)
  - [walletId](#walletid)
  - [startEmailAuth](#startemailauth)
  - [completeEmailAuth](#completeemailauth)
  - [signOut](#signout)
  - [signMessage](#signmessage)
  - [sendTransaction](#sendtransaction)
  - [callContract](#callcontract)
  - [getTransactionStatus](#gettransactionstatus)
  - [listAccess](#listaccess)
  - [revokeAccess](#revokeaccess)
- [IndexerClient](#indexerclient)
  - [getTokenBalances](#gettokenbalances)
- [Types](#types)
  - [OMSClientNetwork](#omsclientnetwork)
  - [OMSClientNetworks](#omsclientnetworks)
  - [OMSClientEnvironment](#omsclientenvironment)
  - [FeeOptionSelector](#feeoptionselector)
  - [TransactionError](#transactionerror)
  - [SendTransactionRequest](#sendtransactionrequest)
  - [TokenBalancesResult](#tokenbalancesresult)
  - [TokenBalancesPage](#tokenbalancespage)
  - [TokenBalance](#tokenbalance)
  - [CredentialInfo](#credentialinfo)

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

**Parameters**

| Name | Type | Description |
|---|---|---|
| `projectAccessKey` | `String` | Your OMS project access key. |
| `environment` | `OMSClientEnvironment` | API endpoint configuration. Defaults to the production OMS endpoints. |

**Properties**

| Name | Type | Description |
|---|---|---|
| `wallet` | `WalletClient` | Handles authentication, signing, and transactions. |
| `indexer` | `IndexerClient` | Queries on-chain state and token balances. |
| `utils` | `OMSClientUtils` | Unit parser and formatter helpers. |

---

## WalletClient

Manages the full wallet lifecycle: authentication, keychain session persistence, signing, and transaction submission.

### walletAddress

```swift
var walletAddress: String
```

The on-chain address of the active wallet. Empty string until `completeEmailAuth` resolves successfully. Persisted to the device keychain across launches.

---

### walletId

```swift
var walletId: String
```

The server-side wallet ID. Empty string until `completeEmailAuth` resolves successfully. Persisted to the device keychain.

---

### startEmailAuth

```swift
func startEmailAuth(email: String) async
```

Sends a one-time passcode to the provided email address to begin authentication.

After this returns, display your OTP input UI and pass the code to [`completeEmailAuth`](#completeemailauth).

**Parameters**

| Name | Type | Description |
|---|---|---|
| `email` | `String` | The email address to send the one-time passcode to. |

**Example**

```swift
await oms.wallet.startEmailAuth(email: "user@example.com")
// Show OTP input
```

---

### completeEmailAuth

```swift
func completeEmailAuth(code: String, walletType: WalletType = .ethereum) async
```

Verifies the OTP code and activates a wallet. Must be called after [`startEmailAuth`](#startemailauth).

Automatically loads an existing wallet of `walletType` from the user's account, or creates a new one if none exists. The wallet address, wallet ID, and session key are saved to the device keychain.

**Parameters**

| Name | Type | Description |
|---|---|---|
| `code` | `String` | The one-time passcode entered by the user. |
| `walletType` | `WalletType` | The wallet type to load or create. Defaults to `.ethereum`. |

**Example**

```swift
await oms.wallet.completeEmailAuth(code: "123456")
print("Wallet ready:", oms.wallet.walletAddress)
```

---

### signOut

```swift
func signOut()
```

Clears the wallet session from the device keychain. After this, `walletAddress` and `walletId` are no longer available and the user must authenticate again via [`startEmailAuth`](#startemailauth).

**Example**

```swift
oms.wallet.signOut()
// Navigate to sign-in screen
```

---

### signMessage

```swift
func signMessage(network: String, message: String) async -> String
```

Signs an arbitrary message using the wallet's session key.

**Parameters**

| Name | Type | Description |
|---|---|---|
| `network` | `String` | The network identifier, e.g. `"polygon"`, `"mainnet"`. |
| `message` | `String` | The message to sign. |

**Returns** `String` — a hex-encoded signature.

**Example**

```swift
let signature = await oms.wallet.signMessage(
    network: "polygon",
    message: "Hello from OMS"
)
```

---

### sendTransaction

`sendTransaction` has two overloads. Both use a prepare/execute flow internally: the server calculates available fee options, the `feeOptionSelector` picks one, and the SDK submits then polls until confirmation.

#### Convenience overload

```swift
func sendTransaction(
    network: String,
    to: String,
    value: String,
    feeOptionSelector: FeeOptionSelector = .first
) async throws -> String
```

Sends a native token transfer. Suitable for the most common case.

**Parameters**

| Name | Type | Description |
|---|---|---|
| `network` | `String` | Network to submit on, e.g. `"polygon"`, `"mainnet"`. |
| `to` | `String` | Recipient wallet address. |
| `value` | `String` | Amount to send in the network's smallest denomination (e.g. wei). |
| `feeOptionSelector` | `FeeOptionSelector` | Strategy for selecting a fee option. Defaults to `.first`. See [FeeOptionSelector](#feeoptionselector). |

**Returns** `String` — the confirmed transaction hash.

**Throws** `TransactionError` — see [TransactionError](#transactionerror).

**Example**

```swift
let txHash = try await oms.wallet.sendTransaction(
    network: "polygon",
    to: "0xRecipient",
    value: "1000000000000000000"
)
```

#### Full overload

```swift
func sendTransaction(
    network: String,
    request: SendTransactionRequest,
    feeOptionSelector: FeeOptionSelector = .first
) async throws -> String
```

Sends a transaction with full parameter control, including raw calldata.

**Parameters**

| Name | Type | Description |
|---|---|---|
| `network` | `String` | Network to submit on. |
| `request` | `SendTransactionRequest` | Full transaction parameters. See [SendTransactionRequest](#sendtransactionrequest). |
| `feeOptionSelector` | `FeeOptionSelector` | Strategy for selecting a fee option. Defaults to `.first`. |

**Returns** `String` — the confirmed transaction hash.

**Throws** `TransactionError`.

**Example**

```swift
let txHash = try await oms.wallet.sendTransaction(
    network: "polygon",
    request: SendTransactionRequest(
        to: "0xContract",
        value: "0",
        data: "0xa9059cbb..."
    ),
    feeOptionSelector: .cheapest
)
```

---

### callContract

```swift
func callContract(
    network: String,
    contract: String,
    method: String,
    args: [AbiArg]?,
    feeOptionSelector: FeeOptionSelector = .first
) async throws -> String
```

Calls a state-changing smart contract function. Uses the same prepare/execute/poll flow as `sendTransaction`.

**Parameters**

| Name | Type | Description |
|---|---|---|
| `network` | `String` | Network to submit on. |
| `contract` | `String` | Address of the target contract. |
| `method` | `String` | ABI function signature, e.g. `"transfer(address,uint256)"`. |
| `args` | `[AbiArg]?` | Ordered list of ABI-encoded arguments, or `nil` for no arguments. |
| `feeOptionSelector` | `FeeOptionSelector` | Strategy for selecting a fee option. Defaults to `.first`. |

**Returns** `String` — the confirmed transaction hash.

**Throws** `TransactionError`.

**Example**

```swift
let txHash = try await oms.wallet.callContract(
    network: "polygon",
    contract: "0xTokenContract",
    method: "transfer(address,uint256)",
    args: [
        AbiArg(type: "address", value: .string("0xRecipient")),
        AbiArg(type: "uint256", value: .string("1000000000000000000")),
    ]
)
```

---

### getTransactionStatus

```swift
func getTransactionStatus(txnId: String) async throws -> TransactionStatusResponse
```

Returns the current status for a prepared or submitted transaction. When the transaction has executed, `txnHash` is included when available.

**Parameters**

| Name | Type | Description |
|---|---|---|
| `txnId` | `String` | Transaction ID returned by the wallet API prepare/execute flow. |

**Returns** `TransactionStatusResponse` — includes `status` and optional `txnHash`.

**Example**

```swift
let status = try await oms.wallet.getTransactionStatus(txnId: "txn_...")
```

---

### listAccess

```swift
func listAccess() async -> [CredentialInfo]
```

Returns all credentials that currently have access to this wallet.

**Returns** `[CredentialInfo]` — see [CredentialInfo](#credentialinfo).

**Example**

```swift
let credentials = await oms.wallet.listAccess()
for cred in credentials {
    print(cred.credentialId, "expires:", cred.expiresAt)
}
```

---

### revokeAccess

```swift
func revokeAccess(targetCredentialId: String) async
```

Permanently revokes a credential's access to this wallet. Cannot be undone.

**Parameters**

| Name | Type | Description |
|---|---|---|
| `targetCredentialId` | `String` | The ID of the credential to revoke. Obtain from [`listAccess`](#listaccess). |

**Example**

```swift
let credentials = await oms.wallet.listAccess()
if let other = credentials.first(where: { !$0.isCaller }) {
    await oms.wallet.revokeAccess(targetCredentialId: other.credentialId)
}
```

---

## IndexerClient

Accessed via `oms.indexer`. Queries on-chain token balances through the OMS Indexer API.

### getTokenBalances

```swift
func getTokenBalances(
    chainId: String,
    contractAddress: String,
    walletAddress: String,
    includeMetadata: Bool
) async throws -> TokenBalancesResult
```

Fetches token balances for a wallet on a given chain and contract (first page, up to 40 entries).

**Parameters**

| Name | Type | Description |
|---|---|---|
| `chainId` | `String` | Numeric chain ID for a supported network, e.g. `"137"` or `"80002"`. Legacy slug values still populate the indexer URL template directly. |
| `contractAddress` | `String` | The token contract address to query. |
| `walletAddress` | `String` | The wallet whose balances to fetch. Pass `oms.wallet.walletAddress` for the active wallet. |
| `includeMetadata` | `Bool` | When `true`, includes token metadata (name, symbol, decimals) in the response. |

**Returns** `TokenBalancesResult` — see [TokenBalancesResult](#tokenbalancesresult).

**Throws** if the network request or JSON decoding fails.

**Example**

```swift
let result = try await oms.indexer.getTokenBalances(
    chainId: "137",
    contractAddress: "0xTokenContract",
    walletAddress: oms.wallet.walletAddress,
    includeMetadata: true
)

for balance in result.balances {
    print(balance.contractAddress ?? "", balance.balance ?? "")
}
```

---

## Types

### OMSClientNetwork

```swift
enum OMSClientNetwork: String, CaseIterable, Sendable, CustomStringConvertible {
    case polygon
    case polygonAmoy

    var chainId: String
    var displayName: String
    var description: String
}
```

| Case | Chain ID | Display name |
|---|---|---|
| `.polygon` | `137` | Polygon |
| `.polygonAmoy` | `80002` | Polygon Amoy |

---

### OMSClientNetworks

```swift
final class OMSClientNetworks {
    static let supportedNetworks: [OMSClientNetwork]
    static func network(chainId: String) -> OMSClientNetwork?
}
```

Static access point for chain-id binding helpers.

---

### OMSClientEnvironment

```swift
struct OMSClientEnvironment {
    static let defaultScope: String

    let walletApiUrl: String
    let apiRpcUrl: String
    let indexerUrlTemplate: String
    var indexerURLTemplate: String
    let scope: String

    func indexerURL(for network: OMSClientNetwork) -> URL?

    init(
        walletApiUrl: String = "https://d1sctl7y41hot5.cloudfront.net",
        apiRpcUrl: String = "https://dev-api.sequence.app/rpc/API",
        indexerUrlTemplate: String = "https://dev-{value}-indexer.sequence.app/rpc/Indexer/",
        scope: String = OMSClientEnvironment.defaultScope
    )
}
```

| Field | Type | Description |
|---|---|---|
| `walletApiUrl` | `String` | Base URL of the OMS Wallet API. |
| `apiRpcUrl` | `String` | Base URL of the OMS API RPC. |
| `indexerUrlTemplate` | `String` | URL template for the Indexer. `{value}` is replaced with the chain ID, e.g. `"https://indexer.example.com/{value}"`. |
| `scope` | `String` | Authorization scope used for signed wallet requests. Defaults to `"proj_1"`. |

The default production configuration is available via `OMSClientEnvironment()`.

---

### FeeOptionSelector

```swift
struct FeeOptionSelector {
    static let first: FeeOptionSelector
    static let cheapest: FeeOptionSelector
    static func custom(_ pick: @escaping Select) -> FeeOptionSelector
}
```

Encapsulates the strategy used to choose a fee option during the transaction prepare/execute flow. All `sendTransaction` and `callContract` calls accept an optional `feeOptionSelector` parameter.

| Selector | Description |
|---|---|
| `.first` | Picks the first fee option returned by the server. Default. |
| `.cheapest` | Picks the option with the lowest fee value. |
| `.custom { options in ... }` | Calls your closure with the full `[FeeOption]` list. Return the option the user selected. Can `throw` to cancel the transaction. |

**Example — presenting a fee picker to the user**

```swift
let txHash = try await oms.wallet.sendTransaction(
    network: "polygon",
    to: "0xRecipient",
    value: "1000000000000000000",
    feeOptionSelector: .custom { options in
        // Present options in your UI and return the chosen one.
        return options[userSelectedIndex]
    }
)
```

---

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

| Case | Description |
|---|---|
| `.noFeeOptionsAvailable` | The server returned no fee options during the prepare step. |
| `.missingTransactionHash` | The transaction was marked as executed but no hash was returned. |
| `.transactionFailed(status:)` | The transaction reached a terminal non-executed status. The associated `TransactionStatus` value describes the failure. |
| `.pollingTimedOut` | The transaction remained pending after the maximum number of polling attempts (~45 seconds). Check the network or retry. |

---

### SendTransactionRequest

```swift
struct SendTransactionRequest {
    let to: String
    let value: String
    let data: String?
}
```

Used with the full overload of `sendTransaction`.

| Field | Type | Description |
|---|---|---|
| `to` | `String` | Recipient or contract address. |
| `value` | `String` | Native token value in the network's smallest denomination (e.g. wei). Pass `"0"` for contract calls with no value. |
| `data` | `String?` | Pre-encoded hex calldata for contract interactions. `nil` for plain transfers. |

---

### TokenBalancesResult

```swift
struct TokenBalancesResult {
    let status: Int
    let page: TokenBalancesPage?
    let balances: [TokenBalance]
}
```

| Field | Type | Description |
|---|---|---|
| `status` | `Int` | HTTP status code of the indexer response. |
| `page` | `TokenBalancesPage?` | Pagination metadata, if present. |
| `balances` | `[TokenBalance]` | Array of token balance entries. |

---

### TokenBalancesPage

```swift
struct TokenBalancesPage: Codable {
    let page: Int
    let pageSize: Int
    let more: Bool
}
```

| Field | Type | Description |
|---|---|---|
| `page` | `Int` | Current page index (zero-based). |
| `pageSize` | `Int` | Number of entries per page (up to 40). |
| `more` | `Bool` | `true` if additional pages are available. |

---

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

| Field | Type | Description |
|---|---|---|
| `contractType` | `String?` | Token standard, e.g. `"ERC20"`, `"ERC721"`, `"ERC1155"`. |
| `contractAddress` | `String?` | Address of the token contract. |
| `accountAddress` | `String?` | Wallet address this balance belongs to. |
| `tokenId` | `String?` | For ERC-721/ERC-1155 tokens, the token ID. Decoded from the wire key `tokenID`. |
| `balance` | `String?` | Balance in the token's smallest denomination. |
| `blockHash` | `String?` | Block hash at which this balance was recorded. |
| `blockNumber` | `Int64?` | Block number at which this balance was recorded. |
| `chainId` | `Int64?` | Numeric chain ID. |

---

### CredentialInfo

```swift
struct CredentialInfo: Codable {
    let credentialId: String
    let expiresAt: String
    let isCaller: Bool
}
```

Returned by [`listAccess`](#listaccess). Represents a credential that has access to the wallet.

| Field | Type | Description |
|---|---|---|
| `credentialId` | `String` | Unique identifier. Pass to `revokeAccess` to remove this credential. |
| `expiresAt` | `String` | ISO 8601 timestamp for when this credential expires. |
| `isCaller` | `Bool` | `true` if this credential belongs to the current active session. |
