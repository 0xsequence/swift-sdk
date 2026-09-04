import CryptoKit
import Foundation
import Testing
@testable import OMSWallet

@Test func TestWalletImportConfigurationRejectsInvalidAndAllZeroPcr0s() throws {
    for values in [[], [String(repeating: "0", count: 95)], [String(repeating: "0", count: 96)], [String(repeating: "z", count: 96)]] {
        #expect(throws: OMSWalletError.self) {
            _ = try WalletImportConfiguration(trustedPcr0s: values)
        }
    }
    _ = try WalletImportConfiguration(trustedPcr0s: ["0x" + String(repeating: "a", count: 96)])
}

@Test func TestWalletImportPrivateKeyValidationCoversScalarAndLengthBoundaries() throws {
    let one = Data(repeating: 0, count: 31) + Data([1])
    #expect(try WalletImportValidation.plaintext(.ethereumBytes(one)) == one)
    #expect(throws: OMSWalletError.self) {
        _ = try WalletImportValidation.plaintext(.ethereumBytes(Data(repeating: 0, count: 32)))
    }
    #expect(throws: OMSWalletError.self) {
        _ = try WalletImportValidation.plaintext(
            .ethereum("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141")
        )
    }
    #expect(try WalletImportValidation.plaintext(.solanaBytes(Data(repeating: 7, count: 64))).count == 64)
    #expect(throws: OMSWalletError.self) {
        _ = try WalletImportValidation.plaintext(.solanaBytes(Data(repeating: 7, count: 31)))
    }
    #expect(throws: OMSWalletError.self) {
        _ = try WalletImportValidation.validateReference(String(repeating: "é", count: 65))
    }
}

@Test func TestWalletImportP256HpkeProducesStandardEncapsulationAndAuthenticatedCiphertext() throws {
    let recipient = P256.KeyAgreement.PrivateKey()
    let plaintext = Data("0x".utf8) + Data(repeating: 0x31, count: 64)
    let sealed = try P256HPKE.seal(
        recipientPublicKey: recipient.publicKey.derRepresentation,
        plaintext: plaintext
    )

    #expect(sealed.encapsulatedKey.count == 65)
    #expect(sealed.encapsulatedKey.first == 4)
    #expect(sealed.ciphertext.count == plaintext.count + 16)
}
