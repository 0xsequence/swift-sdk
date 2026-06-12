public struct TokenMetadataAsset: Codable, Sendable {
    public let id: Int64?
    public let collectionId: Int64?
    public let tokenId: String?
    public let url: String?
    public let metadataField: String?
    public let name: String?
    public let filesize: Int64?
    public let mimeType: String?
    public let width: Int?
    public let height: Int?
    public let updatedAt: String?

    public init(
        id: Int64? = nil,
        collectionId: Int64? = nil,
        tokenId: String? = nil,
        url: String? = nil,
        metadataField: String? = nil,
        name: String? = nil,
        filesize: Int64? = nil,
        mimeType: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.collectionId = collectionId
        self.tokenId = tokenId
        self.url = url
        self.metadataField = metadataField
        self.name = name
        self.filesize = filesize
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case collectionId
        case tokenId
        case tokenID
        case url
        case metadataField
        case name
        case filesize
        case mimeType
        case width
        case height
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(Int64.self, forKey: .id)
        self.collectionId = try container.decodeIfPresent(Int64.self, forKey: .collectionId)
        self.tokenId = try container.decodeIfPresent(String.self, forKey: .tokenId)
            ?? container.decodeIfPresent(String.self, forKey: .tokenID)
        self.url = try container.decodeIfPresent(String.self, forKey: .url)
        self.metadataField = try container.decodeIfPresent(String.self, forKey: .metadataField)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.filesize = try container.decodeIfPresent(Int64.self, forKey: .filesize)
        self.mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        self.width = try container.decodeIfPresent(Int.self, forKey: .width)
        self.height = try container.decodeIfPresent(Int.self, forKey: .height)
        self.updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(collectionId, forKey: .collectionId)
        try container.encodeIfPresent(tokenId, forKey: .tokenID)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encodeIfPresent(metadataField, forKey: .metadataField)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(filesize, forKey: .filesize)
        try container.encodeIfPresent(mimeType, forKey: .mimeType)
        try container.encodeIfPresent(width, forKey: .width)
        try container.encodeIfPresent(height, forKey: .height)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}
