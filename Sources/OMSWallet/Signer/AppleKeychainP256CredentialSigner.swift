import Foundation
import Security

@available(macOS 12.0, iOS 15.0, *)
final class AppleKeychainP256CredentialSigner: CredentialSigner, @unchecked Sendable {
    enum SignerError: Error {
        case keyCreationFailed(String)
        /// The Secure Enclave could not create the session key. On an iOS device there is no
        /// software fallback: sign-in fails instead.
        case secureEnclaveKeyCreationFailed(String)
        case keyLookupFailed(OSStatus)
        case publicKeyUnavailable
        case publicKeyExportFailed(String)
        case unsupportedAlgorithm
        case signingFailed(String)
        case invalidPublicKey
    }

    /// Where session keys are created and which stored keys this signer uses.
    enum KeyStorage: Sendable {
        /// Generated in the Secure Enclave: the private key never leaves it.
        case secureEnclave
        /// A keychain key marked non-extractable.
        case software

        /// The Secure Enclave on an iOS device. The iOS Simulator has no Secure Enclave, so it uses
        /// software keys, and macOS keeps them for now (Secure Enclave keys there need the
        /// data-protection keychain and a keychain entitlement in the host app). Decided at compile
        /// time, so a device build can never fall back to a software key.
        static var platformDefault: KeyStorage {
            #if os(iOS) && !targetEnvironment(simulator)
            .secureEnclave
            #else
            .software
            #endif
        }
    }

    let alg: SigningAlgorithm = .ecdsaP256Sha256

    private static let keychainLock = NSLock()

    private let applicationTag: Data
    private let nonceStorageKey: String
    private let keychain: any KeychainManaging
    let keyStorage: KeyStorage

    init(
        applicationTag: String,
        nonceStorageKey: String,
        keychain: any KeychainManaging = KeychainManager(),
        keyStorage: KeyStorage = .platformDefault
    ) {
        self.applicationTag = Data(applicationTag.utf8)
        self.nonceStorageKey = nonceStorageKey
        self.keychain = keychain
        self.keyStorage = keyStorage
    }

    func credentialId() throws -> String {
        try Self.credentialId(of: try getOrCreatePrivateKey())
    }

    /// Deletes the key only while it is `credentialId`. The key is looked up and then deleted by its
    /// item reference, not by the shared application tag, so a key another process (an app extension
    /// sharing the keychain) stored meanwhile under that tag is kept. The shared nonce is left alone:
    /// a later key's nonces only need to keep increasing.
    func clear(ifCredentialId credentialId: String) throws {
        Self.keychainLock.lock()
        defer { Self.keychainLock.unlock() }

        guard let privateKey = try existingPrivateKey(),
              try Self.credentialId(of: privateKey).lowercased() == credentialId.lowercased() else {
            return
        }
        try Self.deleteKeyItem(privateKey)
    }

    /// The key currently stored under this signer's tag, without creating one.
    func storedKey() throws -> SecKey? {
        Self.keychainLock.lock()
        defer { Self.keychainLock.unlock() }
        return try existingPrivateKey()
    }

    /// Deletes exactly the keychain item `key` refers to. A key stored meanwhile under the same tag
    /// is a different item, so it is kept.
    static func deleteKeyItem(_ key: SecKey) throws {
        let status = SecItemDelete([
            kSecClass as String: kSecClassKey,
            kSecValueRef as String: key
        ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SignerError.keyLookupFailed(status)
        }
    }

    private static func credentialId(of privateKey: SecKey) throws -> String {
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw SignerError.publicKeyUnavailable
        }

        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw SignerError.publicKeyExportFailed(errorDescription(error))
        }

        let bytes = Array(publicKeyData)
        let uncompressed: [UInt8]
        if bytes.count == 65 && bytes.first == 0x04 {
            uncompressed = bytes
        } else if bytes.count == 64 {
            uncompressed = [0x04] + bytes
        } else {
            throw SignerError.invalidPublicKey
        }

