struct WaasWalletData : Codable {
    var type: String
    var address: String
    var comment: String
}

struct WaasWalletResponse : Codable {
    var wallet: WaasWalletData
}
