@available(macOS 12.0, iOS 15.0, *)
final class WalletCredentialSession {
    struct WalletMetadata {
        let walletId: String
        let walletAddress: String
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
        if candidateSigner.hasCredential(),
           signerMatchesStoredCredential(candidateSigner, credentials: credentials) {
            currentSigner = candidateSigner
            return WalletMetadata(
                walletId: credentials.walletId,
                walletAddress: credentials.walletAddress
            )
        }

        _ = try? keychain.delete(forKey: credentialsStorageKey)
        _ = try? candidateSigner.clear()
        currentSigner = Self.makeDefaultCredentialSigner(
            environment: environment,
            keychain: keychain
        )
        return nil
    }

    func persist(walletId: String, walletAddress: String) throws {
        let credentials = StorableCredentials(
            walletId: walletId,
            walletAddress: walletAddress,
            signerCredentialId: try currentSigner.credentialId(),
            signerKeyType: currentSigner.keyType
        )

        try keychain.set(credentials.jsonString(), forKey: credentialsStorageKey)
    }

    func clear() throws {
        try keychain.delete(forKey: credentialsStorageKey)
        _ = try? currentSigner.clear()
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
    ) -> Bool {
        if credentials.signerKeyType != signer.keyType {
            return false
        }

        return (try? signer.credentialId().lowercased()) == credentials.signerCredentialId.lowercased()
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
