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

    let keyType: KeyType = .webCryptoSecp256r1

    private let applicationTag: Data
    private let nonceStorageKey: String
    private let keychain: KeychainManager
    private let nonceLock = NSLock()

    init(
        applicationTag: String,
        nonceStorageKey: String,
        keychain: KeychainManager = KeychainManager()
    ) {
        self.applicationTag = Data(applicationTag.utf8)
        self.nonceStorageKey = nonceStorageKey
        self.keychain = keychain
    }

    func credentialId() throws -> String {
        let privateKey = try getOrCreatePrivateKey()
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
        nonceLock.lock()
        defer { nonceLock.unlock() }

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
            throw SignerError.signingFailed(errorDescription(error))
        }

        let rawSignature = try P256EcdsaSignatureEncoding.derToRaw(derSignature)
        return "0x" + ByteUtils.bytesToHex(data: rawSignature)
    }

    func hasCredential() throws -> Bool {
        try existingPrivateKey() != nil
    }

    func clear() throws {
        let status = SecItemDelete(privateKeyQuery(returnReference: false) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SignerError.keyLookupFailed(status)
        }
        try keychain.delete(forKey: nonceStorageKey)
    }

    private func getOrCreatePrivateKey() throws -> SecKey {
        if let existing = try existingPrivateKey() {
            return existing
        }

        var error: Unmanaged<CFError>?
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: applicationTag,
                kSecAttrIsExtractable as String: false
            ]
        ]

        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw SignerError.keyCreationFailed(errorDescription(error))
        }
        return key
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

    private func errorDescription(_ error: Unmanaged<CFError>?) -> String {
        guard let error else {
            return "unknown error"
        }
        return String(describing: error.takeRetainedValue())
    }
}