        return "0x" + ByteUtils.bytesToHex(data: uncompressed)
    }

    func nextNonce() throws -> String {
        Self.keychainLock.lock()
        defer { Self.keychainLock.unlock() }

        let previous = (try? keychain.string(forKey: nonceStorageKey))?.flatMap(Int64.init) ?? 0
        let now = Int64((Date().timeIntervalSince1970 * 1000).rounded(.down))
        let next = max(now, previous + 1)
        try keychain.set(String(next), forKey: nonceStorageKey)
        return String(next)
    }

    func sign(preimage: String) throws -> String {
        let privateKey = try getOrCreatePrivateKey()
        let algorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256
        guard SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm) else {
            throw SignerError.unsupportedAlgorithm
        }

        var error: Unmanaged<CFError>?
        guard let derSignature = SecKeyCreateSignature(
            privateKey,
            algorithm,
            Data(preimage.utf8) as CFData,
            &error
        ) as Data? else {
            throw SignerError.signingFailed(Self.errorDescription(error))
        }

        let rawSignature = try P256EcdsaSignatureEncoding.derToRaw(derSignature)
        return "0x" + ByteUtils.bytesToHex(data: rawSignature)
    }

    /// The credentials of keys stored under this signer's tag that it will not sign with: software
    /// keys where keys belong in the Secure Enclave (saved before the SDK created them there).
    func unusableKeyCredentialIds() throws -> [String] {
        Self.keychainLock.lock()
        defer { Self.keychainLock.unlock() }
        return try storedKeys().filter { !isUsable($0) }.map { try Self.credentialId(of: $0.key) }
    }

    /// Deletes the keys `unusableKeyCredentialIds` reports, each by its item reference.
    func deleteUnusableKeys() throws {
        Self.keychainLock.lock()
        defer { Self.keychainLock.unlock() }
        for stored in try storedKeys() where !isUsable(stored) {
            try Self.deleteKeyItem(stored.key)
        }
    }

    func hasCredential() throws -> Bool {
        Self.keychainLock.lock()
        defer { Self.keychainLock.unlock() }
        return try existingPrivateKey() != nil
    }

    func clear() throws {
        Self.keychainLock.lock()
        defer { Self.keychainLock.unlock() }

        let status = SecItemDelete(privateKeyQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SignerError.keyLookupFailed(status)
        }
        try keychain.delete(forKey: nonceStorageKey)
    }

    private func getOrCreatePrivateKey() throws -> SecKey {
        Self.keychainLock.lock()
        defer { Self.keychainLock.unlock() }

        if let existing = try existingPrivateKey() {
            return existing
        }

        var error: Unmanaged<CFError>?
        let attributes = try Self.keyCreationAttributes(applicationTag: applicationTag, keyStorage: keyStorage)

        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            switch keyStorage {
            case .secureEnclave:
                throw SignerError.secureEnclaveKeyCreationFailed(Self.errorDescription(error))
            case .software:
                throw SignerError.keyCreationFailed(Self.errorDescription(error))
            }
        }
        return key
    }

    /// A new key is created at each sign-in (sign-out and every sign-in flow clear the previous
    /// one), so its storage and accessibility are set only here. A Secure Enclave key can only be
    /// used to sign, with no user presence check, and only while the device is unlocked; it never
    /// leaves this device.
    static func keyCreationAttributes(applicationTag: Data, keyStorage: KeyStorage) throws -> [String: Any] {
        switch keyStorage {
        case .secureEnclave:
            var error: Unmanaged<CFError>?
            guard let access = SecAccessControlCreateWithFlags(
                nil,
                KeychainManager.accessibility,
                .privateKeyUsage,
                &error
            ) else {
                throw SignerError.secureEnclaveKeyCreationFailed(errorDescription(error))
            }
            return [
                kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
                kSecAttrKeySizeInBits as String: 256,
                kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
                kSecPrivateKeyAttrs as String: [
                    kSecAttrIsPermanent as String: true,
                    kSecAttrApplicationTag as String: applicationTag,
                    kSecAttrAccessControl as String: access
                ] as [String: Any]
            ]
        case .software:
            return [
                kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
                kSecAttrKeySizeInBits as String: 256,
                kSecPrivateKeyAttrs as String: [
                    kSecAttrIsPermanent as String: true,
                    kSecAttrApplicationTag as String: applicationTag,
                    kSecAttrIsExtractable as String: false,
                    kSecAttrAccessible as String: KeychainManager.accessibility
                ] as [String: Any]
            ]
        }
    }

    /// The key this signer uses: the stored key of its `keyStorage`.
    private func existingPrivateKey() throws -> SecKey? {
        try storedKeys().first(where: isUsable)?.key
    }

    private func isUsable(_ stored: (key: SecKey, isSecureEnclave: Bool)) -> Bool {
        stored.isSecureEnclave == (keyStorage == .secureEnclave)
    }

    /// Every private key stored under this signer's tag, with whether the Secure Enclave holds it.
    private func storedKeys() throws -> [(key: SecKey, isSecureEnclave: Bool)] {
        var query = privateKeyQuery()
        query[kSecReturnRef as String] = true
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)

        switch status {
        case errSecSuccess:
            guard let items = items as? [[String: Any]] else {
                return []
            }
            return items.compactMap { item in
                guard let ref = item[kSecValueRef as String] else {
                    return nil
                }
                let tokenID = item[kSecAttrTokenID as String] as? String
                return (ref as! SecKey, tokenID == (kSecAttrTokenIDSecureEnclave as String))
            }
        case errSecItemNotFound:
            return []
        default:
            throw SignerError.keyLookupFailed(status)
        }
    }

    private func privateKeyQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: applicationTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
        ]
    }

    private static func errorDescription(_ error: Unmanaged<CFError>?) -> String {
        guard let error else {
            return "unknown error"
        }
        return String(describing: error.takeRetainedValue())
    }
}

@available(macOS 12.0, iOS 15.0, *)
extension AppleKeychainP256CredentialSigner.SignerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .secureEnclaveKeyCreationFailed(let reason):
            return "The Secure Enclave could not create the session signing key: \(reason)"
        default:
            return nil
        }
    }
}
