import Foundation

public struct TokenBalancesPage: Codable {
    public let page: Int
    public let pageSize: Int
    public let more: Bool
}

public struct TokenBalance: Codable {
    public let contractType: String?
    public let contractAddress: String?
    public let accountAddress: String?
    public let tokenId: String?
    public let balance: String?
    public let blockHash: String?
    public let blockNumber: Int64?
    public let chainId: Int64?

    enum CodingKeys: String, CodingKey {
        case contractType
        case contractAddress
        case accountAddress
        case tokenId = "tokenID"
        case balance
        case blockHash
        case blockNumber
        case chainId
    }
}

public struct TokenBalancesResult {
    public let status: Int
    public let page: TokenBalancesPage?
    public let balances: [TokenBalance]
}

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
public final class IndexerClient {
    private let projectAccessKey: String
    private let environment: OMSClientEnvironment
    private let client: HttpClient
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    internal init(
        projectAccessKey: String,
        environment: OMSClientEnvironment,
        client: HttpClient = HttpClient()
    ) {
        self.projectAccessKey = projectAccessKey
        self.environment = environment
        self.client = client
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func getTokenBalances(
        network: Network,
        contractAddress: String,
        walletAddress: String,
        includeMetadata: Bool
    ) async throws -> TokenBalancesResult {
        let request = TokenBalancesRequest(
            page: RequestPage(page: 0, pageSize: 40, more: false),
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

        let payload = try decoder.decode(TokenBalancesPayload.self, from: response.body)

        return TokenBalancesResult(
            status: response.statusCode,
            page: payload.page,
            balances: payload.balances ?? []
        )
    }

    public func getNativeTokenBalance(
        network: Network,
        walletAddress: String
    ) async throws -> TokenBalance? {
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

    private func indexerUrl(forNetwork network: Network) -> String {
        return environment.indexerUrlString(for: network)
    }

    private func defaultHeaders() -> [String: String] {
        return [
            "X-Access-Key": projectAccessKey,
            "Accept": "application/json"
        ]
    }
}

private struct TokenBalancesRequest: Encodable {
    let page: RequestPage
    let contractAddress: String
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
