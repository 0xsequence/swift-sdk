import Foundation

public enum TronVerificationStatus: String, Codable, Sendable {
    case verified
    case unverified
    case unknown
}

public enum TronTokenStandard: String, Codable, Sendable {
    case trc20
}

public struct TronNativeBalance: Codable, Sendable {
    public let network: TronNetwork
    /// Base58Check (`T…`) account address.
    public let accountAddress: String
    public let name: String
    public let symbol: String
    public let decimals: Int
    /// Raw balance in sun (1 TRX = 1,000,000 sun).
    public let balance: String
    public let formattedBalance: String
    public let imageUrl: String?
    public let metadataUri: String?
    public let verificationStatus: TronVerificationStatus
    public let verificationSource: String
    public let priceUSD: String?
    public let balanceUSD: String?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TronBalanceCodingKeys.self)
        network = try container.decode(TronNetwork.self, forKey: .network)
        accountAddress = try container.decode(String.self, forKey: .accountAddress)
        name = try container.decode(String.self, forKey: .name)
        symbol = try container.decode(String.self, forKey: .symbol)
        decimals = try container.decode(Int.self, forKey: .decimals)
        balance = try container.decode(String.self, forKey: .balance)
        formattedBalance = try container.decode(String.self, forKey: .formattedBalance)
        imageUrl = try container.decodeNonEmptyString(forKey: .imageUrl)
        metadataUri = try container.decodeNonEmptyString(forKey: .metadataUri)
        verificationStatus = try container.decode(TronVerificationStatus.self, forKey: .verificationStatus)
        verificationSource = try container.decode(String.self, forKey: .verificationSource)
        priceUSD = try container.decodeIfPresent(String.self, forKey: .priceUSD)
        balanceUSD = try container.decodeIfPresent(String.self, forKey: .balanceUSD)
    }
}

public struct TronFungibleTokenBalance: Codable, Sendable {
    public let network: TronNetwork
    /// Base58Check (`T…`) account address.
    public let accountAddress: String
    public let tokenStandard: TronTokenStandard
    /// Base58Check (`T…`) TRC-20 contract address.
    public let contractAddress: String
    public let name: String
    public let symbol: String
    public let decimals: Int
    /// Raw balance in the token's base units.
    public let balance: String
    public let formattedBalance: String
    public let imageUrl: String?
    public let metadataUri: String?
    public let verificationStatus: TronVerificationStatus
    public let verificationSource: String
    public let priceUSD: String?
    public let balanceUSD: String?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TronBalanceCodingKeys.self)
        network = try container.decode(TronNetwork.self, forKey: .network)
        accountAddress = try container.decode(String.self, forKey: .accountAddress)
        tokenStandard = try container.decode(TronTokenStandard.self, forKey: .tokenStandard)
        contractAddress = try container.decode(String.self, forKey: .contractAddress)
        name = try container.decode(String.self, forKey: .name)
        symbol = try container.decode(String.self, forKey: .symbol)
        decimals = try container.decode(Int.self, forKey: .decimals)
        balance = try container.decode(String.self, forKey: .balance)
        formattedBalance = try container.decode(String.self, forKey: .formattedBalance)
        imageUrl = try container.decodeNonEmptyString(forKey: .imageUrl)
        metadataUri = try container.decodeNonEmptyString(forKey: .metadataUri)
        verificationStatus = try container.decode(TronVerificationStatus.self, forKey: .verificationStatus)
        verificationSource = try container.decode(String.self, forKey: .verificationSource)
        priceUSD = try container.decodeIfPresent(String.self, forKey: .priceUSD)
        balanceUSD = try container.decodeIfPresent(String.self, forKey: .balanceUSD)
    }
}

private enum TronBalanceCodingKeys: String, CodingKey {
    case network, accountAddress, tokenStandard, contractAddress, name, symbol, decimals, balance
    case formattedBalance, imageUrl, metadataUri, verificationStatus, verificationSource, priceUSD
    case balanceUSD
}

private extension KeyedDecodingContainer where Key == TronBalanceCodingKeys {
    func decodeNonEmptyString(forKey key: Key) throws -> String? {
        guard let value = try decodeIfPresent(String.self, forKey: key), !value.isEmpty else {
            return nil
        }
        return value
    }
}

