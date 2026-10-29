import CryptoKit
import Foundation
import Security
import Testing
@testable import OMSWallet

// Session keys on an iOS device are generated in the Secure Enclave: they sign, but the private key
// can never be exported, right after creation or once the app reloads it from the keychain.
// Run on an unlocked device:
// xcodebuild test -project Tests/DeviceTests/OMSWalletDeviceTests.xcodeproj -scheme OMSWalletDeviceTests
//   -destination 'platform=iOS,id=<device>' -allowProvisioningUpdates

@Test func TestSecureEnclaveSessionKeySignsButCannotBeExportedBeforeAndAfterReload() throws {
    #if targetEnvironment(simulator)
    // The Simulator has no Secure Enclave; the SDK uses software keys there.
    #expect(AppleKeychainP256CredentialSigner.KeyStorage.platformDefault == .software)
    #else
    let tag = "oms.devicetest.\(UUID().uuidString)"
    func signer() -> AppleKeychainP256CredentialSigner {
        AppleKeychainP256CredentialSigner(applicationTag: tag, nonceStorageKey: tag + ".nonce")
    }
    defer { try? signer().clear() }
    #expect(AppleKeychainP256CredentialSigner.KeyStorage.platformDefault == .secureEnclave)

    let created = signer()
    let credentialId = try created.credentialId()
    try expectSecureEnclaveKey(created, credentialId: credentialId, tag: tag)

    // A new signer finds the key in the keychain, as after the app is relaunched.
    let reloaded = signer()
    #expect(try reloaded.credentialId() == credentialId)
    try expectSecureEnclaveKey(reloaded, credentialId: credentialId, tag: tag)
    #endif
}

private func expectSecureEnclaveKey(
    _ signer: AppleKeychainP256CredentialSigner,
    credentialId: String,
    tag: String
) throws {
    let privateKey = try #require(try signer.storedKey())

    // The private key cannot be exported.
    var exportError: Unmanaged<CFError>?
    #expect(SecKeyCopyExternalRepresentation(privateKey, &exportError) == nil)
    #expect(exportError != nil)
    exportError?.release()

    // The keychain item lives in the Secure Enclave and carries an access control. Its protection
    // class and allowed operations cannot be read back through a public API, so they are not
    // checked here; the key is created with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and
    // `privateKeyUsage` (`AppleKeychainP256CredentialSigner.keyCreationAttributes`).
    var item: CFTypeRef?
    let status = SecItemCopyMatching([
        kSecClass as String: kSecClassKey,
        kSecAttrApplicationTag as String: Data(tag.utf8),
        kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        kSecReturnAttributes as String: true
    ] as CFDictionary, &item)
    #expect(status == errSecSuccess)
    let attributes = try #require(item as? [String: Any])
    #expect(attributes[kSecAttrTokenID as String] as? String == kSecAttrTokenIDSecureEnclave as String)
    #expect(attributes[kSecAttrAccessControl as String] != nil)

    // It signs, and the signature verifies against the credential's public key.
    let preimage = "oms secure enclave key \(UUID().uuidString)"
    let signature = try signer.sign(preimage: preimage)
    let publicKey = try P256.Signing.PublicKey(x963Representation: hexBytes(credentialId))
    let ecdsa = try P256.Signing.ECDSASignature(rawRepresentation: hexBytes(signature))
    #expect(publicKey.isValidSignature(ecdsa, for: Data(preimage.utf8)))
}

private func hexBytes(_ hex: String) -> Data {
    let digits = Array(hex.dropFirst(2))
    return Data(stride(from: 0, to: digits.count, by: 2).compactMap { UInt8(String(digits[$0..<$0 + 2]), radix: 16) })
}
