import Foundation

public enum Network: String, CaseIterable, Sendable, CustomStringConvertible {
    case mainnet
    case sepolia
    case polygon
    case polygonAmoy = "amoy"
    case arbitrum
    case arbitrumSepolia = "arbitrum-sepolia"
    case optimism
    case optimismSepolia = "optimism-sepolia"
    case base
    case baseSepolia = "base-sepolia"
    case bsc
    case bscTestnet = "bsc-testnet"
    case arbitrumNova = "arbitrum-nova"
    case avalanche
    case avalancheTestnet = "avalanche-testnet"
    case katana

    public static let amoy: Network = .polygonAmoy

    public var id: Int {
        switch self {
        case .mainnet:
            return 1
        case .sepolia:
            return 11155111
        case .polygon:
            return 137
        case .polygonAmoy:
            return 80002
        case .arbitrum:
            return 42161
        case .arbitrumSepolia:
            return 421614
        case .optimism:
            return 10
        case .optimismSepolia:
            return 11155420
        case .base:
            return 8453
        case .baseSepolia:
            return 84532
        case .bsc:
            return 56
        case .bscTestnet:
            return 97
        case .arbitrumNova:
            return 42170
        case .avalanche:
            return 43114
        case .avalancheTestnet:
            return 43113
        case .katana:
            return 747474
        }
    }

    public var chainId: String {
        String(id)
    }

    public var name: String {
        rawValue
    }

    public var nativeTokenSymbol: String {
        switch self {
        case .mainnet, .sepolia, .arbitrum, .arbitrumSepolia, .optimism, .optimismSepolia,
             .base, .baseSepolia, .arbitrumNova, .katana:
            return "ETH"
        case .polygon, .polygonAmoy:
            return "POL"
        case .bsc, .bscTestnet:
            return "BNB"
        case .avalanche, .avalancheTestnet:
            return "AVAX"
        }
    }

    public var explorerUrl: String {
        switch self {
        case .mainnet:
            return "https://etherscan.io"
        case .sepolia:
            return "https://sepolia.etherscan.io"
        case .polygon:
            return "https://polygonscan.com"
        case .polygonAmoy:
            return "https://amoy.polygonscan.com"
        case .arbitrum:
            return "https://arbiscan.io"
        case .arbitrumSepolia:
            return "https://sepolia.arbiscan.io"
        case .optimism:
            return "https://optimistic.etherscan.io"
        case .optimismSepolia:
            return "https://sepolia-optimism.etherscan.io"
        case .base:
            return "https://basescan.org"
        case .baseSepolia:
            return "https://sepolia.basescan.org"
        case .bsc:
            return "https://bscscan.com"
        case .bscTestnet:
            return "https://testnet.bscscan.com"
        case .arbitrumNova:
            return "https://nova.arbiscan.io"
        case .avalanche:
            return "https://subnets.avax.network/c-chain"
        case .avalancheTestnet:
            return "https://subnets-test.avax.network/c-chain"
        case .katana:
            return "https://katanascan.com"
        }
    }

    public var explorerURL: URL? {
        URL(string: explorerUrl)
    }

    public var displayName: String {
        switch self {
        case .mainnet:
            return "Mainnet"
        case .sepolia:
            return "Sepolia"
        case .polygon:
            return "Polygon"
        case .polygonAmoy:
            return "Polygon Amoy"
        case .arbitrum:
            return "Arbitrum"
        case .arbitrumSepolia:
            return "Arbitrum Sepolia"
        case .optimism:
            return "Optimism"
        case .optimismSepolia:
            return "Optimism Sepolia"
        case .base:
            return "Base"
        case .baseSepolia:
            return "Base Sepolia"
        case .bsc:
            return "BSC"
        case .bscTestnet:
            return "BSC Testnet"
        case .arbitrumNova:
            return "Arbitrum Nova"
        case .avalanche:
            return "Avalanche"
        case .avalancheTestnet:
            return "Avalanche Testnet"
        case .katana:
            return "Katana"
        }
    }

    internal var indexerName: String {
        name
    }

    public var description: String {
        displayName
    }

    public static var supportedNetworks: [Network] {
        Array(allCases)
    }

    public static func findNetworkById(_ chainId: Int) -> Network? {
        supportedNetworks.first { $0.id == chainId }
    }

    public static func findNetworkByName(_ name: String) -> Network? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return supportedNetworks.first { $0.name.lowercased() == normalized }
            ?? (normalized == "polygonamoy" ? .polygonAmoy : nil)
    }
}
