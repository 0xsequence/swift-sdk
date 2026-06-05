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

public struct TokenBalancesPageRequest: Codable, Sendable {
    public let page: Int?
    public let pageSize: Int?

    public init(page: Int? = nil, pageSize: Int? = nil) {
        self.page = page
        self.pageSize = pageSize
    }
}

public struct TokenContractInfo: Codable, Sendable {
    public let chainId: Int64?
    public let address: String?
    public let source: String?
    public let name: String?
    public let type: String?
    public let symbol: String?
    public let decimals: Int?
    public let logoURI: String?
    public let deployed: Bool?
    public let bytecodeHash: String?
    public let extensions: [String: WebRPCJSONValue]?
    public let updatedAt: String?
    public let queuedAt: String?
    public let status: String?

    public init(
        chainId: Int64? = nil,
        address: String? = nil,
        source: String? = nil,
        name: String? = nil,
        type: String? = nil,
        symbol: String? = nil,
        decimals: Int? = nil,
        logoURI: String? = nil,
        deployed: Bool? = nil,
        bytecodeHash: String? = nil,
        extensions: [String: WebRPCJSONValue]? = nil,
        updatedAt: String? = nil,
        queuedAt: String? = nil,
        status: String? = nil
    ) {
        self.chainId = chainId
        self.address = address
        self.source = source
        self.name = name
        self.type = type
        self.symbol = symbol
        self.decimals = decimals
        self.logoURI = logoURI
        self.deployed = deployed
        self.bytecodeHash = bytecodeHash
        self.extensions = extensions
        self.updatedAt = updatedAt
        self.queuedAt = queuedAt
        self.status = status
    }
}

public struct TokenMetadataAsset: Codable, Sendable {
    public let id: Int64?
    public let collectionId: Int64?
    public let tokenId: String?
    public let url: String?
    public let metadataField: String?
    public let name: String?
    public let filesize: Int64?
    public let mimeType: String?
    public let width: Int?
    public let height: Int?
    public let updatedAt: String?

    public init(
        id: Int64? = nil,
        collectionId: Int64? = nil,
        tokenId: String? = nil,
        url: String? = nil,
        metadataField: String? = nil,
        name: String? = nil,
        filesize: Int64? = nil,
        mimeType: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.collectionId = collectionId
        self.tokenId = tokenId
        self.url = url
        self.metadataField = metadataField
        self.name = name
        self.filesize = filesize
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case collectionId
        case tokenId
        case tokenID
        case url
        case metadataField
        case name
        case filesize
        case mimeType
        case width
        case height
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(Int64.self, forKey: .id)
        self.collectionId = try container.decodeIfPresent(Int64.self, forKey: .collectionId)
        self.tokenId = try container.decodeIfPresent(String.self, forKey: .tokenId)
            ?? container.decodeIfPresent(String.self, forKey: .tokenID)
        self.url = try container.decodeIfPresent(String.self, forKey: .url)
        self.metadataField = try container.decodeIfPresent(String.self, forKey: .metadataField)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.filesize = try container.decodeIfPresent(Int64.self, forKey: .filesize)
        self.mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        self.width = try container.decodeIfPresent(Int.self, forKey: .width)
        self.height = try container.decodeIfPresent(Int.self, forKey: .height)
        self.updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(collectionId, forKey: .collectionId)
        try container.encodeIfPresent(tokenId, forKey: .tokenID)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encodeIfPresent(metadataField, forKey: .metadataField)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(filesize, forKey: .filesize)
        try container.encodeIfPresent(mimeType, forKey: .mimeType)
        try container.encodeIfPresent(width, forKey: .width)
        try container.encodeIfPresent(height, forKey: .height)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}

public struct TokenMetadata: Codable, Sendable {
    public let chainId: Int64?
    public let contractAddress: String?
    public let tokenId: String?
    public let source: String?
    public let name: String?
    public let description: String?
    public let image: String?
    public let video: String?
    public let audio: String?
    public let properties: [String: WebRPCJSONValue]?
    public let attributes: [[String: WebRPCJSONValue]]?
    public let imageData: String?
    public let externalUrl: String?
    public let backgroundColor: String?
    public let animationUrl: String?
    public let decimals: Int?
    public let updatedAt: String?
    public let assets: [TokenMetadataAsset]?
    public let status: String?
    public let queuedAt: String?
    public let lastFetched: String?

