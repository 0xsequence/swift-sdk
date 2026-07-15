import Foundation

public enum OMSWalletErrorCode: String, Sendable {
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
    case storageError = "OMS_STORAGE_ERROR"
}

public enum OMSWalletOperation: String, Sendable {
    case pendingWalletSelection = "wallet.pendingWalletSelection"
    case pendingWalletSelectionSelectWallet = "wallet.pendingWalletSelection.selectWallet"
    case pendingWalletSelectionCreateAndSelectWallet = "wallet.pendingWalletSelection.createAndSelectWallet"
    case walletStartEmailAuth = "wallet.startEmailAuth"
    case walletCompleteEmailAuth = "wallet.completeEmailAuth"
    case walletSignInWithOidcIdToken = "wallet.signInWithOidcIdToken"
    case walletStartOIDCRedirectAuth = "wallet.startOIDCRedirectAuth"
    case walletHandleOIDCRedirectCallback = "wallet.handleOIDCRedirectCallback"
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

public enum OMSWalletUpstreamService: String, Sendable {
    case waas = "Waas"
    case indexer = "Indexer"
}

public struct OMSWalletUpstreamError: Equatable, Sendable {
    public let service: OMSWalletUpstreamService
    public let name: String?
    public let code: String?
    public let message: String?
    public let status: Int?

    init(
        service: OMSWalletUpstreamService,
        name: String? = nil,
        code: String? = nil,
        message: String? = nil,
        status: Int? = nil
    ) {
        self.service = service
        self.name = name
        self.code = code
        self.message = message
        self.status = status
    }
}

public struct OMSWalletError: Error, LocalizedError, @unchecked Sendable {
    public let code: OMSWalletErrorCode
    public let operation: OMSWalletOperation?
    public let status: Int?
    public let txnId: String?
    public let retryable: Bool?
    public let upstreamError: OMSWalletUpstreamError?
    public let underlyingError: (any Error)?
    private let message: String

    init(
        code: OMSWalletErrorCode,
        message: String,
        operation: OMSWalletOperation? = nil,
        status: Int? = nil,
        txnId: String? = nil,
        retryable: Bool? = nil,
        upstreamError: OMSWalletUpstreamError? = nil,
        underlyingError: (any Error)? = nil
    ) {
        self.code = code
        self.message = message
        self.operation = operation
        self.status = status
        self.txnId = txnId
        self.retryable = retryable
        self.upstreamError = upstreamError
        self.underlyingError = underlyingError
    }

    public var errorDescription: String? {
        message
    }
}

extension OMSWalletError {
    static func walletSelectionUnavailable(
        operation: OMSWalletOperation? = nil
    ) -> OMSWalletError {
        OMSWalletError(
            code: .walletSelectionUnavailable,
            message: "Selected wallet is not one of the available options.",
            operation: operation
        )
    }

    static func walletSelectionStale(
        operation: OMSWalletOperation? = nil
    ) -> OMSWalletError {
        OMSWalletError(
            code: .walletSelectionStale,
            message: "Pending wallet selection is no longer active.",
            operation: operation
        )
    }

    static func sessionMissing(
        operation: OMSWalletOperation? = nil
    ) -> OMSWalletError {
        OMSWalletError(
            code: .sessionMissing,
            message: "No authenticated wallet session.",
            operation: operation
        )
    }

    static func sessionExpired(
        operation: OMSWalletOperation? = nil
    ) -> OMSWalletError {
        OMSWalletError(
            code: .sessionExpired,
            message: "No active credential.",
            operation: operation
        )
    }

    static func walletSelectionInFlight(
        operation: OMSWalletOperation? = nil
    ) -> OMSWalletError {
        OMSWalletError(
            code: .walletSelectionInFlight,
            message: "Pending wallet selection is already processing.",
            operation: operation
        )
    }

