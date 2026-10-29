import Foundation

@available(macOS 12.0, iOS 15.0, *)
final class WalletCredentialSession {
    struct WalletMetadata {
        let wallet: Wallet
        let expiresAt: String
        let auth: OMSWalletSessionAuth
        /// `nil` when the record has no readable bounds.
        let expiryBounds: SessionExpiryBounds?
        /// The credential the session signed in with.
        let signerCredentialId: String
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

    /// The stored session record. `.unavailable` means the keychain could not be read, for example
    /// while the device is locked; it says nothing about whether a record exists.
    enum StoredSession {
        case none
        case unavailable
        case stored(WalletMetadata)
    }

    /// Whether the signer holds its key. `.unavailable` means the keychain could not be read.
    enum SignerKey {
        case present
        case missing
        case unavailable
    }

    enum Restoration {
        case restored(WalletMetadata)
        /// Nothing to restore, or a record that cannot be used, which was discarded.
        case discarded
        /// The keychain could not be read; nothing was changed.
        case unavailable
    }

    func storedSession() -> StoredSession {
        withLock {
            switch loadCredentials() {
            case .none:
                return .none
            case .unavailable:
                return .unavailable
            case .stored(let credentials):
                return .stored(WalletMetadata(
                    wallet: credentials.wallet,
                    expiresAt: credentials.expiresAt,
                    auth: credentials.auth,
                    expiryBounds: credentials.expiryBounds,
                    signerCredentialId: credentials.signerCredentialId
                ))
            }
        }
    }

    /// Whether the signer holds a key, without restoring or deleting anything. Expiry clears the
    /// key but keeps the record. A failed lookup is `.unavailable`, never `.missing`.
    func signerKey() -> SignerKey {
        withLock {
            do {
                return try signerFactory().hasCredential() ? .present : .missing
            } catch {
                return .unavailable
            }
        }
    }

    func restore() -> Restoration {
        withLock {
            restoreLocked()
        }
    }

    private func restoreLocked() -> Restoration {
        let credentials: StorableCredentials
        switch loadCredentials() {
        case .none:
            return .discarded
        case .unavailable:
            return .unavailable
        case .stored(let stored):
            credentials = stored
        }

        // The caller decided, on its clock, that the session may still be active; an unreadable
        // expiry is discarded.
        guard OMSWalletSession.parseDate(credentials.expiresAt) != nil else {
            clearStoredSession()
            return .discarded
        }

        let candidateSigner = signerFactory()
        do {
            guard try candidateSigner.hasCredential() else {
                _ = try? keychain.delete(forKey: credentialsStorageKey)
                currentSigner = signerFactory()
                return .discarded
            }

            if try signerMatchesStoredCredential(candidateSigner, credentials: credentials) {
                currentSigner = candidateSigner
                return .restored(WalletMetadata(
                    wallet: credentials.wallet,
                    expiresAt: credentials.expiresAt,
                    auth: credentials.auth,
                    expiryBounds: credentials.expiryBounds,
                    signerCredentialId: credentials.signerCredentialId
                ))
            }

            try candidateSigner.clear()
            try keychain.delete(forKey: credentialsStorageKey)
        } catch {
            // A keychain that cannot be read or written now (for example while the device is
            // locked) keeps the record and key for a later attempt.
            currentSigner = signerFactory()
            return .unavailable
        }

        currentSigner = signerFactory()
        return .discarded
    }

    func persist(
        wallet: Wallet,
        expiresAt: String,
        auth: OMSWalletSessionAuth,
        expiryBounds: SessionExpiryBounds?
    ) throws {
        try withLock {
            let credentials = StorableCredentials(
                wallet: wallet,
                signerCredentialId: try currentSigner.credentialId(),
                alg: currentSigner.alg,
                expiresAt: expiresAt,
                auth: auth,
                expiryBounds: expiryBounds
            )

            try keychain.set(credentials.jsonString(), forKey: credentialsStorageKey)
        }
    }

    /// Deletes the signer's key for a session that ended on its own, keeping the record as the
    /// sign-in hint. Only a key that is still `credentialId` is deleted: another process sharing the
    /// keychain may already hold a newer sign-in's key under the same tag.
    func clearSignerKeepingCredentials(ifCredentialId credentialId: String?) throws {
        try withLock {
            if let credentialId {
                try currentSigner.clear(ifCredentialId: credentialId)
            }
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

    private enum LoadedCredentials {
        case none
        case unavailable
        case stored(StorableCredentials)
    }

    private func loadCredentials() -> LoadedCredentials {
        let credentialsJson: String?
        do {
            credentialsJson = try keychain.string(forKey: credentialsStorageKey)
        } catch {
            return .unavailable
        }
        guard let credentialsJson else {
            return .none
        }
        do {
            return .stored(try StorableCredentials.from(jsonString: credentialsJson))
        } catch {
            clearStoredSession()
            return .none
        }
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
        _ = try? signerFactory().clear()
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
