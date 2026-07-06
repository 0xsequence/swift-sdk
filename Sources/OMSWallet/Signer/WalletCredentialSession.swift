import Foundation

@available(macOS 12.0, iOS 15.0, *)
final class WalletCredentialSession {
    struct WalletMetadata {
        let walletId: String
        let walletAddress: String
        let expiresAt: String?
        let auth: OMSWalletSessionAuth
    }

    private let keychain: any KeychainManaging
    private let credentialsStorageKey: String
    private let signerFactory: () -> any CredentialSigner
    private let lock = NSRecursiveLock()
    private var currentSigner: any CredentialSigner

    var signer: any CredentialSigner {
        withLock { currentSigner }
    }

    init(
        environment: OMSWalletEnvironment,
        projectId: String,
        keychain: any KeychainManaging = KeychainManager(),
        signerFactory: ((String, OMSWalletEnvironment, any KeychainManaging) -> any CredentialSigner)? = nil
    ) {
        self.keychain = keychain
        self.credentialsStorageKey = Constants.credentialsStorageKey(environment: environment, scope: projectId)
        let makeSigner = signerFactory ?? Self.makeDefaultCredentialSigner
        let factory = { makeSigner(projectId, environment, keychain) }
        self.signerFactory = factory
        self.currentSigner = factory()
    }

    func storedMetadata() -> WalletMetadata? {
        withLock {
            guard let credentials = loadCredentials() else {
                return nil
            }

            return WalletMetadata(
                walletId: credentials.walletId,
                walletAddress: credentials.walletAddress,
                expiresAt: credentials.expiresAt,
                auth: credentials.auth
            )
        }
    }

    func restore() -> WalletMetadata? {
        withLock {
            restoreLocked()
        }
    }

    private func restoreLocked() -> WalletMetadata? {
        guard let credentials = loadCredentials() else {
            return nil
        }

        guard !Self.sessionIsExpired(expiresAt: credentials.expiresAt) else {
            clearStoredSession()
            return nil
        }

        let candidateSigner = makeCredentialSigner()
        do {
            guard try candidateSigner.hasCredential() else {
                _ = try? keychain.delete(forKey: credentialsStorageKey)
                currentSigner = signerFactory()
                return nil
            }

            if try signerMatchesStoredCredential(candidateSigner, credentials: credentials) {
                currentSigner = candidateSigner
                return WalletMetadata(
                    walletId: credentials.walletId,
                    walletAddress: credentials.walletAddress,
                    expiresAt: credentials.expiresAt,
                    auth: credentials.auth
                )
            }

            try candidateSigner.clear()
            try keychain.delete(forKey: credentialsStorageKey)
        } catch {
            currentSigner = signerFactory()
            return nil
        }

        currentSigner = signerFactory()
        return nil
    }

    func persist(
        walletId: String,
        walletAddress: String,
        expiresAt: String?,
        auth: OMSWalletSessionAuth
    ) throws {
        try withLock {
            let credentials = StorableCredentials(
                walletId: walletId,
                walletAddress: walletAddress,
                signerCredentialId: try currentSigner.credentialId(),
                alg: currentSigner.alg,
                expiresAt: expiresAt,
                auth: auth
            )

            try keychain.set(credentials.jsonString(), forKey: credentialsStorageKey)
        }
    }

    func clearSignerKeepingCredentials() throws {
        try withLock {
            try currentSigner.clear()
            currentSigner = signerFactory()
        }
    }

    func clear() throws {
        try withLock {
            try currentSigner.clear()
            try keychain.delete(forKey: credentialsStorageKey)
            currentSigner = signerFactory()
        }
    }

    private func loadCredentials() -> StorableCredentials? {
        guard let credentialsJson = try? keychain.string(forKey: credentialsStorageKey) else {
            return nil
        }
        return try? StorableCredentials.from(jsonString: credentialsJson)
    }

    private func makeCredentialSigner() -> any CredentialSigner {
        signerFactory()
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

    private func clearStoredSession() {
        _ = try? makeCredentialSigner().clear()
        _ = try? keychain.delete(forKey: credentialsStorageKey)
        currentSigner = signerFactory()
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer {
            lock.unlock()
        }
        return try body()
    }

    private static func sessionIsExpired(expiresAt value: String?) -> Bool {
        guard let expiresAt = parseExpiresAt(value) else {
            return true
        }

        return expiresAt <= Date()
    }

    private static func parseExpiresAt(_ value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private static func makeDefaultCredentialSigner(
        projectId: String,
        environment: OMSWalletEnvironment,
        keychain: any KeychainManaging
    ) -> any CredentialSigner {
        AppleKeychainP256CredentialSigner(
            applicationTag: Constants.credentialApplicationTag(environment: environment, scope: projectId),
            nonceStorageKey: Constants.credentialNonceStorageKey(environment: environment, scope: projectId),
            keychain: keychain
        )
    }
}
