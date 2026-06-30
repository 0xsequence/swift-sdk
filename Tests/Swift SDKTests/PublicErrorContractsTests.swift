import Foundation
import Testing
@testable import OMS_SDK

@Test func TestPublicErrorContractsWaasTransportFailuresHaveUpstreamDetails() async throws {
    let fixture = makeMockWalletClient()
    fixture.transport.enqueueTransportError(
        WebRPCTransportError(message: "WebRPC request failed"),
        for: WaasAPI.CommitVerifier.urlPath
    )

    await expectPublicError(
        try await fixture.client.startEmailAuth(email: "user@example.com"),
        equals: error(
            code: .requestFailed,
            operation: .walletStartEmailAuth,
            message: "WebRPC request failed",
            retryable: true,
            upstreamError: upstream(
                service: .waas,
                name: "WebrpcRequestFailed",
                code: "-1",
                message: "WebRPC request failed"
            )
        )
    )
}

@Test func TestPublicErrorContractsWaasDomainErrorsHaveUpstreamDetails() async throws {
    let fixture = makeMockWalletClient()
    fixture.transport.enqueueRawHTTPError(
        statusCode: 400,
        body: Data(
            """
            {"error":"CommitmentConsumed","code":7008,"msg":"The authentication commitment has already been used","status":400}
            """.utf8
        ),
        for: WaasAPI.CompleteAuth.urlPath
    )

    await expectPublicError(
        try await fixture.client.completeEmailAuth(code: "123456"),
        equals: error(
            code: .authCommitmentConsumed,
            operation: .walletCompleteEmailAuth,
            message: "The authentication commitment has already been used",
            status: 400,
            retryable: false,
            upstreamError: upstream(
                service: .waas,
                name: "CommitmentConsumed",
                code: "7008",
                message: "The authentication commitment has already been used",
                status: 400
            )
        )
    )
}

@Test func TestPublicErrorContractsWaasHttpAndBadResponsesHaveUpstreamDetails() async throws {
    let httpFixture = makeRestoredWalletClient()
    httpFixture.transport.enqueueRawHTTPError(
        statusCode: 500,
        body: Data(
            """
            {"error":"WebrpcBadRequest","code":-4,"msg":"bad request","status":500}
            """.utf8
        ),
        for: WaasAPI.SignMessage.urlPath
    )

    await expectPublicError(
        try await httpFixture.client.signMessage(network: .polygon, message: "hello"),
        equals: error(
            code: .httpError,
            operation: .walletSignMessage,
            message: "bad request",
            status: 500,
            retryable: true,
            upstreamError: upstream(
                service: .waas,
                name: "WebrpcBadRequest",
                code: "-4",
                message: "bad request",
                status: 500
            )
        )
    )

    let nonJsonFixture = makeRestoredWalletClient()
    nonJsonFixture.transport.enqueueRawHTTPError(
        statusCode: 502,
        body: Data("<html>Bad Gateway</html>".utf8),
        for: WaasAPI.SignMessage.urlPath
    )

    let failure = await publicError {
        try await nonJsonFixture.client.signMessage(network: .polygon, message: "hello")
    }
    #expect(failure == error(
        code: .httpError,
        operation: .walletSignMessage,
        message: "bad response",
        status: 502,
        retryable: true,
        upstreamError: upstream(
            service: .waas,
            name: "WebrpcBadResponse",
            code: "-5",
            message: "bad response",
            status: 502
        )
    ))
    #expect(failure.message?.contains("Bad Gateway") == false)
    #expect(failure.upstreamError?.message?.contains("Bad Gateway") == false)
}