    public init(
        chainId: Int64? = nil,
        contractAddress: String? = nil,
        tokenId: String? = nil,
        source: String? = nil,
        name: String? = nil,
        description: String? = nil,
        image: String? = nil,
        video: String? = nil,
        audio: String? = nil,
        properties: [String: WebRPCJSONValue]? = nil,
        attributes: [[String: WebRPCJSONValue]]? = nil,
        imageData: String? = nil,
        externalUrl: String? = nil,
        backgroundColor: String? = nil,
        animationUrl: String? = nil,
        decimals: Int? = nil,
        updatedAt: String? = nil,
        assets: [TokenMetadataAsset]? = nil,
        status: String? = nil,
        queuedAt: String? = nil,
        lastFetched: String? = nil
    ) {
        self.chainId = chainId
        self.contractAddress = contractAddress
        self.tokenId = tokenId
        self.source = source
        self.name = name
        self.description = description
        self.image = image
        self.video = video
        self.audio = audio
        self.properties = properties
        self.attributes = attributes
        self.imageData = imageData
        self.externalUrl = externalUrl
        self.backgroundColor = backgroundColor
        self.animationUrl = animationUrl
        self.decimals = decimals
        self.updatedAt = updatedAt
        self.assets = assets
        self.status = status
        self.queuedAt = queuedAt
        self.lastFetched = lastFetched
    }

    enum CodingKeys: String, CodingKey {
        case chainId
        case contractAddress
        case tokenId
        case tokenID
        case source
        case name
        case description
        case image
        case video
        case audio
        case properties
        case attributes
        case imageData = "image_data"
        case externalUrl = "external_url"
        case backgroundColor = "background_color"
        case animationUrl = "animation_url"
        case decimals
        case updatedAt
        case assets
        case status
        case queuedAt
        case lastFetched
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.chainId = try container.decodeIfPresent(Int64.self, forKey: .chainId)
        self.contractAddress = try container.decodeIfPresent(String.self, forKey: .contractAddress)
        self.tokenId = try container.decodeIfPresent(String.self, forKey: .tokenId)
            ?? container.decodeIfPresent(String.self, forKey: .tokenID)
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.image = try container.decodeIfPresent(String.self, forKey: .image)
        self.video = try container.decodeIfPresent(String.self, forKey: .video)
        self.audio = try container.decodeIfPresent(String.self, forKey: .audio)
        self.properties = try container.decodeIfPresent([String: WebRPCJSONValue].self, forKey: .properties)
        self.attributes = try container.decodeIfPresent([[String: WebRPCJSONValue]].self, forKey: .attributes)
        self.imageData = try container.decodeIfPresent(String.self, forKey: .imageData)
        self.externalUrl = try container.decodeIfPresent(String.self, forKey: .externalUrl)
        self.backgroundColor = try container.decodeIfPresent(String.self, forKey: .backgroundColor)
        self.animationUrl = try container.decodeIfPresent(String.self, forKey: .animationUrl)
        self.decimals = try container.decodeIfPresent(Int.self, forKey: .decimals)
        self.updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        self.assets = try container.decodeIfPresent([TokenMetadataAsset].self, forKey: .assets)
        self.status = try container.decodeIfPresent(String.self, forKey: .status)
        self.queuedAt = try container.decodeIfPresent(String.self, forKey: .queuedAt)
        self.lastFetched = try container.decodeIfPresent(String.self, forKey: .lastFetched)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(chainId, forKey: .chainId)
        try container.encodeIfPresent(contractAddress, forKey: .contractAddress)
        try container.encodeIfPresent(tokenId, forKey: .tokenID)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(image, forKey: .image)
        try container.encodeIfPresent(video, forKey: .video)
        try container.encodeIfPresent(audio, forKey: .audio)
        try container.encodeIfPresent(properties, forKey: .properties)
        try container.encodeIfPresent(attributes, forKey: .attributes)
        try container.encodeIfPresent(imageData, forKey: .imageData)
        try container.encodeIfPresent(externalUrl, forKey: .externalUrl)
        try container.encodeIfPresent(backgroundColor, forKey: .backgroundColor)
        try container.encodeIfPresent(animationUrl, forKey: .animationUrl)
        try container.encodeIfPresent(decimals, forKey: .decimals)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(assets, forKey: .assets)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(queuedAt, forKey: .queuedAt)
        try container.encodeIfPresent(lastFetched, forKey: .lastFetched)
    }
}

public struct TokenBalance: Codable, Sendable {
    public let contractType: String?
    public let contractAddress: String?
    public let accountAddress: String?
    public let tokenId: String?
    public let balance: String?
    public let balanceUSD: String?
    public let priceUSD: String?
    public let priceUpdatedAt: String?
    public let blockHash: String?
    public let blockNumber: Int64?
    public let chainId: Int64?
    public let uniqueCollectibles: String?
    public let isSummary: Bool?
    public let contractInfo: TokenContractInfo?
    public let tokenMetadata: TokenMetadata?

