import Foundation
import Security

@available(macOS 12.0, iOS 15.0, *)
final class AppleKeychainP256CredentialSigner: CredentialSigner, @unchecked Sendable {
    enum SignerError: Error {
        case keyCreationFailed(String)
        case keyLookupFailed(OSStatus)
        case publicKeyUnavailable
        case publicKeyExportFailed(String)
        case unsupportedAlgorithm
        case signingFailed(String)
        case invalidPublicKey
    }

    let alg: SigningAlgorithm = .ecdsaP256Sha256

    private static let keychainLock = NSLock()

    private let applicationTag: Data
    private let nonceStorageKey: String
    private let keychain: any KeychainManaging

    init(
        applicationTag: String,
        nonceStorageKey: String,
        keychain: any KeychainManaging = KeychainManager()
    ) {
        self.applicationTag = Data(applicationTag.utf8)
        self.nonceStorageKey = nonceStorageKey
        self.keychain = keychain
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

    func hasCredential() throws -> Bool {
        Self.keychainLock.lock()
        defer { Self.keychainLock.unlock() }
        return try existingPrivateKey() != nil
    }

    func clear() throws {
        Self.keychainLock.lock()
        defer { Self.keychainLock.unlock() }

        let status = SecItemDelete(privateKeyQuery(returnReference: false) as CFDictionary)
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
        let attributes = Self.keyCreationAttributes(applicationTag: applicationTag)

        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw SignerError.keyCreationFailed(Self.errorDescription(error))
        }
        return key
    }

    /// A new key is created at each sign-in (sign-out and every sign-in flow clear the previous
    /// one), so its accessibility is set only here.
    static func keyCreationAttributes(applicationTag: Data) -> [String: Any] {
        [
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

    private func existingPrivateKey() throws -> SecKey? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(privateKeyQuery(returnReference: true) as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            return (item as! SecKey)
        case errSecItemNotFound:
            return nil
        default:
            throw SignerError.keyLookupFailed(status)
        }
    }

    private func privateKeyQuery(returnReference: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: applicationTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
        ]
        if returnReference {
            query[kSecReturnRef as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
        }
        return query
    }

    private static func errorDescription(_ error: Unmanaged<CFError>?) -> String {
        guard let error else {
            return "unknown error"
        }
        return String(describing: error.takeRetainedValue())
    }
}
