public enum IndexerNetworkType: String, Codable, Sendable {
    case mainnets = "MAINNETS"
    case testnets = "TESTNETS"
    case all = "ALL"
}

public enum ContractVerificationStatus: String, Codable, Sendable {
    case verified = "VERIFIED"
    case unverified = "UNVERIFIED"
    case all = "ALL"
}

public enum SortOrder: String, Codable, Sendable {
    case descending = "DESC"
    case ascending = "ASC"
}

public struct SortBy: Codable, Sendable {
    public let column: String
    public let order: SortOrder

    public init(column: String, order: SortOrder) {
        self.column = column
        self.order = order
    }
}

public struct MetadataOptions: Codable, Sendable {
    public let verifiedOnly: Bool?
    public let unverifiedOnly: Bool?
    public let includeContracts: [String]?

    public init(
        verifiedOnly: Bool? = nil,
        unverifiedOnly: Bool? = nil,
        includeContracts: [String]? = nil
    ) {
        self.verifiedOnly = verifiedOnly
        self.unverifiedOnly = unverifiedOnly
        self.includeContracts = includeContracts
    }
}

public struct GetBalancesParams: Sendable {
    public let walletAddress: String
    public let networks: [Network]?
    public let networkType: IndexerNetworkType?
    public let contractAddresses: [String]?
    public let includeMetadata: Bool
    public let omitPrices: Bool?
    public let tokenIds: [String]?
    public let contractStatus: ContractVerificationStatus?
    public let page: TokenBalancesPageRequest?

    public init(
        walletAddress: String,
        networks: [Network]? = nil,
        networkType: IndexerNetworkType? = nil,
        contractAddresses: [String]? = nil,
        includeMetadata: Bool = true,
        omitPrices: Bool? = nil,
        tokenIds: [String]? = nil,
        contractStatus: ContractVerificationStatus? = nil,
        page: TokenBalancesPageRequest? = nil
    ) {
        self.walletAddress = walletAddress
        self.networks = networks
        self.networkType = networkType
        self.contractAddresses = contractAddresses
        self.includeMetadata = includeMetadata
        self.omitPrices = omitPrices
        self.tokenIds = tokenIds
        self.contractStatus = contractStatus
        self.page = page
    }
}

public struct BalancesResult: Sendable {
    public let status: Int
    public let page: TokenBalancesPage?
    public let nativeBalances: [TokenBalance]
    public let balances: [TokenBalance]

    public init(
        status: Int,
        page: TokenBalancesPage?,
        nativeBalances: [TokenBalance],
        balances: [TokenBalance]
    ) {
        self.status = status
        self.page = page
        self.nativeBalances = nativeBalances
        self.balances = balances
    }
}

public struct GetTransactionHistoryParams: Sendable {
    public let walletAddress: String
    public let networks: [Network]?
    public let networkType: IndexerNetworkType?
    public let contractAddresses: [String]?
    public let transactionHashes: [String]?
    public let metaTransactionIds: [String]?
    public let fromBlock: Int?
    public let toBlock: Int?
    public let tokenId: String?
    public let includeMetadata: Bool
    public let omitPrices: Bool?
    public let metadataOptions: MetadataOptions?
    public let page: TokenBalancesPageRequest?

    public init(
        walletAddress: String,
        networks: [Network]? = nil,
        networkType: IndexerNetworkType? = nil,
        contractAddresses: [String]? = nil,
        transactionHashes: [String]? = nil,
        metaTransactionIds: [String]? = nil,
        fromBlock: Int? = nil,
        toBlock: Int? = nil,
        tokenId: String? = nil,
        includeMetadata: Bool = true,
        omitPrices: Bool? = nil,
        metadataOptions: MetadataOptions? = nil,
        page: TokenBalancesPageRequest? = nil
    ) {
        self.walletAddress = walletAddress
        self.networks = networks
        self.networkType = networkType
        self.contractAddresses = contractAddresses
        self.transactionHashes = transactionHashes
        self.metaTransactionIds = metaTransactionIds
        self.fromBlock = fromBlock
        self.toBlock = toBlock
        self.tokenId = tokenId
        self.includeMetadata = includeMetadata
        self.omitPrices = omitPrices
        self.metadataOptions = metadataOptions
        self.page = page
    }
}

public struct TransactionHistoryResult: Sendable {
    public let status: Int
    public let page: TokenBalancesPage?
    public let transactions: [Transaction]

    public init(status: Int, page: TokenBalancesPage?, transactions: [Transaction]) {
        self.status = status
        self.page = page
        self.transactions = transactions
    }
}
