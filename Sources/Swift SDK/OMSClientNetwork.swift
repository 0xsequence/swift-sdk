/// Swift SDK chain-id binding table.
///
/// Source parity:
/// - `oms-client-kotlin-sdk/src/main/java/com/omsclient/kotlin_sdk/Network.kt`
/// - `OMSClientNetworks.supportedNetworks`
/// - `OMSClientNetworks.network(chainId:)`
public enum OMSClientNetwork: String, CaseIterable, Sendable, CustomStringConvertible {
    case polygon
    case polygonAmoy

    public var chainId: String {
        switch self {
        case .polygon:
            return "137"
        case .polygonAmoy:
            return "80002"
        }
    }

    public var displayName: String {
        switch self {
        case .polygon:
            return "Polygon"
        case .polygonAmoy:
            return "Polygon Amoy"
        }
    }

    internal var indexerName: String {
        switch self {
        case .polygon:
            return "polygon"
        case .polygonAmoy:
            return "amoy"
        }
    }

    public var description: String {
        displayName
    }
}

public final class OMSClientNetworks {
    private init() {}

    public static let supportedNetworks: [OMSClientNetwork] = OMSClientNetwork.allCases

    public static func network(chainId: String) -> OMSClientNetwork? {
        supportedNetworks.first { $0.chainId == chainId }
    }

    internal static func requireSupported(chainId: String) throws -> OMSClientNetwork {
        guard let network = network(chainId: chainId) else {
            throw OMSClientNetworkError.unsupportedChainId(chainId)
        }
        return network
    }
}

public enum OMSClientNetworkError: Error, Equatable {
    case unsupportedChainId(String)
}
