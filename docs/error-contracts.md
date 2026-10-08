# Public Error Contracts

This document is the audit surface for Swift SDK error behavior. It records which
public runtime surfaces can fail, which structured `OMSWalletError` shape apps
should see, what recovery decision the error supports, whether `upstreamError`
should be present, and which tests own the contract.

## Terms

- `code` is the stable app-facing compatibility field. Branch on
  `OMSWalletErrorCode` raw values for durable app behavior.
- `operation` identifies the public SDK operation that failed. Use
  `operation.rawValue` for logs and analytics.
- `retryable` is nullable. When it is non-nil, it describes the failed SDK
  operation, not the whole user intent. For example, retryable transaction
  status polling means retry status lookup; it does not mean blindly resend the
  original transaction write.
- `upstreamError` is normalized diagnostic detail from a remote OMS service
  response, malformed remote response, or transport failure. Use it for logging
  and service-specific troubleshooting, not primary app branching.
  `upstreamError.service` is `.waas` or `.indexer` (raw values `"waas"` and
  `"indexer"`). `upstreamError.code` is a string; numeric WebRPC codes are
  stringified (e.g. `"7313"`).
- `underlyingError` is Swift-local diagnostic context. It is present when the
  SDK wraps a lower-level Swift error such as an internal transaction-flow error, HTTP transport
  failures, `URLError`, generated service-client failures, or a decoding error.
  It can be absent for deliberate local SDK errors such as missing session and
  stale wallet selection. Do not serialize or depend on `underlyingError` for
  cross-SDK behavior.
- `OMS_TRANSACTION_EXECUTION_UNCONFIRMED` means transaction preparation
  succeeded and produced a `txnId`, but the execute request failed before the
  SDK could confirm whether the transaction was submitted. Do not blindly resend
  the write.
- `OMS_TRANSACTION_STATUS_LOOKUP_FAILED` means the transaction was submitted,
  but post-submit status polling failed. Retry by checking transaction status
  with the returned `txnId`.

## Maintenance Approach

- Update this matrix, `Tests/OMSWalletTests/PublicErrorContractsTests.swift`,
  `API.md`, and `README.md` together when a public SDK method gains, removes, or
  intentionally changes an error contract.
- Keep backend and upstream mapping tests representative rather than exhaustive
  per method. Cover each transport or response family through real public calls
  instead of duplicating the same assertions for every method.
- Public runtime methods should own runtime error contract coverage. Use internal
  test fixtures only when the normalized field shape itself is the unit under test.
- Keychain, signer, and storage classes are internal platform boundaries in this
  SDK. Cover their failures in focused tests unless a failure is intentionally
  normalized through a documented public `OMSWalletError`.
- Serialized contract changes are not automatically regressions. Decide whether
  the new error shape is the intended public contract: if correct, update the
  assertion and related docs; if accidental, fix the implementation.
- Treat message changes as user-visible API changes, even when `code` and
  recovery behavior are unchanged.

## SDK Matrix