@Test func TestPublicErrorContractsLocalAuthAndSelectionErrorsHaveNoUpstreamDetails() async throws {
    let emailFixture = makeMockWalletClient()
    emailFixture.client.verifier = ""
    emailFixture.client.challenge = ""

    await expectPublicError(
        try await emailFixture.client.completeEmailAuth(code: "123456"),
        equals: error(
            code: .sessionMissing,
            operation: .walletCompleteEmailAuth,
            message: "No authenticated wallet session."
        )
    )

    let selectionFixture = makeMockWalletClient()
    let availableWallet = testWallet(id: "wallet-1", address: "0x1111111111111111111111111111111111111111")
    try selectionFixture.transport.enqueue(
        completeAuthResponse(wallets: [availableWallet]),
        for: WaasAPI.CompleteAuth.urlPath
    )
    let result = try await selectionFixture.client.completeEmailAuth(
        code: "123456",
        walletSelection: .manual
    )
    guard case .walletSelection(let pendingSelection) = result else {
        Issue.record("Expected pending wallet selection")
        return
    }

    await expectPublicError(
        try await pendingSelection.selectWallet(walletId: "wallet-missing"),
        equals: error(
            code: .walletSelectionUnavailable,
            operation: .pendingWalletSelectionSelectWallet,
            message: "Selected wallet is not one of the available options."
        )
    )

    selectionFixture.client.activePendingWalletSelection = nil
    await expectPublicError(
        try await pendingSelection.createAndSelectWallet(),
        equals: error(
            code: .walletSelectionStale,
            operation: .pendingWalletSelectionCreateAndSelectWallet,
            message: "Pending wallet selection is no longer active."
        )
    )
}

@Test func TestPublicErrorContractsPendingSelectionBackendErrorsAreNormalized() async throws {
    let fixture = makeMockWalletClient()
    let availableWallet = testWallet(id: "wallet-1", address: "0x1111111111111111111111111111111111111111")
    try fixture.transport.enqueue(
        completeAuthResponse(wallets: [availableWallet]),
        for: WaasAPI.CompleteAuth.urlPath
    )
    fixture.transport.enqueueRawHTTPError(
        statusCode: 500,
        body: Data(#"{"error":"WebrpcBadRequest","code":-4,"msg":"use wallet failed","status":500}"#.utf8),
        for: WaasAPI.UseWallet.urlPath
    )

    let result = try await fixture.client.completeEmailAuth(
        code: "123456",
        walletSelection: .manual
    )
    guard case .walletSelection(let pendingSelection) = result else {
        Issue.record("Expected pending wallet selection")
        return
    }

    await expectPublicError(
        try await pendingSelection.selectWallet(walletId: availableWallet.id),
        equals: error(
            code: .httpError,
            operation: .pendingWalletSelectionSelectWallet,
            message: "use wallet failed",
            status: 500,
            retryable: true,
            upstreamError: upstream(
                service: .waas,
                name: "WebrpcBadRequest",
                code: "-4",
                message: "use wallet failed",
                status: 500
            )
        )
    )
}

@Test func TestPublicErrorContractsMissingAndExpiredSessionErrorsHaveNoUpstreamDetails() async throws {
    let missingFixture = makeMockWalletClient()

    await expectPublicError(
        try await missingFixture.client.signMessage(network: .polygon, message: "hello"),
        equals: error(
            code: .sessionMissing,
            operation: .walletSignMessage,
            message: "No authenticated wallet session."
        )
    )

    await expectPublicError(
        try await missingFixture.client.getTransactionStatus(txnId: "txn-missing"),
        equals: error(
            code: .sessionMissing,
            operation: .walletGetTransactionStatus,
            message: "No authenticated wallet session."
        )
    )

    var iterator = missingFixture.client.listAccessPages().makeAsyncIterator()
    await expectPublicError(
        try await iterator.next(),
        equals: error(
            code: .sessionMissing,
            operation: .walletListAccessPages,
            message: "No authenticated wallet session."
        )
    )

    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let expiredFixture = makeMockWalletClient(currentDate: { now })
    expiredFixture.client.walletId = "wallet-main"
    expiredFixture.client.walletAddress = "0xwallet"
    expiredFixture.client.sessionExpiresAt = "2025-01-01T00:00:00Z"

    await expectPublicError(
        try await expiredFixture.client.signMessage(network: .polygon, message: "hello"),
        equals: error(
            code: .sessionExpired,
            operation: .walletSignMessage,
            message: "No active credential."
        )
    )
}

@Test func TestPublicErrorContractsOidcLocalErrorsHaveNoUpstreamDetails() async throws {
    let fixture = makeMockWalletClient(oidcNonceGenerator: { "nonce-123" })
    try fixture.transport.enqueue(
        CommitVerifierResponse(
            verifier: "oidc-verifier",
            loginHint: nil,
            challenge: "pkce-challenge"
        ),
        for: WaasAPI.CommitVerifier.urlPath
    )

    let started = try await fixture.client.startOidcRedirectAuth(
        provider: OidcProviderConfig(
            issuer: "https://issuer.example.test",
            clientId: "client-123",
            authorizationUrl: "https://issuer.example.test/authorize"
        ),
        redirectUri: "omssdkdemo://auth/callback"
    )

    let result = try await fixture.client.handleOidcRedirectCallback(
        "omssdkdemo://auth/callback?error=access_denied&error_description=User%20cancelled&state=\(started.state)"
    )

    guard case .failed(let error as OmsSdkError) = result else {
        Issue.record("Expected OIDC failure")
        return
    }
    #expect(serialize(error) == PublicErrorContract(
        code: .validationError,
        operation: .walletHandleOidcRedirectCallback,
        message: "User cancelled",
        status: nil,
        retryable: nil,
        txnId: nil,
        upstreamError: nil
    ))
}

