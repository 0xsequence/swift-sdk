public struct StorableCredentials : Codable {
    let walletId: String
    let walletAddress: String
    let signerCredentialId: String
    let alg: SigningAlgorithm
    let expiresAt: String?
    let auth: SessionAuth

    init(
        walletId: String,
        walletAddress: String,
        signerCredentialId: String,
        alg: SigningAlgorithm,
        expiresAt: String? = nil,
        auth: SessionAuth
    ) {
        self.walletId = walletId
        self.walletAddress = walletAddress
        self.signerCredentialId = signerCredentialId
        self.alg = alg
        self.expiresAt = expiresAt
        self.auth = auth
    }
}
