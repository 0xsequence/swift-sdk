public enum Network: String, CaseIterable, Sendable, CustomStringConvertible {
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
    
    public static var supportedNetworks: [Network] {
        Array(allCases)
    }

    public static func from(chainId: String) -> Network? {
        supportedNetworks.first { $0.chainId == chainId }
    }
}
