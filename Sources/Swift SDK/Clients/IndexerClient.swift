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

@available(macOS 12.0, iOS 15.0, *)
public final class IndexerClient {
    private let projectAccessKey: String
    private let environment: OMSClientEnvironment
    private let client: HttpClient = HttpClient()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    internal init(
        projectAccessKey: String,
        environment: OMSClientEnvironment
    ) {
        self.projectAccessKey = projectAccessKey
        self.environment = environment
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func getTokenBalances(
        chainId: String,
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

        let baseUrl = indexerUrl(forChainId: chainId)

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

    private func indexerUrl(forChainId chainId: String) -> String {
        return environment.indexerUrlTemplate.replacingOccurrences(
            of: "{value}",
            with: chainId
        )
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

private struct RequestPage: Encodable {
    let page: Int
    let pageSize: Int
    let more: Bool
}