@Test func TestPublicErrorContractsLocalTransactionValidationErrorsHaveNoUpstreamDetails() async throws {
    let fixture = makeRestoredWalletClient()
    try fixture.transport.enqueue(
        PrepareResponse(
            txnId: "txn-no-fees",
            status: .quoted,
            feeOptions: [],
            sponsored: false,
            expiresAt: "2026-04-27T00:00:00Z"
        ),
        for: WaasAPI.PrepareEthereumTransaction.urlPath
    )

    await expectPublicError(
        try await fixture.client.sendTransaction(
            network: .polygon,
            request: SendTransactionRequest(to: "0x1111111111111111111111111111111111111111", value: "0")
        ),
        equals: error(
            code: .validationError,
            operation: .walletSendTransaction,
            message: "No fee options are available for this transaction."
        )
    )
}

@Test func TestPublicErrorContractsBackendFailuresOnWalletReadMethodsHaveUpstreamDetails() async throws {
    let signatureFixture = makeRestoredWalletClient()
    signatureFixture.transport.enqueueRawHTTPError(
        statusCode: 500,
        body: Data(#"{"error":"WebrpcBadRequest","code":-4,"msg":"signature backend failed","status":500}"#.utf8),
        for: WaasPublicAPI.IsValidMessageSignature.urlPath
    )

    await expectPublicError(
        try await signatureFixture.client.isValidMessageSignature(
            network: .polygon,
            walletAddress: "0xwallet",
            message: "hello",
            signature: "0xsig"
        ),
        equals: error(
            code: .httpError,
            operation: .walletIsValidMessageSignature,
            message: "signature backend failed",
            status: 500,
            retryable: true,
            upstreamError: upstream(
                service: .waas,
                name: "WebrpcBadRequest",
                code: "-4",
                message: "signature backend failed",
                status: 500
            )
        )
    )

    let accessFixture = makeRestoredWalletClient()
    accessFixture.transport.enqueueRawHTTPError(
        statusCode: 500,
        body: Data(#"{"error":"WebrpcBadRequest","code":-4,"msg":"access backend failed","status":500}"#.utf8),
        for: WaasAPI.ListAccess.urlPath
    )

    await expectPublicError(
        try await accessFixture.client.listAccessPage(),
        equals: error(
            code: .httpError,
            operation: .walletListAccessPage,
            message: "access backend failed",
            status: 500,
            retryable: true,
            upstreamError: upstream(
                service: .waas,
                name: "WebrpcBadRequest",
                code: "-4",
                message: "access backend failed",
                status: 500
            )
        )
    )
}

@Test func TestPublicErrorContractsDirectTransactionStatusBackendFailuresUsePublicOperation() async throws {
    let fixture = makeRestoredWalletClient()
    fixture.transport.enqueueRawHTTPError(
        statusCode: 404,
        body: Data(#"{"error":"TransactionNotFound","code":7308,"msg":"Transaction not found","status":404}"#.utf8),
        for: WaasAPI.TransactionStatusMethod.urlPath
    )

    await expectPublicError(
        try await fixture.client.getTransactionStatus(txnId: "txn-direct"),
        equals: error(
            code: .requestFailed,
            operation: .walletGetTransactionStatus,
            message: "Transaction not found",
            status: 404,
            retryable: false,
            upstreamError: upstream(
                service: .waas,
                name: "TransactionNotFound",
                code: "7308",
                message: "Transaction not found",
                status: 404
            )
        )
    )
}

@Test func TestPublicErrorContractsTransactionExecuteFailuresAreUnconfirmedWrites() async throws {
    let fixture = makeRestoredWalletClient()
    try fixture.transport.enqueue(
        PrepareResponse(
            txnId: "txn-execute",
            status: .quoted,
            feeOptions: [],
            sponsored: true,
            expiresAt: "2026-04-27T00:00:00Z"
        ),
        for: WaasAPI.PrepareEthereumTransaction.urlPath
    )
    fixture.transport.enqueueRawHTTPError(
        statusCode: 502,
        body: Data("<html>Bad Gateway</html>".utf8),
        for: WaasAPI.Execute.urlPath
    )

    await expectPublicError(
        try await fixture.client.sendTransaction(
            network: .polygon,
            request: SendTransactionRequest(to: "0x1111111111111111111111111111111111111111", value: "0")
        ),
        equals: error(
            code: .transactionExecutionUnconfirmed,
            operation: .walletExecute,
            message: "Transaction execution failed before status could be confirmed",
            status: 502,
            retryable: false,
            txnId: "txn-execute",
            upstreamError: upstream(
                service: .waas,
                name: "WebrpcBadResponse",
                code: "-5",
                message: "bad response",
                status: 502
            )
        )
    )
}

@Test func TestPublicErrorContractsTransactionStatusPollingFailuresPreserveTxnAndUpstreamDetails() async throws {
    let backendFixture = makeRestoredWalletClient()
    try backendFixture.transport.enqueue(
        PrepareResponse(
            txnId: "txn-status",
            status: .quoted,
            feeOptions: [],
            sponsored: true,
            expiresAt: "2026-04-27T00:00:00Z"
        ),
        for: WaasAPI.PrepareEthereumTransaction.urlPath
    )
    try backendFixture.transport.enqueue(
        ExecuteResponse(status: .pending),
        for: WaasAPI.Execute.urlPath
    )
    backendFixture.transport.enqueueRawHTTPError(
        statusCode: 404,
        body: Data(#"{"error":"TransactionNotFound","code":7308,"msg":"Transaction not found","status":404}"#.utf8),
        for: WaasAPI.TransactionStatusMethod.urlPath
    )

    await expectPublicError(
        try await backendFixture.client.sendTransaction(
            network: .polygon,
            request: SendTransactionRequest(to: "0x1111111111111111111111111111111111111111", value: "0")
        ),
        equals: error(
            code: .transactionStatusLookupFailed,
            operation: .walletTransactionStatus,
            message: "Transaction was submitted, but status polling failed",
            status: 404,
            retryable: true,
            txnId: "txn-status",
            upstreamError: upstream(
                service: .waas,
                name: "TransactionNotFound",
                code: "7308",
                message: "Transaction not found",
                status: 404
            )
        )
    )

    let transportFixture = makeRestoredWalletClient()
    try transportFixture.transport.enqueue(
        PrepareResponse(
            txnId: "txn-transport",
            status: .quoted,
            feeOptions: [],
            sponsored: true,
            expiresAt: "2026-04-27T00:00:00Z"
        ),
        for: WaasAPI.PrepareEthereumTransaction.urlPath
    )
    try transportFixture.transport.enqueue(
        ExecuteResponse(status: .pending),
        for: WaasAPI.Execute.urlPath
    )
    transportFixture.transport.enqueueTransportError(
        WebRPCTransportError(message: "WebRPC request failed"),
        for: WaasAPI.TransactionStatusMethod.urlPath
    )

    await expectPublicError(
        try await transportFixture.client.sendTransaction(
            network: .polygon,
            request: SendTransactionRequest(to: "0x1111111111111111111111111111111111111111", value: "0")
        ),
        equals: error(
            code: .transactionStatusLookupFailed,
            operation: .walletTransactionStatus,
            message: "Transaction was submitted, but status polling failed",
            retryable: true,
            txnId: "txn-transport",
            upstreamError: upstream(
                service: .waas,
                name: "WebrpcRequestFailed",
                code: "-1",
                message: "WebRPC request failed"
            )
        )
    )
}

@Test func TestPublicErrorContractsIndexerFailuresHaveUpstreamDetails() async throws {
    let backendClient = makeRecordingIndexerClient(
        recorder: IndexerRequestRecorder(
            statusCode: 500,
            responseBody: Data(#"{"error":"IndexerDown","code":123,"message":"down"}"#.utf8)
        )
    )

    await expectPublicError(
        try await backendClient.getBalances(
            GetBalancesParams(walletAddress: "0xwallet", networks: [.polygon])
        ),
        equals: error(
            code: .httpError,
            operation: .indexerGetBalances,
            message: "down",
            status: 500,
            retryable: true,
            upstreamError: upstream(
                service: .indexer,
                name: "IndexerDown",
                code: "123",
                message: "down",
                status: 500
            )
        )
    )

    let nonJsonClient = makeRecordingIndexerClient(
        recorder: IndexerRequestRecorder(
            statusCode: 502,
            responseBody: Data("<html>Bad Gateway</html>".utf8)
        )
    )
    let nonJsonFailure = await publicError {
        try await nonJsonClient.getBalances(
            GetBalancesParams(walletAddress: "0xwallet", networks: [.polygon])
        )
    }
    #expect(nonJsonFailure == error(
        code: .httpError,
        operation: .indexerGetBalances,
        message: "indexer.getBalances failed with HTTP 502",
        status: 502,
        retryable: true,
        upstreamError: upstream(
            service: .indexer,
            message: "indexer.getBalances failed with HTTP 502",
            status: 502
        )
    ))
    #expect(nonJsonFailure.message?.contains("Bad Gateway") == false)
    #expect(nonJsonFailure.upstreamError?.message?.contains("Bad Gateway") == false)

    let transportClient = makeRecordingIndexerClient(
        recorder: IndexerRequestRecorder(transportError: URLError(.cannotConnectToHost))
    )
    await expectPublicError(
        try await transportClient.getBalances(
            GetBalancesParams(walletAddress: "0xwallet", networks: [.polygon])
        ),
        equals: error(
            code: .requestFailed,
            operation: .indexerGetBalances,
            message: URLError(.cannotConnectToHost).localizedDescription,
            retryable: true,
            upstreamError: upstream(
                service: .indexer,
                name: "NSURLError",
                message: URLError(.cannotConnectToHost).localizedDescription
            )
        )
    )

    let malformedClient = makeRecordingIndexerClient(
        recorder: IndexerRequestRecorder(
            statusCode: 200,
            responseBody: Data("not json".utf8)
        )
    )
    await expectPublicError(
        try await malformedClient.getTransactionHistory(
            GetTransactionHistoryParams(walletAddress: "0xwallet", networks: [.polygon])
        ),
        equals: error(
            code: .invalidResponse,
            operation: .indexerGetTransactionHistory,
            message: "Invalid JSON response from indexer.getTransactionHistory",
            status: 200,
            upstreamError: upstream(
                service: .indexer,
                message: "Invalid JSON response from indexer.getTransactionHistory",
                status: 200
            )
        )
    )
}

@Test func TestPublicErrorContractsConstructedErrorFieldsAreStable() {
    let upstreamError = OmsUpstreamError(
        service: .waas,
        name: "WebrpcRequestFailed",
        code: "-1",
        message: "request failed",
        status: nil
    )
    let sdkError = OmsSdkError(
        code: .requestFailed,
        message: "request failed",
        operation: .walletStartEmailAuth,
        status: nil,
        txnId: "txn-1",
        retryable: true,
        upstreamError: upstreamError
    )

    #expect(serialize(sdkError) == PublicErrorContract(
        code: .requestFailed,
        operation: .walletStartEmailAuth,
        message: "request failed",
        status: nil,
        retryable: true,
        txnId: "txn-1",
        upstreamError: SerializedUpstreamError(
            service: .waas,
            name: "WebrpcRequestFailed",
            code: "-1",
            message: "request failed",
            status: nil
        )
    ))
}

private func makeRestoredWalletClient() -> MockWalletClientFixture {
    let fixture = makeMockWalletClient()
    fixture.client.walletId = "wallet-main"
    fixture.client.walletAddress = "0x1111111111111111111111111111111111111111"
    fixture.client.sessionExpiresAt = "2099-01-01T00:00:00Z"
    return fixture
}

private func expectPublicError<T>(
    _ operation: @autoclosure @escaping () async throws -> T,
    equals expected: PublicErrorContract,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    let actual = await publicError(operation)
    #expect(actual == expected, sourceLocation: sourceLocation)
}

private func publicError<T>(
    _ operation: () async throws -> T,
    sourceLocation: SourceLocation = #_sourceLocation
) async -> PublicErrorContract {
    do {
        _ = try await operation()
        Issue.record("Expected public SDK error", sourceLocation: sourceLocation)
        return PublicErrorContract(
            code: nil,
            operation: nil,
            message: nil,
            status: nil,
            retryable: nil,
            txnId: nil,
            upstreamError: nil
        )
    } catch {
        return serialize(error)
    }
}

private func serialize(_ error: any Error) -> PublicErrorContract {
    guard let sdkError = error as? OmsSdkError else {
        return PublicErrorContract(
            code: nil,
            operation: nil,
            message: error.localizedDescription,
            status: nil,
            retryable: nil,
            txnId: nil,
            upstreamError: nil
        )
    }

    return serialize(sdkError)
}

private func serialize(_ error: OmsSdkError) -> PublicErrorContract {
    PublicErrorContract(
        code: error.code,
        operation: error.operation,
        message: error.localizedDescription,
        status: error.status,
        retryable: error.retryable,
        txnId: error.txnId,
        upstreamError: error.upstreamError.map {
            SerializedUpstreamError(
                service: $0.service,
                name: $0.name,
                code: $0.code,
                message: $0.message,
                status: $0.status
            )
        }
    )
}

private func error(
    code: OmsSdkErrorCode,
    operation: OmsSdkOperation,
    message: String,
    status: Int? = nil,
    retryable: Bool? = nil,
    txnId: String? = nil,
    upstreamError: SerializedUpstreamError? = nil
) -> PublicErrorContract {
    PublicErrorContract(
        code: code,
        operation: operation,
        message: message,
        status: status,
        retryable: retryable,
        txnId: txnId,
        upstreamError: upstreamError
    )
}

private func upstream(
    service: OmsUpstreamService,
    name: String? = nil,
    code: String? = nil,
    message: String? = nil,
    status: Int? = nil
) -> SerializedUpstreamError {
    SerializedUpstreamError(
        service: service,
        name: name,
        code: code,
        message: message,
        status: status
    )
}

private struct PublicErrorContract: Equatable {
    let code: OmsSdkErrorCode?
    let operation: OmsSdkOperation?
    let message: String?
    let status: Int?
    let retryable: Bool?
    let txnId: String?
    let upstreamError: SerializedUpstreamError?
}

private struct SerializedUpstreamError: Equatable {
    let service: OmsUpstreamService?
    let name: String?
    let code: String?
    let message: String?
    let status: Int?
}
