public struct TokenContractInfo: Codable, Sendable {
    public let chainId: Int64?
    public let address: String?
    public let source: String?
    public let name: String?
    public let type: String?
    public let symbol: String?
    public let decimals: Int?
    public let logoURI: String?
    public let deployed: Bool?
    public let bytecodeHash: String?
    public let extensions: [String: JSONValue]?
    public let updatedAt: String?
    public let queuedAt: String?
    public let status: String?

    public init(
        chainId: Int64? = nil,
        address: String? = nil,
        source: String? = nil,
        name: String? = nil,
        type: String? = nil,
        symbol: String? = nil,
        decimals: Int? = nil,
        logoURI: String? = nil,
        deployed: Bool? = nil,
        bytecodeHash: String? = nil,
        extensions: [String: JSONValue]? = nil,
        updatedAt: String? = nil,
        queuedAt: String? = nil,
        status: String? = nil
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