    public init(
        contractType: String?,
        contractAddress: String?,
        accountAddress: String?,
        tokenId: String?,
        balance: String?,
        balanceUSD: String? = nil,
        priceUSD: String? = nil,
        priceUpdatedAt: String? = nil,
        blockHash: String?,
        blockNumber: Int64?,
        chainId: Int64?,
        uniqueCollectibles: String? = nil,
        isSummary: Bool? = nil,
        contractInfo: TokenContractInfo? = nil,
        tokenMetadata: TokenMetadata? = nil
    ) {
        self.contractType = contractType
        self.contractAddress = contractAddress
        self.accountAddress = accountAddress
        self.tokenId = tokenId
        self.balance = balance
        self.balanceUSD = balanceUSD
        self.priceUSD = priceUSD
        self.priceUpdatedAt = priceUpdatedAt
        self.blockHash = blockHash
        self.blockNumber = blockNumber
        self.chainId = chainId
        self.uniqueCollectibles = uniqueCollectibles
        self.isSummary = isSummary
        self.contractInfo = contractInfo
        self.tokenMetadata = tokenMetadata
    }

    enum CodingKeys: String, CodingKey {
        case contractType
        case contractAddress
        case accountAddress
        case tokenId
        case tokenID
        case balance
        case balanceUSD
        case priceUSD
        case priceUpdatedAt
        case blockHash
        case blockNumber
        case chainId
        case uniqueCollectibles
        case isSummary
        case contractInfo
        case tokenMetadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.contractType = try container.decodeIfPresent(String.self, forKey: .contractType)
        self.contractAddress = try container.decodeIfPresent(String.self, forKey: .contractAddress)
        self.accountAddress = try container.decodeIfPresent(String.self, forKey: .accountAddress)
        self.tokenId = try container.decodeIfPresent(String.self, forKey: .tokenId)
            ?? container.decodeIfPresent(String.self, forKey: .tokenID)
        self.balance = try container.decodeIfPresent(String.self, forKey: .balance)
        self.balanceUSD = try container.decodeIfPresent(String.self, forKey: .balanceUSD)
        self.priceUSD = try container.decodeIfPresent(String.self, forKey: .priceUSD)
        self.priceUpdatedAt = try container.decodeIfPresent(String.self, forKey: .priceUpdatedAt)
        self.blockHash = try container.decodeIfPresent(String.self, forKey: .blockHash)
        self.blockNumber = try container.decodeIfPresent(Int64.self, forKey: .blockNumber)
        self.chainId = try container.decodeIfPresent(Int64.self, forKey: .chainId)
        self.uniqueCollectibles = try container.decodeIfPresent(String.self, forKey: .uniqueCollectibles)
        self.isSummary = try container.decodeIfPresent(Bool.self, forKey: .isSummary)
        self.contractInfo = try container.decodeIfPresent(TokenContractInfo.self, forKey: .contractInfo)
        self.tokenMetadata = try container.decodeIfPresent(TokenMetadata.self, forKey: .tokenMetadata)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(contractType, forKey: .contractType)
        try container.encodeIfPresent(contractAddress, forKey: .contractAddress)
        try container.encodeIfPresent(accountAddress, forKey: .accountAddress)
        try container.encodeIfPresent(tokenId, forKey: .tokenID)
        try container.encodeIfPresent(balance, forKey: .balance)
        try container.encodeIfPresent(balanceUSD, forKey: .balanceUSD)
        try container.encodeIfPresent(priceUSD, forKey: .priceUSD)
        try container.encodeIfPresent(priceUpdatedAt, forKey: .priceUpdatedAt)
        try container.encodeIfPresent(blockHash, forKey: .blockHash)
        try container.encodeIfPresent(blockNumber, forKey: .blockNumber)
        try container.encodeIfPresent(chainId, forKey: .chainId)
        try container.encodeIfPresent(uniqueCollectibles, forKey: .uniqueCollectibles)
        try container.encodeIfPresent(isSummary, forKey: .isSummary)
        try container.encodeIfPresent(contractInfo, forKey: .contractInfo)
        try container.encodeIfPresent(tokenMetadata, forKey: .tokenMetadata)
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
