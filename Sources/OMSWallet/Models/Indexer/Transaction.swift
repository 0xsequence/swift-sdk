public struct TransactionTransfer: Codable, Sendable {
    public let transferType: String
    public let contractAddress: String
    public let contractType: String
    public let from: String
    public let to: String
    public let tokenIds: [String]?
    public let amounts: [String]
    public let logIndex: Int
    public let amountsUSD: [String]?
    public let pricesUSD: [String]?
    public let contractInfo: TokenContractInfo?
    public let tokenMetadata: [String: TokenMetadata]?

    public init(
        transferType: String,
        contractAddress: String,
        contractType: String,
        from: String,
        to: String,
        tokenIds: [String]? = nil,
        amounts: [String],
        logIndex: Int,
        amountsUSD: [String]? = nil,
        pricesUSD: [String]? = nil,
        contractInfo: TokenContractInfo? = nil,
        tokenMetadata: [String: TokenMetadata]? = nil
    ) {
        self.transferType = transferType
        self.contractAddress = contractAddress
        self.contractType = contractType
        self.from = from
        self.to = to
        self.tokenIds = tokenIds
        self.amounts = amounts
        self.logIndex = logIndex
        self.amountsUSD = amountsUSD
        self.pricesUSD = pricesUSD
        self.contractInfo = contractInfo
        self.tokenMetadata = tokenMetadata
    }

    enum CodingKeys: String, CodingKey {
        case transferType
        case contractAddress
        case contractType
        case from
        case to
        case tokenIds
        case tokenIDs
        case amounts
        case logIndex
        case amountsUSD
        case pricesUSD
        case contractInfo
        case tokenMetadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.transferType = try container.decode(String.self, forKey: .transferType)
        self.contractAddress = try container.decode(String.self, forKey: .contractAddress)
        self.contractType = try container.decode(String.self, forKey: .contractType)
        self.from = try container.decode(String.self, forKey: .from)
        self.to = try container.decode(String.self, forKey: .to)
        self.tokenIds = try container.decodeIfPresent([String].self, forKey: .tokenIds)
            ?? container.decodeIfPresent([String].self, forKey: .tokenIDs)
        self.amounts = try container.decode([String].self, forKey: .amounts)
        self.logIndex = try container.decode(Int.self, forKey: .logIndex)
        self.amountsUSD = try container.decodeIfPresent([String].self, forKey: .amountsUSD)
        self.pricesUSD = try container.decodeIfPresent([String].self, forKey: .pricesUSD)
        self.contractInfo = try container.decodeIfPresent(TokenContractInfo.self, forKey: .contractInfo)
        self.tokenMetadata = try container.decodeIfPresent([String: TokenMetadata].self, forKey: .tokenMetadata)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(transferType, forKey: .transferType)
        try container.encode(contractAddress, forKey: .contractAddress)
        try container.encode(contractType, forKey: .contractType)
        try container.encode(from, forKey: .from)
        try container.encode(to, forKey: .to)
        try container.encodeIfPresent(tokenIds, forKey: .tokenIDs)
        try container.encode(amounts, forKey: .amounts)
        try container.encode(logIndex, forKey: .logIndex)
        try container.encodeIfPresent(amountsUSD, forKey: .amountsUSD)
        try container.encodeIfPresent(pricesUSD, forKey: .pricesUSD)
        try container.encodeIfPresent(contractInfo, forKey: .contractInfo)
        try container.encodeIfPresent(tokenMetadata, forKey: .tokenMetadata)
    }
}

public struct Transaction: Codable, Sendable {
    public let txnHash: String
    public let blockNumber: Int64
    public let blockHash: String
    public let chainId: Int64
    public let metaTxnId: String?
    public let transfers: [TransactionTransfer]
    public let timestamp: String

    public init(
        txnHash: String,
        blockNumber: Int64,
        blockHash: String,
        chainId: Int64,
        metaTxnId: String? = nil,
        transfers: [TransactionTransfer] = [],
        timestamp: String
    ) {
        self.txnHash = txnHash
        self.blockNumber = blockNumber
        self.blockHash = blockHash
        self.chainId = chainId
        self.metaTxnId = metaTxnId
        self.transfers = transfers
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case txnHash
        case blockNumber
        case blockHash
        case chainId
        case metaTxnId
        case metaTxnID
        case transfers
        case timestamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.txnHash = try container.decode(String.self, forKey: .txnHash)
        self.blockNumber = try container.decode(Int64.self, forKey: .blockNumber)
        self.blockHash = try container.decode(String.self, forKey: .blockHash)
        self.chainId = try container.decode(Int64.self, forKey: .chainId)
        self.metaTxnId = try container.decodeIfPresent(String.self, forKey: .metaTxnId)
            ?? container.decodeIfPresent(String.self, forKey: .metaTxnID)
        self.transfers = try container.decode([TransactionTransfer].self, forKey: .transfers)
        self.timestamp = try container.decode(String.self, forKey: .timestamp)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(txnHash, forKey: .txnHash)
        try container.encode(blockNumber, forKey: .blockNumber)
        try container.encode(blockHash, forKey: .blockHash)
        try container.encode(chainId, forKey: .chainId)
        try container.encodeIfPresent(metaTxnId, forKey: .metaTxnID)
        try container.encode(transfers, forKey: .transfers)
        try container.encode(timestamp, forKey: .timestamp)
    }
}
