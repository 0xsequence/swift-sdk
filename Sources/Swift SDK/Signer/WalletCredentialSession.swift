@available(macOS 12.0, iOS 15.0, *)
final class WalletCredentialSession {
    struct WalletMetadata {
        let walletId: String
        let walletAddress: String
        let expiresAt: String?
        let loginType: SessionLoginType?
        let sessionEmail: String?
    }

    private let environment: OMSClientEnvironment
    private let keychain: KeychainManager
    private let credentialsStorageKey: String
    private var currentSigner: any CredentialSigner

    var signer: any CredentialSigner {
        currentSigner
    }

    init(
        environment: OMSClientEnvironment,
        keychain: KeychainManager = KeychainManager()
    ) {
        self.environment = environment
        self.keychain = keychain
        self.credentialsStorageKey = Constants.credentialsStorageKey(environment: environment)
        self.currentSigner = Self.makeDefaultCredentialSigner(
            environment: environment,
            keychain: keychain
        )
    }

    func restore() -> WalletMetadata? {
        guard let credentials = loadCredentials() else {
            return nil
        }

        let candidateSigner = makeCredentialSigner()
        do {
            guard try candidateSigner.hasCredential() else {
                _ = try? keychain.delete(forKey: credentialsStorageKey)
                currentSigner = Self.makeDefaultCredentialSigner(
                    environment: environment,
                    keychain: keychain
                )
                return nil
            }

            if try signerMatchesStoredCredential(candidateSigner, credentials: credentials) {
                currentSigner = candidateSigner
                return WalletMetadata(
                    walletId: credentials.walletId,
                    walletAddress: credentials.walletAddress,
                    expiresAt: credentials.expiresAt,
                    loginType: credentials.loginType,
                    sessionEmail: credentials.sessionEmail
                )
            }

            try candidateSigner.clear()
            try keychain.delete(forKey: credentialsStorageKey)
        } catch {
            currentSigner = Self.makeDefaultCredentialSigner(
                environment: environment,
                keychain: keychain
            )
            return nil
        }

        currentSigner = Self.makeDefaultCredentialSigner(
            environment: environment,
            keychain: keychain
        )
        return nil
    }

    func persist(
        walletId: String,
        walletAddress: String,
        expiresAt: String?,
        loginType: SessionLoginType?,
        sessionEmail: String?
    ) throws {
        let credentials = StorableCredentials(
            walletId: walletId,
            walletAddress: walletAddress,
            signerCredentialId: try currentSigner.credentialId(),
            alg: currentSigner.alg,
            expiresAt: expiresAt,
            loginType: loginType,
            sessionEmail: sessionEmail
        )

        try keychain.set(credentials.jsonString(), forKey: credentialsStorageKey)
    }

    func clear() throws {
        try currentSigner.clear()
        try keychain.delete(forKey: credentialsStorageKey)
        currentSigner = Self.makeDefaultCredentialSigner(
            environment: environment,
            keychain: keychain
        )
    }

    private func loadCredentials() -> StorableCredentials? {
        guard let credentialsJson = try? keychain.string(forKey: credentialsStorageKey) else {
            return nil
        }
        return try? StorableCredentials.from(jsonString: credentialsJson)
    }

    private func makeCredentialSigner() -> any CredentialSigner {
        Self.makeDefaultCredentialSigner(
            environment: environment,
            keychain: keychain
        )
    }

    private func signerMatchesStoredCredential(
        _ signer: any CredentialSigner,
        credentials: StorableCredentials
    ) throws -> Bool {
        if credentials.alg != signer.alg {
            return false
        }

        return try signer.credentialId().lowercased() == credentials.signerCredentialId.lowercased()
    }

    private static func makeDefaultCredentialSigner(
        environment: OMSClientEnvironment,
        keychain: KeychainManager
    ) -> any CredentialSigner {
        AppleKeychainP256CredentialSigner(
            applicationTag: Constants.credentialApplicationTag(environment: environment),
            nonceStorageKey: Constants.credentialNonceStorageKey(environment: environment),
            keychain: keychain
        )
    }
}
