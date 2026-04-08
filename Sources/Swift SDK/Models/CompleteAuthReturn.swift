public struct Identity : Codable {
    var type: String
    var sub: String
    var email: String
}

public struct Wallet : Codable {
    var type: String
    var address: String
    var index: Int
    var comment: String
}

public struct CompleteAuthReturn : Codable {
    var identity: Identity
    var wallets: [Wallet]
}
