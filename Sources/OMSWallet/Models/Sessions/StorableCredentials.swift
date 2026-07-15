
struct StorableCredentials : Codable {
    let walletId: String
    let walletAddress: String
    let signerCredentialId: String
    let alg: SigningAlgorithm
    let expiresAt: String?
    let auth: OMSWalletSessionAuth

    init(
        walletId: String,
        walletAddress: String,
        signerCredentialId: String,
        alg: SigningAlgorithm,
        expiresAt: String? = nil,
        auth: OMSWalletSessionAuth
    ) {
        self.walletId = walletId
        self.walletAddress = walletAddress
        self.signerCredentialId = signerCredentialId
        self.alg = alg
        self.expiresAt = expiresAt
        self.auth = auth
    }
}
