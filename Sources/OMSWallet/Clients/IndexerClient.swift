import Foundation

private let indexerGatewayWebRPCHeaderValue = "webrpc@v0.31.2;gen-swift@v0.1.2;sequence-indexer@v0.4.0"

private struct GatewayNativeTokenBalances: Decodable {
    let chainId: Int64
    let results: [NativeTokenBalanceResponse]?
}

private struct GatewayTokenBalances: Decodable {
    let chainId: Int64
    let results: [TokenBalance]?
}

private struct GatewayTransactions: Decodable {
    let chainId: Int64
    let results: [Transaction]?
}

private struct NativeTokenBalanceResponse: Decodable {
    let accountAddress: String?
    let chainId: Int64?
    let name: String?
    let symbol: String?
    let balance: String?
    let balanceUSD: String?
    let priceUSD: String?
    let priceUpdatedAt: String?
}

private struct GetTokenBalancesDetailsResponse: Decodable {
    let page: TokenBalancesPage?
    let nativeBalances: [GatewayNativeTokenBalances]?
    let balances: [GatewayTokenBalances]?
}

private struct GetTransactionHistoryResponse: Decodable {
    let page: TokenBalancesPage?
    let transactions: [GatewayTransactions]?
}

@available(macOS 12.0, iOS 15.0, *)
public final class IndexerClient: Sendable {
    private let publishableKey: String
    private let environment: OMSWalletEnvironment
    private let client: HttpClient
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    internal init(
        publishableKey: String,
        environment: OMSWalletEnvironment,
        client: HttpClient = HttpClient()
    ) {
        self.publishableKey = publishableKey
        self.environment = environment
        self.client = client
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func getBalances(_ params: GetBalancesParams) async throws -> BalancesResult {
        try await runOMSWalletOperation(.indexerGetBalances) {
            let chainScope = chainScope(networks: params.networks, networkType: params.networkType)
            let request = GetTokenBalancesDetailsRequest(
                chainIds: chainScope.chainIds,
                networkType: chainScope.networkType,
                filter: TokenBalancesFilter(
                    accountAddresses: [params.walletAddress],
                    contractStatus: params.contractStatus,
                    contractWhitelist: nonEmpty(params.contractAddresses),
                    omitNativeBalances: false,
                    omitPrices: params.omitPrices,
                    tokenIDs: nonEmpty(params.tokenIds)
                ),
                omitMetadata: !params.includeMetadata,
                page: requestPage(params.page)
            )

            let response = try await postJson(
                operation: .indexerGetBalances,
                path: "/GetTokenBalancesDetails",
                request: request,
                responseType: GetTokenBalancesDetailsResponse.self
            )

            return BalancesResult(
                status: response.statusCode,
                page: response.payload.page,
                nativeBalances: flatten(response.payload.nativeBalances).map(nativeTokenBalance),
                balances: flatten(response.payload.balances)
            )
        }
    }

    public func getTransactionHistory(_ params: GetTransactionHistoryParams) async throws -> TransactionHistoryResult {
        try await runOMSWalletOperation(.indexerGetTransactionHistory) {
            let chainScope = chainScope(networks: params.networks, networkType: params.networkType)
            let request = GetTransactionHistoryRequest(
                chainIds: chainScope.chainIds,
                networkType: chainScope.networkType,
                filter: TransactionHistoryFilter(
                    accountAddresses: [params.walletAddress],
                    contractAddresses: nonEmpty(params.contractAddresses),
                    transactionHashes: nonEmpty(params.transactionHashes),
                    metaTransactionIDs: nonEmpty(params.metaTransactionIds),
                    fromBlock: params.fromBlock,
                    toBlock: params.toBlock,
                    tokenID: params.tokenId,
                    omitPrices: params.omitPrices
                ),
                includeMetadata: params.includeMetadata,
                metadataOptions: params.metadataOptions,
                page: requestPage(params.page)
            )

            let response = try await postJson(
                operation: .indexerGetTransactionHistory,
                path: "/GetTransactionHistory",
                request: request,
                responseType: GetTransactionHistoryResponse.self
            )

            return TransactionHistoryResult(
                status: response.statusCode,
                page: response.payload.page,
                transactions: flatten(response.payload.transactions)
            )
        }
    }

    private func postJson<Request: Encodable, Response: Decodable>(
        operation: OMSWalletOperation,
        path: String,
        request: Request,
        responseType: Response.Type
    ) async throws -> (statusCode: Int, payload: Response) {
        let bodyData = try encoder.encode(request)
        let bodyString = String(data: bodyData, encoding: .utf8) ?? "{}"

        let response: HttpResponse
        do {
            response = try await client.postJson(
                baseUrl: environment.indexerGatewayUrl,
                path: path,
                body: bodyString,
                headers: defaultHeaders()
            )
        } catch let error as CancellationError {
            throw error
        } catch let error as HttpError {
            guard case .transport = error else {
                throw error
            }
            let upstreamError = indexerTransportUpstreamError(error)
            throw OMSWalletError(
                code: .requestFailed,
                message: upstreamError.message ?? error.localizedDescription,
                operation: operation,
                retryable: true,
                upstreamError: upstreamError,
                underlyingError: error
            )
        } catch {
            let upstreamError = indexerTransportUpstreamError(error)
            throw OMSWalletError(
                code: .requestFailed,
                message: upstreamError.message ?? error.localizedDescription,
                operation: operation,
                retryable: true,
                upstreamError: upstreamError,
                underlyingError: error
            )
        }
        try validateSuccessResponse(response, operation: operation)

        do {
            return (
                statusCode: response.statusCode,
                payload: try decoder.decode(responseType, from: response.body)
            )
        } catch {
            let message = "Invalid JSON response from \(operation.rawValue)"
            throw OMSWalletError(
                code: .invalidResponse,
                message: message,
                operation: operation,
                status: response.statusCode,
                upstreamError: OMSWalletUpstreamError(
                    service: .indexer,
                    message: message,
                    status: response.statusCode
                ),
                underlyingError: error
            )
        }
    }

    private func chainScope(
        networks: [Network]?,
        networkType: IndexerNetworkType?
    ) -> (chainIds: [Int]?, networkType: IndexerNetworkType?) {
        if let networks, !networks.isEmpty {
            return (chainIds: networks.map(\.id), networkType: nil)
        }
        return (chainIds: nil, networkType: networkType ?? .mainnets)
    }

    private func requestPage(_ page: TokenBalancesPageRequest?) -> TokenBalancesPageRequest {
        TokenBalancesPageRequest(
            page: page?.page ?? 0,
            column: page?.column,
            before: page?.before,
            after: page?.after,
            sort: page?.sort,
            pageSize: page?.pageSize ?? 40
        )
    }

    private func defaultHeaders() -> [String: String] {
        [
            "Api-Key": publishableKey,
            "Accept": "application/json",
            "Webrpc": indexerGatewayWebRPCHeaderValue
        ]
    }

    private func validateSuccessResponse(
        _ response: HttpResponse,
        operation: OMSWalletOperation
    ) throws {
        guard (200...299).contains(response.statusCode) else {
            let fallbackMessage = "\(operation.rawValue) failed with HTTP \(response.statusCode)"
            let upstreamError = indexerResponseUpstreamError(
                from: response.body,
                status: response.statusCode,
                fallbackMessage: fallbackMessage
            )
            throw OMSWalletError(
                code: .httpError,
                message: upstreamError.message ?? fallbackMessage,
                operation: operation,
                status: response.statusCode,
                retryable: response.statusCode >= 500,
                upstreamError: upstreamError
            )
        }
    }
}

private func indexerTransportUpstreamError(_ error: any Error) -> OMSWalletUpstreamError {
    if let httpError = error as? HttpError,
       case .transport(let underlyingError) = httpError {
        return OMSWalletUpstreamError(
            service: .indexer,
            name: String(describing: type(of: underlyingError)),
            message: underlyingError.localizedDescription
        )
    }

    return OMSWalletUpstreamError(
        service: .indexer,
        name: String(describing: type(of: error)),
        message: error.localizedDescription
    )
}

private func indexerResponseUpstreamError(
    from body: Data,
    status: Int,
    fallbackMessage: String
) -> OMSWalletUpstreamError {
    guard
        let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    else {
        return OMSWalletUpstreamError(
            service: .indexer,
            message: fallbackMessage,
            status: status
        )
    }

    return OMSWalletUpstreamError(
        service: .indexer,
        name: stringField(payload, "name") ?? stringField(payload, "error"),
        code: stringOrNumberField(payload, "code"),
        message: stringField(payload, "message") ?? stringField(payload, "msg") ?? fallbackMessage,
        status: status
    )
}

private struct TokenBalancesFilter: Encodable {
    let accountAddresses: [String]
    let contractStatus: ContractVerificationStatus?
    let contractTypes: [String]? = nil
    let contractWhitelist: [String]?
    let contractBlacklist: [String]? = nil
    let omitNativeBalances: Bool
    let omitPrices: Bool?
    let tokenIDs: [String]?
}

private struct GetTokenBalancesDetailsRequest: Encodable {
    let chainIds: [Int]?
    let networkType: IndexerNetworkType?
    let filter: TokenBalancesFilter
    let omitMetadata: Bool
    let page: TokenBalancesPageRequest
}

private struct TransactionHistoryFilter: Encodable {
    let accountAddresses: [String]
    let contractAddresses: [String]?
    let transactionHashes: [String]?
    let metaTransactionIDs: [String]?
    let fromBlock: Int?
    let toBlock: Int?
    let tokenID: String?
    let omitPrices: Bool?
}

private struct GetTransactionHistoryRequest: Encodable {
    let chainIds: [Int]?
    let networkType: IndexerNetworkType?
    let filter: TransactionHistoryFilter
    let includeMetadata: Bool
    let metadataOptions: MetadataOptions?
    let page: TokenBalancesPageRequest
}

private func flatten(_ groups: [GatewayNativeTokenBalances]?) -> [NativeTokenBalanceResponse] {
    groups?.flatMap { $0.results ?? [] } ?? []
}

private func flatten(_ groups: [GatewayTokenBalances]?) -> [TokenBalance] {
    groups?.flatMap { $0.results ?? [] } ?? []
}

private func flatten(_ groups: [GatewayTransactions]?) -> [Transaction] {
    groups?.flatMap { $0.results ?? [] } ?? []
}

private func nativeTokenBalance(_ raw: NativeTokenBalanceResponse) -> TokenBalance {
    TokenBalance(
        contractType: "NATIVE",
        contractAddress: nil,
        accountAddress: raw.accountAddress,
        tokenId: nil,
        name: raw.name,
        symbol: raw.symbol,
        balance: raw.balance,
        balanceUSD: raw.balanceUSD,
        priceUSD: raw.priceUSD,
        priceUpdatedAt: raw.priceUpdatedAt,
        blockHash: nil,
        blockNumber: nil,
        chainId: raw.chainId
    )
}

private func nonEmpty<T>(_ values: [T]?) -> [T]? {
    guard let values, !values.isEmpty else {
        return nil
    }
    return values
}

private func stringField(_ payload: [String: Any], _ key: String) -> String? {
    let value = payload[key]
    return value as? String
}

private func stringOrNumberField(_ payload: [String: Any], _ key: String) -> String? {
    switch payload[key] {
    case let value as String:
        return value
    case let value as Int:
        return String(value)
    case let value as NSNumber:
        return value.stringValue
    default:
        return nil
    }
}
