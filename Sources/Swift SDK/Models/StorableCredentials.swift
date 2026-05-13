public struct StorableCredentials : Codable {
    let walletId: String
    let walletAddress: String
    let signerCredentialId: String
    let signerKeyType: KeyType
    let expiresAt: String?
    let loginType: SessionLoginType?
    let sessionEmail: String?

    init(
        walletId: String,
        walletAddress: String,
        signerCredentialId: String,
        signerKeyType: KeyType,
        expiresAt: String? = nil,
        loginType: SessionLoginType? = nil,
        sessionEmail: String? = nil
    ) {
        self.walletId = walletId
        self.walletAddress = walletAddress
        self.signerCredentialId = signerCredentialId
        self.signerKeyType = signerKeyType
        self.expiresAt = expiresAt
        self.loginType = loginType
        self.sessionEmail = sessionEmail
    }
}
