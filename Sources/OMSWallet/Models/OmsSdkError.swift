import Foundation

public enum OmsSdkErrorCode: String, Sendable {
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

public enum OmsSdkOperation: String, Sendable {
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

public enum OmsUpstreamService: String, Sendable {
    case waas = "Waas"
    case indexer = "Indexer"
}

public struct OmsUpstreamError: Equatable, Sendable {
    public let service: OmsUpstreamService
    public let name: String?
    public let code: String?
    public let message: String?
    public let status: Int?

    public init(
        service: OmsUpstreamService,
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

public struct OmsSdkError: Error, LocalizedError, @unchecked Sendable {
    public let code: OmsSdkErrorCode
    public let operation: OmsSdkOperation?
    public let status: Int?
    public let txnId: String?
    public let retryable: Bool?
    public let upstreamError: OmsUpstreamError?
    public let underlyingError: (any Error)?
    private let message: String

    public init(
        code: OmsSdkErrorCode,
        message: String,
        operation: OmsSdkOperation? = nil,
        status: Int? = nil,
        txnId: String? = nil,
        retryable: Bool? = nil,
        upstreamError: OmsUpstreamError? = nil,
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

public extension OmsSdkError {
    static func walletSelectionUnavailable(
        operation: OmsSdkOperation? = nil
    ) -> OmsSdkError {
        OmsSdkError(
            code: .walletSelectionUnavailable,
            message: "Selected wallet is not one of the available options.",
            operation: operation
        )
    }

    static func walletSelectionStale(
        operation: OmsSdkOperation? = nil
    ) -> OmsSdkError {
        OmsSdkError(
            code: .walletSelectionStale,
            message: "Pending wallet selection is no longer active.",
            operation: operation
        )
    }

    static func sessionMissing(
        operation: OmsSdkOperation? = nil
    ) -> OmsSdkError {
        OmsSdkError(
            code: .sessionMissing,
            message: "No authenticated wallet session.",
            operation: operation
        )
    }

    static func sessionExpired(
        operation: OmsSdkOperation? = nil
    ) -> OmsSdkError {
        OmsSdkError(
            code: .sessionExpired,
            message: "No active credential.",
            operation: operation
        )
    }
}

@available(macOS 12.0, iOS 15.0, *)
func runOmsOperation<T>(
    _ operation: OmsSdkOperation,
    _ body: () async throws -> T
) async throws -> T {
    do {
        return try await body()
    } catch let error as CancellationError {
        throw error
    } catch {
        throw toOmsSdkError(error, operation: operation)
    }
}

@available(macOS 12.0, iOS 15.0, *)
func runOmsOperation<T>(
    _ operation: OmsSdkOperation,
    _ body: () throws -> T
) throws -> T {
    do {
        return try body()
    } catch {
        throw toOmsSdkError(error, operation: operation)
    }
}

func toOmsSdkError(_ error: any Error, operation: OmsSdkOperation) -> OmsSdkError {
    if let omsError = error as? OmsSdkError {
        if omsError.operation == operation || omsError.isNestedTransactionBoundary {
            return omsError
        }
        return OmsSdkError(
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
        return webRPCError.toOmsSdkError(operation: operation)
    }

    if let transportError = error as? WebRPCTransportError {
        return OmsSdkError(
            code: .requestFailed,
            message: transportError.message,
            operation: operation,
            retryable: true,
            upstreamError: transportError.toWaasUpstreamError(),
            underlyingError: transportError
        )
    }

    if let transactionError = error as? TransactionError {
        return transactionError.toOmsSdkError(operation: operation)
    }

    if let httpError = error as? HttpError {
        return httpError.toOmsSdkError(operation: operation)
    }

    if error is DecodingError {
        return OmsSdkError(
            code: .invalidResponse,
            message: error.localizedDescription,
            operation: operation,
            underlyingError: error
        )
    }

    return OmsSdkError(
        code: .validationError,
        message: error.localizedDescription,
        operation: operation,
        underlyingError: error
    )
}

private extension WebRPCError {
    func toOmsSdkError(operation: OmsSdkOperation) -> OmsSdkError {
        let normalizedStatus = normalizedStatus
        let upstreamError = toWaasUpstreamError(status: normalizedStatus)
        let normalizedMessage = normalizedMessage

        if kind == .commitmentConsumed {
            return OmsSdkError(
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
            return OmsSdkError(
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
            return OmsSdkError(
                code: .invalidResponse,
                message: normalizedMessage,
                operation: operation,
                status: normalizedStatus,
                upstreamError: upstreamError,
                underlyingError: self
            )
        }

        return OmsSdkError(
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

    private func toWaasUpstreamError(status: Int?) -> OmsUpstreamError {
        OmsUpstreamError(
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
    func toOmsSdkError(operation: OmsSdkOperation) -> OmsSdkError {
        switch self {
        case .pollingTimedOut:
            return OmsSdkError(
                code: .transactionStatusLookupFailed,
                message: localizedDescription,
                operation: operation,
                retryable: true,
                underlyingError: self
            )
        case .noFeeOptionsAvailable, .noFeeOptionSelected, .missingTransactionHash:
            return OmsSdkError(
                code: .validationError,
                message: localizedDescription,
                operation: operation,
                underlyingError: self
            )
        case .transactionFailed:
            return OmsSdkError(
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
    func toOmsSdkError(operation: OmsSdkOperation) -> OmsSdkError {
        switch self {
        case .invalidResponse:
            return OmsSdkError(
                code: .invalidResponse,
                message: "OMS response was invalid.",
                operation: operation,
                underlyingError: self
            )
        case .transport(let error):
            return OmsSdkError(
                code: .requestFailed,
                message: error.localizedDescription,
                operation: operation,
                retryable: true,
                upstreamError: OmsUpstreamError(
                    service: .indexer,
                    name: String(describing: type(of: error)),
                    message: error.localizedDescription
                ),
                underlyingError: self
            )
        case .invalidUrl, .encodingFailed:
            return OmsSdkError(
                code: .validationError,
                message: localizedDescription,
                operation: operation,
                underlyingError: self
            )
        }
    }
}

private extension WebRPCTransportError {
    func toWaasUpstreamError() -> OmsUpstreamError {
        OmsUpstreamError(
            service: .waas,
            name: "WebrpcRequestFailed",
            code: String(WebRPCErrorKind.webrpcRequestFailed.code),
            message: message,
            status: nil
        )
    }
}

private extension OmsSdkError {
    var isNestedTransactionBoundary: Bool {
        code == .transactionExecutionUnconfirmed || code == .transactionStatusLookupFailed
    }
}
