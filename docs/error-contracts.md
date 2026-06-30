# Public Error Contracts

This document is the audit surface for Swift SDK error behavior. It records which
public runtime surfaces can fail, which structured `OmsSdkError` shape apps
should see, what recovery decision the error supports, whether `upstreamError`
should be present, and which tests own the contract.

## Terms

- `code` is the stable app-facing compatibility field. Branch on
  `OmsSdkErrorCode` raw values for durable app behavior.
- `operation` identifies the public SDK operation that failed. Use
  `operation.rawValue` for logs and analytics.
- `retryable` is nullable. When it is non-nil, it describes the failed SDK
  operation, not the whole user intent. For example, retryable transaction
  status polling means retry status lookup; it does not mean blindly resend the
  original transaction write.
- `upstreamError` is normalized diagnostic detail from a remote OMS service
  response, malformed remote response, or transport failure. Use it for logging
  and service-specific troubleshooting, not primary app branching.
- `underlyingError` is Swift-local diagnostic context. It is present when the
  SDK wraps a lower-level Swift error such as `WebRPCError`,
  `WebRPCTransportError`, `TransactionError`, `HttpError`, `URLError`, or a
  decoding error. It can be absent for deliberate local SDK errors such as
  missing session and stale wallet selection, and for manually constructed
  `OmsSdkError` values unless the caller supplies it. Do not serialize or depend
  on `underlyingError` for cross-SDK behavior.
- `OMS_TRANSACTION_EXECUTION_UNCONFIRMED` means transaction preparation
  succeeded and produced a `txnId`, but the execute request failed before the
  SDK could confirm whether the transaction was submitted. Do not blindly resend
  the write.
- `OMS_TRANSACTION_STATUS_LOOKUP_FAILED` means the transaction was submitted,
  but post-submit status polling failed. Retry by checking transaction status
  with the returned `txnId`.

## Maintenance Approach

- Update this matrix, `Tests/Swift SDKTests/PublicErrorContractsTests.swift`,
  `API.md`, and `README.md` together when a public SDK method gains, removes, or
  intentionally changes an error contract.
- Keep backend and upstream mapping tests representative rather than exhaustive
  per method. Cover each transport or response family through real public calls
  instead of duplicating the same assertions for every method.
- Public runtime methods should own runtime error contract coverage. Only assert
  manually constructed `OmsSdkError` values when the initializer or field shape
  itself is the unit under test.
- Keychain, signer, and storage classes are internal platform boundaries in this
  SDK. Cover their failures in focused tests unless a failure is intentionally
  normalized through a documented public `OmsSdkError`.
- Serialized contract changes are not automatically regressions. Decide whether
  the new error shape is the intended public contract: if correct, update the
  assertion and related docs; if accidental, fix the implementation.
- Treat message changes as user-visible API changes, even when `code` and
  recovery behavior are unchanged.

## SDK Matrix

| Public surface | Failure family | User-facing error | Recovery meaning | `upstreamError` | Covering test |
|---|---|---|---|---|---|
| `oms.wallet.startEmailAuth`, representative WaaS methods | WaaS transport failure | `OmsSdkError`, `.requestFailed`, operation-specific, `retryable == true` for transport failures | Retry the same read/auth request when appropriate | Present | `PublicErrorContractsTests.swift` |
| `oms.wallet.completeEmailAuth` | WaaS domain error | SDK-specific code such as `.authCommitmentConsumed` | Follow the SDK code; for consumed commitments, restart auth | Present | `PublicErrorContractsTests.swift` |
| `oms.wallet.*`, representative WaaS methods | WaaS HTTP error | `OmsSdkError`, `.httpError`, `status`, `retryable == true` for 5xx | Use SDK code/status for branching; log upstream detail | Present | `PublicErrorContractsTests.swift` |
| `oms.wallet.completeEmailAuth` and `PendingWalletSelection` actions | Local auth/session/selection state | `.sessionMissing`, `.walletSelectionStale`, or `.walletSelectionUnavailable` | Fix local flow state or restart auth; no remote diagnostics are expected | Absent | `PublicErrorContractsTests.swift` |
| OIDC redirect and ID-token auth methods | Local OIDC config, callback, storage, or state mismatch | `.sessionMissing`, `.validationError`, or failed OIDC result containing `OmsSdkError` | Fix redirect config/state or restart OIDC flow | Absent | `PublicErrorContractsTests.swift` |
| Protected wallet methods: `getIdToken`, `signMessage`, `signTypedData`, `sendTransaction`, `callContract`, `getTransactionStatus`, `listAccessPage`, `listAccessPages`, `revokeAccess` | Missing or expired local session | `.sessionMissing` or `.sessionExpired` | Authenticate again or recover local session; no remote request was made | Absent | `PublicErrorContractsTests.swift` |
| `oms.wallet.signMessage`, `signTypedData`, `getIdToken`, `sendTransaction`, `callContract` | SDK-local validation or fee-selection failure | `.validationError` | Correct parameters or local fee selection; do not retry as an upstream outage | Absent | `PublicErrorContractsTests.swift` |
| `oms.wallet.isValidMessageSignature`, `isValidTypedDataSignature` | WaaS validation backend failure | `.httpError`, `.requestFailed`, or `.invalidResponse` with the validation operation | Retry based on SDK code/status; log upstream detail | Present | `PublicErrorContractsTests.swift` |
| `oms.wallet.sendTransaction`, `callContract` | Execute request fails after prepare | `.transactionExecutionUnconfirmed`, `operation == .walletExecute`, `retryable == false`, `txnId` | Do not blindly resend the write; preserve `txnId` and upstream detail for diagnostics | Present when execute crossed a transport/upstream boundary | `PublicErrorContractsTests.swift` |
| `oms.wallet.sendTransaction`, `callContract` | Submitted transaction status polling fails | `.transactionStatusLookupFailed`, `operation == .walletTransactionStatus`, `retryable == true`, `txnId` | Retry status lookup, not the original write | Present when polling crossed a transport/upstream boundary | `PublicErrorContractsTests.swift` |
| `oms.wallet.getTransactionStatus` | Direct status lookup backend failure | `.httpError`, `.requestFailed`, or `.invalidResponse` with `operation == .walletGetTransactionStatus` | Retry status lookup or surface backend status to the user | Present | `PublicErrorContractsTests.swift` |
| `oms.wallet.listAccessPage`, `listAccessPages`, `revokeAccess` | WaaS access backend failure | `.httpError`, `.requestFailed`, or `.invalidResponse` with access operation | Retry based on SDK code/status; log upstream detail | Present | `PublicErrorContractsTests.swift` |
| `oms.indexer.getBalances`, `getTransactionHistory` | IndexerGateway backend, transport, malformed JSON, or malformed payload | `.httpError`, `.requestFailed`, or `.invalidResponse` with indexer operation | Retry based on SDK code/status; log upstream detail | Present for remote/transport response failures | `PublicErrorContractsTests.swift` |
| `oms.indexer.getBalances`, `getTransactionHistory` | IndexerGateway non-JSON HTTP body | `.httpError` with sanitized message | Do not expose raw upstream HTML/text bodies; log normalized detail | Present, sanitized | `PublicErrorContractsTests.swift` |
| Public `OmsSdkError` initializer and upstream fields | Error field contract | Stable public fields on constructed errors | Use only when the initializer/field shape is the unit under test | As constructed | `PublicErrorContractsTests.swift` |