| Public surface | Failure family | User-facing error | Recovery meaning | `upstreamError` | Covering test |
|---|---|---|---|---|---|
| `omsWallet.wallet.startEmailAuth`, representative WaaS methods | WaaS transport failure | `OMSWalletError`, `.requestFailed`, operation-specific, `retryable == true` for transport failures | Retry the same read/auth request when appropriate | Present | `PublicErrorContractsTests.swift` |
| `omsWallet.wallet.completeEmailAuth` | WaaS domain error | SDK-specific code such as `.authCommitmentConsumed` | Follow the SDK code; for consumed commitments, restart auth | Present | `PublicErrorContractsTests.swift` |
| `omsWallet.wallet.*`, representative WaaS methods | WaaS HTTP error | `OMSWalletError`, `.httpError`, `status`, `retryable == true` for 5xx | Use SDK code/status for branching; log upstream detail | Present | `PublicErrorContractsTests.swift` |
| `omsWallet.wallet.completeEmailAuth` and `PendingWalletSelection` actions | Local auth/session/selection state | `.sessionMissing`, `.walletSelectionStale`, `.walletSelectionUnavailable`, or `.walletSelectionInFlight` (`OMS_WALLET_SELECTION_IN_FLIGHT`) | Fix local flow state or restart auth; no remote diagnostics are expected | Absent | `PublicErrorContractsTests.swift` |
| OIDC redirect and ID-token auth methods | Local OIDC config or validated callback failure | Thrown `OMSWalletError` with `.sessionMissing` or `.validationError` | Fix redirect config or restart OIDC flow | Absent | `PublicErrorContractsTests.swift` |
| `handleOIDCRedirectCallback` | URL or state does not match the pending redirect | `.notOIDCRedirectCallback` result | Ignore the unrelated callback; the pending redirect remains available | Absent | `MockWalletTests.swift` |
| `omsWallet.wallet.startOIDCRedirectAuth`, `handleOIDCRedirectCallback` | Local OIDC redirect-state persistence or restore failure | Thrown `OMSWalletError` with `.storageError` | Retry OIDC auth after resolving the local storage issue | Absent | `PublicErrorContractsTests.swift` |
| Protected wallet methods: `getIdToken`, signing and transaction methods, wallet import, `getTransactionStatus`, access authorization/usage/listing/revocation | Missing or expired local session | `.sessionMissing` or `.sessionExpired` | Authenticate again or recover local session; no remote request was made | Absent | `PublicErrorContractsTests.swift` |
| `isValidMessageSignature`, `isValidTypedDataSignature`, `isValidSolanaMessageSignature`, `isValidTronMessageSignature`, `isValidTronTypedDataSignature` called without `walletAddress` | No active wallet, or the active wallet belongs to another chain family | `.sessionMissing` (or `.sessionExpired`), or `.validationError` | Sign in with a wallet of the method's family, or pass `walletAddress`; with an address no session is required. No remote request was made | Absent | `SignatureVerificationTests.swift` |
| Wallet signing, transactions, import, and owner access methods | SDK-local validation, wallet-family mismatch (checked against the active wallet's stored type), non-bare contract `method` name, or fee-selection failure | `.validationError` | Correct parameters, select the required wallet family, or fix local fee selection; do not retry as an upstream outage | Absent | `PublicErrorContractsTests.swift`, `WalletImportTests.swift`, `MockWalletTests.swift`, `TronWalletTests.swift` |
| Wallet auth, selection, creation, and import methods | Successful WaaS response with an Ethereum wallet address that is not `0x` plus 40 hex digits, or an unreadable credential `expiresAt` | `.invalidResponse` | Treat the payload as unusable; the wallet is not activated | Absent | `ActiveWalletSessionTests.swift` |
| `omsWallet.wallet.importWallet`, `importEncryptedWallet` | Address already imported (WaaS `AddressAlreadyImported`, code `7313`) | `.walletAddressAlreadyImported` (`OMS_WALLET_ADDRESS_ALREADY_IMPORTED`), `status == 409`, `retryable == false`; the active wallet is unchanged | Select the existing wallet or use a different key | Present | `PublicErrorContractsTests.swift` |
| `omsWallet.wallet.getWalletImportRecipientKey`, `importWallet`, `importEncryptedWallet` | Recipient-key attestation is missing, stale, malformed, untrusted, or does not match the request/response | `.attestationVerificationFailed` with the wallet-import operation | Do not encrypt or submit key material; retry only after confirming the SDK's managed PCR0 trust policy and WaaS environment | Absent | `WalletImportTests.swift` |
| `omsWallet.wallet.isValidMessageSignature`, `isValidSolanaMessageSignature`, `isValidTypedDataSignature`, `isValidTronMessageSignature`, `isValidTronTypedDataSignature` | WaaS validation backend failure | `.httpError`, `.requestFailed`, or `.invalidResponse` with the validation operation | Retry based on SDK code/status; log upstream detail | Present | `PublicErrorContractsTests.swift` |
| `omsWallet.wallet.sendTransaction`, `sendSolanaTransfer`, `sendTronTransaction`, `callContract`, `callTronContract` | Execute request fails after prepare | `.transactionExecutionUnconfirmed`, `operation == .walletExecute`, `retryable == false`, `txnId` | Do not blindly resend the write; preserve `txnId` and upstream detail for diagnostics | Present when execute crossed a transport/upstream boundary | `PublicErrorContractsTests.swift` |
| `omsWallet.wallet.sendTransaction`, `sendSolanaTransfer`, `sendTronTransaction`, `callContract`, `callTronContract` | Submitted transaction status polling fails | `.transactionStatusLookupFailed`, `operation == .walletTransactionStatus`, `retryable == true`, `txnId` | Retry status lookup, not the original write | Present when polling crossed a transport/upstream boundary | `PublicErrorContractsTests.swift` |
| `omsWallet.wallet.getTransactionStatus` | Direct status lookup backend failure | `.httpError`, `.requestFailed`, or `.invalidResponse` with `operation == .walletGetTransactionStatus` | Retry status lookup or surface backend status to the user | Present | `PublicErrorContractsTests.swift` |
| `omsWallet.wallet.inspectRemoteCredential`, `authorizeRemoteAccess`, `getRemoteAccessSession`, `getRemoteAccessSessionUsage`, access listing and revocation | WaaS owner-access backend failure | `.httpError`, `.requestFailed`, or `.invalidResponse` with access operation | Retry based on SDK code/status; log upstream detail | Present | `PublicErrorContractsTests.swift`, `MockWalletTests.swift` |
| `omsWallet.indexer.getBalances`, `getTransactionHistory`, `getSolanaBalances`, `getTronBalances` | IndexerGateway backend, transport, malformed JSON, or malformed payload | `.httpError`, `.requestFailed`, or `.invalidResponse` with indexer operation | Retry based on SDK code/status; log upstream detail | Present for remote/transport response failures | `PublicErrorContractsTests.swift`, `IndexerTests.swift` (including `TestGetTronBalancesRejectsInvalidResponses` and `TestGetTronBalancesSurfacesGatewayRequestErrors`) |
| `omsWallet.indexer.getBalances`, `getTransactionHistory`, `getSolanaBalances`, `getTronBalances` | IndexerGateway non-JSON HTTP body | `.httpError` with sanitized message | Do not expose raw upstream HTML/text bodies; log normalized detail | Present, sanitized | `PublicErrorContractsTests.swift` |
| Normalized `OMSWalletError` values | Error field contract | Stable public fields on SDK-produced errors | Branch on `code`; use the remaining fields for recovery and diagnostics | As normalized by the SDK | `PublicErrorContractsTests.swift` |