    static func storageError(
        message: String,
        operation: OMSWalletOperation? = nil,
        underlyingError: (any Error)? = nil
    ) -> OMSWalletError {
        OMSWalletError(
            code: .storageError,
            message: message,
            operation: operation,
            underlyingError: underlyingError
        )
    }
}

@available(macOS 12.0, iOS 15.0, *)
func runOMSWalletOperation<T>(
    _ operation: OMSWalletOperation,
    _ body: () async throws -> T
) async throws -> T {
    do {
        return try await body()
    } catch let error as CancellationError {
        throw error
    } catch {
        throw toOMSWalletError(error, operation: operation)
    }
}

@available(macOS 12.0, iOS 15.0, *)
func runOMSWalletOperation<T>(
    _ operation: OMSWalletOperation,
    _ body: () throws -> T
) throws -> T {
    do {
        return try body()
    } catch {
        throw toOMSWalletError(error, operation: operation)
    }
}

func toOMSWalletError(_ error: any Error, operation: OMSWalletOperation) -> OMSWalletError {
    if let omsError = error as? OMSWalletError {
        if omsError.operation == operation || omsError.isNestedTransactionBoundary {
            return omsError
        }
        return OMSWalletError(
            code: omsError.code,
            message: omsError.localizedDescription,
            operation: operation,
            status: omsError.status,
            txnId: omsError.txnId,
            retryable: omsError.retryable,
            upstreamError: omsError.upstreamError,
            underlyingError: omsError
        )
    }

    if let webRPCError = error as? WebRPCError {
        return webRPCError.toOMSWalletError(operation: operation)
    }

    if let transportError = error as? WebRPCTransportError {
        return OMSWalletError(
            code: .requestFailed,
            message: transportError.message,
            operation: operation,
            retryable: true,
            upstreamError: transportError.toWaasUpstreamError(),
            underlyingError: transportError
        )
    }

    if let transactionError = error as? TransactionError {
        return transactionError.toOMSWalletError(operation: operation)
    }

    if let httpError = error as? HttpError {
        return httpError.toOMSWalletError(operation: operation)
    }

    if error is DecodingError {
        return OMSWalletError(
            code: .invalidResponse,
            message: error.localizedDescription,
            operation: operation,
            underlyingError: error
        )
    }

    if error is KeychainManager.KeychainError || error is AppleKeychainP256CredentialSigner.SignerError {
        return .storageError(
            message: error.localizedDescription,
            operation: operation,
            underlyingError: error
        )
    }

    return OMSWalletError(
        code: .validationError,
        message: error.localizedDescription,
        operation: operation,
        underlyingError: error
    )
}

private extension WebRPCError {
    func toOMSWalletError(operation: OMSWalletOperation) -> OMSWalletError {
        let normalizedStatus = normalizedStatus
        let upstreamError = toWaasUpstreamError(status: normalizedStatus)
        let normalizedMessage = normalizedMessage

        if kind == .commitmentConsumed {
            return OMSWalletError(
                code: .authCommitmentConsumed,
                message: normalizedMessage,
                operation: operation,
                status: normalizedStatus,
                retryable: false,
                upstreamError: upstreamError,
                underlyingError: self
            )
        }

        if isHttpWebRPCError(status: normalizedStatus) {
            return OMSWalletError(
                code: .httpError,
                message: normalizedMessage,
                operation: operation,
                status: normalizedStatus,
                retryable: normalizedStatus.map { $0 >= 500 } ?? false,
                upstreamError: upstreamError,
                underlyingError: self
            )
        }

        if kind == .webrpcBadResponse || (kind == .unknown && code == WebRPCErrorKind.unknown.code) {
            return OMSWalletError(
                code: .invalidResponse,
                message: normalizedMessage,
                operation: operation,
                status: normalizedStatus,
                upstreamError: upstreamError,
                underlyingError: self
            )
        }

        return OMSWalletError(
            code: .requestFailed,
            message: normalizedMessage,
            operation: operation,
            status: normalizedStatus,
            retryable: normalizedStatus.map { $0 >= 500 } ?? true,
            upstreamError: upstreamError,
            underlyingError: self
        )
    }

    private var normalizedStatus: Int? {
        if error == "WebrpcRequestFailed",
           code == WebRPCErrorKind.webrpcRequestFailed.code,
           status == 400 {
            return nil
        }
        return status
    }

    private var normalizedCode: String {
        if error == "WebrpcBadResponse", code == WebRPCErrorKind.unknown.code {
            return String(WebRPCErrorKind.webrpcBadResponse.code)
        }
        return String(code)
    }

    private var normalizedMessage: String {
        if error == "WebrpcBadResponse", code == WebRPCErrorKind.unknown.code {
            return "bad response"
        }
        return message
    }

    private func toWaasUpstreamError(status: Int?) -> OMSWalletUpstreamError {
        OMSWalletUpstreamError(
            service: .waas,
            name: error,
            code: normalizedCode,
            message: normalizedMessage,
            status: status
        )
    }

    private func isHttpWebRPCError(status: Int?) -> Bool {
        guard let status, status >= 400 && status <= 599 else {
            return false
        }

        switch kind {
        case .webrpcBadRoute,
             .webrpcBadMethod,
             .webrpcBadRequest,
             .webrpcBadResponse,
             .webrpcServerPanic,
             .webrpcInternalError:
            return true
        default:
            return error == "WebrpcBadResponse"
        }
    }
}

private extension TransactionError {
    func toOMSWalletError(operation: OMSWalletOperation) -> OMSWalletError {
        switch self {
        case .pollingTimedOut:
            return OMSWalletError(
                code: .transactionStatusLookupFailed,
                message: localizedDescription,
                operation: operation,
                retryable: true,
                underlyingError: self
            )
        case .noFeeOptionsAvailable, .noFeeOptionSelected, .missingTransactionHash, .invalidPollingOption:
            return OMSWalletError(
                code: .validationError,
                message: localizedDescription,
                operation: operation,
                underlyingError: self
            )
        case .transactionFailed:
            return OMSWalletError(
                code: .requestFailed,
                message: localizedDescription,
                operation: operation,
                retryable: false,
                underlyingError: self
            )
        }
    }
}

private extension HttpError {
    func toOMSWalletError(operation: OMSWalletOperation) -> OMSWalletError {
        switch self {
        case .invalidResponse:
            return OMSWalletError(
                code: .invalidResponse,
                message: "OMS response was invalid.",
                operation: operation,
                underlyingError: self
            )
        case .transport(let error):
            return OMSWalletError(
                code: .requestFailed,
                message: error.localizedDescription,
                operation: operation,
                retryable: true,
                upstreamError: OMSWalletUpstreamError(
                    service: .indexer,
                    name: String(describing: type(of: error)),
                    message: error.localizedDescription
                ),
                underlyingError: self
            )
        case .invalidUrl, .encodingFailed:
            return OMSWalletError(
                code: .validationError,
                message: localizedDescription,
                operation: operation,
                underlyingError: self
            )
        }
    }
}

private extension WebRPCTransportError {
    func toWaasUpstreamError() -> OMSWalletUpstreamError {
        OMSWalletUpstreamError(
            service: .waas,
            name: "WebrpcRequestFailed",
            code: String(WebRPCErrorKind.webrpcRequestFailed.code),
            message: message,
            status: nil
        )
    }
}

private extension OMSWalletError {
    var isNestedTransactionBoundary: Bool {
        code == .transactionExecutionUnconfirmed || code == .transactionStatusLookupFailed
    }
}
