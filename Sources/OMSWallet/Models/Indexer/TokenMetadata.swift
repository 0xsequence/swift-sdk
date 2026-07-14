public struct TokenMetadata: Codable, Sendable {
    public let chainId: Int64?
    public let contractAddress: String?
    public let tokenId: String
    public let source: String
    public let name: String
    public let description: String?
    public let image: String?
    public let video: String?
    public let audio: String?
    public let properties: [String: JSONValue]?
    public let attributes: [[String: JSONValue]]
    public let imageData: String?
    public let externalUrl: String?
    public let backgroundColor: String?
    public let animationUrl: String?
    public let decimals: Int?
    public let updatedAt: String?
    public let assets: [TokenMetadataAsset]?
    public let status: String
    public let queuedAt: String?
    public let lastFetched: String?

    public init(
        chainId: Int64? = nil,
        contractAddress: String? = nil,
        tokenId: String,
        source: String,
        name: String,
        description: String? = nil,
        image: String? = nil,
        video: String? = nil,
        audio: String? = nil,
        properties: [String: JSONValue]? = nil,
        attributes: [[String: JSONValue]],
        imageData: String? = nil,
        externalUrl: String? = nil,
        backgroundColor: String? = nil,
        animationUrl: String? = nil,
        decimals: Int? = nil,
        updatedAt: String? = nil,
        assets: [TokenMetadataAsset]? = nil,
        status: String,
        queuedAt: String? = nil,
        lastFetched: String? = nil
    ) {
        self.chainId = chainId
        self.contractAddress = contractAddress
        self.tokenId = tokenId
        self.source = source
        self.name = name
        self.description = description
        self.image = image
        self.video = video
        self.audio = audio
        self.properties = properties
        self.attributes = attributes
        self.imageData = imageData
        self.externalUrl = externalUrl
        self.backgroundColor = backgroundColor
        self.animationUrl = animationUrl
        self.decimals = decimals
        self.updatedAt = updatedAt
        self.assets = assets
        self.status = status
        self.queuedAt = queuedAt
        self.lastFetched = lastFetched
    }

    enum CodingKeys: String, CodingKey {
        case chainId
        case contractAddress
        case tokenId
        case tokenID
        case source
        case name
        case description
        case image
        case video
        case audio
        case properties
        case attributes
        case imageData = "image_data"
        case externalUrl = "external_url"
        case backgroundColor = "background_color"
        case animationUrl = "animation_url"
        case decimals
        case updatedAt
        case assets
        case status
        case queuedAt
        case lastFetched
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.chainId = try container.decodeIfPresent(Int64.self, forKey: .chainId)
        self.contractAddress = try container.decodeIfPresent(String.self, forKey: .contractAddress)
        if let tokenId = try container.decodeIfPresent(String.self, forKey: .tokenId)
            ?? container.decodeIfPresent(String.self, forKey: .tokenID) {
            self.tokenId = tokenId
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.tokenID,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing tokenId")
            )
        }
        self.source = try container.decode(String.self, forKey: .source)
        self.name = try container.decode(String.self, forKey: .name)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.image = try container.decodeIfPresent(String.self, forKey: .image)
        self.video = try container.decodeIfPresent(String.self, forKey: .video)
        self.audio = try container.decodeIfPresent(String.self, forKey: .audio)
        self.properties = try container.decodeIfPresent([String: JSONValue].self, forKey: .properties)
        self.attributes = try container.decode([[String: JSONValue]].self, forKey: .attributes)
        self.imageData = try container.decodeIfPresent(String.self, forKey: .imageData)
        self.externalUrl = try container.decodeIfPresent(String.self, forKey: .externalUrl)
        self.backgroundColor = try container.decodeIfPresent(String.self, forKey: .backgroundColor)
        self.animationUrl = try container.decodeIfPresent(String.self, forKey: .animationUrl)
        self.decimals = try container.decodeIfPresent(Int.self, forKey: .decimals)
        self.updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        self.assets = try container.decodeIfPresent([TokenMetadataAsset].self, forKey: .assets)
        self.status = try container.decode(String.self, forKey: .status)
        self.queuedAt = try container.decodeIfPresent(String.self, forKey: .queuedAt)
        self.lastFetched = try container.decodeIfPresent(String.self, forKey: .lastFetched)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(chainId, forKey: .chainId)
        try container.encodeIfPresent(contractAddress, forKey: .contractAddress)
        try container.encode(tokenId, forKey: .tokenID)
        try container.encode(source, forKey: .source)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(image, forKey: .image)
        try container.encodeIfPresent(video, forKey: .video)
        try container.encodeIfPresent(audio, forKey: .audio)
        try container.encodeIfPresent(properties, forKey: .properties)
        try container.encode(attributes, forKey: .attributes)
        try container.encodeIfPresent(imageData, forKey: .imageData)
        try container.encodeIfPresent(externalUrl, forKey: .externalUrl)
        try container.encodeIfPresent(backgroundColor, forKey: .backgroundColor)
        try container.encodeIfPresent(animationUrl, forKey: .animationUrl)
        try container.encodeIfPresent(decimals, forKey: .decimals)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(assets, forKey: .assets)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(queuedAt, forKey: .queuedAt)
        try container.encodeIfPresent(lastFetched, forKey: .lastFetched)
    }
}
