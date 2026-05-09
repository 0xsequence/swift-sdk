public struct StorableCredentials : Codable {
    let walletId: String
    let walletAddress: String
    let signerCredentialId: String
    let signerKeyType: KeyType

    init(
        walletId: String,
        walletAddress: String,
        signerCredentialId: String,
        signerKeyType: KeyType
    ) {
        self.walletId = walletId
        self.walletAddress = walletAddress
        self.signerCredentialId = signerCredentialId
        self.signerKeyType = signerKeyType
    }
}
