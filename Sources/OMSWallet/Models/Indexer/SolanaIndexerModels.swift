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
