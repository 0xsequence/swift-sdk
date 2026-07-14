public struct TokenContractInfo: Codable, Sendable {
    public let chainId: Int64
    public let address: String
    public let source: String
    public let name: String
    public let type: String
    public let symbol: String
    public let decimals: Int?
    public let logoURI: String?
    public let deployed: Bool
    public let bytecodeHash: String
    public let extensions: [String: JSONValue]
    public let updatedAt: String
    public let queuedAt: String?
    public let status: String

    public init(
        chainId: Int64,
        address: String,
        source: String,
        name: String,
        type: String,
        symbol: String,
        decimals: Int? = nil,
        logoURI: String? = nil,
        deployed: Bool,
        bytecodeHash: String,
        extensions: [String: JSONValue],
        updatedAt: String,
        queuedAt: String? = nil,
        status: String
    ) {
        self.chainId = chainId
        self.address = address
        self.source = source
        self.name = name
        self.type = type
        self.symbol = symbol
        self.decimals = decimals
        self.logoURI = logoURI
        self.deployed = deployed
        self.bytecodeHash = bytecodeHash
        self.extensions = extensions
        self.updatedAt = updatedAt
        self.queuedAt = queuedAt
        self.status = status
    }
}
