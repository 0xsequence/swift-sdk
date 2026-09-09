import CryptoKit
import Foundation
import SwiftCBOR
import Testing
@testable import OMSWallet

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
        _ = try WalletImportValidation.plaintext(.solana(String(repeating: "1", count: 32)))
    }
    #expect(throws: OMSWalletError.self) {
        _ = try WalletImportValidation.validateReference(String(repeating: "é", count: 65))
    }
}

@Test func TestWalletMappingPreservesUnknownKeyOrigin() throws {
    let wallet = try Wallet(
        waasValue: WaasGenerated.Wallet(
            id: "wallet-id",
            networkFamily: .evm,
            keyOrigin: .unknown("future-origin"),
            address: "0x1111111111111111111111111111111111111111"
        )
    )
    let futureNetworkWallet = try Wallet(
        waasValue: WaasGenerated.Wallet(
            id: "future-wallet-id",
            networkFamily: .unknown("future-network"),
            keyOrigin: .enclave,
            address: "future-address"
        )
    )

    #expect(wallet.keyOrigin == .unknown("future-origin"))
    #expect(futureNetworkWallet.type == .unknown("future-network"))
}

@Test func TestAttestationVerifierRejectsUntrustedOrMismatchedDocuments() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let trustedPcr0 = Data(repeating: 0xaa, count: 48)
    let trustedPcr0s = Set([trustedPcr0.map { String(format: "%02x", $0) }.joined()])
    let requestBody = "{}"
    let responseBody = #"{"keyId":"key-id"}"#
    let nonce = "test-nonce"

    expectAttestationFailure("invalid COSE_Sign1 structure") {
        try AttestationVerifier.verify(
            encodedDocument: Data([0]).base64EncodedString(),
            method: "POST",
            path: "/v1/Waas/GetRecipientKey",
            requestBody: requestBody,
            responseBody: responseBody,
            nonce: nonce,
            trustedPcr0s: trustedPcr0s,
            now: now
        )
    }
    expectAttestationFailure("freshness window") {
        try verifySyntheticAttestation(
            timestamp: now.addingTimeInterval(-6 * 60),
            pcr0: trustedPcr0,
            nonce: nonce,
            requestBody: requestBody,
            responseBody: responseBody,
            trustedPcr0s: trustedPcr0s,
            now: now
        )
    }
    expectAttestationFailure("PCR0 is not trusted") {
        try verifySyntheticAttestation(
            timestamp: now,
            pcr0: Data(repeating: 0xbb, count: 48),
            nonce: nonce,
            requestBody: requestBody,
            responseBody: responseBody,
            trustedPcr0s: trustedPcr0s,
            now: now
        )
    }
    expectAttestationFailure("nonce does not match") {
        try verifySyntheticAttestation(
            timestamp: now,
            pcr0: trustedPcr0,
            nonce: nonce,
            requestBody: requestBody,
            responseBody: responseBody,
            trustedPcr0s: trustedPcr0s,
            now: now,
            verificationNonce: "different-nonce"
        )
    }
    expectAttestationFailure("not bound to the request and response") {
        try verifySyntheticAttestation(
            timestamp: now,
            pcr0: trustedPcr0,
            nonce: nonce,
            requestBody: requestBody,
            responseBody: responseBody,
            trustedPcr0s: trustedPcr0s,
            now: now,
            verificationResponseBody: "{}"
        )
    }
    expectAttestationFailure("does not use the AWS Nitro root") {
        try verifySyntheticAttestation(
            timestamp: now,
            pcr0: trustedPcr0,
            nonce: nonce,
            requestBody: requestBody,
            responseBody: responseBody,
            trustedPcr0s: trustedPcr0s,
            now: now
        )
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

private func verifySyntheticAttestation(
    timestamp: Date,
    pcr0: Data,
    nonce: String,
    requestBody: String,
    responseBody: String,
    trustedPcr0s: Set<String>,
    now: Date,
    verificationNonce: String? = nil,
    verificationResponseBody: String? = nil
) throws {
    let method = "POST"
    let path = "/v1/Waas/GetRecipientKey"
    let preimage = "\(method) \(path)\n\(requestBody)\n\(responseBody)"
    let hash = Data(SHA256.hash(data: Data(preimage.utf8))).base64EncodedString()
    let protectedHeader = CBOR.map([.unsignedInt(1): .negativeInt(34)]).encode()
    let payload = CBOR.map([
        "digest": "SHA384",
        "timestamp": .unsignedInt(UInt64(timestamp.timeIntervalSince1970 * 1_000)),
        "pcrs": .map([.unsignedInt(0): .byteString([UInt8](pcr0))]),
        "certificate": .byteString([1]),
        "cabundle": .array([.byteString([2])]),
        "user_data": .byteString([UInt8]("Sequence/1:\(hash)".utf8)),
        "nonce": .byteString([UInt8](nonce.utf8))
    ]).encode()
    let document = CBOR.tagged(
        .init(rawValue: 18),
        .array([
            .byteString(protectedHeader),
            .map([:]),
            .byteString(payload),
            .byteString([UInt8](repeating: 0, count: 96))
        ])
    )

    try AttestationVerifier.verify(
        encodedDocument: Data(document.encode()).base64EncodedString(),
        method: method,
        path: path,
        requestBody: requestBody,
        responseBody: verificationResponseBody ?? responseBody,
        nonce: verificationNonce ?? nonce,
        trustedPcr0s: trustedPcr0s,
        now: now
    )
}

private func expectAttestationFailure(
    _ expectedMessage: String,
    operation: () throws -> Void
) {
    do {
        try operation()
        Issue.record("Expected attestation verification to fail")
    } catch let error as OMSWalletError {
        #expect(error.code == .attestationVerificationFailed)
        #expect(error.errorDescription?.contains(expectedMessage) == true)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
