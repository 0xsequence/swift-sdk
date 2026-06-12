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