public enum TronBalance: Decodable, Sendable {
    case native(TronNativeBalance)
    case fungibleToken(TronFungibleTokenBalance)

    private enum CodingKeys: String, CodingKey { case assetType, tokenStandard, contractAddress }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .assetType) {
        case "native":
            guard try container.decodeIfPresent(String.self, forKey: .tokenStandard) == nil,
                  try container.decodeIfPresent(String.self, forKey: .contractAddress) == nil else {
                throw DecodingError.dataCorruptedError(forKey: .assetType, in: container, debugDescription: "Native balance contains token fields")
            }
            self = .native(try TronNativeBalance(from: decoder))
        case "fungible-token":
            self = .fungibleToken(try TronFungibleTokenBalance(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .assetType, in: container, debugDescription: "Unsupported Tron asset type")
        }
    }

    public var network: TronNetwork {
        switch self {
        case .native(let balance): balance.network
        case .fungibleToken(let balance): balance.network
        }
    }

    public var accountAddress: String {
        switch self {
        case .native(let balance): balance.accountAddress
        case .fungibleToken(let balance): balance.accountAddress
        }
    }

    public var name: String {
        switch self {
        case .native(let balance): balance.name
        case .fungibleToken(let balance): balance.name
        }
    }

    public var symbol: String {
        switch self {
        case .native(let balance): balance.symbol
        case .fungibleToken(let balance): balance.symbol
        }
    }

    public var decimals: Int {
        switch self {
        case .native(let balance): balance.decimals
        case .fungibleToken(let balance): balance.decimals
        }
    }

    public var balance: String {
        switch self {
        case .native(let balance): balance.balance
        case .fungibleToken(let balance): balance.balance
        }
    }

    public var formattedBalance: String {
        switch self {
        case .native(let balance): balance.formattedBalance
        case .fungibleToken(let balance): balance.formattedBalance
        }
    }

    public var imageUrl: String? {
        switch self {
        case .native(let balance): balance.imageUrl
        case .fungibleToken(let balance): balance.imageUrl
        }
    }

    public var metadataUri: String? {
        switch self {
        case .native(let balance): balance.metadataUri
        case .fungibleToken(let balance): balance.metadataUri
        }
    }

    public var verificationStatus: TronVerificationStatus {
        switch self {
        case .native(let balance): balance.verificationStatus
        case .fungibleToken(let balance): balance.verificationStatus
        }
    }

    public var verificationSource: String {
        switch self {
        case .native(let balance): balance.verificationSource
        case .fungibleToken(let balance): balance.verificationSource
        }
    }

    public var priceUSD: String? {
        switch self {
        case .native(let balance): balance.priceUSD
        case .fungibleToken(let balance): balance.priceUSD
        }
    }

    public var balanceUSD: String? {
        switch self {
        case .native(let balance): balance.balanceUSD
        case .fungibleToken(let balance): balance.balanceUSD
        }
    }
}

public struct TronNetworkError: Codable, Sendable {
    public let network: TronNetwork
    public let reason: String
}

public struct GetTronBalancesParams: Sendable {
    /// Base58Check (`T…`) wallet address.
    public let walletAddress: String
    public let networks: [TronNetwork]
    public let includeMetadata: Bool
    public let omitNativeBalances: Bool?
    /// Only return these TRC-20 contracts (`T…`).
    public let contractAddresses: [String]
    /// Exclude these TRC-20 contracts (`T…`).
    public let excludedContractAddresses: [String]

    public init(
        walletAddress: String,
        networks: [TronNetwork] = [.mainnet, .nile],
        includeMetadata: Bool = true,
        omitNativeBalances: Bool? = nil,
        contractAddresses: [String] = [],
        excludedContractAddresses: [String] = []
    ) {
        self.walletAddress = walletAddress
        self.networks = networks
        self.includeMetadata = includeMetadata
        self.omitNativeBalances = omitNativeBalances
        self.contractAddresses = contractAddresses
        self.excludedContractAddresses = excludedContractAddresses
    }
}

public struct TronBalancesResult: Sendable {
    public let status: Int
    public let balances: [TronBalance]
    public let errors: [TronNetworkError]
}
