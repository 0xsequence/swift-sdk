import CryptoKit
import Foundation
import Testing
@testable import OMSWallet

// RFC 9180 test vector for mode_base, DHKEM(P-256, HKDF-SHA256), HKDF-SHA256, AES-256-GCM
// (kem_id 0x0010, kdf_id 0x0001, aead_id 0x0002), from the official CFRG test vectors referenced
// by RFC 9180: https://github.com/cfrg/draft-irtf-cfrg-hpke/blob/master/test-vectors.json
private enum RFC9180P256Sha256Aes256GcmBase {
    static let info = "4f6465206f6e2061204772656369616e2055726e"
    static let skRm = "317f915db7bc629c48fe765587897e01e282d3e8445f79f27f65d031a88082b2"
    static let skEm = "90345e3a1d116c1dd39ae76d95ab858c142223a63e44f8f85318cfa91a84858e"
    static let pkRm = "04abc7e49a4c6b3566d77d0304addc6ed0e98512ffccf505e6a8e3eb25c685136f853148544876de76c0f2ef99cdc3a05ccf5ded7860c7c021238f9e2073d2356c"
    static let pkEm = "04c06b4f6bebc7bb495cb797ab753f911aff80aefb86fd8b6fcc35525f3ab5f03e0b21bd31a86c6048af3cb2d98e0d3bf01da5cc4c39ff5370d331a4f1f7d5a4e0"
    static let enc = "04c06b4f6bebc7bb495cb797ab753f911aff80aefb86fd8b6fcc35525f3ab5f03e0b21bd31a86c6048af3cb2d98e0d3bf01da5cc4c39ff5370d331a4f1f7d5a4e0"
    static let sharedSecret = "48893fecd82f7c3456af6a42d8f56325d21e08c10fa81299986aaff54cde7b49"
    static let keyScheduleContext = "008fc3aeb832490a4b5ab3e42023287db29a1f4bc7c222c0df228727b70a4021127f1ff3fd1aa97af7e5d473e1cb01ba74831133d9659b6c26b03a038a49a84074"
    static let secret = "520da82c752ee6e0be7aafbad57a62535d266b6333513d3eb94cb497dceaf94e"
    static let key = "ee16802a936d5f544771131900ee6973d0551de9e852ece2ef34bf0d5f9e1d1d"
    static let baseNonce = "9bc50980832a7b4b58c40161"

    // encryptions[0]: sequence number 0, so the nonce is base_nonce.
    static let aad = "436f756e742d30"
    static let plaintext = "4265617574792069732074727574682c20747275746820626561757479"
    static let ciphertext = "58c61a45059d0c5704560e9d88b564a8b63f1364b8d1fcb3c4c6ddc1d291742465e902cd216f8908da49f8f96f"
}

private func hex(_ value: String) throws -> Data {
    var bytes = [UInt8]()
    var index = value.startIndex
    while index < value.endIndex {
        let next = value.index(index, offsetBy: 2)
        bytes.append(try #require(UInt8(value[index..<next], radix: 16)))
        index = next
    }
    return Data(bytes)
}

private func hex(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

@Test func TestWalletImportP256HpkeMatchesRfc9180TestVector() throws {
    typealias Vector = RFC9180P256Sha256Aes256GcmBase
    let ephemeral = try P256.KeyAgreement.PrivateKey(rawRepresentation: hex(Vector.skEm))
    let recipient = try P256.KeyAgreement.PublicKey(x963Representation: hex(Vector.pkRm))
    #expect(hex(ephemeral.publicKey.x963Representation) == Vector.pkEm)
    #expect(try P256.KeyAgreement.PrivateKey(rawRepresentation: hex(Vector.skRm)).publicKey.x963Representation == hex(Vector.pkRm))

    let context = try P256HPKE.setupBaseSender(
        recipientPublicKey: recipient.derRepresentation,
        ephemeralPrivateKey: ephemeral,
        info: hex(Vector.info)
    )
    #expect(hex(context.encapsulatedKey) == Vector.enc)
    #expect(hex(context.sharedSecret) == Vector.sharedSecret)
    #expect(hex(context.keyScheduleContext) == Vector.keyScheduleContext)
    #expect(hex(context.secret) == Vector.secret)
    #expect(hex(context.key) == Vector.key)
    #expect(hex(context.baseNonce) == Vector.baseNonce)

    let sealed = try P256HPKE.seal(
        recipientPublicKey: recipient.derRepresentation,
        plaintext: hex(Vector.plaintext),
        ephemeralPrivateKey: ephemeral,
        info: hex(Vector.info),
        aad: hex(Vector.aad)
    )
    #expect(hex(sealed.encapsulatedKey) == Vector.enc)
    #expect(hex(sealed.ciphertext) == Vector.ciphertext)
}

// CryptoKit's HPKE API requires macOS 14 or iOS 17; Swift Testing skips this test on older systems.
@available(macOS 14.0, iOS 17.0, *)
@Test func TestWalletImportP256HpkeOpensWithCryptoKitRecipient() throws {
    let recipientKey = P256.KeyAgreement.PrivateKey()
    let plaintext = Data("0x".utf8) + Data(repeating: 0x31, count: 64)

    let sealed = try P256HPKE.seal(
        recipientPublicKey: recipientKey.publicKey.derRepresentation,
        plaintext: plaintext
    )
    var recipient = try HPKE.Recipient(
        privateKey: recipientKey,
        ciphersuite: .P256_SHA256_AES_GCM_256,
        info: Data(),
        encapsulatedKey: sealed.encapsulatedKey
    )
    #expect(try recipient.open(sealed.ciphertext, authenticating: Data()) == plaintext)

    var tampered = sealed.ciphertext
    tampered[tampered.startIndex] ^= 0x01
    var tamperedRecipient = try HPKE.Recipient(
        privateKey: recipientKey,
        ciphersuite: .P256_SHA256_AES_GCM_256,
        info: Data(),
        encapsulatedKey: sealed.encapsulatedKey
    )
    #expect(throws: (any Error).self) {
        try tamperedRecipient.open(tampered, authenticating: Data())
    }

    // CryptoKit also opens the RFC 9180 vector ciphertext, cross-checking the vector itself.
    typealias Vector = RFC9180P256Sha256Aes256GcmBase
    var vectorRecipient = try HPKE.Recipient(
        privateKey: P256.KeyAgreement.PrivateKey(rawRepresentation: hex(Vector.skRm)),
        ciphersuite: .P256_SHA256_AES_GCM_256,
        info: hex(Vector.info),
        encapsulatedKey: hex(Vector.enc)
    )
    #expect(try vectorRecipient.open(hex(Vector.ciphertext), authenticating: hex(Vector.aad)) == hex(Vector.plaintext))
}
