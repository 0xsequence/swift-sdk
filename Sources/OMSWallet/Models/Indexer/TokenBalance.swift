public struct NativeTokenBalance: Codable, Sendable {
    public let contractType: String
    public let accountAddress: String
    public let name: String
    public let symbol: String
    public let balance: String
    public let chainId: Int64
    public let balanceUSD: String?
    public let priceUSD: String?
    public let priceUpdatedAt: String?

    public init(
        accountAddress: String,
        name: String,
        symbol: String,
        balance: String,
        chainId: Int64,
        balanceUSD: String? = nil,
        priceUSD: String? = nil,
        priceUpdatedAt: String? = nil
    ) {
        self.contractType = "NATIVE"
        self.accountAddress = accountAddress
        self.name = name
        self.symbol = symbol
        self.balance = balance
        self.chainId = chainId
        self.balanceUSD = balanceUSD
        self.priceUSD = priceUSD
        self.priceUpdatedAt = priceUpdatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case accountAddress
        case name
        case symbol
        case balance
        case balanceWei
        case chainId
        case balanceUSD
        case priceUSD
        case priceUpdatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.contractType = "NATIVE"
        self.accountAddress = try container.decode(String.self, forKey: .accountAddress)
        self.name = try container.decode(String.self, forKey: .name)
        self.symbol = try container.decode(String.self, forKey: .symbol)
        self.balance = try container.decodeIfPresent(String.self, forKey: .balance)
            ?? container.decode(String.self, forKey: .balanceWei)
        self.chainId = try container.decode(Int64.self, forKey: .chainId)
        self.balanceUSD = try container.decodeIfPresent(String.self, forKey: .balanceUSD)
        self.priceUSD = try container.decodeIfPresent(String.self, forKey: .priceUSD)
        self.priceUpdatedAt = try container.decodeIfPresent(String.self, forKey: .priceUpdatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accountAddress, forKey: .accountAddress)
        try container.encode(name, forKey: .name)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(balance, forKey: .balance)
        try container.encode(chainId, forKey: .chainId)
        try container.encodeIfPresent(balanceUSD, forKey: .balanceUSD)
        try container.encodeIfPresent(priceUSD, forKey: .priceUSD)
        try container.encodeIfPresent(priceUpdatedAt, forKey: .priceUpdatedAt)
    }
}

public struct ContractTokenBalance: Codable, Sendable {
    public let contractType: String
    public let contractAddress: String
    public let accountAddress: String
    public let tokenId: String
    public let balance: String
    public let blockHash: String
    public let blockNumber: Int64
    public let chainId: Int64
    public let balanceUSD: String?
    public let priceUSD: String?
    public let priceUpdatedAt: String?
    public let uniqueCollectibles: String?
    public let isSummary: Bool?
    public let contractInfo: TokenContractInfo?
    public let tokenMetadata: TokenMetadata?

    public init(
        contractType: String,
        contractAddress: String,
        accountAddress: String,
        tokenId: String,
        balance: String,
        blockHash: String,
        blockNumber: Int64,
        chainId: Int64,
        balanceUSD: String? = nil,
        priceUSD: String? = nil,
        priceUpdatedAt: String? = nil,
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
        self.blockHash = blockHash
        self.blockNumber = blockNumber
        self.chainId = chainId
        self.balanceUSD = balanceUSD
        self.priceUSD = priceUSD
        self.priceUpdatedAt = priceUpdatedAt
        self.uniqueCollectibles = uniqueCollectibles
        self.isSummary = isSummary
        self.contractInfo = contractInfo
        self.tokenMetadata = tokenMetadata
    }

    private enum CodingKeys: String, CodingKey {
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
        self.contractType = try container.decode(String.self, forKey: .contractType)
        self.contractAddress = try container.decode(String.self, forKey: .contractAddress)
        self.accountAddress = try container.decode(String.self, forKey: .accountAddress)
        if let tokenId = try container.decodeIfPresent(String.self, forKey: .tokenId)
            ?? container.decodeIfPresent(String.self, forKey: .tokenID) {
            self.tokenId = tokenId
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.tokenID,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Missing tokenId"
                )
            )
        }
        self.balance = try container.decode(String.self, forKey: .balance)
        self.balanceUSD = try container.decodeIfPresent(String.self, forKey: .balanceUSD)
        self.priceUSD = try container.decodeIfPresent(String.self, forKey: .priceUSD)
        self.priceUpdatedAt = try container.decodeIfPresent(String.self, forKey: .priceUpdatedAt)
        self.blockHash = try container.decode(String.self, forKey: .blockHash)
        self.blockNumber = try container.decode(Int64.self, forKey: .blockNumber)
        self.chainId = try container.decode(Int64.self, forKey: .chainId)
        self.uniqueCollectibles = try container.decodeIfPresent(String.self, forKey: .uniqueCollectibles)
        self.isSummary = try container.decodeIfPresent(Bool.self, forKey: .isSummary)
        self.contractInfo = try container.decodeIfPresent(TokenContractInfo.self, forKey: .contractInfo)
        self.tokenMetadata = try container.decodeIfPresent(TokenMetadata.self, forKey: .tokenMetadata)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(contractType, forKey: .contractType)
        try container.encode(contractAddress, forKey: .contractAddress)
        try container.encode(accountAddress, forKey: .accountAddress)
        try container.encode(tokenId, forKey: .tokenID)
        try container.encode(balance, forKey: .balance)
        try container.encodeIfPresent(balanceUSD, forKey: .balanceUSD)
        try container.encodeIfPresent(priceUSD, forKey: .priceUSD)
        try container.encodeIfPresent(priceUpdatedAt, forKey: .priceUpdatedAt)
        try container.encode(blockHash, forKey: .blockHash)
        try container.encode(blockNumber, forKey: .blockNumber)
        try container.encode(chainId, forKey: .chainId)
        try container.encodeIfPresent(uniqueCollectibles, forKey: .uniqueCollectibles)
        try container.encodeIfPresent(isSummary, forKey: .isSummary)
        try container.encodeIfPresent(contractInfo, forKey: .contractInfo)
        try container.encodeIfPresent(tokenMetadata, forKey: .tokenMetadata)
    }
}

public enum TokenBalance: Sendable {
    case native(NativeTokenBalance)
    case contract(ContractTokenBalance)

    public var contractType: String {
        switch self {
        case .native(let balance): balance.contractType
        case .contract(let balance): balance.contractType
        }
    }

    public var accountAddress: String {
        switch self {
        case .native(let balance): balance.accountAddress
        case .contract(let balance): balance.accountAddress
        }
    }

    public var balance: String {
        switch self {
        case .native(let balance): balance.balance
        case .contract(let balance): balance.balance
        }
    }

    public var chainId: Int64 {
        switch self {
        case .native(let balance): balance.chainId
        case .contract(let balance): balance.chainId
        }
    }

    public var balanceUSD: String? {
        switch self {
        case .native(let balance): balance.balanceUSD
        case .contract(let balance): balance.balanceUSD
        }
    }

    public var priceUSD: String? {
        switch self {
        case .native(let balance): balance.priceUSD
        case .contract(let balance): balance.priceUSD
        }
    }

    public var priceUpdatedAt: String? {
        switch self {
        case .native(let balance): balance.priceUpdatedAt
        case .contract(let balance): balance.priceUpdatedAt
        }
    }
}
