public struct Identity : Codable {
    public var type: String
    public var sub: String
    public var email: String
}

public struct Wallet : Codable {
    public var type: String
    public var address: String
    public var index: Int
    public var comment: String
}

public struct CompleteAuthReturn : Codable {
    public var identity: Identity
    public var wallets: [Wallet]
}
