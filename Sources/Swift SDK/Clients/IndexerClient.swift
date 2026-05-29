import Foundation

public struct TokenBalancesPage: Codable, Sendable {
    public let page: Int
    public let pageSize: Int
    public let more: Bool

    public init(page: Int, pageSize: Int, more: Bool) {
        self.page = page
        self.pageSize = pageSize
        self.more = more
    }
}

public struct TokenBalance: Codable, Sendable {
    public let contractType: String?
    public let contractAddress: String?
    public let accountAddress: String?
    public let tokenId: String?
    public let balance: String?
    public let blockHash: String?
    public let blockNumber: Int64?
    public let chainId: Int64?

    public init(
        contractType: String?,
        contractAddress: String?,
        accountAddress: String?,
        tokenId: String?,
        balance: String?,
        blockHash: String?,
        blockNumber: Int64?,
        chainId: Int64?
    ) {
        self.contractType = contractType
        self.contractAddress = contractAddress
        self.accountAddress = accountAddress
        self.tokenId = tokenId
        self.balance = balance
        self.blockHash = blockHash
        self.blockNumber = blockNumber
        self.chainId = chainId
    }

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

public struct TokenBalancesResult: Sendable {
    public let status: Int
    public let page: TokenBalancesPage?
    public let balances: [TokenBalance]

    public init(status: Int, page: TokenBalancesPage?, balances: [TokenBalance]) {
        self.status = status
        self.page = page
        self.balances = balances
    }
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
protocol WalletIndexerClient {
    func getTokenBalances(
        network: Network,
        contractAddress: String,
        walletAddress: String,
        includeMetadata: Bool
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
            "X-Access-Key": publishableKey,
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
