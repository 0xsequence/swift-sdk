import Foundation

private struct TokenBalancesPayload: Codable {
    let page: TokenBalancesPage?
    let balances: [TokenBalance]?
}

private struct NativeTokenBalancePayload: Decodable {
    let balance: NativeTokenBalanceResponse?
}

private struct NativeTokenBalanceResponse: Decodable {
    let accountAddress: String?
    let balance: String?
    let balanceWei: String?
    let chainId: Int64?
}

@available(macOS 12.0, iOS 15.0, *)
protocol WalletIndexerClient {
    func getTokenBalances(
        network: Network,
        contractAddress: String?,
        walletAddress: String,
        includeMetadata: Bool,
        page: TokenBalancesPageRequest
    ) async throws -> TokenBalancesResult

    func getNativeTokenBalance(
        network: Network,
        walletAddress: String
    ) async throws -> TokenBalance?
}

@available(macOS 12.0, iOS 15.0, *)
public final class IndexerClient: WalletIndexerClient {
    private let publishableKey: String
    private let environment: OMSClientEnvironment
    private let client: HttpClient
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    internal init(
        publishableKey: String,
        environment: OMSClientEnvironment,
        client: HttpClient = HttpClient()
    ) {
        self.publishableKey = publishableKey
        self.environment = environment
        self.client = client
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func getTokenBalances(
        network: Network,
        contractAddress: String? = nil,
        walletAddress: String,
        includeMetadata: Bool,
        page: TokenBalancesPageRequest = TokenBalancesPageRequest()
    ) async throws -> TokenBalancesResult {
        try await runOmsOperation(.indexerGetTokenBalances) {
            let request = TokenBalancesRequest(
                page: RequestPage(
                    page: page.page ?? 0,
                    pageSize: page.pageSize ?? 40,
                    more: false
                ),
                contractAddress: contractAddress,
                accountAddress: walletAddress,
                includeMetadata: includeMetadata
            )

            let bodyData = try encoder.encode(request)
            let bodyString = String(data: bodyData, encoding: .utf8) ?? "{}"

            let baseUrl = indexerUrl(forNetwork: network)

            let response = try await client.postJson(
                baseUrl: baseUrl,
                path: "/GetTokenBalances",
                body: bodyString,
                headers: defaultHeaders()
            )
            try validateSuccessResponse(response, operation: .indexerGetTokenBalances)

            let payload = try decoder.decode(TokenBalancesPayload.self, from: response.body)

            return TokenBalancesResult(
                status: response.statusCode,
                page: payload.page,
                balances: payload.balances ?? []
            )
        }
    }

    public func getNativeTokenBalance(
        network: Network,
        walletAddress: String
    ) async throws -> TokenBalance? {
        try await runOmsOperation(.indexerGetNativeTokenBalance) {
            let request = NativeTokenBalanceRequest(accountAddress: walletAddress)

            let bodyData = try encoder.encode(request)
            let bodyString = String(data: bodyData, encoding: .utf8) ?? "{}"

            let baseUrl = indexerUrl(forNetwork: network)

            let response = try await client.postJson(
                baseUrl: baseUrl,
                path: "/GetNativeTokenBalance",
                body: bodyString,
                headers: defaultHeaders()
            )
            try validateSuccessResponse(response, operation: .indexerGetNativeTokenBalance)

            let payload = try decoder.decode(NativeTokenBalancePayload.self, from: response.body)
            guard let balance = payload.balance else {
                return nil
            }

            return TokenBalance(
                contractType: "NATIVE",
                contractAddress: nil,
                accountAddress: balance.accountAddress,
                tokenId: nil,
                balance: balance.balance ?? balance.balanceWei,
                blockHash: nil,
                blockNumber: nil,
                chainId: balance.chainId ?? Int64(network.chainId)
            )
        }
    }

    private func indexerUrl(forNetwork network: Network) -> String {
        return environment.indexerUrlString(for: network)
    }

    private func defaultHeaders() -> [String: String] {
        return [
            "X-Access-Key": publishableKey,
            "Accept": "application/json"
        ]
    }

    private func validateSuccessResponse(
        _ response: HttpResponse,
        operation: OmsSdkOperation
    ) throws {
        guard (200...299).contains(response.statusCode) else {
            throw OmsSdkError(
                code: .httpError,
                message: "Indexer request failed with HTTP status \(response.statusCode).",
                operation: operation,
                status: response.statusCode,
                retryable: response.statusCode >= 500
            )
        }
    }
}

private struct TokenBalancesRequest: Encodable {
    let page: RequestPage
    let contractAddress: String?
    let accountAddress: String
    let includeMetadata: Bool
}

private struct NativeTokenBalanceRequest: Encodable {
    let accountAddress: String
}

private struct RequestPage: Encodable {
    let page: Int
    let pageSize: Int
    let more: Bool
}
