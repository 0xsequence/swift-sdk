import Foundation

public struct TokenBalancesPage: Codable {
    let page: Int
    let pageSize: Int
    let more: Bool
}

public struct TokenBalance: Codable {
    let contractType: String?
    let contractAddress: String?
    let accountAddress: String?
    let tokenId: String?
    let balance: String?
    let blockHash: String?
    let blockNumber: Int64?
    let chainId: Int64?

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
    let status: Int
    let page: TokenBalancesPage?
    let balances: [TokenBalance]
}

private struct TokenBalancesPayload: Codable {
    let page: TokenBalancesPage?
    let balances: [TokenBalance]?
}

@available(macOS 12.0, iOS 15.0, *)
public final class IndexerClient {
    private let projectAccessKey: String
    private let environment: OmsEnvironment
    private let client: HttpClient = HttpClient()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    internal init(
        projectAccessKey: String,
        environment: OmsEnvironment
    ) {
        self.projectAccessKey = projectAccessKey
        self.environment = environment
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    func getTokenBalances(
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
