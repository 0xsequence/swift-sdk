import Foundation

public enum SolanaVerificationStatus: String, Codable, Sendable {
    case verified
    case unverified
    case unknown
}

public enum SolanaVerificationSource: String, Codable, Sendable {
    case jupiter
    case solflareUtl = "solflare-utl"
    case none
}

public enum SolanaTokenProgram: String, Codable, Sendable {
    case splToken = "spl-token"
    case token2022 = "token-2022"
}

public struct SolanaNativeBalance: Codable, Sendable {
    public let network: SolanaNetwork
    public let accountAddress: String
    public let name: String
    public let symbol: String
    public let decimals: Int
    public let balance: String
    public let formattedBalance: String
    public let imageUrl: String?
    public let metadataUri: String?
    public let verificationStatus: SolanaVerificationStatus
    public let verificationSource: SolanaVerificationSource
    public let priceUSD: String?
    public let balanceUSD: String?
}

public struct SolanaFungibleTokenBalance: Codable, Sendable {
    public let network: SolanaNetwork
    public let accountAddress: String
    public let tokenProgram: SolanaTokenProgram
    public let mintAddress: String
    public let name: String
    public let symbol: String
    public let decimals: Int
    public let balance: String
    public let formattedBalance: String
    public let imageUrl: String?
    public let metadataUri: String?
    public let verificationStatus: SolanaVerificationStatus
    public let verificationSource: SolanaVerificationSource
    public let priceUSD: String?
    public let balanceUSD: String?
}

public enum SolanaBalance: Decodable, Sendable {
    case native(SolanaNativeBalance)
    case fungibleToken(SolanaFungibleTokenBalance)

    private enum CodingKeys: String, CodingKey { case assetType, tokenProgram, mintAddress }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .assetType) {
        case "native":
            guard try container.decodeIfPresent(String.self, forKey: .tokenProgram) == nil,
                  try container.decodeIfPresent(String.self, forKey: .mintAddress) == nil else {
                throw DecodingError.dataCorruptedError(forKey: .assetType, in: container, debugDescription: "Native balance contains token fields")
            }
            self = .native(try SolanaNativeBalance(from: decoder))
        case "fungible-token":
            self = .fungibleToken(try SolanaFungibleTokenBalance(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .assetType, in: container, debugDescription: "Unsupported Solana asset type")
        }
    }

    public var network: SolanaNetwork {
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

    public var verificationStatus: SolanaVerificationStatus {
        switch self {
        case .native(let balance): balance.verificationStatus
        case .fungibleToken(let balance): balance.verificationStatus
        }
    }

    public var verificationSource: SolanaVerificationSource {
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

public struct SolanaNetworkError: Codable, Sendable {
    public let network: SolanaNetwork
    public let reason: String
}

public struct GetSolanaBalancesParams: Sendable {
    public let walletAddress: String
    public let networks: [SolanaNetwork]
    public let includeMetadata: Bool
    public let omitNativeBalances: Bool?
    public let mintAddresses: [String]
    public let excludedMintAddresses: [String]

    public init(
        walletAddress: String,
        networks: [SolanaNetwork] = [.mainnet, .devnet],
        includeMetadata: Bool = true,
        omitNativeBalances: Bool? = nil,
        mintAddresses: [String] = [],
        excludedMintAddresses: [String] = []
    ) {
        self.walletAddress = walletAddress
        self.networks = networks
        self.includeMetadata = includeMetadata
        self.omitNativeBalances = omitNativeBalances
        self.mintAddresses = mintAddresses
        self.excludedMintAddresses = excludedMintAddresses
    }
}

public struct SolanaBalancesResult: Sendable {
    public let status: Int
    public let balances: [SolanaBalance]
    public let errors: [SolanaNetworkError]
}
