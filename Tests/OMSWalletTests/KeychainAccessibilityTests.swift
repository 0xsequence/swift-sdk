import Foundation
import Security
import Testing
@testable import OMSWallet

private func accessibility(_ attributes: [String: Any]) -> String? {
    (attributes[kSecAttrAccessible as String] as? String)
}

@Test func TestKeychainWritesBindItemsToThisDevice() {
    let expected = kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
    let data = Data("value".utf8)
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "service",
        kSecAttrAccount as String: "key"
    ]

    let addQuery = KeychainManager.addQuery(query, data: data)
    #expect(accessibility(addQuery) == expected)
    #expect(addQuery[kSecValueData as String] as? Data == data)
    #expect(addQuery[kSecAttrAccount as String] as? String == "key")

    // An update sets it too, so an item stored by an older SDK version moves to this class on its
    // next write.
    let updateAttributes = KeychainManager.updateAttributes(data: data)
    #expect(accessibility(updateAttributes) == expected)
    #expect(updateAttributes[kSecValueData as String] as? Data == data)
}

@Test func TestCredentialSigningKeyIsCreatedBoundToThisDevice() throws {
    let tag = Data("tag".utf8)
    let attributes = try AppleKeychainP256CredentialSigner.keyCreationAttributes(applicationTag: tag, keyStorage: .software)
    let privateKeyAttributes = try #require(attributes[kSecPrivateKeyAttrs as String] as? [String: Any])

    #expect(attributes[kSecAttrTokenID as String] == nil)
    #expect(accessibility(privateKeyAttributes) == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
    #expect(privateKeyAttributes[kSecAttrIsExtractable as String] as? Bool == false)
    #expect(privateKeyAttributes[kSecAttrIsPermanent as String] as? Bool == true)
    #expect(privateKeyAttributes[kSecAttrApplicationTag as String] as? Data == tag)
}

@Test func TestSecureEnclaveSigningKeyIsCreatedInTheSecureEnclave() throws {
    // Its accessibility and signing-only use are in the access control, which a real device test
    // checks on the created key (SecureEnclaveKeyTests).
    let tag = Data("tag".utf8)
    let attributes = try AppleKeychainP256CredentialSigner.keyCreationAttributes(applicationTag: tag, keyStorage: .secureEnclave)
    let privateKeyAttributes = try #require(attributes[kSecPrivateKeyAttrs as String] as? [String: Any])

    #expect(attributes[kSecAttrTokenID as String] as? String == kSecAttrTokenIDSecureEnclave as String)
    #expect(privateKeyAttributes[kSecAttrAccessControl as String] != nil)
    #expect(privateKeyAttributes[kSecAttrIsPermanent as String] as? Bool == true)
    #expect(privateKeyAttributes[kSecAttrApplicationTag as String] as? Data == tag)
}
